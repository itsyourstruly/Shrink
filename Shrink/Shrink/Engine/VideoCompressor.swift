//
//  VideoCompressor.swift
//  Shrink
//

import Foundation
import AVFoundation
import VideoToolbox
import CoreMedia
import CoreVideo

nonisolated final class VideoCompressor: @unchecked Sendable {
    
    // Thread-safe progress tracker to avoid Swift 6 concurrency mutable capture warnings
    private final class ProgressTrackerState: @unchecked Sendable {
        var lastReportedProgress: Double = -1.0
        var lastReportedTime = Date.distantPast
        var frameCount: Int = 0
    }
    
    private var reader: AVAssetReader?
    private var assetWriter: AVAssetWriter?
    private var exportSession: AVAssetExportSession?
    private var isCancelled = false
    private let cancelQueue = DispatchQueue(label: "shrink.video-cancel")
    
    func cancel() {
        cancelQueue.sync {
            isCancelled = true
        }
        reader?.cancelReading()
        assetWriter?.cancelWriting()
        exportSession?.cancelExport()
    }
    
    private var cancelled: Bool {
        cancelQueue.sync { isCancelled }
    }
    
    func compress(inputURL: URL, outputURL: URL, settings: VideoSettings, progressHandler: @escaping @Sendable (Double, Int64?) -> Void) async throws -> Int64 {
        cancelQueue.sync { isCancelled = false }
        
        let isAccessingInput = inputURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessingInput {
                inputURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let asset = AVURLAsset(url: inputURL)
        
        // Get original file size
        var originalSize: Int64 = 10 * 1024 * 1024 // 10MB fallback
        if let attrs = try? FileManager.default.attributesOfItem(atPath: inputURL.path),
           let size = attrs[.size] as? Int64 {
            originalSize = size
        }
        
        // Decide which path to take:
        // - AVAssetExportSession: used when NO actual bitrate compression is needed
        //   (codec conversion only, or ratio >= 0.99). This path uses Apple's internal
        //   optimized DMA pipeline which is significantly faster.
        // - Manual AVAssetReader/Writer: used for actual size compression (ratio < 0.99)
        //   or custom resolution changes. This gives us precise bitrate control.
        let needsActualCompression = settings.targetSizeRatio < 0.99
        let hasCustomResolution = settings.targetResolutionWidth != nil || settings.targetResolutionHeight != nil
        let modifiesAudio = settings.audioMode == "Mute" || settings.audioMode == "Compress"
        
        if !needsActualCompression && !hasCustomResolution && !modifiesAudio {
            // Fast-path: AVAssetExportSession for codec conversion / passthrough
            let chosenPreset = (settings.codec == "HEVC") ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality
            
            let isCompatible = await AVAssetExportSession.compatibility(ofExportPreset: chosenPreset, with: asset, outputFileType: .mp4)
            if isCompatible {
                if let session = AVAssetExportSession(asset: asset, presetName: chosenPreset) {
                    self.exportSession = session
                    
                    let tempOutputURL = outputURL.deletingLastPathComponent().appendingPathComponent(outputURL.lastPathComponent + ".tmp")
                    
                    // Remove temp file if it exists
                    if FileManager.default.fileExists(atPath: tempOutputURL.path) {
                        try? FileManager.default.removeItem(at: tempOutputURL)
                    }
                    
                    session.outputFileType = .mp4
                    session.shouldOptimizeForNetworkUse = true
                    
                    // Estimate output file length once before export
                    var estimatedLength: Int64 = 0
                    if #available(macOS 15.0, *) {
                        estimatedLength = await withCheckedContinuation { continuation in
                            session.estimateOutputFileLength { size, _ in
                                continuation.resume(returning: size)
                            }
                        }
                    } else {
                        estimatedLength = session.estimatedOutputFileLength
                    }
                    
                    // Monitor progress using the states sequence
                    let states = session.states(updateInterval: 0.1)
                    let progressTask = Task {
                        for await state in states {
                            if case .exporting(let progress) = state {
                                let estimatedWritten = estimatedLength > 0 ? Int64(Double(estimatedLength) * progress.fractionCompleted) : nil
                                progressHandler(progress.fractionCompleted, estimatedWritten)
                            }
                        }
                    }
                    
                    defer {
                        progressTask.cancel()
                    }
                    
                    do {
                        try await session.export(to: tempOutputURL, as: .mp4)
                        
                        // Remove destination if it exists
                        if FileManager.default.fileExists(atPath: outputURL.path) {
                            try? FileManager.default.removeItem(at: outputURL)
                        }
                        // Move temp file to final destination
                        try FileManager.default.moveItem(at: tempOutputURL, to: outputURL)
                        
                        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
                        let size = attrs[.size] as? Int64 ?? 0
                        
                        progressHandler(1.0, size)
                    } catch {
                        try? FileManager.default.removeItem(at: tempOutputURL)
                        if error is CancellationError || (error as? AVError)?.code == .operationCancelled {
                            throw NSError(domain: "VideoCompressorError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Operation cancelled."])
                        } else {
                            throw error
                        }
                    }
                    
                    // Return file size
                    let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
                    let size = attrs[.size] as? Int64 ?? 0
                    return size
                }
            }
        }
        
        // Manual pipeline: used for actual compression, resolution changes, and audio modifications.
        // Optimized with: hardware acceleration, speed-prioritized encoding, B-frame disabling,
        // RealTime encoding hint, raised bitrate cap, zero-copy buffers, Metal compatibility.
        return try await compressViaManualPipeline(
            asset: asset,
            inputURL: inputURL,
            outputURL: outputURL,
            settings: settings,
            originalSize: originalSize,
            progressHandler: progressHandler
        )
    }
    
    // MARK: - Manual AVAssetReader/AVAssetWriter Pipeline
    
    private func compressViaManualPipeline(
        asset: AVURLAsset,
        inputURL: URL,
        outputURL: URL,
        settings: VideoSettings,
        originalSize: Int64,
        progressHandler: @escaping @Sendable (Double, Int64?) -> Void
    ) async throws -> Int64 {
        
        let tempOutputURL = outputURL.deletingLastPathComponent().appendingPathComponent(outputURL.lastPathComponent + ".tmp")
        
        // Remove temp file if it exists
        if FileManager.default.fileExists(atPath: tempOutputURL.path) {
            try? FileManager.default.removeItem(at: tempOutputURL)
        }
        
        let isProRes = settings.codec.hasPrefix("ProRes")
        let fileType: AVFileType = isProRes ? .mov : .mp4
        
        guard let reader = try? AVAssetReader(asset: asset),
              let writer = try? AVAssetWriter(outputURL: tempOutputURL, fileType: fileType) else {
            throw NSError(domain: "VideoCompressorError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize video reader/writer."])
        }
        
        self.reader = reader
        self.assetWriter = writer
        
        // Load tracks asynchronously (modern Swift 6 concurrency)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        
        guard let videoTrack = videoTracks.first else {
            throw NSError(domain: "VideoCompressorError", code: 2, userInfo: [NSLocalizedDescriptionKey: "No video track found in file."])
        }
        
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let duration = try await asset.load(.duration).seconds
        let characteristics = try await videoTrack.load(.mediaCharacteristics)
        let isHDR = characteristics.contains(.containsHDRVideo)
        let estimatedDataRate = try await videoTrack.load(.estimatedDataRate)
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        
        var videoInput: AVAssetWriterInput?
        var videoOutput: AVAssetReaderTrackOutput?
        
        // Calculate scaled dimensions (must be even for encoder compatibility)
        var scaledWidth = Int(naturalSize.width)
        var scaledHeight = Int(naturalSize.height)
        
        if let targetW = settings.targetResolutionWidth, let targetH = settings.targetResolutionHeight {
            let isPortrait = (transform.b != 0 && transform.c != 0)
            if isPortrait {
                scaledWidth = min(targetW, targetH)
                scaledHeight = max(targetW, targetH)
            } else {
                scaledWidth = max(targetW, targetH)
                scaledHeight = min(targetW, targetH)
            }
            // Only force even dimensions if we are actively scaling
            scaledWidth = (scaledWidth / 2) * 2
            scaledHeight = (scaledHeight / 2) * 2
        }
        
        // Determine target bitrate
        let sourceBitrate = Double(estimatedDataRate)
        var targetBitrate: Int
        if settings.compressionMethod == .bitrate {
            targetBitrate = settings.targetBitrateKbps * 1000
        } else {
            let baseBitrate = sourceBitrate > 0 ? sourceBitrate : (Double(originalSize) * 8.0 / duration)
            targetBitrate = Int(baseBitrate * settings.targetSizeRatio)
        }
        targetBitrate = max(200000, min(targetBitrate, 100_000_000)) // Clamp between 200kbps and 100Mbps
        
        // Setup Video Output settings with zero-copy IOSurface backing
        var pixelFormats = [
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        if isHDR {
            pixelFormats.insert(kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, at: 0)
        }
        
        let readerOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormats,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerOutputSettings)
        output.alwaysCopiesSampleData = false
        
        // Setup Video Input settings (compression parameters)
        let codecType: AVVideoCodecType
        switch settings.codec {
        case "HEVC":
            codecType = .hevc
        case "H264":
            codecType = .h264
        case "ProRes422":
            codecType = .proRes422
        case "ProRes422HQ":
            codecType = .proRes422HQ
        case "ProRes422LT":
            codecType = .proRes422LT
        case "ProRes422Proxy":
            codecType = .proRes422Proxy
        case "ProRes4444":
            codecType = .proRes4444
        default:
            codecType = .h264
        }
        
        var compressionProperties: [String: Any] = [:]
        
        if !isProRes {
            let profileLevel: CFString
            if settings.codec == "HEVC" {
                profileLevel = isHDR ? kVTProfileLevel_HEVC_Main10_AutoLevel : kVTProfileLevel_HEVC_Main_AutoLevel
            } else {
                profileLevel = kVTProfileLevel_H264_Main_AutoLevel
            }
            compressionProperties[AVVideoAverageBitRateKey] = targetBitrate
            compressionProperties[AVVideoProfileLevelKey] = profileLevel
            compressionProperties[AVVideoAllowFrameReorderingKey] = true
            
            // Prioritize encoding speed over quality for fast compression on large files
            compressionProperties[kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String] = true
            // Use offline encoding mode to maximize processing throughput
            compressionProperties[kVTCompressionPropertyKey_RealTime as String] = false
            // Prevent power-saving CPU throttling for user-initiated background transcode
            compressionProperties[kVTCompressionPropertyKey_MaximizePowerEfficiency as String] = false
            
            // Read original frame rate and keyframe interval
            let nominalFrameRate = try? await videoTrack.load(.nominalFrameRate)
            let fps = Int(nominalFrameRate ?? 30)
            compressionProperties[AVVideoExpectedSourceFrameRateKey] = fps
            compressionProperties[AVVideoMaxKeyFrameIntervalKey] = fps * 2
        }

        // Require hardware-accelerated encoding on Apple Silicon
        let encoderSpec: [String: Any] = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true,
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true
        ]
        
        var colorProperties: [String: Any] = [:]
        if let formatDesc = formatDescriptions.first {
            if let primaries = CMFormatDescriptionGetExtension(formatDesc, extensionKey: kCVImageBufferColorPrimariesKey) {
                colorProperties[AVVideoColorPrimariesKey] = primaries
            }
            if let transfer = CMFormatDescriptionGetExtension(formatDesc, extensionKey: kCVImageBufferTransferFunctionKey) {
                colorProperties[AVVideoTransferFunctionKey] = transfer
            }
            if let matrix = CMFormatDescriptionGetExtension(formatDesc, extensionKey: kCVImageBufferYCbCrMatrixKey) {
                colorProperties[AVVideoYCbCrMatrixKey] = matrix
            }
        }
        
        var writerInputSettings: [String: Any] = [
            AVVideoCodecKey: codecType,
            AVVideoWidthKey: scaledWidth,
            AVVideoHeightKey: scaledHeight,
            AVVideoEncoderSpecificationKey: encoderSpec,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill
        ]
        if !compressionProperties.isEmpty {
            writerInputSettings[AVVideoCompressionPropertiesKey] = compressionProperties
        }
        if !colorProperties.isEmpty {
            writerInputSettings[AVVideoColorPropertiesKey] = colorProperties
        }
        
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: writerInputSettings)
        input.expectsMediaDataInRealTime = false
        input.transform = transform
        
        if reader.canAdd(output) && writer.canAdd(input) {
            reader.add(output)
            writer.add(input)
            videoInput = input
            videoOutput = output
        } else {
            throw NSError(domain: "VideoCompressorError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to configure video pipeline."])
        }
        
        var audioInput: AVAssetWriterInput?
        var audioOutput: AVAssetReaderTrackOutput?
        
        // Setup Audio track if exists and not muted
        if let audioTrack = audioTracks.first, settings.audioMode != "Mute" {
            let output: AVAssetReaderTrackOutput
            let input: AVAssetWriterInput
            
            if settings.audioMode == "Keep" {
                // Passthrough mode: copy compressed audio samples directly without transcoding
                output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
                
                let formatDescriptions = try? await audioTrack.load(.formatDescriptions)
                let formatHint = formatDescriptions?.first
                input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: formatHint)
            } else {
                // Compress mode
                let audioOutputSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM
                ]
                output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: audioOutputSettings)
                
                var writerAudioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVNumberOfChannelsKey: 2,
                    AVSampleRateKey: 44100.0
                ]
                writerAudioSettings[AVEncoderBitRateKey] = settings.audioBitrate
                
                input = AVAssetWriterInput(mediaType: .audio, outputSettings: writerAudioSettings)
            }
            
            input.expectsMediaDataInRealTime = false
            output.alwaysCopiesSampleData = false
            
            if reader.canAdd(output) && writer.canAdd(input) {
                reader.add(output)
                writer.add(input)
                audioInput = input
                audioOutput = output
            }
        }
        
        // Start reading and writing
        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "VideoCompressorError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Reader failed to start."])
        }
        
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "VideoCompressorError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Video writer failed to start."])
        }
        
        writer.startSession(atSourceTime: .zero)
        
        let tracker = ProgressTrackerState()

        // Transcode loops running in parallel on a unified work queue
        try await withThrowingTaskGroup(of: Void.self) { group in
            if let videoInput = videoInput, let videoOutput = videoOutput {
                group.addTask {
                    try await self.transcode(input: videoInput, output: videoOutput, duration: duration, targetBitrate: targetBitrate, progressTracker: tracker, progressHandler: progressHandler)
                }
            }
            
            if let audioInput = audioInput, let audioOutput = audioOutput {
                group.addTask {
                    try await self.transcode(input: audioInput, output: audioOutput, duration: nil, targetBitrate: nil, progressTracker: nil, progressHandler: nil)
                }
            }
            
            try await group.waitForAll()
        }
        
        if cancelled {
            // Clean up partial output file
            try? FileManager.default.removeItem(at: tempOutputURL)
            throw NSError(domain: "VideoCompressorError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Operation cancelled."])
        }
        
        if reader.status == .failed {
            try? FileManager.default.removeItem(at: tempOutputURL)
            throw reader.error ?? NSError(domain: "VideoCompressorError", code: 7, userInfo: [NSLocalizedDescriptionKey: "Reader failed midway during compression."])
        }
        
        // Finish writing and report file size
        return try await withCheckedThrowingContinuation { continuation in
            writer.finishWriting {
                if writer.status == .completed {
                    do {
                        // Remove destination if it exists
                        if FileManager.default.fileExists(atPath: outputURL.path) {
                            try FileManager.default.removeItem(at: outputURL)
                        }
                        // Move temp file to final destination
                        try FileManager.default.moveItem(at: tempOutputURL, to: outputURL)
                        
                        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
                        let size = attrs[.size] as? Int64 ?? 0
                        progressHandler(1.0, size)
                        continuation.resume(returning: size)
                    } catch {
                        try? FileManager.default.removeItem(at: tempOutputURL)
                        continuation.resume(throwing: error)
                    }
                } else {
                    try? FileManager.default.removeItem(at: tempOutputURL)
                    continuation.resume(throwing: writer.error ?? NSError(domain: "VideoCompressorError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize video file."]))
                }
            }
        }
    }
    
    private func transcode(
        input: AVAssetWriterInput,
        output: AVAssetReaderTrackOutput,
        duration: Double?,
        targetBitrate: Int?,
        progressTracker: ProgressTrackerState?,
        progressHandler: (@Sendable (Double, Int64?) -> Void)?
    ) async throws {
        let stream = AsyncStream<CMSampleBuffer?> { continuation in
            input.requestMediaDataWhenReady(on: .global(qos: .userInitiated)) {
                while input.isReadyForMoreMediaData {
                    if self.cancelled {
                        continuation.yield(nil)
                        continuation.finish()
                        return
                    }
                    
                    if let buffer = output.copyNextSampleBuffer() {
                        continuation.yield(buffer)
                    } else {
                        continuation.yield(nil)
                        continuation.finish()
                        return
                    }
                }
            }
        }
        
        for await sampleBuffer in stream {
            guard let buffer = sampleBuffer else { break }
            
            if let duration = duration, let targetBitrate = targetBitrate, let tracker = progressTracker, let handler = progressHandler {
                let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
                let progress = duration > 0 ? (timestamp / duration) : 0.0
                
                tracker.frameCount += 1
                let now = Date()
                if now.timeIntervalSince(tracker.lastReportedTime) >= 0.1 {
                    tracker.lastReportedTime = now
                    let estimatedBytes = Int64((Double(targetBitrate) * duration / 8.0) * progress)
                    handler(progress, estimatedBytes)
                }
            }
            
            if !input.append(buffer) {
                reader?.cancelReading()
                throw NSError(domain: "VideoCompressorError", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to append buffer to writer."])
            }
        }
        
        input.markAsFinished()
    }
}
