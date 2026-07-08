//
//  ImageCompressor.swift
//  Shrink
//

import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import Metal
import UniformTypeIdentifiers

nonisolated class ImageCompressor {
    
    func compress(inputURL: URL, outputURL: URL, settings: ImageSettings) throws -> Int64 {
        let srcExt = inputURL.pathExtension.lowercased()
        let isAdvancedFormat = ["psd", "tga", "dds", "exr", "hdr", "pcx", "eps", "pgm", "ppm", "pbm", "pnm", "avif", "jp2", "j2k", "ico", "fits", "xcf", "pix", "mng", "cr2", "nef", "arw", "raf", "orf", "rw2", "pef", "erf", "mef", "mos", "sr2", "srf", "dcr", "kdc", "crw", "x3f", "dng"].contains(srcExt)
        let useMagick = UserDefaults.standard.bool(forKey: "use_magick_for_image_compression")
        if useMagick && isAdvancedFormat, let magickPath = ExternalToolManager.findToolPath(.magick) {
            return try compressUsingMagick(executablePath: magickPath, inputURL: inputURL, outputURL: outputURL, settings: settings)
        }
        
        return try autoreleasepool {
        // Resolve security scoping
        let isAccessingInput = inputURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessingInput {
                inputURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let imageSource = CGImageSourceCreateWithURL(inputURL as CFURL, sourceOptions as CFDictionary) else {
            throw NSError(domain: "ImageCompressorError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open image file."])
        }
        
        // Get original dimensions without decoding if possible
        var originalWidth = 0
        var originalHeight = 0
        
        if let sourceProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {
            if let w = (sourceProperties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue {
                originalWidth = w
            } else if let w = sourceProperties[kCGImagePropertyPixelWidth] as? Int {
                originalWidth = w
            }
            if let h = (sourceProperties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue {
                originalHeight = h
            } else if let h = sourceProperties[kCGImagePropertyPixelHeight] as? Int {
                originalHeight = h
            }
        }
        
        var fallbackCgImage: CGImage? = nil
        if originalWidth <= 0 || originalHeight <= 0 {
            guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "ImageCompressorError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to load image contents."])
            }
            originalWidth = cgImage.width
            originalHeight = cgImage.height
            fallbackCgImage = cgImage
        }
        
        // Map targetSizeRatio to quality and scale
        let ratio = settings.targetSizeRatio
        let calculatedQuality: Float
        var calculatedScale: Float
        
        if ratio >= 0.8 {
            calculatedQuality = Float(ratio)
            calculatedScale = 1.0
        } else {
            calculatedQuality = 0.8
            calculatedScale = Float(sqrt(ratio / 0.8))
        }
        
        // Apply target resolution scaling (bounding box fit) if provided
        if let targetW = settings.targetResolutionWidth, let targetH = settings.targetResolutionHeight {
            let scaleX = Float(targetW) / Float(originalWidth)
            let scaleY = Float(targetH) / Float(originalHeight)
            let fitScale = min(scaleX, scaleY)
            if fitScale < 1.0 {
                calculatedScale = min(calculatedScale, fitScale)
            }
        }
        
        // Map format name to UTType identifier early (used for alpha handling)
        let uti: UTType
        switch settings.format.uppercased() {
        case "PNG":
            uti = .png
        case "HEIC", "HEIF":
            uti = .heic
        case "WEBP":
            uti = UTType("org.webmproject.webp") ?? .jpeg
        case "TIFF", "TIF":
            uti = .tiff
        default: // Default to JPEG
            uti = .jpeg
        }

        // Apply scaling if scale < 1.0 using GPU-accelerated or thumbnail creation
        let processedImage: CGImage
        if calculatedScale < 1.0 && calculatedScale > 0.0 {
            let targetMaxPixelSize = max(1, max(Int(Float(originalWidth) * calculatedScale), Int(Float(originalHeight) * calculatedScale)))
            
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: targetMaxPixelSize,
                kCGImageSourceShouldCache: false
            ]
            
            if let scaledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) {
                processedImage = scaledImage
            } else if let fullImage = fallbackCgImage ?? CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
                      let gpuScaled = try? GPUImageScaler.scale(image: fullImage, scale: calculatedScale) {
                processedImage = gpuScaled
            } else {
                // Fallback to full resolution image
                if let fallback = fallbackCgImage {
                    processedImage = fallback
                } else {
                    guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                        throw NSError(domain: "ImageCompressorError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to load image contents."])
                    }
                    processedImage = cgImage
                }
            }
        } else {
            if let fallback = fallbackCgImage {
                processedImage = fallback
            } else {
                guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                    throw NSError(domain: "ImageCompressorError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to load image contents."])
                }
                processedImage = cgImage
            }
        }
        
        // Prepare destination
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, uti.identifier as CFString, 1, nil) else {
            throw NSError(domain: "ImageCompressorError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to create image destination."])
        }
        
        var properties: [CFString: Any] = [:]
        
        // Quality applies to JPEG and HEIC/WEBP lossy formats
        if uti != .png && uti != .tiff {
            properties[kCGImageDestinationLossyCompressionQuality] = calculatedQuality
        }
        
        // If target format doesn't support alpha (e.g. JPEG/HEIC) and the processed image
        // has an alpha channel, draw it into an opaque RGB context to drop alpha. This
        // avoids warnings about saving opaque images with alpha and reduces output size.
        var finalImage = processedImage
        let supportsAlpha: Bool = {
            if uti == .png || uti == .tiff { return true }
            if let webpType = UTType("org.webmproject.webp"), uti == webpType { return true }
            return false
        }()
        if !supportsAlpha {
            let alpha = processedImage.alphaInfo
            let hasAlpha: Bool = {
                switch alpha {
                case .none, .noneSkipFirst, .noneSkipLast:
                    return false
                default:
                    return true
                }
            }()
            if hasAlpha {
                if let opaque = ImageCompressor.makeOpaqueImage(from: processedImage) {
                    finalImage = opaque
                }
            }
        }

        // Handle metadata preservation/stripping
        if !settings.stripMetadata {
            if let sourceProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {
                for (key, value) in sourceProperties {
                    // Skip keys that will be overridden by the destination renderer (e.g. width, height)
                    if key != kCGImagePropertyPixelWidth && key != kCGImagePropertyPixelHeight && key != kCGImagePropertyOrientation {
                        properties[key] = value
                    }
                }
            }
        }
        
        CGImageDestinationAddImage(destination, finalImage, properties as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "ImageCompressorError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize and write image output."])
        }
        
        // Return compressed size
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        if let fileSize = fileAttributes[.size] as? Int64 {
            return fileSize
        }
        
        return 0
        }
    }
    
    private func compressUsingMagick(
        executablePath: String,
        inputURL: URL,
        outputURL: URL,
        settings: ImageSettings
    ) throws -> Int64 {
        let isAccessingInput = inputURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessingInput {
                inputURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let ratio = settings.targetSizeRatio
        let calculatedQuality: Int
        var calculatedScale: Float
        
        if ratio >= 0.8 {
            calculatedQuality = Int(ratio * 100)
            calculatedScale = 1.0
        } else {
            calculatedQuality = 80
            calculatedScale = Float(sqrt(ratio / 0.8))
        }
        
        var args: [String] = []
        
        // Input path (append [0] for PSD to get first layer)
        let srcExt = inputURL.pathExtension.lowercased()
        if srcExt == "psd" {
            args.append("\(inputURL.path)[0]")
        } else {
            args.append(inputURL.path)
        }
        
        // Strip metadata if requested
        if settings.stripMetadata {
            args.append("-strip")
        }
        
        // Handle quality for lossy formats (JPEG/WEBP/HEIC)
        let dstExt = settings.format.lowercased()
        if dstExt != "png" {
            args += ["-quality", "\(calculatedQuality)"]
        }
        
        // Handle resizing if scale < 1.0
        if calculatedScale < 1.0 && calculatedScale > 0.0 {
            let scalePct = Int(calculatedScale * 100)
            args += ["-resize", "\(scalePct)%"]
        }
        
        // Or if specific resolution target is set
        if let targetW = settings.targetResolutionWidth, let targetH = settings.targetResolutionHeight {
            args += ["-resize", "\(targetW)x\(targetH)>"] // '>' means only shrink if larger
        }
        
        // Output path
        args.append(outputURL.path)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "ImageCompressorError", code: 12, userInfo: [NSLocalizedDescriptionKey: "ImageMagick compression failed with exit code \(process.terminationStatus)"])
        }
        
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        return fileAttributes[.size] as? Int64 ?? 0
    }
}

nonisolated private enum GPUImageScaler {
    static func scale(image: CGImage, scale: Float) throws -> CGImage {
        guard let context = GPUResourcePool.shared.ciContext else {
            throw NSError(domain: "ImageCompressorError", code: 7, userInfo: [NSLocalizedDescriptionKey: "GPU context unavailable."])
        }
        let ciImage = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CILanczosScaleTransform") else {
            throw NSError(domain: "ImageCompressorError", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to create scaling filter."])
        }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
        guard let outputImage = filter.outputImage else {
            throw NSError(domain: "ImageCompressorError", code: 9, userInfo: [NSLocalizedDescriptionKey: "Failed to scale image."])
        }
        let extent = outputImage.extent.integral
        guard let scaledCgImage = context.createCGImage(outputImage, from: extent) else {
            throw NSError(domain: "ImageCompressorError", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to create scaled image."])
        }
        return scaledCgImage
    }
}

// Shared GPU / CI resources to avoid per-image allocation overhead
nonisolated private final class GPUResourcePool: Sendable {
    static let shared = GPUResourcePool()
    let device: MTLDevice?
    let ciContext: CIContext?

    private init() {
        self.device = MTLCreateSystemDefaultDevice()
        if let d = self.device {
            // Use MTL-based CIContext for best throughput
            self.ciContext = CIContext(mtlDevice: d)
        } else {
            self.ciContext = nil
        }
    }
}

extension ImageCompressor {
    // Create an opaque copy by drawing into an RGB (no alpha) context.
    nonisolated static func makeOpaqueImage(from cgImage: CGImage) -> CGImage? {
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue))

        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else {
            return nil
        }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        // Fill white background to preserve look when dropping alpha
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(rect)
        ctx.draw(cgImage, in: rect)
        return ctx.makeImage()
    }
}
