//
//  ArchiveSettingsManager.swift
//  Shrink
//

import Foundation

enum ArchiveSettingsManager {
    
    private static func compressKey(for format: ArchiveFormat) -> String {
        return "compress_\(format.keySuffix)_enabled"
    }
    
    private static func decompressKey(for format: ArchiveFormat) -> String {
        return "decompress_\(format.keySuffix)_enabled"
    }
    
    static func isCompressionEnabled(for format: ArchiveFormat) -> Bool {
        guard format.isCompressionSupported else { return false }
        // Defaults to true if not set
        if UserDefaults.standard.object(forKey: compressKey(for: format)) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: compressKey(for: format))
    }
    
    static func setCompressionEnabled(for format: ArchiveFormat, enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: compressKey(for: format))
        // Post notification so other views can update if needed
        NotificationCenter.default.post(name: .archiveSettingsChanged, object: nil)
    }
    
    static func isDecompressionEnabled(for format: ArchiveFormat) -> Bool {
        // Defaults to true if not set
        if UserDefaults.standard.object(forKey: decompressKey(for: format)) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: decompressKey(for: format))
    }
    
    static func setDecompressionEnabled(for format: ArchiveFormat, enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: decompressKey(for: format))
        // Post notification so other views can update if needed
        NotificationCenter.default.post(name: .archiveSettingsChanged, object: nil)
    }
}

extension ArchiveFormat {
    var keySuffix: String {
        switch self {
        case .zip: return "zip"
        case .tar: return "tar"
        case .tgz: return "tgz"
        case .sevenZip: return "sevenZip"
        case .rar: return "rar"
        case .gzip: return "gzip"
        case .bzip2: return "bzip2"
        case .xz: return "xz"
        case .lzma: return "lzma"
        case .cab: return "cab"
        case .msi: return "msi"
        case .iso: return "iso"
        case .sit: return "sit"
        case .sitx: return "sitx"
        case .dd: return "dd"
        case .cpt: return "cpt"
        case .arj: return "arj"
        case .arc: return "arc"
        case .zoo: return "zoo"
        case .lzh: return "lzh"
        }
    }
    
    var isCompressionEnabled: Bool {
        ArchiveSettingsManager.isCompressionEnabled(for: self)
    }
    
    var isDecompressionEnabled: Bool {
        ArchiveSettingsManager.isDecompressionEnabled(for: self)
    }
    
    var isCompressionSupported: Bool {
        switch self {
        case .zip, .tar, .tgz, .sevenZip: return true
        default: return false
        }
    }
}

extension NSNotification.Name {
    static let archiveSettingsChanged = NSNotification.Name("archiveSettingsChanged")
}
