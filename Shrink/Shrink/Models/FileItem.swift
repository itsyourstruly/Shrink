//
//  FileItem.swift
//  Shrink
//

import Foundation
import UniformTypeIdentifiers

enum FileType: String, CaseIterable, Identifiable, Sendable {
    case image = "Image"
    case video = "Video"
    case audio = "Audio"
    case pdf = "PDF"
    case archive = "Archive"
    case general = "General File"
    
    var id: String { rawValue }
    
    var systemIcon: String {
        switch self {
        case .image: return "photo.fill"
        case .video: return "video.fill"
        case .audio: return "music.note"
        case .pdf: return "doc.richtext.fill"
        case .archive: return "archivebox.fill"
        case .general: return "doc.fill"
        }
    }
}

enum FileStatus: Equatable, Hashable, Sendable {
    case pending
    case processing(progress: Double)
    case completed(newSize: Int64, outputURL: URL)
    case failed(message: String)
}

struct SubMediaItem: Identifiable, Hashable, Sendable {
    let id: UUID = UUID()
    let url: URL
    let fileType: FileType
    let originalSize: Int64
    var targetSizeRatio: Double
    var isManuallyAdjusted: Bool = false
    
    var customResolutionWidth: Int? = nil
    var customResolutionHeight: Int? = nil
    var customAudioMode: String? = nil
    var customAudioBitrate: Int? = nil
    var customCompressionMethod: VideoCompressionMethod? = nil
    var customTargetBitrateKbps: Int? = nil
    var customCodec: String? = nil
    var customImageFormat: String? = nil
    
    var name: String {
        url.lastPathComponent
    }
}

struct FileItem: Identifiable, Hashable, Sendable {
    let id: UUID = UUID()
    let url: URL
    var status: FileStatus = .pending
    var width: Int? = nil
    var height: Int? = nil
    var duration: Double? = nil
    var frameRate: Double? = nil
    var originalSize: Int64 = 0
    var detectedTypes: Set<FileType> = []
    var typeCounts: [FileType: Int] = [:]
    var typeSizes: [FileType: Int64] = [:]
    var isChecked: Bool = true
    var customTargetSizeRatio: Double? = nil
    var isManuallyAdjusted: Bool = false
    var subMediaItems: [SubMediaItem] = []
    
    var customResolutionWidth: Int? = nil
    var customResolutionHeight: Int? = nil
    var customAudioMode: String? = nil
    var customAudioBitrate: Int? = nil
    var customCompressionMethod: VideoCompressionMethod? = nil
    var customTargetBitrateKbps: Int? = nil
    var customCodec: String? = nil
    var customImageFormat: String? = nil
    
    var targetConvertFormat: String? = nil
    var extensionCounts: [String: Int] = [:]
    
    var isExpanded: Bool = false
    var subItems: [FileItem] = []
    // For virtual items coming from inside archives (not real filesystem URLs)
    var isVirtualDirectory: Bool = false
    var archiveEntryPath: String? = nil
    var parentArchiveURL: URL? = nil
    
    var name: String {
        url.lastPathComponent
    }
    
    var isDirectory: Bool {
        if isVirtualDirectory { return true }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            return isDir.boolValue
        }
        return false
    }
    
    var isAllCheckedRecursive: Bool {
        guard isChecked else { return false }
        if isDirectory {
            if subItems.isEmpty {
                return isChecked
            }
            return subItems.allSatisfy { $0.isAllCheckedRecursive }
        }
        return true
    }
    
    var hasAnyCheckedRecursive: Bool {
        if isChecked { return true }
        if isDirectory {
            return subItems.contains { $0.hasAnyCheckedRecursive }
        }
        return false
    }
    
    init(url: URL) {
        let localURL = url
        self.url = localURL
        
        let type = self.fileType
        self.detectedTypes = [type]
        self.typeCounts = [type: 1]
        
        // Quick size for files
        let isAccessing = localURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                localURL.stopAccessingSecurityScopedResource()
            }
        }
        
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isDir) {
            if !isDir.boolValue {
                do {
                    let values = try localURL.resourceValues(forKeys: [.fileSizeKey])
                    if let fileSize = values.fileSize {
                        let size = Int64(fileSize)
                        self.originalSize = size
                        self.typeSizes = [type: size]
                        return
                    }
                } catch {
                    // Fallback to FileManager attributes if resourceValues fails
                }
                if let attrs = try? FileManager.default.attributesOfItem(atPath: localURL.path),
                   let size = attrs[.size] as? Int64 {
                    self.originalSize = size
                    self.typeSizes = [type: size]
                }
            } else {
                self.typeSizes = [type: 0]
            }
        }
    }
    
    // Asynchronous factory method to handle directory size calculation
    static func create(url: URL) async -> FileItem {
        // The initializer handles basic setup. Size calculation for directories
        // is now handled on-demand to improve performance.
        return FileItem(url: url)
    }
    
    // Asynchronously calculate folder metadata without building the sub-item tree
    static func calculateFolderMetadataAsync(at folderURL: URL) async -> FolderScanResult {
        return await Task.detached(priority: .userInitiated) {
            let result = calculateFolderMetadataRecursive(at: folderURL)
            return FolderScanResult(
                size: result.size,
                detectedTypes: result.detectedTypes,
                typeCounts: result.typeCounts,
                typeSizes: result.typeSizes,
                subMediaItems: result.subMediaItems,
                extensionCounts: result.extensionCounts,
                subItems: [] // Return empty subItems as we are only calculating metadata
            )
        }.value
    }

    // New recursive function for metadata calculation without building FileItem tree
    private nonisolated static func calculateFolderMetadataRecursive(at folderURL: URL) -> (size: Int64, detectedTypes: Set<FileType>, typeCounts: [FileType: Int], typeSizes: [FileType: Int64], subMediaItems: [SubMediaItem], extensionCounts: [String: Int]) {
        let fileManager = FileManager.default
        let properties: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        
        let isAccessing = folderURL.startAccessingSecurityScopedResource()
        defer { if isAccessing { folderURL.stopAccessingSecurityScopedResource() } }
        
        guard let contents = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: properties, options: [.skipsHiddenFiles]) else {
            return (0, [], [:], [:], [], [:])
        }
        
        var totalSize: Int64 = 0, typeCounts: [FileType: Int] = [:], typeSizes: [FileType: Int64] = [:], extensionCounts: [String: Int] = [:]
        var detectedTypes = Set<FileType>(), subMediaItems: [SubMediaItem] = []
        
        for fileURL in contents {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(properties))
                if resourceValues.isDirectory ?? false {
                    let subResult = calculateFolderMetadataRecursive(at: fileURL)
                    totalSize += subResult.size
                    detectedTypes.formUnion(subResult.detectedTypes)
                    subResult.typeCounts.forEach { typeCounts[$0.key, default: 0] += $0.value }
                    subResult.typeSizes.forEach { typeSizes[$0.key, default: 0] += $0.value }
                    subMediaItems.append(contentsOf: subResult.subMediaItems)
                    subResult.extensionCounts.forEach { extensionCounts[$0.key, default: 0] += $0.value }
                } else {
                    let size = Int64(resourceValues.fileSize ?? 0)
                    totalSize += size
                    let ext = fileURL.pathExtension.lowercased()
                    if !ext.isEmpty { extensionCounts[ext, default: 0] += 1 }
                    let type = getFileTypeForURL(fileURL)
                    detectedTypes.insert(type)
                    typeCounts[type, default: 0] += 1
                    typeSizes[type, default: 0] += size
                    if type == .image || type == .video {
                        subMediaItems.append(SubMediaItem(url: fileURL, fileType: type, originalSize: size, targetSizeRatio: type == .image ? 0.8 : 0.7))
                    }
                }
            } catch { continue }
        }
        return (totalSize, detectedTypes, typeCounts, typeSizes, subMediaItems, extensionCounts)
    }

    struct FolderScanResult: Sendable {
        let size: Int64
        let detectedTypes: Set<FileType>
        let typeCounts: [FileType: Int]
        let typeSizes: [FileType: Int64]
        let subMediaItems: [SubMediaItem]
        let extensionCounts: [String: Int]
        let subItems: [FileItem]
    }
    
    // Asynchronously scan folder contents in the background
    static func scanFolderAsync(at folderURL: URL, shallow: Bool = false) async -> FolderScanResult {
        return await Task.detached(priority: .userInitiated) {
            let result: (size: Int64, detectedTypes: Set<FileType>, typeCounts: [FileType: Int], typeSizes: [FileType: Int64], subMediaItems: [SubMediaItem], extensionCounts: [String: Int], subItems: [FileItem])
            
            if shallow {
                result = await scanFolderShallow(at: folderURL)
            } else {
                result = scanFolderRecursive(at: folderURL)
            }

            return FolderScanResult(
                size: result.size,
                detectedTypes: result.detectedTypes,
                typeCounts: result.typeCounts,
                typeSizes: result.typeSizes,
                subMediaItems: result.subMediaItems,
                extensionCounts: result.extensionCounts,
                subItems: result.subItems
            )
        }.value
    }
    
    private static func scanFolderShallow(at folderURL: URL) async -> (size: Int64, detectedTypes: Set<FileType>, typeCounts: [FileType: Int], typeSizes: [FileType: Int64], subMediaItems: [SubMediaItem], extensionCounts: [String: Int], subItems: [FileItem]) {
        let fileManager = FileManager.default
        let properties: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        
        let isAccessing = folderURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }
        
        guard let contents = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: properties, options: [.skipsHiddenFiles]) else {
            return (0, [], [:], [:], [], [:], [])
        }
        
        var totalSize: Int64 = 0
        var subItems: [FileItem] = []
        
        // Use a task group to create items concurrently for better performance
        await withTaskGroup(of: FileItem.self) { group in
            for fileURL in contents {
                group.addTask { await Self.create(url: fileURL) }
            }
            for await subItem in group {
                subItems.append(subItem)
            }
        }
        
        // Sort subItems: directories first, then files alphabetically
        subItems.sort { (lhs, rhs) -> Bool in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
        
        // The total size is the sum of the sizes of the immediate children.
        // For sub-directories, their size has already been calculated by the async `create` method.
        totalSize = subItems.reduce(0) { $0 + $1.originalSize }
        
        // For a shallow scan, we don't have deep type info, so we return empty collections for those.
        return (totalSize, [], [:], [:], [], [:], subItems)
    }
    
    private nonisolated static func scanFolderRecursive(at folderURL: URL) -> (size: Int64, detectedTypes: Set<FileType>, typeCounts: [FileType: Int], typeSizes: [FileType: Int64], subMediaItems: [SubMediaItem], extensionCounts: [String: Int], subItems: [FileItem]) {
        let fileManager = FileManager.default
        let properties: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        
        let isAccessing = folderURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }
        
        guard let contents = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: properties, options: [.skipsHiddenFiles]) else {
            return (0, [], [:], [:], [], [:], [])
        }
        
        var totalSize: Int64 = 0
        var detectedTypes = Set<FileType>()
        var typeCounts: [FileType: Int] = [:]
        var typeSizes: [FileType: Int64] = [:]
        var subMediaItems: [SubMediaItem] = []
        var extensionCounts: [String: Int] = [:]
        var subItems: [FileItem] = []
        
        for fileURL in contents {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(properties))
                let isDir = resourceValues.isDirectory ?? false
                
                if isDir {
                    let subResult = scanFolderRecursive(at: fileURL)
                    
                    var subFolderItem = FileItem(url: fileURL)
                    subFolderItem.originalSize = subResult.size
                    subFolderItem.detectedTypes = subResult.detectedTypes
                    subFolderItem.typeCounts = subResult.typeCounts
                    subFolderItem.typeSizes = subResult.typeSizes
                    subFolderItem.subMediaItems = subResult.subMediaItems
                    subFolderItem.extensionCounts = subResult.extensionCounts
                    subFolderItem.subItems = subResult.subItems
                    
                    totalSize += subResult.size
                    detectedTypes.formUnion(subResult.detectedTypes)
                    for (type, count) in subResult.typeCounts {
                        typeCounts[type, default: 0] += count
                    }
                    for (type, size) in subResult.typeSizes {
                        typeSizes[type, default: 0] += size
                    }
                    subMediaItems.append(contentsOf: subResult.subMediaItems)
                    for (ext, count) in subResult.extensionCounts {
                        extensionCounts[ext, default: 0] += count
                    }
                    
                    subItems.append(subFolderItem)
                } else {
                    let size = Int64(resourceValues.fileSize ?? 0)
                    totalSize += size
                    
                    let ext = fileURL.pathExtension.lowercased()
                    if !ext.isEmpty {
                        extensionCounts[ext, default: 0] += 1
                    }
                    
                    let type = getFileTypeForURL(fileURL)
                    detectedTypes.insert(type)
                    typeCounts[type, default: 0] += 1
                    typeSizes[type, default: 0] += size

                    // If this is an archive, try to list its contents and create virtual subItems
                    if type == .archive {
                        let entries = ArchiveCompressor.listContentsSync(archiveURL: fileURL)
                        if !entries.isEmpty {
                            // Build nodes map for entries by path
                            var nodeMap: [String: FileItem] = [:]

                            func makeVirtualItem(path: String, isDir: Bool, size: Int64) -> FileItem? {
                                // Ensure the virtual URL can be created safely
                                guard let virtualURL = URL(string: fileURL.absoluteString + "/" + path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!) else { return nil }
                                var item = FileItem(url: virtualURL)
                                item.originalSize = size
                                let detected = getFileTypeForURL(URL(fileURLWithPath: path))
                                item.detectedTypes = [detected]
                                item.typeCounts = [detected: 1]
                                item.typeSizes = [detected: size]
                                item.isVirtualDirectory = isDir
                                item.archiveEntryPath = path
                                item.parentArchiveURL = fileURL
                                return item
                            }

                            // Create nodes for each entry
                            for (entryPath, entrySize, entryIsDir) in entries {
                                let normalized = entryPath.trimmingCharacters(in: .whitespacesAndNewlines)
                                if normalized.isEmpty { continue }
                                if let item = makeVirtualItem(path: normalized, isDir: entryIsDir, size: entrySize) {
                                    nodeMap[normalized] = item
                                }
                            }

                            // Ensure parent directories exist and build hierarchy
                            for path in Array(nodeMap.keys).sorted(by: { $0.count < $1.count }) {
                                let components = path.split(separator: "/").map { String($0) }
                                if components.count <= 1 { continue }
                                var parentComponents = components
                                parentComponents.removeLast()
                                var parentPath = parentComponents.joined(separator: "/")
                                while true {
                                    if nodeMap[parentPath] == nil, let pitem = makeVirtualItem(path: parentPath, isDir: true, size: 0) {
                                        // create parent virtual dir if it doesn't exist
                                        nodeMap[parentPath] = pitem
                                    }
                                    // attach child to parent
                                    if let child = nodeMap[path], let parent = nodeMap[parentPath] {
                                        if !parent.subItems.contains(where: { $0.archiveEntryPath == child.archiveEntryPath && $0.parentArchiveURL == child.parentArchiveURL }) {
                                            nodeMap[parentPath]!.subItems.append(child)
                                        }
                                    }

                                    // Move up one level
                                    if parentPath.contains("/") {
                                        var comps = parentPath.split(separator: "/").map { String($0) }
                                        comps.removeLast()
                                        parentPath = comps.joined(separator: "/")
                                    } else {
                                        break
                                    }
                                }
                            }

                            // Collect top-level items (those without a parent)
                            var topLevel: [FileItem] = []
                            for (p, node) in nodeMap {
                                let parentPath = (p as NSString).deletingLastPathComponent
                                if parentPath.isEmpty || nodeMap[parentPath] == nil {
                                    topLevel.append(node)
                                }
                            }

                            // Sort top-level entries: directories first then name
                            topLevel.sort { (lhs, rhs) -> Bool in
                                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
                                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
                            }

                            var archiveItem = FileItem(url: fileURL)
                            archiveItem.originalSize = size
                            archiveItem.detectedTypes = [type]
                            archiveItem.typeCounts = [type: 1]
                            archiveItem.typeSizes = [type: size]
                            archiveItem.subItems = topLevel
                            archiveItem.isVirtualDirectory = true
                            subItems.append(archiveItem)
                        } else {
                            // Could not list archive; treat as regular file
                            var subItem = FileItem(url: fileURL)
                            subItem.originalSize = size
                            subItem.detectedTypes = [type]
                            subItem.typeCounts = [type: 1]
                            subItem.typeSizes = [type: size]
                            subItems.append(subItem)
                        }
                    } else {
                        var subItem = FileItem(url: fileURL)
                        subItem.originalSize = size
                        subItem.detectedTypes = [type]
                        subItem.typeCounts = [type: 1]
                        subItem.typeSizes = [type: size]
                        
                        subItems.append(subItem)
                        
                        if type == .image || type == .video {
                            let subMedia = SubMediaItem(
                                url: fileURL,
                                fileType: type,
                                originalSize: size,
                                targetSizeRatio: type == .image ? 0.8 : 0.7
                            )
                            subMediaItems.append(subMedia)
                        }
                    }
                }
            } catch {
                continue
            }
        }
        
        // Sort subItems: directories first, then files alphabetically
        subItems.sort { (lhs, rhs) -> Bool in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
        
        return (totalSize, detectedTypes, typeCounts, typeSizes, subMediaItems, extensionCounts, subItems)
    }
    
    nonisolated static func getFileTypeBySignature(at url: URL) -> FileType? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return nil
        }
        
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer {
            try? fileHandle.close()
        }
        
        guard let data = try? fileHandle.read(upToCount: 8) else {
            return nil
        }
        
        if data.count >= 1 {
            // ARC: 1A
            if data.starts(with: [0x1A]) {
                return .archive
            }
        }
        
        if data.count >= 2 {
            // Zip: PK.. (50 4B)
            if data.starts(with: [0x50, 0x4B]) {
                return .archive
            }
            // Gzip: 1F 8B
            if data.starts(with: [0x1F, 0x8B]) {
                return .archive
            }
            // Bzip2: BZh (42 5A 68)
            if data.starts(with: [0x42, 0x5A, 0x68]) {
                return .archive
            }
            // ARJ: 60 EA
            if data.starts(with: [0x60, 0xEA]) {
                return .archive
            }
        }
        
        if data.count >= 4 {
            // 7z: 37 7A BC AF
            if data.starts(with: [0x37, 0x7A, 0xBC, 0xAF]) {
                return .archive
            }
            // RAR: Rar! (52 61 72 21)
            if data.starts(with: [0x52, 0x61, 0x72, 0x21]) {
                return .archive
            }
            // StuffIt: SIT! (53 49 54 21) or Stuff (53 74 75 66)
            if data.starts(with: [0x53, 0x49, 0x54, 0x21]) || data.starts(with: [0x53, 0x74, 0x75, 0x66]) {
                return .archive
            }
            // StuffIt X: SITC (53 49 54 43)
            if data.starts(with: [0x53, 0x49, 0x54, 0x43]) {
                return .archive
            }
            // CAB: MSCF (4D 53 43 46)
            if data.starts(with: [0x4D, 0x53, 0x43, 0x46]) {
                return .archive
            }
            // DMS: DMS! (44 4D 53 21)
            if data.starts(with: [0x44, 0x4D, 0x53, 0x21]) {
                return .archive
            }
            // LZX: LZX (4C 5A 58)
            if data.starts(with: [0x4C, 0x5A, 0x58]) {
                return .archive
            }
            // Zoo: ZOO (5A 4F 4F)
            if data.starts(with: [0x5A, 0x4F, 0x4F]) {
                return .archive
            }
            // Squeeze: 76 47
            if data.starts(with: [0x76, 0x47]) {
                return .archive
            }
            // PDF: %PDF (25 50 44 46)
            if data.starts(with: [0x25, 0x50, 0x44, 0x46]) {
                return .pdf
            }
        }
        
        if data.count >= 5 {
            // LZH / LHA: check offset 2 for "-lh" (2d 6c 68)
            let sub = data.subdata(in: 2..<5)
            if sub == Data([0x2D, 0x6C, 0x68]) {
                return .archive
            }
        }
        
        if data.count >= 6 {
            // Xz: FD 37 7A 58 5A 00
            if data.starts(with: [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) {
                return .archive
            }
        }
        
        if data.count >= 8 {
            // MSI: D0 CF 11 E0 A1 B1 1A E1
            if data.starts(with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) {
                return .archive
            }
        }
        
        return nil
    }

    nonisolated static func getFileTypeForURL(_ url: URL) -> FileType {
        if let signatureType = getFileTypeBySignature(at: url) {
            return signatureType
        }
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "webp", "bmp", "raw", "psd", "tga", "dds", "exr", "hdr", "pcx", "eps", "pgm", "ppm", "pbm", "pnm", "avif", "jp2", "j2k", "ico", "fits", "xcf", "pix", "mng", "cr2", "nef", "arw", "raf", "orf", "rw2", "pef", "erf", "mef", "mos", "sr2", "srf", "dcr", "kdc", "crw", "x3f", "dng"].contains(ext) {
            return .image
        } else if ["mp4", "mov", "m4v", "mkv", "avi", "webm", "flv", "wmv", "3gp"].contains(ext) {
            return .video
        } else if ["mp3", "m4a", "wav", "aac", "flac", "ogg", "wma"].contains(ext) {
            return .audio
        } else if ext == "pdf" {
            return .pdf
        } else if ["zip", "7z", "tar", "gz", "tgz", "rar", "bz2", "xz", "z", "sit", "sitx", "dd", "cpt", "arj", "arc", "zoo", "lzh", "lha", "adf", "dms", "lzx", "crl", "sq", "cab", "msi", "iso"].contains(ext) {
            return .archive
        } else {
            return .general
        }
    }
    
    // Asynchronously calculate folder size in the background
    static func calculateFolderSizeAsync(at folderURL: URL) async -> Int64 {
        return await Task.detached(priority: .userInitiated) {
            return getFolderSize(at: folderURL)
        }.value
    }
    
    nonisolated private static func getFolderSize(at folderURL: URL) -> Int64 {
        let fileManager = FileManager.default
        let properties: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        
        let isAccessing = folderURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }
        
        guard let enumerator = fileManager.enumerator(at: folderURL,
                                                      includingPropertiesForKeys: properties,
                                                      options: [.skipsHiddenFiles]) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(properties))
                if let isDir = resourceValues.isDirectory, isDir {
                    continue
                }
                if let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            } catch {
                continue
            }
        }
        return totalSize
    }
    
    // Helper to create a new instance with the folder size calculated.
    private func withCalculatedSize() async -> FileItem {
        var copy = self
        copy.originalSize = await Self.calculateFolderSizeAsync(at: self.url)
        return copy
    }
    
    var fileType: FileType {
        if let signatureType = Self.getFileTypeBySignature(at: url) {
            return signatureType
        }
        let ext = url.pathExtension.lowercased()
        
        // Match by extension
        if ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "webp", "bmp", "raw", "psd", "tga", "dds", "exr", "hdr", "pcx", "eps", "pgm", "ppm", "pbm", "pnm", "avif", "jp2", "j2k", "ico", "fits", "xcf", "pix", "mng", "cr2", "nef", "arw", "raf", "orf", "rw2", "pef", "erf", "mef", "mos", "sr2", "srf", "dcr", "kdc", "crw", "x3f", "dng"].contains(ext) {
            return .image
        } else if ["mp4", "mov", "m4v", "mkv", "avi", "webm", "flv", "wmv", "3gp"].contains(ext) {
            return .video
        } else if ["mp3", "m4a", "wav", "aac", "flac", "ogg", "wma"].contains(ext) {
            return .audio
        } else if ext == "pdf" {
            return .pdf
        } else if ["zip", "7z", "tar", "gz", "tgz", "rar", "bz2", "xz", "z", "sit", "sitx", "dd", "cpt", "arj", "arc", "zoo", "lzh", "lha", "adf", "dms", "lzx", "crl", "sq", "cab", "msi", "iso"].contains(ext) {
            return .archive
        } else {
            return .general
        }
    }
    
    // Format bytes to human readable string
    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.isChecked == rhs.isChecked &&
        lhs.isExpanded == rhs.isExpanded &&
        lhs.originalSize == rhs.originalSize &&
        lhs.status == rhs.status &&
        lhs.subItems == rhs.subItems &&
        lhs.customCodec == rhs.customCodec &&
        lhs.customImageFormat == rhs.customImageFormat &&
        lhs.customTargetSizeRatio == rhs.customTargetSizeRatio &&
        lhs.customResolutionWidth == rhs.customResolutionWidth &&
        lhs.customResolutionHeight == rhs.customResolutionHeight &&
        lhs.customAudioMode == rhs.customAudioMode &&
        lhs.customAudioBitrate == rhs.customAudioBitrate &&
        lhs.customCompressionMethod == rhs.customCompressionMethod &&
        lhs.customTargetBitrateKbps == rhs.customTargetBitrateKbps &&
        lhs.targetConvertFormat == rhs.targetConvertFormat &&
        lhs.width == rhs.width &&
        lhs.height == rhs.height &&
        lhs.duration == rhs.duration &&
        lhs.frameRate == rhs.frameRate
    }
}
