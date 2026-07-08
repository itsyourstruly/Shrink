//
//  FileMetadataReader.swift
//  Shrink
//

import Foundation
import ImageIO
import AVFoundation

nonisolated struct FileMetadata {
    var width: Int?
    var height: Int?
    var duration: Double?
    var frameRate: Double?
}

nonisolated class FileMetadataReader {
    
    static func readMetadata(for url: URL) async -> FileMetadata {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        let ext = url.pathExtension.lowercased()
        var meta = FileMetadata()
        
        // 1. Process Images
        if ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "webp", "bmp", "raw", "psd", "tga", "dds", "exr", "hdr", "pcx", "eps", "pgm", "ppm", "pbm", "pnm", "avif", "jp2", "j2k", "ico", "fits", "xcf", "pix", "mng", "cr2", "nef", "arw", "raf", "orf", "rw2", "pef", "erf", "mef", "mos", "sr2", "srf", "dcr", "kdc", "crw", "x3f", "dng"].contains(ext) {
            // Try ImageMagick first for advanced formats
            let isAdvanced = ["psd", "tga", "dds", "exr", "hdr", "pcx", "eps", "pgm", "ppm", "pbm", "pnm", "avif", "jp2", "j2k", "ico", "fits", "xcf", "pix", "mng", "cr2", "nef", "arw", "raf", "orf", "rw2", "pef", "erf", "mef", "mos", "sr2", "srf", "dcr", "kdc", "crw", "x3f", "dng"].contains(ext)
            let useMagick = UserDefaults.standard.bool(forKey: "use_magick_for_image_compression") || UserDefaults.standard.bool(forKey: "use_magick_for_image_conversion")
            if useMagick && isAdvanced, let magickPath = ExternalToolManager.findToolPath(.magick) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: magickPath)
                let inputPath = ext == "psd" ? "\(url.path)[0]" : url.path
                process.arguments = ["identify", "-format", "%w %h", inputPath]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        if let data = try? pipe.fileHandleForReading.readToEnd(),
                           let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                            let parts = output.components(separatedBy: " ")
                            if parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) {
                                meta.width = w
                                meta.height = h
                                return meta
                            }
                        }
                    }
                } catch {
                    // Fall back to native ImageIO
                }
            }
            
            if let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
               let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {
                meta.width = properties[kCGImagePropertyPixelWidth] as? Int
                meta.height = properties[kCGImagePropertyPixelHeight] as? Int
            }
        }
        // 2. Process Videos
        else if ["mp4", "mov", "m4v", "mkv", "avi", "webm"].contains(ext) {
            let asset = AVURLAsset(url: url)
            do {
                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                if let videoTrack = videoTracks.first {
                    let size = try await videoTrack.load(.naturalSize)
                    let transform = try await videoTrack.load(.preferredTransform)
                    let nominalFrameRate = try? await videoTrack.load(.nominalFrameRate)
                    
                    // Check if transform rotates the video (portrait orientation)
                    let isPortrait = (transform.b != 0 && transform.c != 0)
                    meta.width = Int(isPortrait ? size.height : size.width)
                    meta.height = Int(isPortrait ? size.width : size.height)
                    if let nominalFrameRate = nominalFrameRate {
                        meta.frameRate = Double(nominalFrameRate)
                    }
                }
                
                let dur = try await asset.load(.duration)
                meta.duration = dur.seconds
            } catch {
                print("Failed to read video metadata: \(error)")
            }
        }
        // 3. Process Audio files
        else if ["mp3", "m4a", "wav", "aac", "flac", "ogg"].contains(ext) {
            let asset = AVURLAsset(url: url)
            do {
                let dur = try await asset.load(.duration)
                meta.duration = dur.seconds
            } catch {
                print("Failed to read audio duration: \(error)")
            }
        }
        
        return meta
    }
}
