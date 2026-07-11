//
//  FileConverter.swift
//  Shrink
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AVFoundation
import PDFKit
import AppKit
import CoreMedia
import CoreVideo

nonisolated class FileConverter: @unchecked Sendable {
    
    private var activeProcess: Process?
    private var activeAudioCompressor: AudioCompressor?
    private var activeVideoCompressor: VideoCompressor?
    private var activeArchiveCompressor: ArchiveCompressor?
    private var isCancelled = false
    private let lock = NSLock()
    
    func cancel() {
        lock.lock()
        isCancelled = true
        activeProcess?.terminate()
        activeAudioCompressor?.cancel()
        activeVideoCompressor?.cancel()
        activeArchiveCompressor?.cancel()
        lock.unlock()
    }
    
    private var cancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }
    
    // Supported extensions mapping
    static let supportedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "webp", "heic", "heif", "tiff", "tif", "gif", "bmp", "svg",
        "cr2", "nef", "arw", "psd", "tga", "dds", "exr", "hdr", "pcx", "eps", "pgm", "ppm", "pbm",
        "pnm", "avif", "jp2", "j2k", "ico", "fits", "xcf", "pix", "mng", "raf", "orf", "rw2",
        "pef", "erf", "mef", "mos", "sr2", "srf", "dcr", "kdc", "crw", "x3f", "dng",
        "mp4", "mov", "mkv", "avi", "webm", "flv", "wmv",
        "mp3", "m4a", "wav", "flac", "aac", "ogg",
        "pdf", "docx", "doc", "txt", "rtf", "epub", "md", "markdown", "html", "odt",
        "zip", "7z", "tar", "gz", "tgz"
    ]
    
    static func enabledTargetFormats(forExtension ext: String) -> [String] {
        return targetFormats(forExtension: ext).filter { format in
            let key = "convert_\(format.lowercased())_enabled"
            let isEnabled = UserDefaults.standard.object(forKey: key) == nil ? true : UserDefaults.standard.bool(forKey: key)
            guard isEnabled else { return false }
            
            if let tool = toolRequired(from: ext, to: format) {
                switch tool {
                case .ffmpeg:
                    return UserDefaults.standard.bool(forKey: "use_ffmpeg") && ExternalToolManager.isToolAvailable(.ffmpeg)
                case .magick:
                    return UserDefaults.standard.bool(forKey: "use_magick") && ExternalToolManager.isToolAvailable(.magick)
                case .pandoc:
                    return UserDefaults.standard.bool(forKey: "use_pandoc") && ExternalToolManager.isToolAvailable(.pandoc)
                case .sevenZip:
                    return UserDefaults.standard.bool(forKey: "use_sevenzip_for_archive") && ExternalToolManager.isToolAvailable(.sevenZip)
                }
            }
            return true
        }
    }

    static func targetFormats(forExtension ext: String) -> [String] {
        let cleanExt = ext.lowercased()
        switch cleanExt {
        case "psd", "tga", "dds", "exr", "hdr", "pcx", "eps", "pgm", "ppm", "pbm", "pnm", "avif", "jp2", "j2k", "ico", "fits", "xcf", "pix", "mng", "cr2", "nef", "arw", "raf", "orf", "rw2", "pef", "erf", "mef", "mos", "sr2", "srf", "dcr", "kdc", "crw", "x3f", "dng":
            return ["png", "jpeg", "webp", "pdf", "avif", "heic", "tiff"]
        case "png":
            return ["jpeg", "webp", "heic", "tiff", "gif", "bmp", "pdf", "avif", "psd", "tga", "dds", "exr", "hdr", "pcx", "eps", "ico"]
        case "jpeg", "jpg":
            return ["png", "webp", "heic", "tiff", "gif", "pdf", "avif", "psd", "tga", "dds", "exr", "hdr", "pcx", "eps", "ico"]
        case "webp":
            return ["png", "jpeg", "gif", "avif"]
        case "heic", "heif":
            return ["jpeg", "png", "webp", "avif"]
        case "tiff", "tif":
            return ["jpeg", "png", "pdf", "avif"]
        case "gif":
            return ["mp4", "webm", "png", "jpeg", "avif"]
        case "svg":
            return ["png", "jpeg", "pdf"]
        case "mp4":
            return ["mov", "mkv", "avi", "webm", "flv", "gif", "mp3"]
        case "mov":
            return ["mp4", "mkv", "avi", "prores"]
        case "mkv":
            return ["mp4", "mov", "avi"]
        case "avi":
            return ["mp4", "mov", "mkv"]
        case "webm":
            return ["mp4", "mov", "gif"]
        case "wmv":
            return ["mp4", "mov"]
        case "mp3":
            return ["wav", "m4a", "flac", "aac", "ogg"]
        case "m4a":
            return ["mp3", "wav", "flac"]
        case "wav":
            return ["mp3", "m4a", "flac", "aac"]
        case "flac":
            return ["wav", "mp3", "m4a"]
        case "ogg":
            return ["mp3", "wav"]
        case "pdf":
            return ["jpeg", "png", "docx", "txt", "epub", "html", "odt", "md"]
        case "docx", "doc":
            return ["pdf", "txt", "rtf", "epub", "html", "odt", "md"]
        case "txt":
            return ["pdf", "docx", "epub", "html", "md"]
        case "rtf":
            return ["pdf", "docx", "html", "md"]
        case "epub":
            return ["pdf", "mobi", "txt", "docx", "html", "md"]
        case "md", "markdown":
            return ["pdf", "docx", "html", "epub", "txt", "rtf", "odt"]
        case "html":
            return ["pdf", "docx", "md", "epub", "txt", "rtf", "odt"]
        case "odt":
            return ["pdf", "docx", "md", "epub", "txt", "rtf", "html"]
        case "zip":
            return ["7z", "tar.gz"]
        case "7z":
            return ["zip"]
        case "tar", "gz", "tgz":
            return ["zip", "7z"]
        default:
            return []
        }
    }
    
    static func toolRequired(from src: String, to dst: String) -> ExternalTool? {
        let src = src.lowercased()
        let dst = dst.lowercased()
        
        let useFFmpegVideo = UserDefaults.standard.bool(forKey: "use_ffmpeg_for_video_conversion") && ExternalToolManager.isToolAvailable(.ffmpeg)
        let useFFmpegAudio = UserDefaults.standard.bool(forKey: "use_ffmpeg_for_audio_conversion") && ExternalToolManager.isToolAvailable(.ffmpeg)
        let useMagick = UserDefaults.standard.bool(forKey: "use_magick_for_image_conversion") && ExternalToolManager.isToolAvailable(.magick)
        let usePandoc = UserDefaults.standard.bool(forKey: "use_pandoc_for_document_conversion") && ExternalToolManager.isToolAvailable(.pandoc)
        
        // 1. Image Conversions
        let nonNativeImageFormats = ["tga", "dds", "pcx", "pgm", "ppm", "pbm", "pnm", "fits", "xcf", "pix", "mng"]
        let advancedImageFormats = [
            "psd", "tga", "dds", "exr", "hdr", "pcx", "eps", "pgm", "ppm", "pbm", "pnm",
            "avif", "jp2", "j2k", "ico", "fits", "xcf", "pix", "mng",
            "cr2", "nef", "arw", "raf", "orf", "rw2", "pef", "erf", "mef", "mos", "sr2", "srf", "dcr", "kdc", "crw", "x3f", "dng"
        ]
        
        let isSrcImage = advancedImageFormats.contains(src) || ["png", "jpg", "jpeg", "webp", "heic", "heif", "tiff", "tif", "gif", "bmp"].contains(src)
        let isDstImage = advancedImageFormats.contains(dst) || ["png", "jpg", "jpeg", "webp", "heic", "heif", "tiff", "tif", "gif", "bmp"].contains(dst)
        
        if isSrcImage || isDstImage {
            if useMagick && (advancedImageFormats.contains(src) || advancedImageFormats.contains(dst)) {
                return .magick
            }
            if nonNativeImageFormats.contains(src) || nonNativeImageFormats.contains(dst) {
                return .magick
            }
            return nil
        }
        
        // 2. Document Conversions
        let nonNativeDocFormats = ["epub", "mobi"]
        let pandocFormats = ["epub", "mobi", "md", "markdown", "html", "odt", "pdf", "docx", "doc", "txt", "rtf"]
        
        let isSrcDoc = pandocFormats.contains(src)
        let isDstDoc = pandocFormats.contains(dst)
        
        if isSrcDoc && isDstDoc {
            if src == "pdf" && dst == "docx" {
                return .pandoc
            }
            if nonNativeDocFormats.contains(src) || nonNativeDocFormats.contains(dst) {
                return .pandoc
            }
            if usePandoc {
                // If the user preferred pandoc, let's use it for non-trivial doc conversions
                let isNative = (src == "pdf" && dst == "txt") || 
                               (src == "pdf" && ["jpeg", "jpg", "png"].contains(dst)) ||
                               (["docx", "rtf", "doc"].contains(src) && dst == "txt") ||
                               (src == "txt" && dst == "docx") ||
                               (["docx", "doc", "rtf", "txt"].contains(src) && dst == "pdf")
                if !isNative {
                    return .pandoc
                }
            }
            return nil
        }
        
        // 3. Audio & Video Conversions
        let nonNativeVideoFormats = ["webm", "mkv", "avi", "flv", "wmv"]
        let audioFormats = ["mp3", "ogg", "wav", "m4a", "flac", "aac"]
        
        let isAudioConv = audioFormats.contains(src) && audioFormats.contains(dst)
        
        if isAudioConv {
            if src == "ogg" || dst == "ogg" || dst == "mp3" {
                return .ffmpeg
            }
            if useFFmpegAudio {
                return .ffmpeg
            }
            return nil
        } else {
            // Video conversion
            if nonNativeVideoFormats.contains(src) || nonNativeVideoFormats.contains(dst) || src == "ogg" || dst == "ogg" || dst == "mp3" {
                return .ffmpeg
            }
            if useFFmpegVideo {
                if src == "gif" && ["mp4", "webm"].contains(dst) {
                    return .ffmpeg
                }
                if ["mp4", "mov"].contains(src) && ["mp4", "mov"].contains(dst) {
                    return nil
                }
                if ["mp3", "m4a", "wav", "flac", "aac"].contains(src) || ["mp3", "m4a", "wav", "flac", "aac"].contains(dst) {
                    return .ffmpeg
                }
            }
            return nil
        }
    }
    
    func convert(
        inputURL: URL,
        outputURL: URL,
        targetFormat: String,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> Int64 {
        resetCancelled()
        
        let srcExt = inputURL.pathExtension.lowercased()
        let dstExt = targetFormat.lowercased()
        
        print("[CONVERT] Converting \(inputURL.lastPathComponent) to .\(dstExt)")
        
        // Route conversion based on types
        if isImage(srcExt) && isImage(dstExt) {
            return try await convertImage(inputURL: inputURL, outputURL: outputURL, targetFormat: dstExt, progressHandler: progressHandler)
        } else if isVideo(srcExt) && isVideo(dstExt) {
            return try await convertVideo(inputURL: inputURL, outputURL: outputURL, targetFormat: dstExt, progressHandler: progressHandler)
        } else if isAudio(srcExt) && isAudio(dstExt) {
            return try await convertAudio(inputURL: inputURL, outputURL: outputURL, targetFormat: dstExt, progressHandler: progressHandler)
        } else if isDocument(srcExt) && isDocument(dstExt) {
            return try await convertDocument(inputURL: inputURL, outputURL: outputURL, targetFormat: dstExt, progressHandler: progressHandler)
        } else if isArchive(srcExt) && isArchive(dstExt) {
            return try await convertArchive(inputURL: inputURL, outputURL: outputURL, targetFormat: dstExt, progressHandler: progressHandler)
        } else {
            throw NSError(domain: "FileConverterError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported conversion direction from .\(srcExt) to .\(dstExt)."])
        }
    }
    
    private func isImage(_ ext: String) -> Bool {
        return ["png", "jpg", "jpeg", "webp", "heic", "heif", "tiff", "tif", "gif", "bmp", "svg", "cr2", "nef", "arw", "pdf", "dng", "psd", "tga", "dds", "exr", "hdr", "pcx", "eps", "pgm", "ppm", "pbm", "pnm", "avif", "jp2", "j2k", "ico", "fits", "xcf", "pix", "mng", "raf", "orf", "rw2", "pef", "erf", "mef", "mos", "sr2", "srf", "dcr", "kdc", "crw", "x3f"].contains(ext)
    }
    
    private func isVideo(_ ext: String) -> Bool {
        return ["mp4", "mov", "mkv", "avi", "webm", "flv", "wmv", "prores", "gif", "mp3"].contains(ext)
    }
    
    private func isAudio(_ ext: String) -> Bool {
        return ["mp3", "m4a", "wav", "flac", "aac", "ogg"].contains(ext)
    }
    
    private func isDocument(_ ext: String) -> Bool {
        return ["pdf", "docx", "doc", "txt", "rtf", "epub", "mobi", "md", "markdown", "html", "odt"].contains(ext)
    }
    
    private func isArchive(_ ext: String) -> Bool {
        return ["zip", "7z", "tar", "gz", "tgz", "tar.gz"].contains(ext)
    }
    
    // MARK: - Image Conversion
    private func convertImage(
        inputURL: URL,
        outputURL: URL,
        targetFormat: String,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> Int64 {
        progressHandler(0.1)
        
        let srcExt = inputURL.pathExtension.lowercased()
        let useMagick = UserDefaults.standard.bool(forKey: "use_magick_for_image_conversion") && ExternalToolManager.isToolAvailable(.magick)
        
        if useMagick {
            if let magickPath = ExternalToolManager.findToolPath(.magick) {
                progressHandler(0.3)
                let inputPath = srcExt == "psd" ? "\(inputURL.path)[0]" : inputURL.path
                let args = [inputPath, outputURL.path]
                try await runExternalProcess(executablePath: magickPath, arguments: args, progressHandler: progressHandler)
                return try getFileSize(outputURL)
            }
        }
        
        // Special case SVG -> Raster/PDF
        if srcExt == "svg" {
            progressHandler(0.3)
            guard let nsImage = NSImage(contentsOf: inputURL),
                  let tiffData = nsImage.tiffRepresentation,
                  let imageSource = CGImageSourceCreateWithData(tiffData as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "FileConverterError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to load and rasterize SVG file."])
            }
            progressHandler(0.7)
            if targetFormat == "pdf" {
                try saveCGImageToPDF(cgImage, outputURL: outputURL)
            } else {
                try saveCGImage(cgImage, to: outputURL, format: targetFormat)
            }
            progressHandler(1.0)
            return try getFileSize(outputURL)
        }
        
        // Special case RAW -> DNG
        if ["cr2", "nef", "arw", "raf", "orf", "rw2", "pef", "erf", "mef", "mos", "sr2", "srf", "dcr", "kdc", "crw", "x3f"].contains(srcExt) && targetFormat == "dng" {
            progressHandler(0.3)
            guard let imageSource = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "FileConverterError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to load RAW image source."])
            }
            progressHandler(0.6)
            try saveCGImage(cgImage, to: outputURL, format: "dng")
            progressHandler(1.0)
            return try getFileSize(outputURL)
        }
        
        // Special case Image -> PDF
        if targetFormat == "pdf" {
            progressHandler(0.3)
            guard let imageSource = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "FileConverterError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to load source image."])
            }
            progressHandler(0.7)
            try saveCGImageToPDF(cgImage, outputURL: outputURL)
            progressHandler(1.0)
            return try getFileSize(outputURL)
        }
        
        // General Image -> Image
        guard let imageSource = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            let nonNativeImageFormats = ["tga", "dds", "pcx", "pgm", "ppm", "pbm", "pnm", "fits", "xcf", "pix", "mng"]
            if nonNativeImageFormats.contains(srcExt) {
                throw NSError(domain: "FileConverterError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Converting .\(srcExt) files requires the ImageMagick plugin. Please install and enable it in Settings -> Plugins."])
            }
            throw NSError(domain: "FileConverterError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to load source image. Format .\(srcExt) may not be natively supported on this macOS version."])
        }
        progressHandler(0.6)
        try saveCGImage(cgImage, to: outputURL, format: targetFormat)
        progressHandler(1.0)
        return try getFileSize(outputURL)
    }
    
    private func getUTType(for format: String) -> UTType {
        switch format.lowercased() {
        case "png": return .png
        case "webp": return UTType("org.webmproject.webp") ?? .png
        case "heic", "heif": return .heic
        case "tiff", "tif": return .tiff
        case "bmp": return .bmp
        case "gif": return .gif
        case "dng": return UTType("com.adobe.raw-dng") ?? .tiff
        default: return .jpeg
        }
    }
    
    private func saveCGImage(_ cgImage: CGImage, to url: URL, format: String) throws {
        let uti = getUTType(for: format)
        
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, uti.identifier as CFString, 1, nil) else {
            throw NSError(domain: "FileConverterError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to create destination for image conversion."])
        }
        
        // Strip alpha if saving to JPEG/HEIC
        var finalImage = cgImage
        if uti != .png && uti != .gif {
            if let opaque = ImageCompressor.makeOpaqueImage(from: cgImage) {
                finalImage = opaque
            }
        }
        
        CGImageDestinationAddImage(destination, finalImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "FileConverterError", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize image destination."])
        }
    }
    
    private func saveCGImageToPDF(_ cgImage: CGImage, outputURL: URL) throws {
        guard let consumer = CGDataConsumer(url: outputURL as CFURL) else {
            throw NSError(domain: "FileConverterError", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to create PDF consumer."])
        }
        
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        var mediaBox = CGRect(x: 0, y: 0, width: width, height: height)
        
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "FileConverterError", code: 9, userInfo: [NSLocalizedDescriptionKey: "Failed to create PDF context."])
        }
        
        pdfContext.beginPage(mediaBox: &mediaBox)
        pdfContext.draw(cgImage, in: mediaBox)
        pdfContext.endPage()
        pdfContext.closePDF()
    }
    
    // MARK: - Video Conversion
    private func convertVideo(
        inputURL: URL,
        outputURL: URL,
        targetFormat: String,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> Int64 {
        let srcExt = inputURL.pathExtension.lowercased()
        let dstExt = targetFormat.lowercased()
        
        let useFFmpeg = UserDefaults.standard.bool(forKey: "use_ffmpeg_for_video_conversion") && ExternalToolManager.isToolAvailable(.ffmpeg)
        
        let tool = FileConverter.toolRequired(from: srcExt, to: dstExt)
        if tool == .ffmpeg {
            if useFFmpeg, let ffmpegPath = ExternalToolManager.findToolPath(.ffmpeg) {
                var args = ["-y", "-i", inputURL.path]
                if dstExt == "mp3" {
                    args += ["-vn", "-acodec", "libmp3lame", "-ab", "192k", outputURL.path]
                } else if dstExt == "gif" {
                    args += ["-vf", "fps=15,scale=480:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse", "-loop", "0", outputURL.path]
                } else if dstExt == "webm" {
                    args += ["-c:v", "libvpx-vp9", "-c:a", "libvorbis", outputURL.path]
                } else {
                    // General video conversion to container
                    args += ["-c:v", "libx264", "-c:a", "aac", "-b:a", "128k", outputURL.path]
                }
                
                try await runExternalProcess(executablePath: ffmpegPath, arguments: args, progressHandler: progressHandler)
                return try getFileSize(outputURL)
            } else {
                // If destination is GIF and FFmpeg is not available, we can convert natively!
                if dstExt == "gif" {
                    try await convertVideoToGIF(inputURL: inputURL, outputURL: outputURL, progressHandler: progressHandler)
                    return try getFileSize(outputURL)
                }
                
                throw NSError(domain: "FileConverterError", code: 10, userInfo: [NSLocalizedDescriptionKey: "Converting to/from .\(dstExt) requires the FFmpeg plugin. Please install and enable it in Settings -> Plugins."])
            }
        }
        
        // Native Animated GIF to Video conversion
        if srcExt == "gif" && ["mp4", "mov"].contains(dstExt) {
            try await convertGIFToVideo(inputURL: inputURL, outputURL: outputURL, targetFormat: dstExt, progressHandler: progressHandler)
            return try getFileSize(outputURL)
        }
        
        // Native Video to GIF conversion
        if ["mp4", "mov"].contains(srcExt) && dstExt == "gif" {
            try await convertVideoToGIF(inputURL: inputURL, outputURL: outputURL, progressHandler: progressHandler)
            return try getFileSize(outputURL)
        }
        
        // Native video container conversion (MP4 <-> MOV, MOV -> ProRes)
        progressHandler(0.1)
        let asset = AVURLAsset(url: inputURL)
        let preset: String
        if dstExt == "prores" {
            preset = "AVAssetExportPresetAppleProRes422HQ"
        } else {
            preset = AVAssetExportPresetHighestQuality
        }
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw NSError(domain: "FileConverterError", code: 11, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize AVAssetExportSession."])
        }
        
        try checkIfCancelled()
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = dstExt == "mov" ? AVFileType.mov : AVFileType.mp4
        
        let states = exportSession.states(updateInterval: 0.1)
        let progressTask = Task {
            for await state in states {
                if case .exporting(let progress) = state {
                    progressHandler(progress.fractionCompleted)
                }
            }
        }
        
        defer {
            progressTask.cancel()
        }
        
        if #available(macOS 15.0, *) {
            try await exportSession.export(to: outputURL, as: dstExt == "mov" ? .mov : .mp4)
        } else {
            await exportSession.export()
        }
        progressHandler(1.0)
        return try getFileSize(outputURL)
    }
    
    // MARK: - Audio Conversion
    private func convertAudio(
        inputURL: URL,
        outputURL: URL,
        targetFormat: String,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> Int64 {
        let srcExt = inputURL.pathExtension.lowercased()
        let dstExt = targetFormat.lowercased()
        
        let useFFmpeg = UserDefaults.standard.bool(forKey: "use_ffmpeg_for_audio_conversion") && ExternalToolManager.isToolAvailable(.ffmpeg)
        let tool = FileConverter.toolRequired(from: srcExt, to: dstExt)
        if tool == .ffmpeg {
            if useFFmpeg, let ffmpegPath = ExternalToolManager.findToolPath(.ffmpeg) {
                var args = ["-y", "-i", inputURL.path]
                if dstExt == "mp3" {
                    args += ["-acodec", "libmp3lame", "-ab", "192k", outputURL.path]
                } else if dstExt == "ogg" {
                    args += ["-acodec", "libvorbis", "-aq", "5", outputURL.path]
                } else {
                    args += [outputURL.path]
                }
                
                try await runExternalProcess(executablePath: ffmpegPath, arguments: args, progressHandler: progressHandler)
                return try getFileSize(outputURL)
            } else {
                throw NSError(domain: "FileConverterError", code: 12, userInfo: [NSLocalizedDescriptionKey: "Conversion to/from .\(dstExt) requires the FFmpeg plugin. Please install and enable it in Settings -> Plugins."])
            }
        }
        
        // Native audio conversion (AAC, WAV, FLAC, M4A)
        progressHandler(0.1)
        let asset = AVURLAsset(url: inputURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw NSError(domain: "FileConverterError", code: 13, userInfo: [NSLocalizedDescriptionKey: "No audio track found in file."])
        }
        
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        let fileType: AVFileType
        let formatID: AudioFormatID
        
        switch dstExt {
        case "wav":
            fileType = .wav
            formatID = kAudioFormatLinearPCM
        case "flac":
            fileType = AVFileType(rawValue: "org.xiph.flac")
            formatID = kAudioFormatFLAC
        default: // m4a, aac
            fileType = .m4a
            formatID = kAudioFormatMPEG4AAC
        }
        
        guard let reader = try? AVAssetReader(asset: asset),
              let writer = try? AVAssetWriter(outputURL: outputURL, fileType: fileType) else {
            throw NSError(domain: "FileConverterError", code: 14, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize native audio reader/writer."])
        }
        
        // Decode to linear PCM
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        
        // Encode setting
        var writerSettings: [String: Any] = [
            AVFormatIDKey: formatID,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100.0
        ]
        if formatID == kAudioFormatMPEG4AAC {
            writerSettings[AVEncoderBitRateKey] = 192000
        }
        
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
        writerInput.expectsMediaDataInRealTime = false
        
        if reader.canAdd(readerOutput) && writer.canAdd(writerInput) {
            reader.add(readerOutput)
            writer.add(writerInput)
        } else {
            throw NSError(domain: "FileConverterError", code: 15, userInfo: [NSLocalizedDescriptionKey: "Failed to configure native audio transcoding pipeline."])
        }
        
        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "FileConverterError", code: 16, userInfo: [NSLocalizedDescriptionKey: "Audio reader failed."])
        }
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "FileConverterError", code: 17, userInfo: [NSLocalizedDescriptionKey: "Audio writer failed."])
        }
        
        writer.startSession(atSourceTime: .zero)
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let queue = DispatchQueue(label: "shrink.audio-transcode")
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    if self.cancelled {
                        writerInput.markAsFinished()
                        reader.cancelReading()
                        writer.cancelWriting()
                        continuation.resume()
                        return
                    }
                    
                    if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(sampleBuffer)
                    } else {
                        writerInput.markAsFinished()
                        if reader.status == .completed {
                            writer.finishWriting {
                                continuation.resume()
                            }
                        } else {
                            writer.cancelWriting()
                            continuation.resume()
                        }
                        return
                    }
                }
            }
        }
        
        progressHandler(1.0)
        return try getFileSize(outputURL)
    }
    
    // MARK: - Document Conversion
    private func convertDocument(
        inputURL: URL,
        outputURL: URL,
        targetFormat: String,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> Int64 {
        let srcExt = inputURL.pathExtension.lowercased()
        let dstExt = targetFormat.lowercased()
        
        let usePandoc = UserDefaults.standard.bool(forKey: "use_pandoc_for_document_conversion") && ExternalToolManager.isToolAvailable(.pandoc)
        let tool = FileConverter.toolRequired(from: srcExt, to: dstExt)
        if tool == .pandoc {
            if usePandoc, let pandocPath = ExternalToolManager.findToolPath(.pandoc) {
                let args = [inputURL.path, "-o", outputURL.path]
                try await runExternalProcess(executablePath: pandocPath, arguments: args, progressHandler: progressHandler)
                return try getFileSize(outputURL)
            } else {
                throw NSError(domain: "FileConverterError", code: 18, userInfo: [NSLocalizedDescriptionKey: "Conversion to/from .\(dstExt) requires the Pandoc plugin. Please install and enable it in Settings -> Plugins."])
            }
        }
        
        // Native Document Conversion
        progressHandler(0.1)
        
        // 1. PDF -> TXT (Extract text)
        if srcExt == "pdf" && dstExt == "txt" {
            guard let pdf = PDFDocument(url: inputURL) else {
                throw NSError(domain: "FileConverterError", code: 19, userInfo: [NSLocalizedDescriptionKey: "Failed to open PDF document."])
            }
            var fullText = ""
            let pageCount = pdf.pageCount
            for i in 0..<pageCount {
                if cancelled { throw NSError(domain: "FileConverterError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Cancelled."]) }
                if let page = pdf.page(at: i), let txt = page.string {
                    fullText += txt + "\n"
                }
                progressHandler(0.1 + Double(i) / Double(pageCount) * 0.8)
            }
            try fullText.write(to: outputURL, atomically: true, encoding: .utf8)
            progressHandler(1.0)
            return try getFileSize(outputURL)
        }
        
        // 2. PDF -> Images (Page-by-page)
        if srcExt == "pdf" && ["jpeg", "jpg", "png"].contains(dstExt) {
            guard let pdf = PDFDocument(url: inputURL) else {
                throw NSError(domain: "FileConverterError", code: 20, userInfo: [NSLocalizedDescriptionKey: "Failed to open PDF document."])
            }
            let pageCount = pdf.pageCount
            let baseName = outputURL.deletingPathExtension().lastPathComponent
            let outputDir = outputURL.deletingLastPathComponent()
            
            for i in 0..<pageCount {
                if cancelled { throw NSError(domain: "FileConverterError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Cancelled."]) }
                guard let page = pdf.page(at: i) else { continue }
                
                let rect = page.bounds(for: .mediaBox)
                // Draw page at 300 DPI for high quality (4x scaling)
                let scale: CGFloat = 4.0
                let size = CGSize(width: rect.width * scale, height: rect.height * scale)
                
                let nsImage = NSImage(size: size)
                nsImage.lockFocus()
                if let context = NSGraphicsContext.current?.cgContext {
                    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                    context.fill(CGRect(origin: .zero, size: size))
                    context.scaleBy(x: scale, y: scale)
                    page.draw(with: .mediaBox, to: context)
                }
                nsImage.unlockFocus()
                
                guard let tiff = nsImage.tiffRepresentation,
                      let source = CGImageSourceCreateWithData(tiff as CFData, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    continue
                }
                
                let pageOutputURL = outputDir.appendingPathComponent("\(baseName)_page_\(i + 1).\(dstExt)")
                try saveCGImage(cgImage, to: pageOutputURL, format: dstExt)
                progressHandler(0.1 + Double(i) / Double(pageCount) * 0.8)
            }
            progressHandler(1.0)
            return 0 // Multiple files created
        }
        
        // 3. MD / Markdown -> HTML / TXT / DOCX / RTF / ODT / PDF
        if srcExt == "md" || srcExt == "markdown" {
            let markdownContent = try String(contentsOf: inputURL, encoding: .utf8)
            let htmlContent = await MarkdownParser.toHTML(markdownContent)
            
            if dstExt == "html" {
                try htmlContent.write(to: outputURL, atomically: true, encoding: .utf8)
                progressHandler(1.0)
                return try getFileSize(outputURL)
            }
            
            // Save temporary HTML for textutil / print conversion
            let tempHTMLURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".html")
            try htmlContent.write(to: tempHTMLURL, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: tempHTMLURL) }
            
            if dstExt == "pdf" {
                try await printHTMLToPDF(htmlURL: tempHTMLURL, outputURL: outputURL)
                progressHandler(1.0)
                return try getFileSize(outputURL)
            }
            
            // Otherwise convert via textutil (TXT, DOCX, RTF, ODT, DOC)
            if ["docx", "doc", "rtf", "txt", "odt"].contains(dstExt) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
                process.arguments = ["-convert", dstExt == "doc" ? "doc" : dstExt, tempHTMLURL.path, "-output", outputURL.path]
                try await runProcessAsync(process)
                progressHandler(1.0)
                return try getFileSize(outputURL)
            }
        }
        
        // 4. HTML/DOCX/DOC/RTF/TXT/ODT -> MD / Markdown
        if dstExt == "md" || dstExt == "markdown" {
            var htmlContent = ""
            if srcExt == "html" {
                htmlContent = try String(contentsOf: inputURL, encoding: .utf8)
            } else if ["docx", "doc", "rtf", "txt", "odt"].contains(srcExt) {
                // Convert to temporary HTML via textutil first
                let tempHTMLURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".html")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
                process.arguments = ["-convert", "html", inputURL.path, "-output", tempHTMLURL.path]
                try await runProcessAsync(process)
                htmlContent = try String(contentsOf: tempHTMLURL, encoding: .utf8)
                try? FileManager.default.removeItem(at: tempHTMLURL)
            } else {
                throw NSError(domain: "FileConverterError", code: 22, userInfo: [NSLocalizedDescriptionKey: "Unsupported source format for Markdown conversion."])
            }
            
            let mdContent = HTMLToMarkdown.convert(htmlContent)
            try mdContent.write(to: outputURL, atomically: true, encoding: .utf8)
            progressHandler(1.0)
            return try getFileSize(outputURL)
        }
        
        // 5. DOCX / DOC / RTF / TXT / HTML / ODT -> PDF
        if ["docx", "doc", "rtf", "txt", "html", "odt"].contains(srcExt) && dstExt == "pdf" {
            var sourceURL = inputURL
            var isTempHTML = false
            
            if srcExt == "odt" {
                // ODT is not natively readable by NSAttributedString, so transcode it to HTML first
                let tempHTMLURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".html")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
                process.arguments = ["-convert", "html", inputURL.path, "-output", tempHTMLURL.path]
                try await runProcessAsync(process)
                sourceURL = tempHTMLURL
                isTempHTML = true
            }
            
            defer {
                if isTempHTML {
                    try? FileManager.default.removeItem(at: sourceURL)
                }
            }
            
            try await printHTMLToPDF(htmlURL: sourceURL, outputURL: outputURL)
            progressHandler(1.0)
            return try getFileSize(outputURL)
        }
        
        // 6. Cross-conversion using textutil (DOCX, DOC, RTF, TXT, HTML, ODT -> DOCX, DOC, RTF, TXT, HTML, ODT)
        let textutilFormats = ["docx", "doc", "rtf", "txt", "html", "odt"]
        if textutilFormats.contains(srcExt) && textutilFormats.contains(dstExt) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
            process.arguments = ["-convert", dstExt == "doc" ? "doc" : dstExt, inputURL.path, "-output", outputURL.path]
            try await runProcessAsync(process)
            progressHandler(1.0)
            return try getFileSize(outputURL)
        }
        
        throw NSError(domain: "FileConverterError", code: 22, userInfo: [NSLocalizedDescriptionKey: "Unsupported native document conversion from .\(srcExt) to .\(dstExt)."])
    }
    
    // MARK: - Archive Conversion
    private func convertArchive(
        inputURL: URL,
        outputURL: URL,
        targetFormat: String,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> Int64 {
        progressHandler(0.1)
        
        let fileManager = FileManager.default
        let tempExtractDir = fileManager.temporaryDirectory.appendingPathComponent("shrink_conv_archive_" + UUID().uuidString)
        
        try fileManager.createDirectory(at: tempExtractDir, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: tempExtractDir)
        }
        
        // 1. Decompress source archive to temp folder
        let decompressor = ArchiveCompressor()
        setActiveCompressor(decompressor)
        
        progressHandler(0.2)
        try await decompressor.decompress(
            archiveURL: inputURL,
            destinationURL: tempExtractDir,
            password: nil,
            progressHandler: { p in
                progressHandler(0.2 + p * 0.3) // 20% to 50%
            }
        )
        
        try checkIfCancelled()
        
        // 2. Compress temp folder to target format
        let compressor = ArchiveCompressor()
        setActiveCompressor(compressor)
        
        let format: ArchiveFormat
        switch targetFormat.lowercased() {
        case "7z": format = .sevenZip
        case "tar": format = .tar
        case "tgz", "tar.gz": format = .tgz
        default: format = .zip
        }
        
        // Collect URLs to compress inside temp folder
        let contents = try fileManager.contentsOfDirectory(at: tempExtractDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        
        try await compressor.compress(
            urls: contents,
            destinationURL: outputURL,
            format: format,
            compressionLevel: 5,
            password: nil,
            splitSize: nil,
            progressHandler: { p in
                progressHandler(0.5 + p * 0.5) // 50% to 100%
            }
        )
        
        return try getFileSize(outputURL)
    }
    
    // MARK: - Process Execution Helpers
    private func runProcessAsync(_ process: Process) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(domain: "FileConverterError", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Process exit with code \(proc.terminationStatus)"]))
                }
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Synchronous Concurrency Helpers
    private func resetCancelled() {
        lock.lock()
        defer { lock.unlock() }
        isCancelled = false
    }

    private func checkIfCancelled() throws {
        lock.lock()
        defer { lock.unlock() }
        if isCancelled {
            throw NSError(domain: "FileConverterError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Conversion cancelled."])
        }
    }

    private func setActiveCompressor(_ compressor: ArchiveCompressor?) {
        lock.lock()
        defer { lock.unlock() }
        activeArchiveCompressor = compressor
    }

    private func setActiveProcess(_ process: Process?) throws {
        lock.lock()
        defer { lock.unlock() }
        if isCancelled && process != nil {
            throw NSError(domain: "FileConverterError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Operation cancelled."])
        }
        activeProcess = process
    }

    private func clearActiveProcess() {
        lock.lock()
        defer { lock.unlock() }
        activeProcess = nil
    }
    
    private func runExternalProcess(
        executablePath: String,
        arguments: [String],
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        
        try setActiveProcess(process)
        
        defer {
            clearActiveProcess()
        }
        
        let outputPipe = Pipe()
        process.standardError = outputPipe
        process.standardOutput = Pipe()
        
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                outputPipe.fileHandleForReading.readabilityHandler = nil
            } else if let chunk = String(data: data, encoding: .utf8) {
                // Parse FFmpeg progress: e.g. frame=  123 fps= 25 time=00:00:05.12
                // We can extract time or simply report incremental progress based on stdout lines
                if chunk.contains("time=") {
                    // Send dummy progress or parse actual duration
                    progressHandler(0.5)
                }
            }
        }
        
        try await runProcessAsync(process)
        progressHandler(1.0)
    }
    
    private func getFileSize(_ url: URL) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return attrs[.size] as? Int64 ?? 0
    }
    
    // MARK: - Native Document Printing Helpers
    private func printHTMLToPDF(htmlURL: URL, outputURL: URL) async throws {
        let srcExt = htmlURL.pathExtension.lowercased()
        let documentType: NSAttributedString.DocumentType
        if srcExt == "rtf" {
            documentType = .rtf
        } else if srcExt == "txt" {
            documentType = .plain
        } else if srcExt == "html" {
            documentType = .html
        } else {
            documentType = .wordML
        }
        
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: documentType
        ]
        
        try await MainActor.run {
            let attrStr = try NSAttributedString(url: htmlURL, options: options, documentAttributes: nil)
            
            let printInfo = NSPrintInfo.shared
            let printDict = printInfo.dictionary()
            printDict[NSPrintInfo.AttributeKey.jobDisposition] = NSPrintInfo.JobDisposition.save
            printDict[NSPrintInfo.AttributeKey.jobSavingURL] = outputURL
            
            printInfo.horizontalPagination = .fit
            printInfo.verticalPagination = .automatic
            
            printInfo.leftMargin = 36
            printInfo.rightMargin = 36
            printInfo.topMargin = 36
            printInfo.bottomMargin = 36
            
            let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 700))
            textView.textStorage?.setAttributedString(attrStr)
            
            let printOp = NSPrintOperation(view: textView, printInfo: printInfo)
            printOp.showsPrintPanel = false
            printOp.showsProgressPanel = false
            
            guard printOp.run() else {
                throw NSError(domain: "FileConverterError", code: 21, userInfo: [NSLocalizedDescriptionKey: "Native PDF rendering failed."])
            }
        }
    }
    
    // MARK: - Native GIF and Video Transcoding Helpers
    private func convertGIFToVideo(
        inputURL: URL,
        outputURL: URL,
        targetFormat: String,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil) else {
            throw NSError(domain: "FileConverterError", code: 30, userInfo: [NSLocalizedDescriptionKey: "Failed to open GIF source."])
        }
        
        let count = CGImageSourceGetCount(source)
        guard count > 0 else {
            throw NSError(domain: "FileConverterError", code: 31, userInfo: [NSLocalizedDescriptionKey: "GIF contains no frames."])
        }
        
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            throw NSError(domain: "FileConverterError", code: 32, userInfo: [NSLocalizedDescriptionKey: "Failed to read GIF frame dimensions."])
        }
        
        let videoWidth = (Int(width) / 2) * 2
        let videoHeight = (Int(height) / 2) * 2
        let videoSize = CGSize(width: videoWidth, height: videoHeight)
        
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        let fileType: AVFileType = targetFormat.lowercased() == "mov" ? .mov : .mp4
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoWidth,
            AVVideoHeightKey: videoHeight
        ]
        
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: videoWidth,
                kCVPixelBufferHeightKey as String: videoHeight
            ]
        )
        
        if writer.canAdd(writerInput) {
            writer.add(writerInput)
        } else {
            throw NSError(domain: "FileConverterError", code: 33, userInfo: [NSLocalizedDescriptionKey: "Failed to add video input to asset writer."])
        }
        
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        
        var currentTime = CMTime.zero
        for i in 0..<count {
            try checkIfCancelled()
            
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            
            var frameDuration = 0.1
            if let frameProps = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any],
               let gifProps = frameProps[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                if let unclamped = gifProps[kCGImagePropertyGIFUnclampedDelayTime] as? Double {
                    frameDuration = unclamped
                } else if let delay = gifProps[kCGImagePropertyGIFDelayTime] as? Double {
                    frameDuration = delay
                }
            }
            if frameDuration < 0.011 {
                frameDuration = 0.1
            }
            
            guard let buffer = pixelBuffer(from: cgImage, size: videoSize) else {
                continue
            }
            
            while !writerInput.isReadyForMoreMediaData {
                if cancelled {
                    writer.cancelWriting()
                    throw NSError(domain: "FileConverterError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Conversion cancelled."])
                }
                try await Task.sleep(for: .milliseconds(5))
            }
            
            adaptor.append(buffer, withPresentationTime: currentTime)
            
            let delta = CMTime(seconds: frameDuration, preferredTimescale: 600)
            currentTime = CMTimeAdd(currentTime, delta)
            
            progressHandler(Double(i) / Double(count))
        }
        
        writerInput.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }
    }
    
    private func convertVideoToGIF(
        inputURL: URL,
        outputURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: inputURL)
        let duration = try await asset.load(.duration).seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        let fps = 15.0
        let frameCount = max(1, Int(duration * fps))
        
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
            throw NSError(domain: "FileConverterError", code: 40, userInfo: [NSLocalizedDescriptionKey: "Failed to create GIF destination."])
        }
        
        let fileProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        
        let frameDelay = 1.0 / fps
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDelay
            ]
        ] as [CFString : Any]
        
        for i in 0..<frameCount {
            try checkIfCancelled()
            
            let time = CMTime(seconds: Double(i) * frameDelay, preferredTimescale: 600)
            do {
                let cgImage = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
                    generator.generateCGImageAsynchronously(for: time) { image, _, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if let image = image {
                            continuation.resume(returning: image)
                        } else {
                            continuation.resume(throwing: NSError(domain: "FileConverterError", code: 41, userInfo: [NSLocalizedDescriptionKey: "Unknown generator error."]))
                        }
                    }
                }
                
                CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
            } catch {
                print("Failed to generate video frame for GIF: \(error)")
            }
            
            progressHandler(Double(i) / Double(frameCount))
        }
        
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "FileConverterError", code: 42, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize GIF compilation."])
        }
    }
    
    private func pixelBuffer(from cgImage: CGImage, size: CGSize) -> CVPixelBuffer? {
        let options: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32ARGB,
            options as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        let data = CVPixelBufferGetBaseAddress(buffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: data,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        return buffer
    }
}

// MARK: - Native Markdown parsing helpers
fileprivate struct MarkdownParser {
    static func toHTML(_ markdown: String) -> String {
        var html = ""
        var inList = false
        var inCodeBlock = false
        
        let lines = markdown.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    html += "</code></pre>\n"
                    inCodeBlock = false
                } else {
                    html += "<pre><code>"
                    inCodeBlock = true
                }
                continue
            }
            
            if inCodeBlock {
                html += line + "\n"
                continue
            }
            
            if inList && !trimmed.hasPrefix("- ") && !trimmed.hasPrefix("* ") {
                html += "</ul>\n"
                inList = false
            }
            
            if trimmed.isEmpty {
                html += "<br/>\n"
                continue
            }
            
            if trimmed.hasPrefix("#") {
                let parts = trimmed.split(separator: " ", maxSplits: 1)
                if let headerText = parts.last {
                    let level = parts.first?.count ?? 1
                    let levelClamped = min(6, max(1, level))
                    let parsedText = parseInline(String(headerText))
                    html += "<h\(levelClamped)>\(parsedText)</h\(levelClamped)>\n"
                }
                continue
            }
            
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                if !inList {
                    html += "<ul>\n"
                    inList = true
                }
                let itemText = String(trimmed.dropFirst(2))
                let parsedText = parseInline(itemText)
                html += "<li>\(parsedText)</li>\n"
                continue
            }
            
            let parsedText = parseInline(line)
            html += "<p>\(parsedText)</p>\n"
        }
        
        if inList {
            html += "</ul>\n"
        }
        
        return "<html><body>\n\(html)\n</body></html>"
    }
    
    private static func parseInline(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        
        result = parseRegex(result, pattern: "\\*\\*(.*?)\\*\\*", replacement: "<strong>$1</strong>")
        result = parseRegex(result, pattern: "__(.*?)__", replacement: "<strong>$1</strong>")
        result = parseRegex(result, pattern: "\\*(.*?)\\*", replacement: "<em>$1</em>")
        result = parseRegex(result, pattern: "_(.*?)_", replacement: "<em>$1</em>")
        result = parseRegex(result, pattern: "`([^`]+)`", replacement: "<code>$1</code>")
        return result
    }
    
    private static func parseRegex(_ text: String, pattern: String, replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }
}

fileprivate struct HTMLToMarkdown {
    static func convert(_ html: String) -> String {
        var result = html
        
        for level in 1...6 {
            let pattern = "<h\(level)>(.*?)</h\(level)>"
            let prefix = String(repeating: "#", count: level) + " "
            result = parseRegex(result, pattern: pattern, replacement: "\n\(prefix)$1\n")
        }
        
        result = parseRegex(result, pattern: "<strong>(.*?)</strong>", replacement: "**$1**")
        result = parseRegex(result, pattern: "<b>(.*?)</b>", replacement: "**$1**")
        result = parseRegex(result, pattern: "<em>(.*?)</em>", replacement: "*$1*")
        result = parseRegex(result, pattern: "<i>(.*?)</i>", replacement: "*$1*")
        result = parseRegex(result, pattern: "<pre><code>(.*?)</code></pre>", replacement: "\n```\n$1\n```\n")
        result = parseRegex(result, pattern: "<code>(.*?)</code>", replacement: "`$1`")
        result = parseRegex(result, pattern: "<p>(.*?)</p>", replacement: "\n$1\n")
        result = result.replacingOccurrences(of: "<br/>", with: "\n")
        result = result.replacingOccurrences(of: "<br>", with: "\n")
        result = parseRegex(result, pattern: "<li>(.*?)</li>", replacement: "- $1\n")
        result = result.replacingOccurrences(of: "<ul>", with: "\n")
        result = result.replacingOccurrences(of: "</ul>", with: "\n")
        result = parseRegex(result, pattern: "<[^>]+>", replacement: "")
        
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func parseRegex(_ text: String, pattern: String, replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }
}
