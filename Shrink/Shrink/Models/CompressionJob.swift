//
//  CompressionJob.swift
//  Shrink
//

import Foundation

struct CompressionJob: Sendable {
    let mode: AppMode
    let outputDir: URL
    let selectedFiles: [FileItem]
    let customOutputName: String
    let customSuffix: String
    let predominantType: FileType?
    
    let imageSettings: ImageSettings
    let videoSettings: VideoSettings
    let audioSettings: AudioSettings
    let archiveSettings: ArchiveSettings
    let decompressSettings: DecompressSettings
    let pdfSettings: PDFSettings
    let outputStyle: OutputStyle
    let mediaFilter: MediaFilter
}
