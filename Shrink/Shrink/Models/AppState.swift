//
//  AppState.swift
//  Shrink
//

import Foundation
import SwiftUI
import Combine
import Sparkle

enum AppMode: String, CaseIterable, Identifiable, Sendable {
    case compress = "Compress"
    case decompress = "Decompress"
    
    var id: String { rawValue }
}

enum OutputStyle: String, CaseIterable, Identifiable, Sendable {
    case archive = "Single Archive"
    case individual = "Individual Files"
    case subfolder = "Single Folder"
    case extractMedia = "Extract & Compress Media"
    
    var id: String { rawValue }
}

enum ArchiveHandlingMode: String, CaseIterable, Identifiable, Sendable {
    case compress = "Compress already compressed files"
    case ignore = "Ignore already compressed files"
    var id: String { rawValue }
}


enum OutputLocationType: String, CaseIterable, Identifiable {
    case sameAsSource = "Same as Source"
    case downloads = "Downloads"
    case desktop = "Desktop"
    case custom = "Custom Location..."
    
    var id: String { rawValue }
}

enum MediaFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All Files"
    case imagesOnly = "Images Only"
    case videosOnly = "Videos Only"
    case audioOnly = "Audio Only"
    case pdfOnly = "PDF Only"
    
    var id: String { rawValue }
}

// Media Compression Settings
struct ImageSettings: Sendable {
    var compressEnabled: Bool = true
    var format: String = "HEIC" // HEIC, JPEG, PNG
    var targetSizeRatio: Double = 0.8 // target size ratio (0.05 to 1.0)
    var stripMetadata: Bool = true
    var targetResolutionWidth: Int? = nil
    var targetResolutionHeight: Int? = nil
}

enum VideoCompressionMethod: String, CaseIterable, Identifiable, Sendable {
    case targetSize = "Target Size"
    case bitrate = "Bitrate"
    
    var id: String { rawValue }
}

struct VideoSettings: Sendable {
    var compressEnabled: Bool = true
    var codec: String = "HEVC"   // HEVC, H264
    var compressionMethod: VideoCompressionMethod = .targetSize
    var targetSizeRatio: Double = 0.7 // target size ratio (0.05 to 1.0)
    var targetBitrateKbps: Int = 5000 // default 5 Mbps
    var targetResolutionWidth: Int? = nil  // nil means original
    var targetResolutionHeight: Int? = nil // nil means original
    var audioMode: String = "Compress" // Mute, Keep, Compress
    var audioBitrate: Int = 128000 // bits per second (128 kbps)
}

struct AudioSettings: Sendable {
    var compressEnabled: Bool = true
    var format: String = "M4A"   // M4A (AAC), MP3
    var bitrate: Int = 128000    // bits per second (128 kbps)
}

struct PDFSettings: Sendable {
    var compressEnabled: Bool = true
}

struct ArchiveSettings: Sendable {
    var format: ArchiveFormat = .zip
    var compressionLevel: Int = 5 // 1 (Fastest) to 9 (Maximum)
    var splitArchive: Bool = false
    var splitSize: Int64 = 100 * 1024 * 1024 // 100 MB default
    var passwordEnabled: Bool = false
    var password: String = ""
}

struct DecompressSettings: Sendable {
    var createSubfolder: Bool = true
    var overwriteExisting: Bool = false
    var passwordEnabled: Bool = false
    var password: String = ""
}

struct CompressionResult {
    let originalSize: Int64
    let newSize: Int64
    let elapsedSeconds: Int
    let originalURL: URL
    let compressedURL: URL
}

@MainActor
@Observable
class AppState {
    // Files
    var selectedFiles: [FileItem] = []
    
    // Finder Sync Extension Mode
    var isFinderSyncMode: Bool = false
    var wasLaunchedByFinderSync: Bool = false
    
    // Track progresses of individual files by URL (especially useful for folders)
    var fileProgresses: [URL: Double] = [:]
    
    // Active selection
    var selectedFileID: UUID? = nil
    
    // Image-specific destination settings
    var imageOutputLocationType: OutputLocationType = .sameAsSource
    var imageCustomOutputFolder: URL? = nil
    var imageOutputStyle: OutputStyle = .individual
    var imageArchiveFormat: ArchiveFormat = .zip
    var imageCustomOutputName: String = ""
    var imageCustomSuffix: String = "_shrunk"
    
    // Video-specific destination settings
    var videoOutputLocationType: OutputLocationType = .sameAsSource
    var videoCustomOutputFolder: URL? = nil
    var videoOutputStyle: OutputStyle = .individual
    var videoArchiveFormat: ArchiveFormat = .zip
    var videoCustomOutputName: String = ""
    var videoCustomSuffix: String = "_shrunk"
    
    // Audio-specific destination settings
    var audioOutputLocationType: OutputLocationType = .sameAsSource
    var audioCustomOutputFolder: URL? = nil
    var audioOutputStyle: OutputStyle = .individual
    var audioArchiveFormat: ArchiveFormat = .zip
    var audioCustomOutputName: String = ""
    var audioCustomSuffix: String = "_shrunk"
    
    // PDF-specific destination settings
    var pdfOutputLocationType: OutputLocationType = .sameAsSource
    var pdfCustomOutputFolder: URL? = nil
    var pdfOutputStyle: OutputStyle = .individual
    var pdfArchiveFormat: ArchiveFormat = .zip
    var pdfCustomOutputName: String = ""
    var pdfCustomSuffix: String = "_shrunk"
    
    // Conversion-specific destination settings
    var convertOutputLocationType: OutputLocationType = .sameAsSource
    var convertCustomOutputFolder: URL? = nil
    var convertOutputStyle: OutputStyle = .individual
    var convertArchiveFormat: ArchiveFormat = .zip
    var convertCustomOutputName: String = ""
    var convertCustomSuffix: String = "_converted"
    
    // Output Style options
    var outputStyle: OutputStyle = .archive
    var saveIndividualToSubfolder: Bool = false
    var individualSubfolderName: String = "Compressed_Files"
    var archiveHandlingMode: ArchiveHandlingMode = .ignore
    
    // Processing state
    var isProcessing: Bool = false
    var showProcessingOverlay: Bool = false
    var currentProgress: Double = 0.0
    var activeJobTitle: String = ""
    var elapsedSeconds: Int = 0
    var estimatedSecondsRemaining: Int? = nil
    
    let compressionStats = CompressionStats()
    var throughputText: String = ""
    
    // Completion / Error state (displayed by ProcessingOverlay)
    var compressionResult: CompressionResult? = nil
    var compressionError: String? = nil
    var compressionStartTotalSize: Int64 = 0
    
    // Settings
    var mode: AppMode = .compress
    var outputLocationType: OutputLocationType = .sameAsSource
    var customOutputFolder: URL? = nil
    var customOutputName: String = ""
    var customSuffix: String = "_shrunk"
    
    // Compression sub-settings
    var imageSettings = ImageSettings()
    var videoSettings = VideoSettings()
    var audioSettings = AudioSettings()
    var pdfSettings = PDFSettings()
    var archiveSettings = ArchiveSettings()
    var decompressSettings = DecompressSettings()
    
    private var timer: Timer?
    private var engine: CompressorEngine?
    
    // Tool Installation State
    var installingTool: String? = nil
    var installProgressText: String = ""
    private var activeConverters: [UUID: FileConverter] = [:]
    
    @ObservationIgnored
    private var settingsObserver: Any? = nil
    
    // Sparkle Updater
    @ObservationIgnored
    var updaterController: SPUStandardUpdaterController? = nil
    
    @ObservationIgnored
    private var canCheckForUpdatesObservation: NSKeyValueObservation?
    @ObservationIgnored
    private var automaticallyChecksObservation: NSKeyValueObservation?
    @ObservationIgnored
    private var automaticallyDownloadsObservation: NSKeyValueObservation?
    
    var canCheckForUpdates = false
    
    var automaticallyChecksForUpdates = false {
        didSet {
            if let updater = updaterController?.updater, updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates {
                updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            }
        }
    }
    
    var automaticallyDownloadsUpdates = false {
        didSet {
            if let updater = updaterController?.updater, updater.automaticallyDownloadsUpdates != automaticallyDownloadsUpdates {
                updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
            }
        }
    }
    
    init() {
        var defaults: [String: Any] = [
            "default_suffix": "_shrunk",
            "decompress_create_subfolder": true,
            "decompress_overwrite_existing": false,
            "compress_zip_enabled": true,
            "compress_tar_enabled": true,
            "compress_tgz_enabled": true,
            "compress_sevenZip_enabled": true,
            "decompress_zip_enabled": true,
            "decompress_tar_enabled": true,
            "decompress_tgz_enabled": true,
            "decompress_sevenZip_enabled": true,
            "decompress_rar_enabled": true,
            "use_magick_for_image_compression": false,
            "use_magick_for_image_conversion": false,
            "use_ffmpeg_for_video_compression": false,
            "use_ffmpeg_for_video_conversion": false,
            "use_ffmpeg_for_audio_compression": false,
            "use_ffmpeg_for_audio_conversion": false,
            "use_pandoc_for_document_conversion": false,
            "use_sevenzip_for_archive": true,
            "use_ffmpeg": false,
            "use_magick": false,
            "use_pandoc": false
        ]
        
        let conversionFormats = [
            "png", "jpeg", "webp", "heic", "tiff", "gif", "bmp", "pdf", "avif", "psd", "tga", "dds", "exr", "hdr", "pcx", "eps", "ico",
            "mp4", "mov", "mkv", "avi", "webm", "flv", "prores", "mp3", "wav", "m4a", "flac", "aac", "ogg",
            "docx", "txt", "rtf", "epub", "html", "odt", "md"
        ]
        for fmt in conversionFormats {
            defaults["convert_\(fmt)_enabled"] = true
        }
        
        UserDefaults.standard.register(defaults: defaults)
        
        UserDefaults.shared.register(defaults: [
            "finder_extension_enabled": false,
            "finder_show_compress_archive": true,
            "finder_show_compress_image": true,
            "finder_show_compress_video": true,
            "finder_show_compress_audio": true,
            "finder_show_convert_file": true,
            "default_image_shrink_ratio": 0.8,
            "default_video_shrink_ratio": 0.7,
            "default_audio_bitrate": 128000,
            "default_archive_compression_level": 5
        ])
        
        // Listen for settings changes
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .archiveSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.loadSettings()
            }
        }
        
        // Initial load
        self.loadSettings()
        
        // Initialize Sparkle Updater
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.updaterController = controller
        
        let updater = controller.updater
        self.canCheckForUpdates = updater.canCheckForUpdates
        self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        
        self.canCheckForUpdatesObservation = updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
            Task { @MainActor in
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
        
        self.automaticallyChecksObservation = updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] updater, _ in
            Task { @MainActor in
                self?.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
            }
        }
        
        self.automaticallyDownloadsObservation = updater.observe(\.automaticallyDownloadsUpdates, options: [.new]) { [weak self] updater, _ in
            Task { @MainActor in
                self?.automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
            }
        }
    }
    
    deinit {
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
    
    private func loadSettings() {
        let prevDefaultSuffix = self.customSuffix
        let newDefaultSuffix = UserDefaults.standard.string(forKey: "default_suffix") ?? "_shrunk"
        self.customSuffix = newDefaultSuffix
        
        if self.imageCustomSuffix == prevDefaultSuffix {
            self.imageCustomSuffix = newDefaultSuffix
        }
        if self.videoCustomSuffix == prevDefaultSuffix {
            self.videoCustomSuffix = newDefaultSuffix
        }
        
        self.decompressSettings.createSubfolder = UserDefaults.standard.bool(forKey: "decompress_create_subfolder")
        self.decompressSettings.overwriteExisting = UserDefaults.standard.bool(forKey: "decompress_overwrite_existing")
        
        // Sync unified settings to task-specific settings
        let useFFmpeg = UserDefaults.standard.bool(forKey: "use_ffmpeg")
        UserDefaults.standard.set(useFFmpeg, forKey: "use_ffmpeg_for_video_compression")
        UserDefaults.standard.set(useFFmpeg, forKey: "use_ffmpeg_for_video_conversion")
        UserDefaults.standard.set(useFFmpeg, forKey: "use_ffmpeg_for_audio_compression")
        UserDefaults.standard.set(useFFmpeg, forKey: "use_ffmpeg_for_audio_conversion")
        
        let useMagick = UserDefaults.standard.bool(forKey: "use_magick")
        UserDefaults.standard.set(useMagick, forKey: "use_magick_for_image_compression")
        UserDefaults.standard.set(useMagick, forKey: "use_magick_for_image_conversion")
        
        let usePandoc = UserDefaults.standard.bool(forKey: "use_pandoc")
        UserDefaults.standard.set(usePandoc, forKey: "use_pandoc_for_document_conversion")
        
        let imgRatio = UserDefaults.shared.double(forKey: "default_image_shrink_ratio")
        self.imageSettings.targetSizeRatio = imgRatio > 0 ? imgRatio : 0.8
        
        let vidRatio = UserDefaults.shared.double(forKey: "default_video_shrink_ratio")
        self.videoSettings.targetSizeRatio = vidRatio > 0 ? vidRatio : 0.7
        
        let audBitrate = UserDefaults.shared.integer(forKey: "default_audio_bitrate")
        self.audioSettings.bitrate = audBitrate > 0 ? audBitrate : 128000
        
        let archiveLevel = UserDefaults.shared.integer(forKey: "default_archive_compression_level")
        self.archiveSettings.compressionLevel = archiveLevel > 0 ? archiveLevel : 5
        
        self.coerceDisabledFormats()
    }
    
    private func coerceDisabledFormats() {
        let enabledCompressionFormats = ArchiveFormat.allCases.filter { ArchiveSettingsManager.isCompressionEnabled(for: $0) }
        
        if !enabledCompressionFormats.isEmpty {
            if !ArchiveSettingsManager.isCompressionEnabled(for: archiveSettings.format) {
                archiveSettings.format = enabledCompressionFormats.first ?? .zip
            }
            if !ArchiveSettingsManager.isCompressionEnabled(for: imageArchiveFormat) {
                imageArchiveFormat = enabledCompressionFormats.first ?? .zip
            }
            if !ArchiveSettingsManager.isCompressionEnabled(for: videoArchiveFormat) {
                videoArchiveFormat = enabledCompressionFormats.first ?? .zip
            }
            if !ArchiveSettingsManager.isCompressionEnabled(for: convertArchiveFormat) {
                convertArchiveFormat = enabledCompressionFormats.first ?? .zip
            }
        }
    }
    
    // Derived properties
    var totalSize: Int64 {
        selectedFiles.reduce(0) { $0 + recursiveCheckedSize(of: $1) }
    }
    
    private func recursiveCheckedSize(of item: FileItem) -> Int64 {
        if !item.isDirectory {
            return item.isChecked ? item.originalSize : 0
        }
        if item.isChecked && item.subItems.isEmpty {
            return item.originalSize
        }
        var size: Int64 = 0
        for sub in item.subItems {
            size += recursiveCheckedSize(of: sub)
        }
        return size
    }
    
    var isArchiveMode: Bool {
        return outputStyle == .archive
    }
    
    var aggregateDetectedTypes: Set<FileType> {
        var types: Set<FileType> = []
        for file in selectedFiles {
            collectCheckedTypesRecursive(in: file, types: &types)
        }
        return types
    }
    
    private func collectCheckedTypesRecursive(in item: FileItem, types: inout Set<FileType>) {
        if !item.isDirectory {
            if item.isChecked {
                types.insert(item.fileType)
            }
        } else {
            if item.isChecked {
                if item.subItems.isEmpty {
                    types.formUnion(item.detectedTypes)
                } else {
                    for sub in item.subItems {
                        collectCheckedTypesRecursive(in: sub, types: &types)
                    }
                }
            }
        }
    }
    
    func totalSize(for type: FileType) -> Int64 {
        selectedFiles.reduce(0) { $0 + recursiveCheckedSize(of: $1, for: type) }
    }
    
    private func recursiveCheckedSize(of item: FileItem, for type: FileType) -> Int64 {
        if !item.isDirectory {
            return (item.isChecked && item.fileType == type) ? item.originalSize : 0
        }
        if item.isChecked && item.subItems.isEmpty {
            return item.typeSizes[type] ?? 0
        }
        var size: Int64 = 0
        for sub in item.subItems {
            size += recursiveCheckedSize(of: sub, for: type)
        }
        return size
    }
    
    // Get predominant file type if uniform selection
    var predominantType: FileType? {
        let checked = collectCheckedFilesRecursive(in: selectedFiles)
        guard !checked.isEmpty else { return nil }
        let firstType = checked.first!.fileType
        if checked.allSatisfy({ $0.fileType == firstType }) {
            return firstType
        }
        return nil
    }
    
    private func collectCheckedFilesRecursive(in list: [FileItem]) -> [FileItem] {
        var files: [FileItem] = []
        for item in list {
            if !item.isDirectory {
                if item.isChecked {
                    files.append(item)
                }
            } else {
                files.append(contentsOf: collectCheckedFilesRecursive(in: item.subItems))
            }
        }
        return files
    }
    
    // Resolved Output Directory
    var resolvedOutputDirectory: URL? {
        resolvedOutputDirectory(for: .all)
    }
    
    var resolvedConvertOutputDirectory: URL? {
        switch convertOutputLocationType {
        case .sameAsSource:
            guard let firstURL = selectedFiles.first(where: { $0.isChecked })?.url ?? selectedFiles.first?.url else { return nil }
            return firstURL.deletingLastPathComponent()
        case .downloads:
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        case .desktop:
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        case .custom:
            return convertCustomOutputFolder
        }
    }
    
    func resolvedOutputDirectory(for filter: MediaFilter) -> URL? {
        let locationType: OutputLocationType
        let customFolder: URL?
        
        switch filter {
        case .all:
            locationType = outputLocationType
            customFolder = customOutputFolder
        case .imagesOnly:
            locationType = imageOutputLocationType
            customFolder = imageCustomOutputFolder
        case .videosOnly:
            locationType = videoOutputLocationType
            customFolder = videoCustomOutputFolder
        case .audioOnly:
            locationType = audioOutputLocationType
            customFolder = audioCustomOutputFolder
        case .pdfOnly:
            locationType = pdfOutputLocationType
            customFolder = pdfCustomOutputFolder
        }
        
        return resolveURL(for: locationType, customFolder: customFolder)
    }
    
    private func resolveURL(for locationType: OutputLocationType, customFolder: URL?) -> URL? {
        switch locationType {
        case .sameAsSource:
            // Use the parent directory of the first *checked* file as the source.
            guard let firstURL = selectedFiles.first(where: { $0.isChecked })?.url else { return nil }
            return firstURL.deletingLastPathComponent()
        case .downloads:
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        case .desktop:
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        case .custom:
            return customFolder
        }
    }
    
    // Add items by file URLs
    func addFiles(urls: [URL]) {
        var newlyAddedID: UUID? = nil
        for url in urls {
            // Resolve file-reference or security-scoped URLs to standard file path URLs
            let cleanURL = url.resolvingSymlinksInPath().standardized
            
            // Avoid duplicates, but reset status if already completed or failed
            if let existingIndex = selectedFiles.firstIndex(where: { $0.url.standardizedFileURL.path == cleanURL.standardizedFileURL.path }) {
                let status = selectedFiles[existingIndex].status
                switch status {
                case .completed, .failed:
                    selectedFiles[existingIndex].status = .pending
                default:
                    break
                }
            } else {
                let item = FileItem(url: cleanURL)
                selectedFiles.append(item)
                if newlyAddedID == nil { newlyAddedID = item.id }
                
                let itemId = item.id
                
                // Load metadata and folder contents asynchronously
                Task {
                    if item.isDirectory {
                        // For directories, perform a lightweight metadata scan in the background.
                        // This gets total size and type info without building the whole UI tree.
                        let scanResult = await FileItem.calculateFolderMetadataAsync(at: cleanURL)
                        await MainActor.run {
                            if let idx = self.selectedFiles.firstIndex(where: { $0.id == itemId }) {
                                self.selectedFiles[idx].originalSize = scanResult.size
                                self.selectedFiles[idx].detectedTypes = scanResult.detectedTypes
                                self.selectedFiles[idx].typeCounts = scanResult.typeCounts
                                self.selectedFiles[idx].typeSizes = scanResult.typeSizes
                                self.selectedFiles[idx].subMediaItems = scanResult.subMediaItems
                                self.selectedFiles[idx].extensionCounts = scanResult.extensionCounts
                                self.selectedFiles[idx].subItems = [] // Sub-items are loaded lazily on expansion
                                self.updateModeBasedOnSelection()
                            }
                        }
                    } else {
                        // For single files, just read their metadata.
                        let meta = await FileMetadataReader.readMetadata(for: cleanURL)
                        await MainActor.run {
                            if let idx = self.selectedFiles.firstIndex(where: { $0.id == itemId }) {
                                self.selectedFiles[idx].width = meta.width
                                self.selectedFiles[idx].height = meta.height
                                self.selectedFiles[idx].duration = meta.duration
                                self.selectedFiles[idx].frameRate = meta.frameRate
                                
                                // If it's an archive, also list its contents asynchronously.
                                if self.selectedFiles[idx].fileType == .archive {
                                    Task {
                                        let entries = await ArchiveCompressor.listContents(archiveURL: cleanURL)
                                        await MainActor.run {
                                            if let idx = self.selectedFiles.firstIndex(where: { $0.id == itemId }) {
                                                if !entries.isEmpty {
                                                    var nodeMap: [String: FileItem] = [:]
                                                    @MainActor func makeVirtualItem(path: String, isDir: Bool, size: Int64) -> FileItem? {
                                                        guard let virtualURL = URL(string: cleanURL.absoluteString + "/" + path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!) else { return nil }
                                                        var item = FileItem(url: virtualURL)
                                                        item.originalSize = size
                                                        let detected = FileItem.getFileTypeForURL(URL(fileURLWithPath: path))
                                                        item.detectedTypes = [detected]
                                                        item.typeCounts = [detected: 1]
                                                        item.typeSizes = [detected: size]
                                                        item.isVirtualDirectory = isDir
                                                        item.archiveEntryPath = path
                                                        item.parentArchiveURL = cleanURL
                                                        return item
                                                    }

                                                    for (entryPath, entrySize, entryIsDir) in entries {
                                                        let normalized = entryPath.trimmingCharacters(in: .whitespacesAndNewlines)
                                                        if normalized.isEmpty { continue }
                                                        if let item = makeVirtualItem(path: normalized, isDir: entryIsDir, size: entrySize) {
                                                            nodeMap[normalized] = item
                                                        }
                                                    }

                                                    for path in Array(nodeMap.keys).sorted(by: { $0.count < $1.count }) {
                                                        let components = path.split(separator: "/").map { String($0) }
                                                        if components.count <= 1 { continue }
                                                        var parentComponents = components
                                                        parentComponents.removeLast()
                                                        var parentPath = parentComponents.joined(separator: "/")
                                                        while true {
                                                            if nodeMap[parentPath] == nil, let pitem = makeVirtualItem(path: parentPath, isDir: true, size: 0) {
                                                                nodeMap[parentPath] = pitem
                                                            }
                                                            if let child = nodeMap[path], let _ = nodeMap[parentPath] {
                                                                if !nodeMap[parentPath]!.subItems.contains(where: { $0.archiveEntryPath == child.archiveEntryPath }) {
                                                                    nodeMap[parentPath]!.subItems.append(child)
                                                                }
                                                            }
                                                            if parentPath.contains("/") {
                                                                var comps = parentPath.split(separator: "/").map { String($0) }
                                                                comps.removeLast()
                                                                parentPath = comps.joined(separator: "/")
                                                            } else {
                                                                break
                                                            }
                                                        }
                                                    }

                                                    var topLevel: [FileItem] = []
                                                    for (p, node) in nodeMap {
                                                        let parentPath = (p as NSString).deletingLastPathComponent
                                                        if parentPath.isEmpty || nodeMap[parentPath] == nil {
                                                            topLevel.append(node)
                                                        }
                                                    }
                                                    topLevel.sort { (lhs, rhs) -> Bool in
                                                        if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
                                                        return lhs.name.localizedCompare(rhs.name) == .orderedAscending
                                                    }

                                                    self.selectedFiles[idx].subItems = topLevel
                                                    self.selectedFiles[idx].isVirtualDirectory = true
                                                }
                                                self.recalculateParentCheckedStates()
                                                self.selectedFiles = self.selectedFiles
                                            }
                                        }
                                    }
                                }
                                self.updateModeBasedOnSelection()
                            }
                        }
                    }
                }
            }
        }
        
        // Auto populate output archive name if empty and we have files
        if customOutputName.isEmpty, let first = selectedFiles.first {
            if selectedFiles.count == 1 {
                customOutputName = first.url.deletingPathExtension().lastPathComponent + "_shrunk"
            } else {
                customOutputName = "archive_shrunk"
            }
        }
        
        if let newID = newlyAddedID {
            selectedFileID = newID
        } else if selectedFileID == nil, let first = selectedFiles.first {
            selectedFileID = first.id
        }
        
        // Default the main output style to archive. Other sections have their own styles.
        outputStyle = .archive
        
        // Default output destinations to Same as Source when files are imported
        outputLocationType = .sameAsSource
        imageOutputLocationType = .sameAsSource
        videoOutputLocationType = .sameAsSource
        audioOutputLocationType = .sameAsSource
        convertOutputLocationType = .sameAsSource
        
        validateOutputStyles()
        updateModeBasedOnSelection()
    }
    
    func validateOutputStyles() {
        let hasFolder = selectedFiles.contains(where: { $0.isDirectory })
        if !hasFolder && outputStyle == .extractMedia {
            outputStyle = .archive
        }
        
        let defaultName: String
        if let first = selectedFiles.first {
            defaultName = selectedFiles.count == 1 ? first.url.deletingPathExtension().lastPathComponent + "_shrunk" : "archive_shrunk"
        } else {
            defaultName = ""
        }
        
        let defaultImageName = selectedFiles.count == 1 ? defaultName : "images_shrunk"
        let defaultVideoName = selectedFiles.count == 1 ? defaultName : "videos_shrunk"
        
        if customOutputName.isEmpty || customOutputName == "archive_shrink" || customOutputName == "archive_shrunk" || customOutputName == "extracted_media" || customOutputName == "extracted_media_shrunk" || customOutputName.hasSuffix("_shrunk") {
            if outputStyle == .extractMedia {
                customOutputName = "extracted_media_shrunk"
            } else {
                customOutputName = defaultName
            }
        }
        
        if imageCustomOutputName.isEmpty || imageCustomOutputName == "images_shrunk" || imageCustomOutputName == "archive_shrunk" || imageCustomOutputName.hasSuffix("_shrunk") {
            imageCustomOutputName = defaultImageName
        }
        
        if videoCustomOutputName.isEmpty || videoCustomOutputName == "videos_shrunk" || videoCustomOutputName == "archive_shrunk" || videoCustomOutputName.hasSuffix("_shrunk") {
            videoCustomOutputName = defaultVideoName
        }
        
        let defaultPdfName = selectedFiles.count == 1 ? defaultName : "pdf_shrunk"
        if pdfCustomOutputName.isEmpty || pdfCustomOutputName == "pdf_shrunk" || pdfCustomOutputName == "archive_shrunk" || pdfCustomOutputName.hasSuffix("_shrunk") {
            pdfCustomOutputName = defaultPdfName
        }
    }
    
    // Remove item
    func removeFile(id: UUID) {
        if selectedFiles.contains(where: { $0.id == id }) {
            selectedFiles.removeAll { $0.id == id }
            if selectedFileID == id {
                selectedFileID = selectedFiles.first?.id
            }
            if selectedFiles.isEmpty {
                customOutputName = ""
            }
        } else {
            // Recursively remove from subItems
            for i in 0..<selectedFiles.count {
                if removeFileRecursive(in: &selectedFiles[i], id: id) {
                    break
                }
            }
        }
        recalculateParentCheckedStates()
        selectedFiles = selectedFiles
        validateOutputStyles()
        updateModeBasedOnSelection()
    }
    
    private func removeFileRecursive(in item: inout FileItem, id: UUID) -> Bool {
        if item.subItems.contains(where: { $0.id == id }) {
            item.subItems.removeAll { $0.id == id }
            return true
        }
        for i in 0..<item.subItems.count {
            if removeFileRecursive(in: &item.subItems[i], id: id) {
                return true
            }
        }
        return false
    }
    
    func toggleFileChecked(id: UUID) {
        // Search in top-level items
        if let idx = selectedFiles.firstIndex(where: { $0.id == id }) {
            selectedFiles[idx].isChecked.toggle()
            let checkedState = selectedFiles[idx].isChecked
            setAllSubItemsChecked(in: &selectedFiles[idx], checked: checkedState)
            if !checkedState && selectedFileID == id {
                selectedFileID = nil
            }
        } else {
            // Search recursively in subItems
            for i in 0..<selectedFiles.count {
                if toggleFileCheckedRecursive(in: &selectedFiles[i], id: id) {
                    break
                }
            }
        }
        
        // Reset location type to sameAsSource when selection changes
        outputLocationType = .sameAsSource
        imageOutputLocationType = .sameAsSource
        videoOutputLocationType = .sameAsSource
        audioOutputLocationType = .sameAsSource
        convertOutputLocationType = .sameAsSource
        
        recalculateParentCheckedStates()
        selectedFiles = selectedFiles
        updateModeBasedOnSelection()
    }
    
    func selectSingleFile(id: UUID) {
        guard let item = findFile(id: id) else { return }
        
        if item.isChecked {
            // If already selected, deselect it (uncheck it and its sub-items)
            setFileChecked(id: id, checked: false)
            if selectedFileID == id {
                selectedFileID = nil
            }
        } else {
            // Deselect all files first
            for i in 0..<selectedFiles.count {
                selectedFiles[i].isChecked = false
                setAllSubItemsChecked(in: &selectedFiles[i], checked: false)
            }
            
            // Now select this file
            setFileChecked(id: id, checked: true)
            selectedFileID = id
        }
        
        // Reset location type to sameAsSource when selection changes
        outputLocationType = .sameAsSource
        imageOutputLocationType = .sameAsSource
        videoOutputLocationType = .sameAsSource
        audioOutputLocationType = .sameAsSource
        convertOutputLocationType = .sameAsSource
        
        recalculateParentCheckedStates()
        selectedFiles = selectedFiles
        updateModeBasedOnSelection()
    }
    
    private func setFileChecked(id: UUID, checked: Bool) {
        if let idx = selectedFiles.firstIndex(where: { $0.id == id }) {
            selectedFiles[idx].isChecked = checked
            setAllSubItemsChecked(in: &selectedFiles[idx], checked: checked)
        } else {
            for i in 0..<selectedFiles.count {
                if setFileCheckedRecursive(in: &selectedFiles[i], id: id, checked: checked) {
                    break
                }
            }
        }
    }
    
    private func setFileCheckedRecursive(in item: inout FileItem, id: UUID, checked: Bool) -> Bool {
        if let idx = item.subItems.firstIndex(where: { $0.id == id }) {
            item.subItems[idx].isChecked = checked
            setAllSubItemsChecked(in: &item.subItems[idx], checked: checked)
            return true
        }
        for i in 0..<item.subItems.count {
            if setFileCheckedRecursive(in: &item.subItems[i], id: id, checked: checked) {
                return true
            }
        }
        return false
    }
    
    func toggleAllChecked(target: Bool) {
        for i in 0..<selectedFiles.count {
            selectedFiles[i].isChecked = target
            setAllSubItemsChecked(in: &selectedFiles[i], checked: target)
        }
        selectedFiles = selectedFiles
        updateModeBasedOnSelection()
    }
    
    func cascadeImageSettings(ratio: Double) {
        imageSettings.targetSizeRatio = ratio
        for i in 0..<selectedFiles.count {
            cascadeImageSettingsRecursive(in: &selectedFiles[i], ratio: ratio)
        }
        selectedFiles = selectedFiles
    }
    
    private func cascadeImageSettingsRecursive(in item: inout FileItem, ratio: Double) {
        if item.isChecked {
            if item.isDirectory {
                for j in 0..<item.subMediaItems.count {
                    if item.subMediaItems[j].fileType == .image && !item.subMediaItems[j].isManuallyAdjusted {
                        item.subMediaItems[j].targetSizeRatio = ratio
                    }
                }
                for j in 0..<item.subItems.count {
                    cascadeImageSettingsRecursive(in: &item.subItems[j], ratio: ratio)
                }
            } else if item.fileType == .image && !item.isManuallyAdjusted {
                item.customTargetSizeRatio = ratio
            }
        }
    }
    
    func cascadeVideoSettings(ratio: Double) {
        videoSettings.targetSizeRatio = ratio
        for i in 0..<selectedFiles.count {
            cascadeVideoSettingsRecursive(in: &selectedFiles[i], ratio: ratio)
        }
        selectedFiles = selectedFiles
    }
    
    private func cascadeVideoSettingsRecursive(in item: inout FileItem, ratio: Double) {
        if item.isChecked {
            if item.isDirectory {
                for j in 0..<item.subMediaItems.count {
                    if item.subMediaItems[j].fileType == .video && !item.subMediaItems[j].isManuallyAdjusted {
                        item.subMediaItems[j].targetSizeRatio = ratio
                        
                        let duration = item.duration ?? 30.0
                        let subItem = item.subMediaItems[j]
                        let originalSize = Double(subItem.originalSize)
                        let audioBitrate = Double(subItem.customAudioBitrate ?? videoSettings.audioBitrate)
                        let audioMode = subItem.customAudioMode ?? videoSettings.audioMode
                        let audioBytes = (audioMode == "Mute" ? 0.0 : audioBitrate / 8.0) * duration
                        let targetSizeBytes = originalSize * ratio
                        let videoBytes = max(targetSizeBytes - audioBytes, targetSizeBytes * 0.15)
                        let kbps = Int((videoBytes * 8.0) / (duration * 1000.0))
                        item.subMediaItems[j].customTargetBitrateKbps = max(200, min(kbps, 100000))
                    }
                }
                for j in 0..<item.subItems.count {
                    cascadeVideoSettingsRecursive(in: &item.subItems[j], ratio: ratio)
                }
            } else if item.fileType == .video && !item.isManuallyAdjusted {
                item.customTargetSizeRatio = ratio
                
                let duration = item.duration ?? 30.0
                let originalSize = Double(item.originalSize)
                let audioBitrate = Double(item.customAudioBitrate ?? videoSettings.audioBitrate)
                let audioMode = item.customAudioMode ?? videoSettings.audioMode
                let audioBytes = (audioMode == "Mute" ? 0.0 : audioBitrate / 8.0) * duration
                let targetSizeBytes = originalSize * ratio
                let videoBytes = max(targetSizeBytes - audioBytes, targetSizeBytes * 0.15)
                let kbps = Int((videoBytes * 8.0) / (duration * 1000.0))
                item.customTargetBitrateKbps = max(200, min(kbps, 100000))
            }
        }
    }
    
    func cascadeVideoBitrateSettings(kbps: Int) {
        videoSettings.targetBitrateKbps = kbps
        for i in 0..<selectedFiles.count {
            cascadeVideoBitrateSettingsRecursive(in: &selectedFiles[i], kbps: kbps)
        }
        selectedFiles = selectedFiles
    }
    
    private func cascadeVideoBitrateSettingsRecursive(in item: inout FileItem, kbps: Int) {
        if item.isChecked {
            if item.isDirectory {
                for j in 0..<item.subMediaItems.count {
                    if item.subMediaItems[j].fileType == .video && !item.subMediaItems[j].isManuallyAdjusted {
                        item.subMediaItems[j].customTargetBitrateKbps = kbps
                        item.subMediaItems[j].customCompressionMethod = .bitrate
                        
                        let duration = item.duration ?? 30.0
                        let subItem = item.subMediaItems[j]
                        let originalSize = Double(subItem.originalSize)
                        let audioBitrate = Double(subItem.customAudioBitrate ?? videoSettings.audioBitrate)
                        let audioMode = subItem.customAudioMode ?? videoSettings.audioMode
                        let audioBytes = (audioMode == "Mute" ? 0.0 : audioBitrate / 8.0) * duration
                        let videoBytes = (Double(kbps * 1000) / 8.0) * duration
                        let totalBytes = videoBytes + audioBytes
                        item.subMediaItems[j].targetSizeRatio = max(0.05, min(1.0, totalBytes / originalSize))
                    }
                }
                for j in 0..<item.subItems.count {
                    cascadeVideoBitrateSettingsRecursive(in: &item.subItems[j], kbps: kbps)
                }
            } else if item.fileType == .video && !item.isManuallyAdjusted {
                item.customTargetBitrateKbps = kbps
                item.customCompressionMethod = .bitrate
                
                let duration = item.duration ?? 30.0
                let originalSize = Double(item.originalSize)
                let audioBitrate = Double(item.customAudioBitrate ?? videoSettings.audioBitrate)
                let audioMode = item.customAudioMode ?? videoSettings.audioMode
                let audioBytes = (audioMode == "Mute" ? 0.0 : audioBitrate / 8.0) * duration
                let videoBytes = (Double(kbps * 1000) / 8.0) * duration
                let totalBytes = videoBytes + audioBytes
                item.customTargetSizeRatio = max(0.05, min(1.0, totalBytes / originalSize))
            }
        }
    }


    
    private func setAllSubItemsChecked(in item: inout FileItem, checked: Bool) {
        for j in 0..<item.subItems.count {
            item.subItems[j].isChecked = checked
            if item.subItems[j].isDirectory {
                setAllSubItemsChecked(in: &item.subItems[j], checked: checked)
            }
        }
    }
    
    private func toggleFileCheckedRecursive(in item: inout FileItem, id: UUID) -> Bool {
        if let idx = item.subItems.firstIndex(where: { $0.id == id }) {
            item.subItems[idx].isChecked.toggle()
            let checkedState = item.subItems[idx].isChecked
            setAllSubItemsChecked(in: &item.subItems[idx], checked: checkedState)
            if !checkedState && selectedFileID == id {
                selectedFileID = nil
            }
            return true
        }
        for i in 0..<item.subItems.count {
            if toggleFileCheckedRecursive(in: &item.subItems[i], id: id) {
                return true
            }
        }
        return false
    }
    
    func recalculateParentCheckedStates() {
        for i in 0..<selectedFiles.count {
            if selectedFiles[i].isDirectory {
                _ = recalculateFolderCheckedState(in: &selectedFiles[i])
            }
        }
    }
    
    @discardableResult
    private func recalculateFolderCheckedState(in item: inout FileItem) -> Bool {
        guard item.isDirectory else { return item.isChecked }
        
        if item.subItems.isEmpty {
            return item.isChecked
        }
        
        var anySubChecked = false
        for j in 0..<item.subItems.count {
            let subChecked = recalculateFolderCheckedState(in: &item.subItems[j])
            if subChecked {
                anySubChecked = true
            }
        }
        
        item.isChecked = anySubChecked
        return anySubChecked
    }
    
    func toggleFileExpanded(id: UUID) {
        _ = toggleFileExpandedRecursive(in: &selectedFiles, id: id)
        
        // If expanding, populate folder contents if needed
        if let path = findIndexPath(for: id) {
            // Check if the item is now expanded and needs population
            Task {
                await populateFolderIfNeeded(at: path)
            }
        }
        selectedFiles = selectedFiles
    }
    
    private func toggleFileExpandedRecursive(in items: inout [FileItem], id: UUID) -> Bool {
        for i in 0..<items.count {
            if items[i].id == id {
                items[i].isExpanded.toggle()
                return true
            }
            if !items[i].subItems.isEmpty {
                if toggleFileExpandedRecursive(in: &items[i].subItems, id: id) {
                    return true
                }
            }
        }
        return false
    }

    // Find index path to an item as array of indices into selectedFiles/subItems
    private func findIndexPath(for id: UUID) -> [Int]? {
        for i in 0..<selectedFiles.count {
            if selectedFiles[i].id == id { return [i] }
            if let path = findIndexPathRecursive(in: selectedFiles[i], id: id, prefix: [i]) {
                return path
            }
        }
        return nil
    }

    private func findIndexPathRecursive(in item: FileItem, id: UUID, prefix: [Int]) -> [Int]? {
        for j in 0..<item.subItems.count {
            if item.subItems[j].id == id { return prefix + [j] }
            if let deeper = findIndexPathRecursive(in: item.subItems[j], id: id, prefix: prefix + [j]) {
                return deeper
            }
        }
        return nil
    }

    // Populate folder contents asynchronously when expanded and empty
    @MainActor
    private func populateFolderIfNeeded(at indexPath: [Int]) async {        
        // Use the helper to get a reference to the item to be populated
        guard var item = findFile(at: indexPath) else { return }
        
        // Only populate if it's an expanded directory and has no subItems yet.
        if !item.isDirectory || !item.isExpanded || !item.subItems.isEmpty {
            return
        }

        // Perform a shallow scan to get immediate children.
        let folderURL = item.url
        let scanResult = await FileItem.scanFolderAsync(at: folderURL, shallow: true)

        // Update the item's subItems and ensure their checked state matches the parent.
        // The shallow scan now correctly calculates sub-directory sizes, so no extra loop is needed.
        item.subItems = scanResult.subItems
        
        // Resolve statuses from disk
        resolveSubItemStatusesForFolder(item: &item)
        
        setAllSubItemsCheckedRecursive(&item, checked: item.isChecked)

        // Write the modified item back into the main data structure.
        writeItemBack(item, at: indexPath)
        
        // After populating, kick off background tasks to calculate the total size
        // for any new sub-directories. This updates their UI from "0 B" to their real size.
        for subItem in item.subItems where subItem.isDirectory {
            Task.detached(priority: .background) {
                let subItemSize = await FileItem.calculateFolderSizeAsync(at: subItem.url)
                await MainActor.run { [weak self] in
                    self?.updateFileItem(id: subItem.id) { file in
                        file.originalSize = subItemSize
                    }
                }
            }
        }
    }
    
    func resolveSubItemStatusesForFolder(item: inout FileItem) {
        let cleanName = item.url.deletingPathExtension().lastPathComponent
        
        var candidateDirs: [URL] = []
        if case .completed(_, let destFolderURL) = item.status {
            candidateDirs.append(destFolderURL)
        }
        
        let filters: [MediaFilter] = [.all, .imagesOnly, .videosOnly, .audioOnly, .pdfOnly]
        for filter in filters {
            if let outputDir = resolvedOutputDirectory(for: filter) {
                candidateDirs.append(outputDir)
                let subfolderName = individualSubfolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Compressed_Files" : individualSubfolderName
                candidateDirs.append(outputDir.appendingPathComponent(subfolderName))
                
                let suffixes = [customSuffix, videoCustomSuffix, imageCustomSuffix, audioCustomSuffix, pdfCustomSuffix, convertCustomSuffix, "_shrunk"]
                for suffix in suffixes {
                    candidateDirs.append(outputDir.appendingPathComponent("\(cleanName)\(suffix)"))
                }
            }
        }
        
        let suffixes = Array(Set([
            customSuffix,
            videoCustomSuffix,
            imageCustomSuffix,
            audioCustomSuffix,
            pdfCustomSuffix,
            convertCustomSuffix,
            ""
        ]))
        
        for j in 0..<item.subItems.count {
            let subItem = item.subItems[j]
            if case .completed = subItem.status {
                continue
            }
            
            let subCleanName = subItem.url.deletingPathExtension().lastPathComponent
            let parentPrefixLength = item.url.path.hasSuffix("/") ? item.url.path.count : item.url.path.count + 1
            let relativeDir = subItem.url.deletingLastPathComponent()
            let relativePathDir = String(relativeDir.path.dropFirst(parentPrefixLength))
            
            var resolvedTargetURL: URL? = nil
            for destFolderURL in Array(Set(candidateDirs)) {
                let targetSubfolderURL = relativePathDir.isEmpty ? destFolderURL : destFolderURL.appendingPathComponent(relativePathDir)
                
                let subExtensions = Array(Set([
                    subItem.url.pathExtension.lowercased(),
                    "mp4",
                    imageSettings.format.lowercased(),
                    audioSettings.format.lowercased(),
                    "pdf"
                ]))
                
                for suffix in suffixes {
                    for ext in subExtensions {
                        let targetName = "\(subCleanName)\(suffix).\(ext)"
                        let testURL1 = targetSubfolderURL.appendingPathComponent(targetName)
                        if FileManager.default.fileExists(atPath: testURL1.path) {
                            resolvedTargetURL = testURL1
                            break
                        }
                        let testURL2 = destFolderURL.deletingLastPathComponent().appendingPathComponent(targetName)
                        if FileManager.default.fileExists(atPath: testURL2.path) {
                            resolvedTargetURL = testURL2
                            break
                        }
                    }
                    if resolvedTargetURL != nil { break }
                }
                if resolvedTargetURL != nil { break }
            }
            
            if let targetURL = resolvedTargetURL {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir) {
                    if isDir.boolValue {
                        item.subItems[j].status = .completed(newSize: 0, outputURL: targetURL)
                        
                        let subItemId = subItem.id
                        Task.detached(priority: .background) {
                            let size = await FileItem.calculateFolderSizeAsync(at: targetURL)
                            await MainActor.run { [weak self] in
                                self?.updateFileItem(id: subItemId) { file in
                                    if case .completed(_, let outURL) = file.status {
                                        file.status = .completed(newSize: size, outputURL: outURL)
                                    }
                                }
                            }
                        }
                    } else {
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: targetURL.path),
                           let size = attrs[.size] as? Int64 {
                            item.subItems[j].status = .completed(newSize: size, outputURL: targetURL)
                        }
                    }
                }
            } else {
                if case .completed(_, let destURL) = item.status {
                    item.subItems[j].status = .completed(newSize: 0, outputURL: destURL)
                }
            }
        }
    }

    // Helper to write modified item back into selectedFiles using index path
    @MainActor
    private func writeItemBack(_ newItem: FileItem, at indexPath: [Int]) {
        guard !indexPath.isEmpty else { return }
        if indexPath.count == 1 {
            let top = indexPath[0]
            if top < selectedFiles.count {
                selectedFiles[top] = newItem
            }
            selectedFiles = selectedFiles
            return
        }

        func helper(_ arr: inout [FileItem], _ path: [Int]) {
            guard !path.isEmpty else { return }
            if path.count == 1 {
                let idx = path[0]
                if idx < arr.count {
                    arr[idx] = newItem
                }
                return
            }
            let first = path[0]
            let rest = Array(path.dropFirst())
            if first < arr.count {
                helper(&arr[first].subItems, rest)
            }
        }

        let path = indexPath
        helper(&selectedFiles, path)
        selectedFiles = selectedFiles
    }

    // Helper to find a FileItem at a specific index path.
    // Returns a copy of the item.
    private func findFile(at indexPath: [Int]) -> FileItem? {
        guard !indexPath.isEmpty else { return nil }
        var path = indexPath
        
        let topIndex = path.removeFirst()
        guard topIndex < selectedFiles.count else { return nil }
        var currentItem = selectedFiles[topIndex]
        
        while !path.isEmpty {
            let subIndex = path.removeFirst()
            guard subIndex < currentItem.subItems.count else { return nil }
            currentItem = currentItem.subItems[subIndex]
        }
        
        return currentItem
    }

    // Recursively set checked state for subitems
    private func setAllSubItemsCheckedRecursive(_ item: inout FileItem, checked: Bool) {
        for j in 0..<item.subItems.count {
            item.subItems[j].isChecked = checked
            if item.subItems[j].isDirectory {
                setAllSubItemsCheckedRecursive(&item.subItems[j], checked: checked)
            }
        }
    }
    
    // Clear all items
    func clearFiles() {
        selectedFiles.removeAll()
        selectedFileID = nil
        customOutputName = ""
        currentProgress = 0.0
        isProcessing = false
        stopTimer()
        validateOutputStyles()
        updateModeBasedOnSelection()
    }
    
    func updateModeBasedOnSelection() {
        let checked = selectedFiles.filter { $0.isChecked }
        guard !checked.isEmpty else { return }
        
        let allArchives = checked.allSatisfy { $0.fileType == .archive }
        if allArchives {
            mode = .decompress
        } else {
            mode = .compress
        }
    }
    
    private func hasCheckedItemsRecursive(_ item: FileItem) -> Bool {
        if item.isChecked { return true }
        for sub in item.subItems {
            if hasCheckedItemsRecursive(sub) {
                return true
            }
        }
        return false
    }
    
    // Start processing
    func startShrinking(filter: MediaFilter = .all) {
        var filesToProcess = selectedFiles.filter { hasCheckedItemsRecursive($0) }
        
        // Handle ignore already compressed files
        if archiveHandlingMode == .ignore && mode == .compress {
            filesToProcess = filesToProcess.filter { $0.fileType != .archive }
        }
        
        guard !filesToProcess.isEmpty else { return }
        
        guard var outputDir = resolvedOutputDirectory(for: filter) else {
            return
        }
        
        isProcessing = true
        showProcessingOverlay = true
        currentProgress = 0.0
        fileProgresses.removeAll()
        activeJobTitle = mode == .compress ? "Compressing files..." : "Decompressing files..."
        elapsedSeconds = 0
        estimatedSecondsRemaining = nil
        compressionResult = nil
        compressionError = nil
        compressionStartTotalSize = filesToProcess.reduce(0) { $0 + $1.originalSize }
        
        // Start timer
        startTimer()
        
        // Resolve output style based on filter
        let resolvedStyle: OutputStyle
        switch filter {
        case .all:
            resolvedStyle = .archive // General tab automatically uses archive
        case .imagesOnly:
            resolvedStyle = imageOutputStyle
        case .videosOnly:
            resolvedStyle = videoOutputStyle
        case .audioOnly:
            resolvedStyle = audioOutputStyle
        case .pdfOnly:
            resolvedStyle = pdfOutputStyle
        }
        
        // Resolve archive format based on filter
        var resolvedArchiveSettings = archiveSettings
        switch filter {
        case .all:
            break
        case .imagesOnly:
            resolvedArchiveSettings.format = imageArchiveFormat
        case .videosOnly:
            resolvedArchiveSettings.format = videoArchiveFormat
        case .audioOnly:
            resolvedArchiveSettings.format = audioArchiveFormat
        case .pdfOnly:
            resolvedArchiveSettings.format = pdfArchiveFormat
        }
        
        // Resolve output name based on filter
        let resolvedOutputName: String
        let resolvedSuffix: String
        if filter == .imagesOnly {
            resolvedOutputName = imageCustomOutputName.isEmpty ? "images_shrunk" : imageCustomOutputName
            resolvedSuffix = imageCustomSuffix
        } else if filter == .videosOnly {
            resolvedOutputName = videoCustomOutputName.isEmpty ? "videos_shrunk" : videoCustomOutputName
            resolvedSuffix = videoCustomSuffix
        } else if filter == .audioOnly {
            resolvedOutputName = audioCustomOutputName.isEmpty ? "audio_shrunk" : audioCustomOutputName
            resolvedSuffix = audioCustomSuffix
        } else if filter == .pdfOnly {
            resolvedOutputName = pdfCustomOutputName.isEmpty ? "pdf_shrunk" : pdfCustomOutputName
            resolvedSuffix = pdfCustomSuffix
        } else {
            resolvedOutputName = customOutputName
            resolvedSuffix = customSuffix
        }
        
        // Create subfolder for individual mode if enabled
        if resolvedStyle == .subfolder {
            let folderName = resolvedOutputName.isEmpty ? "Compressed_Files" : resolvedOutputName
            let subfolderDir = outputDir.appendingPathComponent(folderName)
            do {
                try FileManager.default.createDirectory(at: subfolderDir, withIntermediateDirectories: true)
                outputDir = subfolderDir
            } catch {
                print("Failed to create subfolder for individual outputs: \(error)")
            }
        } else if resolvedStyle == .individual && saveIndividualToSubfolder {
            let folderName = individualSubfolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Compressed_Files" : individualSubfolderName
            let subfolderDir = outputDir.appendingPathComponent(folderName)
            do {
                try FileManager.default.createDirectory(at: subfolderDir, withIntermediateDirectories: true)
                outputDir = subfolderDir
            } catch {
                print("Failed to create subfolder for individual outputs: \(error)")
            }
        }
        
        // Instantiate engine
        let engine = CompressorEngine(state: self)
        self.engine = engine
        
        // Reset checked files statuses
        for i in 0..<selectedFiles.count {
            if selectedFiles[i].isChecked {
                selectedFiles[i].status = .pending
                for j in 0..<selectedFiles[i].subItems.count {
                    selectedFiles[i].subItems[j].status = .pending
                }
            }
        }
        
        // Package thread-safe compression configuration on MainActor
        let job = CompressionJob(
            mode: mode,
            outputDir: outputDir,
            selectedFiles: filesToProcess,
            customOutputName: resolvedOutputName,
            customSuffix: resolvedSuffix,
            predominantType: predominantType,
            imageSettings: imageSettings,
            videoSettings: videoSettings,
            audioSettings: audioSettings,
            archiveSettings: resolvedArchiveSettings,
            decompressSettings: decompressSettings,
            pdfSettings: pdfSettings,
            outputStyle: resolvedStyle,
            mediaFilter: filter,
        )
        
        // Launch background task
        Task.detached(priority: .userInitiated) {
            await engine.execute(job: job)
        }
    }
    
    // Cancel active operation
    func cancelShrinking() {
        let engineRef = engine
        engine = nil
        
        // Cancel in background to avoid blocking the UI
        Task.detached(priority: .userInitiated) {
            await engineRef?.cancel()
        }
        
        isProcessing = false
        showProcessingOverlay = false
        stopTimer()
        throughputText = ""
        
        // Mark remaining items as failed
        for i in 0..<selectedFiles.count {
            if case .processing = selectedFiles[i].status {
                selectedFiles[i].status = .failed(message: "Cancelled by user")
            } else if selectedFiles[i].status == .pending {
                selectedFiles[i].status = .failed(message: "Cancelled")
            }
        }
        
        if wasLaunchedByFinderSync {
            FinderSyncWindowManager.shared.closeProgressWindow()
            NSApp.terminate(nil)
        }
    }
    
    // Dismiss the completion/error overlay and return to file list
    func dismissCompletion() {
        compressionResult = nil
        compressionError = nil
        showProcessingOverlay = false
        throughputText = ""
        
        if wasLaunchedByFinderSync {
            FinderSyncWindowManager.shared.closeProgressWindow()
            NSApp.terminate(nil)
        }
    }
    
    // Timer helper
    private func startTimer() {
        stopTimer()
        let stats = compressionStats
        stats.reset()
        throughputText = ""
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task.detached(priority: .userInitiated) { [weak self, stats] in
                guard let self = self else { return }
                let (readSpeed, writeSpeed) = stats.getSpeedAndStep()
                
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.elapsedSeconds += 1
                    self.updateThroughputText(readSpeed: readSpeed, writeSpeed: writeSpeed)
                    
                    // Simple remaining time estimation based on progress
                    if self.currentProgress > 0.05 {
                        let totalEstimated = Double(self.elapsedSeconds) / self.currentProgress
                        let remaining = totalEstimated - Double(self.elapsedSeconds)
                        self.estimatedSecondsRemaining = Int(remaining)
                    }
                }
            }
        }
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    func updateThroughputText(readSpeed: Int64, writeSpeed: Int64) {
        let readStr = formatSpeed(readSpeed)
        let writeStr = formatSpeed(writeSpeed)
        throughputText = "R: \(readStr)  W: \(writeStr)"
    }
    
    private func formatSpeed(_ bytesPerSecond: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useGB]
        formatter.countStyle = .file
        let str = formatter.string(fromByteCount: bytesPerSecond)
        return "\(str)/s"
    }
    
    // MARK: - Format Conversion Support
    
    func installTool(_ tool: ExternalTool) async {
        self.installingTool = tool.name
        self.installProgressText = "Starting installation..."
        
        do {
            try await ExternalToolManager.install(tool) { [weak self] log in
                Task { @MainActor [weak self] in
                    self?.installProgressText = log
                }
            }
            self.installingTool = nil
            self.installProgressText = ""
        } catch {
            self.installProgressText = "Error: \(error.localizedDescription)"
            Task {
                try? await Task.sleep(for: .seconds(5))
                if self.installingTool == tool.name {
                    self.installingTool = nil
                    self.installProgressText = ""
                }
            }
        }
    }

    func uninstallTool(_ tool: ExternalTool) async {
        self.installingTool = tool.name
        self.installProgressText = "Starting uninstallation..."
        
        do {
            try await ExternalToolManager.uninstall(tool) { [weak self] log in
                Task { @MainActor [weak self] in
                    self?.installProgressText = log
                }
            }
            self.installingTool = nil
            self.installProgressText = ""
        } catch {
            self.installProgressText = "Error: \(error.localizedDescription)"
            Task {
                try? await Task.sleep(for: .seconds(5))
                if self.installingTool == tool.name {
                    self.installingTool = nil
                    self.installProgressText = ""
                }
            }
        }
    }
    
    func convertFileItem(_ fileItem: FileItem, targetFormat: String) {
        guard containsFile(id: fileItem.id) else { return }
        
        guard let outputDir = resolvedConvertOutputDirectory else { return }
        let cleanName = fileItem.url.deletingPathExtension().lastPathComponent
        let suffix = convertCustomSuffix.isEmpty ? "_converted" : convertCustomSuffix
        
        // Define base name of output
        let baseName: String
        if targetFormat.lowercased() == "pdf" && fileItem.fileType == .pdf {
            baseName = "\(cleanName)\(suffix).pdf"
        } else {
            baseName = "\(cleanName)\(suffix).\(targetFormat.lowercased())"
        }
        
        let targetOutputURL: URL
        let tempConvURL: URL?
        let isArchive = convertOutputStyle == .archive
        let isSubfolder = convertOutputStyle == .subfolder
        let archiveFormat = convertArchiveFormat
        
        if isArchive {
            // Write to a temporary directory first, then compress
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("shrink_conv_temp_" + UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            tempConvURL = tempDir.appendingPathComponent(baseName)
            
            let archiveName = convertCustomOutputName.isEmpty ? "\(cleanName)\(suffix)" : convertCustomOutputName
            let archiveExt = archiveFormat.fileExtension
            targetOutputURL = outputDir.appendingPathComponent("\(archiveName).\(archiveExt)")
        } else if isSubfolder {
            let folderName = convertCustomOutputName.isEmpty ? "Converted_Files" : convertCustomOutputName
            let subfolderURL = outputDir.appendingPathComponent(folderName)
            try? FileManager.default.createDirectory(at: subfolderURL, withIntermediateDirectories: true)
            tempConvURL = nil
            targetOutputURL = subfolderURL.appendingPathComponent(baseName)
        } else {
            // Individual
            tempConvURL = nil
            targetOutputURL = outputDir.appendingPathComponent(baseName)
        }
        
        let outputURLToUse = tempConvURL ?? targetOutputURL
        
        setFileStatus(id: fileItem.id, status: .processing(progress: 0.0))
        isProcessing = true
        activeJobTitle = "Converting: \(fileItem.name)..."
        
        let converter = FileConverter()
        activeConverters[fileItem.id] = converter
        
        let fileId = fileItem.id
        let inputURL = fileItem.url
        
        Task.detached(priority: .userInitiated) {
            do {
                let newSize = try await converter.convert(inputURL: inputURL, outputURL: outputURLToUse, targetFormat: targetFormat) { progress in
                    Task { @MainActor [weak self] in
                        self?.setFileStatus(id: fileId, status: .processing(progress: progress * (isArchive ? 0.7 : 1.0)))
                    }
                }
                
                var finalSize = newSize
                let finalOutputURL = targetOutputURL
                
                if isArchive, let tempURL = tempConvURL {
                    // Compress the temp file into the archive
                    let compressor = ArchiveCompressor()
                    await MainActor.run { [weak self] in
                        if let self = self {
                            self.activeConverters[fileId] = nil
                        }
                    }
                    
                    try await compressor.compress(
                        urls: [tempURL],
                        destinationURL: targetOutputURL,
                        format: archiveFormat,
                        compressionLevel: 5,
                        password: nil,
                        splitSize: nil,
                        progressHandler: { p in
                            Task { @MainActor [weak self] in
                                self?.setFileStatus(id: fileId, status: .processing(progress: 0.7 + p * 0.3))
                            }
                        }
                    )
                    
                    // Clean up temp directory
                    try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
                    
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: targetOutputURL.path),
                       let size = attrs[.size] as? Int64 {
                        finalSize = size
                    }
                }
                
                let completedSize = finalSize
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.activeConverters.removeValue(forKey: fileId)
                    self.isProcessing = false
                    self.setFileStatus(id: fileId, status: .completed(newSize: completedSize, outputURL: finalOutputURL))
                }
            } catch {
                if isArchive, let tempURL = tempConvURL {
                    try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
                }
                
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.activeConverters.removeValue(forKey: fileId)
                    self.isProcessing = false
                    self.setFileStatus(id: fileId, status: .failed(message: error.localizedDescription))
                }
            }
        }
    }

    
    func convertFolderFiles(in folderItem: FileItem, sourceExtension: String, targetFormat: String) {
        guard containsFile(id: folderItem.id) else { return }
        
        guard let outputDir = resolvedConvertOutputDirectory else { return }
        let cleanName = folderItem.url.lastPathComponent
        let suffix = convertCustomSuffix.isEmpty ? "_converted" : convertCustomSuffix
        
        let isArchive = convertOutputStyle == .archive
        let archiveFormat = convertArchiveFormat
        
        // Output folder name
        let folderName = convertCustomOutputName.isEmpty ? "\(cleanName)\(suffix)" : convertCustomOutputName
        
        let destFolderURL: URL
        let tempFolderURL: URL?
        let targetOutputURL: URL
        
        if isArchive {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("shrink_conv_f_temp_" + UUID().uuidString)
            destFolderURL = tempDir.appendingPathComponent(folderName)
            tempFolderURL = tempDir
            let archiveExt = archiveFormat.fileExtension
            targetOutputURL = outputDir.appendingPathComponent("\(folderName).\(archiveExt)")
        } else {
            destFolderURL = outputDir.appendingPathComponent(folderName)
            tempFolderURL = nil
            targetOutputURL = destFolderURL
        }
        
        setFolderConversionPending(id: folderItem.id)
        isProcessing = true
        activeJobTitle = "Converting .\(sourceExtension) files in \(folderItem.name)..."
        
        let folderId = folderItem.id
        let inputFolderURL = folderItem.url
        let converter = FileConverter()
        activeConverters[folderId] = converter
        
        Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let properties: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
            
            var matchingFiles: [URL] = []
            if let enumerator = fileManager.enumerator(at: inputFolderURL, includingPropertiesForKeys: properties, options: [.skipsHiddenFiles]) {
                while let fileURL = enumerator.nextObject() as? URL {
                    if let isDir = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir {
                        continue
                    }
                    if fileURL.pathExtension.lowercased() == sourceExtension.lowercased() {
                        matchingFiles.append(fileURL)
                    }
                }
            }
            
            guard !matchingFiles.isEmpty else {
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.activeConverters.removeValue(forKey: folderId)
                    self.isProcessing = false
                    self.setFileStatus(id: folderId, status: .completed(newSize: 0, outputURL: targetOutputURL))
                }
                return
            }
            
            do {
                try fileManager.createDirectory(at: destFolderURL, withIntermediateDirectories: true)
                
                var completedCount = 0
                for fileURL in matchingFiles {
                    let relativePath = fileURL.path.replacingOccurrences(of: inputFolderURL.path + "/", with: "")
                    let relPathWithoutExt = URL(fileURLWithPath: relativePath).deletingPathExtension().path
                    let fileDestURL = destFolderURL.appendingPathComponent("\(relPathWithoutExt).\(targetFormat.lowercased())")
                    
                    try fileManager.createDirectory(at: fileDestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    
                    await MainActor.run { [weak self] in
                        self?.updateFileProgress(url: fileURL, progress: 0.05)
                    }
                    
                    do {
                        _ = try await converter.convert(inputURL: fileURL, outputURL: fileDestURL, targetFormat: targetFormat) { fileProgress in
                            Task { @MainActor [weak self] in
                                self?.updateFileProgress(url: fileURL, progress: fileProgress)
                            }
                        }
                        
                        let subItemSize = (try? fileManager.attributesOfItem(atPath: fileDestURL.path)[.size] as? Int64) ?? 0
                        await MainActor.run { [weak self] in
                            self?.updateFileCompleted(url: fileURL, newSize: subItemSize, outputURL: fileDestURL)
                        }
                    } catch {
                        await MainActor.run { [weak self] in
                            self?.updateFileFailed(url: fileURL, message: error.localizedDescription)
                        }
                        throw error
                    }
                    
                    completedCount += 1
                    let progress = Double(completedCount) / Double(matchingFiles.count)
                    await MainActor.run { [weak self] in
                        self?.setFileStatus(id: folderId, status: .processing(progress: progress * (isArchive ? 0.7 : 1.0)))
                    }
                }
                
                var finalSize: Int64 = 0
                
                if isArchive, let tempDir = tempFolderURL {
                    // Compress the destFolderURL into targetOutputURL archive
                    let compressor = ArchiveCompressor()
                    
                    // Collect contents of temp dest folder
                    let contents = try fileManager.contentsOfDirectory(at: destFolderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                    
                    try await compressor.compress(
                        urls: contents,
                        destinationURL: targetOutputURL,
                        format: archiveFormat,
                        compressionLevel: 5,
                        password: nil,
                        splitSize: nil,
                        progressHandler: { p in
                            Task { @MainActor [weak self] in
                                self?.setFileStatus(id: folderId, status: .processing(progress: 0.7 + p * 0.3))
                            }
                        }
                    )
                    
                    // Clean up temp folder
                    try? fileManager.removeItem(at: tempDir)
                    
                    if let attrs = try? fileManager.attributesOfItem(atPath: targetOutputURL.path),
                       let size = attrs[.size] as? Int64 {
                        finalSize = size
                    }
                } else {
                    finalSize = await FileItem.calculateFolderSizeAsync(at: destFolderURL)
                }
                
                let completedSize = finalSize
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.activeConverters.removeValue(forKey: folderId)
                    self.isProcessing = false
                    self.setFileStatus(id: folderId, status: .completed(newSize: completedSize, outputURL: targetOutputURL))
                }
            } catch {
                if let tempDir = tempFolderURL {
                    try? fileManager.removeItem(at: tempDir)
                }
                
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.activeConverters.removeValue(forKey: folderId)
                    self.isProcessing = false
                    self.setFileStatus(id: folderId, status: .failed(message: error.localizedDescription))
                }
            }
        }
    }

    
    // MARK: - Individual File and Folder Progress Helpers
    
    func findFile(id: UUID) -> FileItem? {
        for file in selectedFiles {
            if file.id == id {
                return file
            }
            if let found = findFileRecursive(in: file, id: id) {
                return found
            }
        }
        return nil
    }
    
    private func findFileRecursive(in item: FileItem, id: UUID) -> FileItem? {
        for sub in item.subItems {
            if sub.id == id {
                return sub
            }
            if let found = findFileRecursive(in: sub, id: id) {
                return found
            }
        }
        return nil
    }
    
    func containsFile(id: UUID) -> Bool {
        return findFile(id: id) != nil
    }
    
    func updateFileItem(id: UUID, updater: (inout FileItem) -> Void) {
        if let idx = selectedFiles.firstIndex(where: { $0.id == id }) {
            updater(&selectedFiles[idx])
            selectedFiles = selectedFiles
        } else {
            for i in 0..<selectedFiles.count {
                if updateFileItemRecursive(in: &selectedFiles[i], id: id, updater: updater) {
                    selectedFiles = selectedFiles
                    break
                }
            }
        }
    }
    
    private func updateFileItemRecursive(in item: inout FileItem, id: UUID, updater: (inout FileItem) -> Void) -> Bool {
        if item.id == id {
            updater(&item)
            return true
        }
        for j in 0..<item.subItems.count {
            if updateFileItemRecursive(in: &item.subItems[j], id: id, updater: updater) {
                return true
            }
        }
        return false
    }
    
    private func updateFileRecursive(in list: inout [FileItem], updated: FileItem) -> Bool {
        for i in 0..<list.count {
            if list[i].id == updated.id {
                list[i] = updated
                return true
            }
            if !list[i].subItems.isEmpty {
                if updateFileRecursive(in: &list[i].subItems, updated: updated) {
                    return true
                }
            }
        }
        return false
    }
    
    func updateSubMediaItem(folderId: UUID, subItemId: UUID, updater: (inout SubMediaItem) -> Void) {
        if var folder = findFile(id: folderId) {
            if let subIdx = folder.subMediaItems.firstIndex(where: { $0.id == subItemId }) {
                updater(&folder.subMediaItems[subIdx])
                _ = updateFileRecursive(in: &selectedFiles, updated: folder)
            }
        }
    }
    
    func updateFileProgress(url: URL, progress: Double) {
        fileProgresses[url] = progress
        _ = updateFileStatusRecursive(in: &selectedFiles, url: url, status: .processing(progress: progress))
        recalculateAllFolderProgress()
    }
    
    func updateFileCompleted(url: URL, newSize: Int64, outputURL: URL) {
        fileProgresses[url] = 1.0
        _ = updateFileStatusRecursive(in: &selectedFiles, url: url, status: .completed(newSize: newSize, outputURL: outputURL))
        recalculateAllFolderProgress()
    }
    
    func updateFileFailed(url: URL, message: String) {
        fileProgresses[url] = 1.0
        _ = updateFileStatusRecursive(in: &selectedFiles, url: url, status: .failed(message: message))
        recalculateAllFolderProgress()
    }
    
    func setFileStatus(id: UUID, status: FileStatus) {
        if updateFileStatusRecursiveById(in: &selectedFiles, id: id, status: status) {
            recalculateAllFolderProgress()
            // For @Observable to detect changes in nested struct properties, we need to signal the change.
            self.selectedFiles = self.selectedFiles
            
            if isProcessing {
                updateBatchConversionProgress()
            }
        }
    }
    
    private func updateBatchConversionProgress() {
        let files = selectedFiles.filter { $0.isChecked }
        guard !files.isEmpty else { return }
        
        var totalProgress = 0.0
        for f in files {
            switch f.status {
            case .completed:
                totalProgress += 1.0
            case .failed:
                totalProgress += 1.0
            case .processing(let prog):
                totalProgress += prog
            case .pending:
                break
            }
        }
        self.currentProgress = totalProgress / Double(files.count)
    }
    
    func setFolderConversionPending(id: UUID) {
        if updateFileStatusRecursiveById(in: &selectedFiles, id: id, status: .processing(progress: 0.0)) {
            if var item = findFile(id: id) {
                setAllSubItemsPending(in: &item)
                _ = updateFileRecursive(in: &selectedFiles, updated: item)
            }
            recalculateAllFolderProgress()
        }
    }
    
    private func setAllSubItemsPending(in item: inout FileItem) {
        for j in 0..<item.subItems.count {
            item.subItems[j].status = .pending
            if item.subItems[j].isDirectory {
                setAllSubItemsPending(in: &item.subItems[j])
            }
        }
    }
    
    private func setStatusRecursive(item: inout FileItem, status: FileStatus) {
        item.status = status
        if item.isDirectory {
            for j in 0..<item.subItems.count {
                if !isStatusFinal(item.subItems[j].status) {
                    if case .failed(let message) = status {
                        setStatusRecursive(item: &item.subItems[j], status: .failed(message: message))
                    } else if case .completed(_, let outputURL) = status {
                        setStatusRecursive(item: &item.subItems[j], status: .completed(newSize: 0, outputURL: outputURL))
                    }
                }
            }
        }
    }
    
    private func updateFileStatusRecursive(in list: inout [FileItem], url: URL, status: FileStatus) -> Bool {
        let targetPath = url.standardizedFileURL.path
        for i in 0..<list.count {
            if list[i].url.standardizedFileURL.path == targetPath {
                setStatusRecursive(item: &list[i], status: status)
                return true
            }
            if !list[i].subItems.isEmpty {
                if updateFileStatusRecursive(in: &list[i].subItems, url: url, status: status) {
                    return true
                }
            }
        }
        return false
    }
    
    private func updateFileStatusRecursiveById(in list: inout [FileItem], id: UUID, status: FileStatus) -> Bool {
        for i in 0..<list.count {
            if list[i].id == id {
                setStatusRecursive(item: &list[i], status: status)
                return true
            }
            if !list[i].subItems.isEmpty {
                if updateFileStatusRecursiveById(in: &list[i].subItems, id: id, status: status) {
                    return true
                }
            }
        }
        return false
    }
    
    private func isStatusFinal(_ status: FileStatus) -> Bool {
        switch status {
        case .completed, .failed: return true
        default: return false
        }
    }
    
    func recalculateAllFolderProgress() {
        for i in 0..<selectedFiles.count {
            if selectedFiles[i].isDirectory {
                recalculateProgress(for: &selectedFiles[i])
            }
        }
        // For @Observable to detect changes in nested struct properties, we need to signal the change.
        self.selectedFiles = self.selectedFiles
    }
    
    private func recalculateProgress(for item: inout FileItem) {
        for i in 0..<item.subItems.count {
            if item.subItems[i].isDirectory {
                recalculateProgress(for: &item.subItems[i])
            }
        }
        
        guard item.isDirectory else { return }
        
        // If subItems is empty but we have subMediaItems, calculate progress using the flat list
        if item.subItems.isEmpty {
            guard !item.subMediaItems.isEmpty else { return }
            let totalOriginalSize = item.subMediaItems.reduce(0) { $0 + $1.originalSize }
            guard totalOriginalSize > 0 else { return }
            
            var completedBytes: Double = 0.0
            var allCompletedOrFailed = true
            
            for subMedia in item.subMediaItems {
                let progress = fileProgresses[subMedia.url] ?? 0.0
                completedBytes += Double(subMedia.originalSize) * progress
                if progress < 1.0 {
                    allCompletedOrFailed = false
                }
            }
            
            // If the folder was explicitly set to completed or failed by the engine, do not override it
            if isStatusFinal(item.status) {
                return
            }
            
            if allCompletedOrFailed {
                item.status = .processing(progress: 0.99)
            } else {
                let progress = completedBytes / Double(totalOriginalSize)
                item.status = .processing(progress: min(0.99, max(0.0, progress)))
            }
            return
        }
        
        let subItemsList = item.subItems
        guard !subItemsList.isEmpty else { return }
        
        let activeSubItems = subItemsList.filter { $0.isChecked }
        if activeSubItems.isEmpty {
            return
        }
        
        let totalOriginalSize = activeSubItems.reduce(0) { $0 + $1.originalSize }
        guard totalOriginalSize > 0 else { return }
        
        var completedBytes: Double = 0.0
        var allCompletedOrFailed = true
        var hasSuccess = false
        var lastOutputURL: URL? = nil
        var totalNewSize: Int64 = 0
        var failMessage = ""
        
        for subItem in activeSubItems {
            switch subItem.status {
            case .pending:
                allCompletedOrFailed = false
            case .processing(let progress):
                allCompletedOrFailed = false
                completedBytes += Double(subItem.originalSize) * progress
            case .completed(let newSize, let outputURL):
                completedBytes += Double(subItem.originalSize)
                totalNewSize += newSize
                lastOutputURL = outputURL
                hasSuccess = true
            case .failed(let message):
                completedBytes += Double(subItem.originalSize)
                failMessage = message
            }
        }
        
        if allCompletedOrFailed {
            // Crucial fix: If the parent folder status is already completed, do not overwrite it.
            // This prevents status regression to .processing(progress: 0.99) or .completed with wrong URL.
            if case .completed = item.status {
                return
            }
            if hasSuccess {
                let folderOutputURL = lastOutputURL?.deletingLastPathComponent() ?? item.url
                item.status = .completed(newSize: totalNewSize, outputURL: folderOutputURL)
            } else {
                item.status = .failed(message: failMessage.isEmpty ? "Folder compression failed" : failMessage)
            }
        } else {
            // Crucial fix: If the parent folder status is already completed, do not overwrite it.
            if case .completed = item.status {
                return
            }
            let progress = completedBytes / Double(totalOriginalSize)
            item.status = .processing(progress: min(0.99, max(0.0, progress)))
        }
    }
    
    func startShrinkingSingleItem(_ item: FileItem) {
        guard let match = findFile(id: item.id) else { return }
        
        var outputDir: URL?
        let locationType: OutputLocationType
        let customFolder: URL?
        
        if self.mode == .compress && match.fileType == .image {
            locationType = imageOutputLocationType
            customFolder = imageCustomOutputFolder
        } else if self.mode == .compress && match.fileType == .video {
            locationType = videoOutputLocationType
            customFolder = videoCustomOutputFolder
        } else {
            locationType = outputLocationType
            customFolder = customOutputFolder
        }
        
        switch locationType {
        case .sameAsSource:
            outputDir = match.url.deletingLastPathComponent()
        case .downloads:
            outputDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        case .desktop:
            outputDir = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        case .custom:
            outputDir = customFolder
        }
        
        guard let resolvedOutputDir = outputDir else {
            return
        }
        
        isProcessing = true
        showProcessingOverlay = true
        currentProgress = 0.0
        fileProgresses.removeAll()
        activeJobTitle = mode == .compress ? "Compressing \(match.name)..." : "Decompressing \(match.name)..."
        elapsedSeconds = 0
        estimatedSecondsRemaining = nil
        compressionResult = nil
        compressionError = nil
        compressionStartTotalSize = match.originalSize
        
        startTimer()
        
        let resolvedStyle: OutputStyle = match.isDirectory ? .subfolder : .individual
        
        let engine = CompressorEngine(state: self)
        self.engine = engine
        
        updateFileItem(id: match.id) { file in
            file.status = .pending
            self.setAllSubItemsPending(in: &file)
        }
        
        let job = CompressionJob(
            mode: mode,
            outputDir: resolvedOutputDir,
            selectedFiles: [match],
            customOutputName: customOutputName,
            customSuffix: customSuffix,
            predominantType: predominantType,
            imageSettings: imageSettings,
            videoSettings: videoSettings,
            audioSettings: audioSettings,
            archiveSettings: archiveSettings,
            decompressSettings: decompressSettings,
            pdfSettings: pdfSettings,
            outputStyle: resolvedStyle,
            mediaFilter: .all,
        )
        
        Task.detached(priority: .userInitiated) {
            await engine.execute(job: job)
        }
    }
    
    func startBatchConversion(overallTargets: [String: String]) {
        var filesToConvert: [(item: FileItem, targetFormat: String)] = []
        
        func collect(item: FileItem) {
            guard item.isChecked else { return }
            if !item.isDirectory {
                let ext = item.url.pathExtension.lowercased()
                let targetFormat = item.targetConvertFormat ?? overallTargets[ext] ?? FileConverter.enabledTargetFormats(forExtension: ext).first
                if let targetFormat = targetFormat, !targetFormat.isEmpty {
                    filesToConvert.append((item, targetFormat))
                }
            } else {
                for sub in item.subItems {
                    collect(item: sub)
                }
            }
        }
        
        for item in selectedFiles {
            collect(item: item)
        }
        
        guard !filesToConvert.isEmpty else { return }
        
        guard let outputDir = resolvedConvertOutputDirectory else { return }
        let suffix = convertCustomSuffix.isEmpty ? "_converted" : convertCustomSuffix
        let convertStyle = self.convertOutputStyle
        let customName = self.convertCustomOutputName
        
        isProcessing = true
        activeJobTitle = "Converting \(filesToConvert.count) files..."
        
        let startTime = Date()
        elapsedSeconds = 0
        startTimer()
        
        Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: Void.self) { group in
                for pair in filesToConvert {
                    group.addTask {
                        let fileItem = pair.item
                        let targetFormat = pair.targetFormat
                        
                        await MainActor.run {
                            self.setFileStatus(id: fileItem.id, status: .processing(progress: 0.0))
                        }
                        
                        let cleanName = fileItem.url.deletingPathExtension().lastPathComponent
                        let baseName = "\(cleanName)\(suffix).\(targetFormat.lowercased())"
                        
                        let targetOutputURL: URL
                        let isArchive = convertStyle == .archive
                        let isSubfolder = convertStyle == .subfolder
                        
                        if isArchive {
                            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("shrink_conv_temp_" + UUID().uuidString)
                            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                            targetOutputURL = tempDir.appendingPathComponent(baseName)
                        } else if isSubfolder {
                            let folderName = customName.isEmpty ? "Converted_Files" : customName
                            let subfolderURL = outputDir.appendingPathComponent(folderName)
                            try? FileManager.default.createDirectory(at: subfolderURL, withIntermediateDirectories: true)
                            targetOutputURL = subfolderURL.appendingPathComponent(baseName)
                        } else {
                            targetOutputURL = outputDir.appendingPathComponent(baseName)
                        }
                        
                        let converter = FileConverter()
                        await MainActor.run {
                            self.activeConverters[fileItem.id] = converter
                        }
                        
                        do {
                            _ = try await converter.convert(inputURL: fileItem.url, outputURL: targetOutputURL, targetFormat: targetFormat) { progress in
                                Task { @MainActor in
                                    self.setFileStatus(id: fileItem.id, status: .processing(progress: progress))
                                }
                            }
                            
                            let finalSize = (try? FileManager.default.attributesOfItem(atPath: targetOutputURL.path)[.size] as? Int64) ?? 0
                            
                            await MainActor.run {
                                self.activeConverters.removeValue(forKey: fileItem.id)
                                self.setFileStatus(id: fileItem.id, status: .completed(newSize: finalSize, outputURL: targetOutputURL))
                            }
                        } catch {
                            await MainActor.run {
                                self.activeConverters.removeValue(forKey: fileItem.id)
                                self.setFileStatus(id: fileItem.id, status: .failed(message: error.localizedDescription))
                            }
                        }
                    }
                }
                
                await group.waitForAll()
            }
            
            let elapsed = Int(Date().timeIntervalSince(startTime))
            
            await MainActor.run {
                self.stopTimer()
                self.isProcessing = false
                
                if self.isFinderSyncMode {
                    var totalOriginalSize: Int64 = 0
                    var totalNewSize: Int64 = 0
                    
                    for pair in filesToConvert {
                        totalOriginalSize += pair.item.originalSize
                        if case .completed(let newSize, _) = pair.item.status {
                            totalNewSize += newSize
                        } else {
                            totalNewSize += pair.item.originalSize
                        }
                    }
                    
                    if let firstItem = filesToConvert.first?.item {
                        self.compressionResult = CompressionResult(
                            originalSize: totalOriginalSize,
                            newSize: totalNewSize,
                            elapsedSeconds: elapsed,
                            originalURL: firstItem.url,
                            compressedURL: outputDir
                        )
                    }
                }
            }
        }
    }
    
    func handleIncomingURL(_ url: URL) {
        guard url.scheme == "shrink" else { return }
        
        let components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        guard let host = url.host else { return }
        
        // Parse files param
        guard let filesQueryItem = components?.queryItems?.first(where: { $0.name == "files" }),
              let filesParam = filesQueryItem.value else {
            return
        }
        
        let paths = filesParam.split(separator: ",").compactMap { base64Str -> URL? in
            guard let data = Data(base64Encoded: String(base64Str)),
                  let path = String(data: data, encoding: .utf8) else {
                return nil
            }
            return URL(fileURLWithPath: path)
        }
        
        guard !paths.isEmpty else { return }
        
        // We are handling a Finder Sync action
        self.isFinderSyncMode = true
        self.wasLaunchedByFinderSync = true
        
        // Hide main window on MainActor and show the Finder Sync HUD
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)
            FinderSyncWindowManager.shared.showProgressWindow(state: self)
            
            // Hide main app window
            NSApp.windows.forEach { win in
                if win != FinderSyncWindowManager.shared.window && win.title == "Shrink" {
                    win.orderOut(nil)
                }
            }
            
            // Prepare files and load metadata
            self.clearFiles()
            self.isProcessing = true
            self.activeJobTitle = "Preparing files..."
            self.currentProgress = 0.0
            
            var loadedItems: [FileItem] = []
            for p in paths {
                let cleanURL = p.resolvingSymlinksInPath().standardized
                var item = FileItem(url: cleanURL)
                
                if item.isDirectory {
                    let scanResult = await FileItem.calculateFolderMetadataAsync(at: cleanURL)
                    item.originalSize = scanResult.size
                    item.detectedTypes = scanResult.detectedTypes
                    item.typeCounts = scanResult.typeCounts
                    item.typeSizes = scanResult.typeSizes
                    item.subMediaItems = scanResult.subMediaItems
                    item.extensionCounts = scanResult.extensionCounts
                    item.subItems = []
                } else {
                    let meta = await FileMetadataReader.readMetadata(for: cleanURL)
                    item.width = meta.width
                    item.height = meta.height
                    item.duration = meta.duration
                    item.frameRate = meta.frameRate
                    
                    if item.fileType == .archive {
                        let entries = await ArchiveCompressor.listContents(archiveURL: cleanURL)
                        if !entries.isEmpty {
                            var nodeMap: [String: FileItem] = [:]
                            func makeVirtualItem(path: String, isDir: Bool, size: Int64) -> FileItem? {
                                guard let virtualURL = URL(string: cleanURL.absoluteString + "/" + path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!) else { return nil }
                                var virtual = FileItem(url: virtualURL)
                                virtual.originalSize = size
                                let detected = FileItem.getFileTypeForURL(URL(fileURLWithPath: path))
                                virtual.detectedTypes = [detected]
                                virtual.typeCounts = [detected: 1]
                                virtual.typeSizes = [detected: size]
                                virtual.isVirtualDirectory = isDir
                                virtual.archiveEntryPath = path
                                virtual.parentArchiveURL = cleanURL
                                return virtual
                            }

                            var virtualSubItems: [FileItem] = []
                            for (entryPath, entrySize, entryIsDir) in entries {
                                let normalized = entryPath.trimmingCharacters(in: .whitespacesAndNewlines)
                                if normalized.isEmpty { continue }
                                
                                let components = normalized.split(separator: "/")
                                var currentPath = ""
                                
                                for (i, comp) in components.enumerated() {
                                    let isLast = i == components.count - 1
                                    let parentPath = currentPath
                                    currentPath = parentPath.isEmpty ? String(comp) : "\(parentPath)/\(comp)"
                                    
                                    if nodeMap[currentPath] == nil {
                                        let itemIsDir = !isLast || entryIsDir
                                        let itemSize = isLast ? entrySize : 0
                                        if let virtualItem = makeVirtualItem(path: currentPath, isDir: itemIsDir, size: itemSize) {
                                            nodeMap[currentPath] = virtualItem
                                            if parentPath.isEmpty {
                                                virtualSubItems.append(virtualItem)
                                            } else if var parentNode = nodeMap[parentPath] {
                                                parentNode.subItems.append(virtualItem)
                                                nodeMap[parentPath] = parentNode
                                            }
                                        }
                                    }
                                }
                            }
                            item.subItems = virtualSubItems
                        }
                    }
                }
                loadedItems.append(item)
            }
            
            self.selectedFiles = loadedItems
            self.updateModeBasedOnSelection()
            
            if host == "compress" {
                let typeParam = components?.queryItems?.first(where: { $0.name == "type" })?.value ?? "archive"
                
                let filter: MediaFilter
                switch typeParam {
                case "image":
                    self.mode = .compress
                    filter = .imagesOnly
                case "video":
                    self.mode = .compress
                    filter = .videosOnly
                case "audio":
                    self.mode = .compress
                    filter = .audioOnly
                case "archive":
                    self.mode = .compress
                    filter = .all
                default:
                    self.mode = .compress
                    filter = .all
                }
                
                self.startShrinking(filter: filter)
                
            } else if host == "convert" {
                guard let formatParam = components?.queryItems?.first(where: { $0.name == "format" })?.value else {
                    self.isProcessing = false
                    return
                }
                
                var overallTargets: [String: String] = [:]
                for p in paths {
                    let ext = p.pathExtension.lowercased()
                    overallTargets[ext] = formatParam.uppercased()
                }
                
                self.startBatchConversion(overallTargets: overallTargets)
            }
        }
    }
}
