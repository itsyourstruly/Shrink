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
    
    private var _activeProcess: Process?
    private let processLock = NSLock()
    private var activeProcess: Process? {
        get {
            processLock.lock()
            defer { processLock.unlock() }
            return _activeProcess
        }
        set {
            processLock.lock()
            defer { processLock.unlock() }
            _activeProcess = newValue
        }
    }
    
    func cancel() {
        cancelQueue.sync {
            isCancelled = true
        }
        reader?.cancelReading()
        assetWriter?.cancelWriting()
        exportSession?.cancelExport()
        processLock.lock()
        _activeProcess?.terminate()
        processLock.unlock()
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
        
        let useFFmpeg = UserDefaults.standard.bool(forKey: "use_ffmpeg_for_video_compression") && ExternalToolManager.isToolAvailable(.ffmpeg)
        if useFFmpeg, let ffmpegPath = ExternalToolManager.findToolPath(.ffmpeg) {
            return try await compressViaFFmpeg(
                ffmpegPath: ffmpegPath,
                inputURL: inputURL,
                outputURL: outputURL,
                settings: settings,
                progressHandler: progressHandler
            )
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
                    
                    let tempOutputURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("mp4")
                    
                    // Remove temp file if it exists
                    if FileManager.default.fileExists(atPath: tempOutputURL.path) {
                        try? FileManager.default.removeItem(at: tempOutputURL)
                    }
                    
                    session.outputFileType = .mp4
                    session.shouldOptimizeForNetworkUse = true
                    
                    // Estimate output file length once before export
                    let estimatedLength = session.estimatedOutputFileLength
                    
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
        
        let isProRes = settings.codec.hasPrefix("ProRes")
        let fileType: AVFileType = isProRes ? .mov : .mp4
        
        let tempOutputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileType == .mov ? "mov" : "mp4")
        
        // Remove temp file if it exists
        
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
        let rawDuration = try await asset.load(.duration).seconds
        let duration = (rawDuration.isNaN || rawDuration <= 0) ? 1.0 : rawDuration
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
        let isFinished = AtomicBool(false)
        let stateLock = NSLock()
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "shrink.video-transcode-serialize")
            input.requestMediaDataWhenReady(on: queue) {
                if isFinished.value { return }
                
                while input.isReadyForMoreMediaData {
                    if self.cancelled {
                        if !isFinished.value {
                            isFinished.set(true)
                            input.markAsFinished()
                            continuation.resume(throwing: NSError(domain: "VideoCompressorError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Operation cancelled."]))
                        }
                        return
                    }
                    
                    let shouldBreak: Bool = autoreleasepool {
                        if let buffer = output.copyNextSampleBuffer() {
                            if let duration = duration, let targetBitrate = targetBitrate, let tracker = progressTracker, let handler = progressHandler {
                                let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
                                let progress = duration > 0 ? (timestamp / duration) : 0.0
                                
                                stateLock.lock()
                                tracker.frameCount += 1
                                let now = Date()
                                let shouldReport = now.timeIntervalSince(tracker.lastReportedTime) >= 0.1
                                if shouldReport {
                                    tracker.lastReportedTime = now
                                }
                                stateLock.unlock()
                                
                                if shouldReport {
                                    let estimatedBytes = Int64((Double(targetBitrate) * duration / 8.0) * progress)
                                    handler(progress, estimatedBytes)
                                }
                            }
                            
                            if !input.append(buffer) {
                                self.reader?.cancelReading()
                                let err = self.assetWriter?.error ?? NSError(domain: "VideoCompressorError", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to append buffer to writer."])
                                if !isFinished.value {
                                    isFinished.set(true)
                                    input.markAsFinished()
                                    continuation.resume(throwing: err)
                                }
                                return true
                            }
                            return false
                        } else {
                            if !isFinished.value {
                                isFinished.set(true)
                                input.markAsFinished()
                                continuation.resume(returning: ())
                            }
                            return true
                        }
                    }
                    if shouldBreak {
                        break
                    }
                }
            }
        }
    }
    
    private func compressViaFFmpeg(
        ffmpegPath: String,
        inputURL: URL,
        outputURL: URL,
        settings: VideoSettings,
        progressHandler: @escaping @Sendable (Double, Int64?) -> Void
    ) async throws -> Int64 {
        do {
            // Try with hardware acceleration
            return try await runFFmpegCompression(
                ffmpegPath: ffmpegPath,
                inputURL: inputURL,
                outputURL: outputURL,
                settings: settings,
                useHardware: true,
                progressHandler: progressHandler
            )
        } catch {
            print("[FFMPEG DEBUG] Hardware accelerated encoding failed: \(error). Falling back to software encoding...")
            // Fall back to software encoding
            return try await runFFmpegCompression(
                ffmpegPath: ffmpegPath,
                inputURL: inputURL,
                outputURL: outputURL,
                settings: settings,
                useHardware: false,
                progressHandler: progressHandler
            )
        }
    }
    
    private func runFFmpegCompression(
        ffmpegPath: String,
        inputURL: URL,
        outputURL: URL,
        settings: VideoSettings,
        useHardware: Bool,
        progressHandler: @escaping @Sendable (Double, Int64?) -> Void
    ) async throws -> Int64 {
        let tempOutputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(outputURL.pathExtension)
        
        // Remove temp file if it exists
        if FileManager.default.fileExists(atPath: tempOutputURL.path) {
            try? FileManager.default.removeItem(at: tempOutputURL)
        }
        
        let asset = AVURLAsset(url: inputURL)
        let duration = try await asset.load(.duration).seconds
        
        var originalSize: Int64 = 10 * 1024 * 1024
        if let attrs = try? FileManager.default.attributesOfItem(atPath: inputURL.path),
           let size = attrs[.size] as? Int64 {
            originalSize = size
        }
        
        var targetBitrate: Int
        if settings.compressionMethod == .bitrate {
            targetBitrate = settings.targetBitrateKbps * 1000
        } else {
            let sourceBitrate: Double
            if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first,
               let estRate = try? await videoTrack.load(.estimatedDataRate) {
                sourceBitrate = Double(estRate)
            } else {
                sourceBitrate = duration > 0 ? (Double(originalSize) * 8.0 / duration) : 5_000_000
            }
            targetBitrate = Int(sourceBitrate * settings.targetSizeRatio)
        }
        targetBitrate = max(200000, min(targetBitrate, 100_000_000))
        
        // Compute quality mapping for VideoToolbox (ranges 1 to 100)
        let q: Int
        if settings.compressionMethod == .bitrate {
            let refBitrate = (settings.codec == "HEVC") ? 2500.0 : 5000.0
            let ratio = Double(settings.targetBitrateKbps) / refBitrate
            if ratio < 1.0 {
                q = Int(15.0 + (ratio * 50.0))
            } else {
                q = Int(65.0 + (min(3.0, ratio - 1.0) / 2.0 * 25.0))
            }
        } else {
            q = Int(15.0 + (settings.targetSizeRatio * 75.0))
        }
        let clampedQ = max(1, min(q, 100))
        
        var args = ["-y", "-i", inputURL.path]
        
        switch settings.codec {
        case "HEVC":
            if useHardware {
                args += ["-c:v", "hevc_videotoolbox", "-q:v", "\(clampedQ)", "-tag:v", "hvc1"]
            } else {
                args += ["-c:v", "libx265", "-b:v", "\(targetBitrate)", "-preset", "veryfast", "-tag:v", "hvc1"]
            }
        case "H264":
            if useHardware {
                args += ["-c:v", "h264_videotoolbox", "-q:v", "\(clampedQ)"]
            } else {
                args += ["-c:v", "libx264", "-b:v", "\(targetBitrate)", "-preset", "veryfast"]
            }
        case "ProRes422":
            let encoder = useHardware ? "prores_videotoolbox" : "prores_ks"
            args += ["-c:v", encoder, "-profile:v", "2"]
        case "ProRes422HQ":
            let encoder = useHardware ? "prores_videotoolbox" : "prores_ks"
            args += ["-c:v", encoder, "-profile:v", "3"]
        case "ProRes422LT":
            let encoder = useHardware ? "prores_videotoolbox" : "prores_ks"
            args += ["-c:v", encoder, "-profile:v", "1"]
        case "ProRes422Proxy":
            let encoder = useHardware ? "prores_videotoolbox" : "prores_ks"
            args += ["-c:v", encoder, "-profile:v", "0"]
        case "ProRes4444":
            let encoder = useHardware ? "prores_videotoolbox" : "prores_ks"
            args += ["-c:v", encoder, "-profile:v", "4"]
        default:
            if useHardware {
                args += ["-c:v", "h264_videotoolbox", "-q:v", "\(clampedQ)"]
            } else {
                args += ["-c:v", "libx264", "-b:v", "\(targetBitrate)", "-preset", "veryfast"]
            }
        }
        
        if let targetW = settings.targetResolutionWidth, let targetH = settings.targetResolutionHeight {
            var scaledWidth = targetW
            var scaledHeight = targetH
            
            if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first {
                let naturalSize = try await videoTrack.load(.naturalSize)
                let transform = try await videoTrack.load(.preferredTransform)
                let isPortrait = (transform.b != 0 && transform.c != 0)
                if isPortrait {
                    scaledWidth = min(targetW, targetH)
                    scaledHeight = max(targetW, targetH)
                } else {
                    scaledWidth = max(targetW, targetH)
                    scaledHeight = min(targetW, targetH)
                }
            }
            scaledWidth = (scaledWidth / 2) * 2
            scaledHeight = (scaledHeight / 2) * 2
            
            args += ["-vf", "scale=w=\(scaledWidth):h=\(scaledHeight)"]
        }
        
        switch settings.audioMode {
        case "Mute":
            args += ["-an"]
        case "Keep":
            args += ["-c:a", "copy"]
        case "Compress":
            args += ["-c:a", "aac", "-b:a", "\(settings.audioBitrate)"]
        default:
            args += ["-c:a", "copy"]
        }
        
        args.append(tempOutputURL.path)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = args
        
        self.activeProcess = process
        defer { self.activeProcess = nil }
        
        if cancelled {
            throw NSError(domain: "VideoCompressorError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Operation cancelled."])
        }
        
        let outputPipe = Pipe()
        process.standardError = outputPipe
        process.standardOutput = Pipe()
        
        var accumulatedStderr = ""
        let stderrLock = NSLock()
        
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                outputPipe.fileHandleForReading.readabilityHandler = nil
            } else if let chunk = String(data: data, encoding: .utf8) {
                stderrLock.lock()
                accumulatedStderr += chunk
                stderrLock.unlock()
                
                if let processedSeconds = self.parseFFmpegTime(chunk) {
                    let progress = duration > 0 ? min(0.99, processedSeconds / duration) : 0.0
                    let estimatedBytes = Int64(Double(targetBitrate) * duration / 8.0 * progress)
                    progressHandler(progress, estimatedBytes)
                }
            }
        }
        
        try await runProcessAsync(process, errorAccumulator: {
            stderrLock.lock()
            defer { stderrLock.unlock() }
            return accumulatedStderr
        })
        
        if cancelled {
            try? FileManager.default.removeItem(at: tempOutputURL)
            throw NSError(domain: "VideoCompressorError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Operation cancelled."])
        }
        
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.moveItem(at: tempOutputURL, to: outputURL)
        
        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = attrs[.size] as? Int64 ?? 0
        progressHandler(1.0, size)
        
        return size
    }
    
    private func parseFFmpegTime(_ line: String) -> Double? {
        guard let range = line.range(of: "time=") else { return nil }
        let timePart = line[range.upperBound...]
        let cleanTimeStr = timePart.prefix { $0 != " " && $0 != "\n" && $0 != "\r" && $0 != "," }
        let parts = cleanTimeStr.split(separator: ":")
        if parts.count == 3 {
            if let hours = Double(parts[0]),
               let minutes = Double(parts[1]),
               let seconds = Double(parts[2]) {
                return hours * 3600.0 + minutes * 60.0 + seconds
            }
        } else if let seconds = Double(cleanTimeStr) {
            return seconds
        }
        return nil
    }
    
    private func runProcessAsync(_ process: Process, errorAccumulator: (() -> String)? = nil) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let details = errorAccumulator?() ?? ""
                    let cleanDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
                    let displayMsg = cleanDetails.isEmpty ? "Process exit with code \(proc.terminationStatus)" : cleanDetails
                    continuation.resume(throwing: NSError(domain: "VideoCompressorError", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: displayMsg]))
                }
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
