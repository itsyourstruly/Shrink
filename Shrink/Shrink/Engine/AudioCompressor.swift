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
    
    func cancel() {
        isCancelled = true
        assetReader?.cancelReading()
        assetWriter?.cancelWriting()
    }
    
    func compress(inputURL: URL, outputURL: URL, settings: AudioSettings) async throws -> Int64 {
        isCancelled = false
        
        let isAccessingInput = inputURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessingInput {
                inputURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let asset = AVURLAsset(url: inputURL)
        
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        guard let reader = try? AVAssetReader(asset: asset),
              let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .m4a) else {
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
                    
                    if let sampleBuffer = output.copyNextSampleBuffer() {
                        input.append(sampleBuffer)
                    } else {
                        stateLock.lock()
                        if !isFinished.value {
                            isFinished.set(true)
                            input.markAsFinished()
                            continuation.resume()
                        }
                        stateLock.unlock()
                        break
                    }
                }
            }
        }
        
        if isCancelled {
            throw NSError(domain: "AudioCompressorError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Operation cancelled."])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            writer.finishWriting {
                if writer.status == .completed {
                    do {
                        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
                        let size = attrs[.size] as? Int64 ?? 0
                        continuation.resume(returning: size)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(throwing: writer.error ?? NSError(domain: "AudioCompressorError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize audio file."]))
                }
            }
        }
    }
}
