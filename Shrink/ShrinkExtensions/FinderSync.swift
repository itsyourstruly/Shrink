//
//  FinderSync.swift
//  ShrinkExtensions
//

import Cocoa
import FinderSync

// Duplicate UserDefaults.shared locally for the extension bundle
extension UserDefaults {
    static let sharedSuiteName = "group.amo.Shrink"
    
    static var shared: UserDefaults {
        return UserDefaults(suiteName: sharedSuiteName) ?? .standard
    }
}

class FinderSync: FIFinderSync {
    
    override init() {
        super.init()
        
        NSLog("FinderSync() launched from %@", Bundle.main.bundlePath as NSString)
        
        // Observe root filesystem so the extension works in all Finder windows
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }
    
    // MARK: - Primary Finder Sync protocol methods
    
    override func beginObservingDirectory(at url: URL) {
        NSLog("beginObservingDirectoryAtURL: %@", url.path as NSString)
    }
    
    override func endObservingDirectory(at url: URL) {
        NSLog("endObservingDirectoryAtURL: %@", url.path as NSString)
    }
    
    // MARK: - Menu and toolbar item support
    
    override var toolbarItemName: String {
        return "Shrink"
    }
    
    override var toolbarItemToolTip: String {
        return "Shrink: Compress or convert files quickly."
    }
    
    override var toolbarItemImage: NSImage {
        return NSImage(systemSymbolName: "arrow.down.right.and.arrow.up.left", accessibilityDescription: "Shrink") ?? NSImage()
    }
    
    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        // Master switch check
        let isEnabled = UserDefaults.shared.object(forKey: "finder_extension_enabled") as? Bool ?? false
        guard isEnabled else { return NSMenu(title: "") }
        
        // Only show context menus when clicking on items (files or folders)
        guard menuKind == .contextualMenuForItems else { return NSMenu(title: "") }
        
        let selectedItems = FIFinderSyncController.default().selectedItemURLs() ?? []
        guard !selectedItems.isEmpty else { return NSMenu(title: "") }
        
        let mainMenu = NSMenu(title: "")
        
        // Root context menu item: "Shrink" parent menu
        let parentItem = NSMenuItem(title: "Shrink", action: nil, keyEquivalent: "")
        parentItem.image = NSImage(systemSymbolName: "arrow.down.right.and.arrow.up.left", accessibilityDescription: "Shrink")
        
        let subMenu = NSMenu(title: "Shrink")
        
        let defaults = UserDefaults.shared
        
        let showArchive = defaults.object(forKey: "finder_show_compress_archive") as? Bool ?? true
        let showImage = defaults.object(forKey: "finder_show_compress_image") as? Bool ?? true
        let showVideo = defaults.object(forKey: "finder_show_compress_video") as? Bool ?? true
        let showAudio = defaults.object(forKey: "finder_show_compress_audio") as? Bool ?? true
        let showConvert = defaults.object(forKey: "finder_show_convert_file") as? Bool ?? true
        
        // 1. Archive
        if showArchive {
            let item = NSMenuItem(title: "Compress as Archive", action: #selector(compressAction(_:)), keyEquivalent: "")
            item.representedObject = "archive"
            item.image = NSImage(systemSymbolName: "archivebox", accessibilityDescription: nil)
            subMenu.addItem(item)
        }
        
        // 2. Image
        if showImage {
            let item = NSMenuItem(title: "Compress Image", action: #selector(compressAction(_:)), keyEquivalent: "")
            item.representedObject = "image"
            item.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
            subMenu.addItem(item)
        }
        
        // 3. Video
        if showVideo {
            let item = NSMenuItem(title: "Compress Video", action: #selector(compressAction(_:)), keyEquivalent: "")
            item.representedObject = "video"
            item.image = NSImage(systemSymbolName: "video", accessibilityDescription: nil)
            subMenu.addItem(item)
        }
        
        // 4. Audio
        if showAudio {
            let item = NSMenuItem(title: "Compress Audio", action: #selector(compressAction(_:)), keyEquivalent: "")
            item.representedObject = "audio"
            item.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
            subMenu.addItem(item)
        }
        
        // 5. Convert to...
        if showConvert {
            let convertItem = NSMenuItem(title: "Convert to", action: nil, keyEquivalent: "")
            convertItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
            
            let convertSubMenu = NSMenu(title: "Convert to")
            let formats = getConversionFormats(for: selectedItems)
            
            if !formats.isEmpty {
                for format in formats {
                    let formatItem = NSMenuItem(title: format, action: #selector(convertAction(_:)), keyEquivalent: "")
                    formatItem.representedObject = format
                    convertSubMenu.addItem(formatItem)
                }
            } else {
                let noFormatsItem = NSMenuItem(title: "No Formats Available", action: nil, keyEquivalent: "")
                noFormatsItem.isEnabled = false
                convertSubMenu.addItem(noFormatsItem)
            }
            
            convertItem.submenu = convertSubMenu
            subMenu.addItem(convertItem)
        }
        
        if subMenu.items.isEmpty {
            return NSMenu(title: "")
        }
        
        parentItem.submenu = subMenu
        mainMenu.addItem(parentItem)
        
        return mainMenu
    }
    
    @objc func compressAction(_ sender: NSMenuItem) {
        guard let type = sender.representedObject as? String else { return }
        let selectedItems = FIFinderSyncController.default().selectedItemURLs() ?? []
        guard !selectedItems.isEmpty else { return }
        
        let encodedPaths = selectedItems.map { url in
            Data(url.path.utf8).base64EncodedString()
        }.joined(separator: ",")
        
        let urlString = "shrink://compress?type=\(type)&files=\(encodedPaths)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func convertAction(_ sender: NSMenuItem) {
        guard let format = sender.representedObject as? String else { return }
        let selectedItems = FIFinderSyncController.default().selectedItemURLs() ?? []
        guard !selectedItems.isEmpty else { return }
        
        let encodedPaths = selectedItems.map { url in
            Data(url.path.utf8).base64EncodedString()
        }.joined(separator: ",")
        
        let urlString = "shrink://convert?format=\(format)&files=\(encodedPaths)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func getConversionFormats(for urls: [URL]) -> [String] {
        guard !urls.isEmpty else { return [] }
        
        var isAllImage = true
        var isAllVideo = true
        var isAllAudio = true
        var isAllDoc = true
        
        let defaults = UserDefaults.shared
        let useFFmpeg = defaults.bool(forKey: "use_ffmpeg")
        let useMagick = defaults.bool(forKey: "use_magick")
        let usePandoc = defaults.bool(forKey: "use_pandoc")
        
        for url in urls {
            let ext = url.pathExtension.lowercased()
            if !["png", "jpg", "jpeg", "heic", "heif", "webp", "gif", "tiff", "bmp", "avif"].contains(ext) {
                isAllImage = false
            }
            if !["mp4", "mov", "m4v", "mkv", "avi", "webm", "flv"].contains(ext) {
                isAllVideo = false
            }
            if !["mp3", "wav", "m4a", "flac", "aac", "ogg"].contains(ext) {
                isAllAudio = false
            }
            if !["pdf", "docx", "txt", "rtf", "epub", "html", "odt", "md", "markdown"].contains(ext) {
                isAllDoc = false
            }
        }
        
        if isAllImage {
            var formats = ["PNG", "JPEG", "WebP", "HEIC"]
            if useMagick {
                formats.append(contentsOf: ["AVIF", "TIFF", "GIF", "BMP"])
            }
            return formats
        } else if isAllVideo {
            var formats = ["MP4", "MOV"]
            if useFFmpeg {
                formats.append(contentsOf: ["MKV", "AVI", "WebM", "ProRes"])
            }
            return formats
        } else if isAllAudio {
            var formats = ["WAV", "M4A", "FLAC", "AAC"]
            if useFFmpeg {
                formats.insert("MP3", at: 0)
                formats.append("OGG")
            }
            return formats
        } else if isAllDoc {
            var formats = ["PDF", "DOCX", "TXT", "RTF"]
            if usePandoc {
                formats.append(contentsOf: ["ePub", "HTML", "Markdown"])
            }
            return formats
        } else {
            // Mixed selection defaults to standard archives
            return ["ZIP", "7Z", "TAR"]
        }
    }
}
