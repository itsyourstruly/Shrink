//
//  AudioCompressor.swift
//  Shrink
//

import Foundation
import AVFoundation

extension AVAssetWriterInput: @retroactive @unchecked Sendable {}
extension AVAssetReaderTrackOutput: @retroactive @unchecked Sendable {}
extension AVAssetWriter: @retroactive @unchecked Sendable {}
extension AVAssetReader: @retroactive @unchecked Sendable {}

nonisolated final class AudioCompressor: @unchecked Sendable {
    
    private var assetReader: AVAssetReader?
    private var assetWriter: AVAssetWriter?
    private var isCancelled = false
    
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
        isCancelled = true
        assetReader?.cancelReading()
        assetWriter?.cancelWriting()
        processLock.lock()
        _activeProcess?.terminate()
        processLock.unlock()
    }
    
    func compress(inputURL: URL, outputURL: URL, settings: AudioSettings) async throws -> Int64 {
        isCancelled = false
        
        let isAccessingInput = inputURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessingInput {
                inputURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let useFFmpeg = UserDefaults.standard.bool(forKey: "use_ffmpeg_for_audio_compression") && ExternalToolManager.isToolAvailable(.ffmpeg)
        if useFFmpeg, let ffmpegPath = ExternalToolManager.findToolPath(.ffmpeg) {
            return try await compressViaFFmpeg(
                ffmpegPath: ffmpegPath,
                inputURL: inputURL,
                outputURL: outputURL,
                settings: settings
            )
        }
        
        let asset = AVURLAsset(url: inputURL)
        
        let tempOutputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        
        if FileManager.default.fileExists(atPath: tempOutputURL.path) {
            try? FileManager.default.removeItem(at: tempOutputURL)
        }
        
        guard let reader = try? AVAssetReader(asset: asset),
              let writer = try? AVAssetWriter(outputURL: tempOutputURL, fileType: .m4a) else {
            throw NSError(domain: "AudioCompressorError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize audio reader/writer."])
        }
        
        self.assetReader = reader
        self.assetWriter = writer
        
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw NSError(domain: "AudioCompressorError", code: 2, userInfo: [NSLocalizedDescriptionKey: "No audio track found in file."])
        }
        
        // Setup Output (PCM decode)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM
        ]
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        
        // Setup Input (AAC compress)
        let writerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100.0,
            AVEncoderBitRateKey: settings.bitrate
        ]
        
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
        input.expectsMediaDataInRealTime = false
        
        if reader.canAdd(output) && writer.canAdd(input) {
            reader.add(output)
            writer.add(input)
        } else {
            throw NSError(domain: "AudioCompressorError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to configure audio pipeline."])
        }
        
        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "AudioCompressorError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Audio reader failed to start."])
        }
        
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "AudioCompressorError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Audio writer failed to start."])
        }
        
        writer.startSession(atSourceTime: .zero)
        
        let isFinished = AtomicBool(false)
        let stateLock = NSLock()
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let queue = DispatchQueue(label: "shrink.audio-compress")
            input.requestMediaDataWhenReady(on: queue) {
                stateLock.lock()
                if isFinished.value {
                    stateLock.unlock()
                    return
                }
                stateLock.unlock()
                
                while input.isReadyForMoreMediaData {
                    if self.isCancelled {
                        stateLock.lock()
                        if !isFinished.value {
                            isFinished.set(true)
                            input.markAsFinished()
                            continuation.resume()
                        }
                        stateLock.unlock()
                        return
                    }
                    
                    let shouldBreak: Bool = autoreleasepool {
                        if let sampleBuffer = output.copyNextSampleBuffer() {
                            input.append(sampleBuffer)
                            return false
                        } else {
                            stateLock.lock()
                            if !isFinished.value {
                                isFinished.set(true)
                                input.markAsFinished()
                                continuation.resume()
                            }
                            stateLock.unlock()
                            return true
                        }
                    }
                    if shouldBreak {
                        break
                    }
                }
            }
        }
        
        if isCancelled {
            try? FileManager.default.removeItem(at: tempOutputURL)
            throw NSError(domain: "AudioCompressorError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Operation cancelled."])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            writer.finishWriting {
                if writer.status == .completed {
                    do {
                        if FileManager.default.fileExists(atPath: outputURL.path) {
                            try FileManager.default.removeItem(at: outputURL)
                        }
                        try FileManager.default.moveItem(at: tempOutputURL, to: outputURL)
                        
                        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
                        let size = attrs[.size] as? Int64 ?? 0
                        continuation.resume(returning: size)
                    } catch {
                        try? FileManager.default.removeItem(at: tempOutputURL)
                        continuation.resume(throwing: error)
                    }
                } else {
                    try? FileManager.default.removeItem(at: tempOutputURL)
                    continuation.resume(throwing: writer.error ?? NSError(domain: "AudioCompressorError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize audio file."]))
                }
            }
        }
    }
    
    private func compressViaFFmpeg(
        ffmpegPath: String,
        inputURL: URL,
        outputURL: URL,
        settings: AudioSettings
    ) async throws -> Int64 {
        let tempOutputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(settings.format.lowercased())
        
        // Remove temp file if it exists
        if FileManager.default.fileExists(atPath: tempOutputURL.path) {
            try? FileManager.default.removeItem(at: tempOutputURL)
        }
        
        var args = ["-y", "-i", inputURL.path]
        let ext = settings.format.lowercased()
        if ext == "mp3" {
            args += ["-acodec", "libmp3lame", "-b:a", "\(settings.bitrate)", tempOutputURL.path]
        } else {
            args += ["-acodec", "aac", "-b:a", "\(settings.bitrate)", tempOutputURL.path]
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = args
        
        self.activeProcess = process
        defer { self.activeProcess = nil }
        
        if isCancelled {
            throw NSError(domain: "AudioCompressorError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Operation cancelled."])
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
            }
        }
        
        try await runProcessAsync(process, errorAccumulator: {
            stderrLock.lock()
            defer { stderrLock.unlock() }
            return accumulatedStderr
        })
        
        if isCancelled {
            try? FileManager.default.removeItem(at: tempOutputURL)
            throw NSError(domain: "AudioCompressorError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Operation cancelled."])
        }
        
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.moveItem(at: tempOutputURL, to: outputURL)
        
        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        return attrs[.size] as? Int64 ?? 0
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
                    continuation.resume(throwing: NSError(domain: "AudioCompressorError", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: displayMsg]))
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
