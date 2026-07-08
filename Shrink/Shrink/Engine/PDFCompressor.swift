//
//  PDFCompressor.swift
//  Shrink
//

import Foundation
import PDFKit
import CoreGraphics

nonisolated class PDFCompressor {
    
    func compress(inputURL: URL, outputURL: URL) throws -> Int64 {
        let isAccessingInput = inputURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessingInput {
                inputURL.stopAccessingSecurityScopedResource()
            }
        }
        
        guard let pdfDocument = PDFDocument(url: inputURL) else {
            throw NSError(domain: "PDFCompressorError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open PDF document."])
        }
        
        // Remove destination if it exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        guard let consumer = CGDataConsumer(url: outputURL as CFURL) else {
            throw NSError(domain: "PDFCompressorError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create PDF writer consumer."])
        }
        
        // Setup options - we can compress images by default
        let auxiliaryInfo: [CFString: Any] = [
            kCGPDFContextCreator: "Shrink App" as CFString
        ]
        
        guard let context = CGContext(consumer: consumer, mediaBox: nil, auxiliaryInfo as CFDictionary) else {
            throw NSError(domain: "PDFCompressorError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create PDF graphics context."])
        }
        
        let pageCount = pdfDocument.pageCount
        for i in 0..<pageCount {
            guard let page = pdfDocument.page(at: i) else { continue }
            let mediaBox = page.bounds(for: .mediaBox)
            
            var box = mediaBox
            context.beginPage(mediaBox: &box)
            
            // Draw page
            context.saveGState()
            
            // CoreGraphics PDF drawing requires flipping context or drawing using PDFPage's draw method
            // PDFKit provides page.draw(with:to:) which handles correct rotation and scale!
            let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.current = nsContext
            
            page.draw(with: .mediaBox, to: context)
            
            context.restoreGState()
            context.endPage()
        }
        
        context.closePDF()
        
        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        return attrs[.size] as? Int64 ?? 0
    }
}
