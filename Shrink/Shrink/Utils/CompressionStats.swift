//
//  CompressionStats.swift
//  Shrink
//

import Foundation

final class CompressionStats: @unchecked Sendable {
    private let lock = NSLock()
    private var bytesRead: Int64 = 0
    private var completedBytesWritten: Int64 = 0
    private var activeOutputURLs: Set<URL> = []
    private var logicalWrittenBytes: [URL: Int64] = [:]
    
    // For speed calculations
    private var lastReadBytes: Int64 = 0
    private var lastWrittenBytes: Int64 = 0
    private var smoothedReadSpeed: Double = 0.0
    private var smoothedWriteSpeed: Double = 0.0
    
    func reset() {
        lock.lock()
        bytesRead = 0
        completedBytesWritten = 0
        activeOutputURLs.removeAll()
        logicalWrittenBytes.removeAll()
        lastReadBytes = 0
        lastWrittenBytes = 0
        smoothedReadSpeed = 0.0
        smoothedWriteSpeed = 0.0
        lock.unlock()
    }
    
    func addRead(_ bytes: Int64) {
        lock.lock()
        bytesRead += bytes
        lock.unlock()
    }
    
    func setRead(_ bytes: Int64) {
        lock.lock()
        bytesRead = bytes
        lock.unlock()
    }
    
    func addCompletedWritten(_ bytes: Int64) {
        lock.lock()
        completedBytesWritten += bytes
        lock.unlock()
    }
    
    func registerActiveOutput(_ url: URL) {
        lock.lock()
        activeOutputURLs.insert(url)
        lock.unlock()
    }
    
    func setLogicalWritten(for url: URL, bytes: Int64) {
        lock.lock()
        logicalWrittenBytes[url.standardizedFileURL] = bytes
        lock.unlock()
    }
    
    func unregisterActiveOutput(_ url: URL, finalSize: Int64) {
        lock.lock()
        activeOutputURLs.remove(url)
        logicalWrittenBytes.removeValue(forKey: url.standardizedFileURL)
        completedBytesWritten += finalSize
        lock.unlock()
    }
    
    var readBytes: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return bytesRead
    }
    
    func getSpeedAndStep() -> (readSpeed: Int64, writeSpeed: Int64) {
        lock.lock()
        defer { lock.unlock() }
        
        let currentRead = bytesRead
        
        var activeBytes: Int64 = 0
        let fm = FileManager.default
        for url in activeOutputURLs {
            let standardURL = url.standardizedFileURL
            if let logicalBytes = logicalWrittenBytes[standardURL] {
                activeBytes += logicalBytes
                continue
            }
            
            // 1. Direct file check
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64 {
                activeBytes += size
            }
            
            // 2. Video temp file (url + .tmp)
            let tmpPath = url.path + ".tmp"
            if let attrs = try? fm.attributesOfItem(atPath: tmpPath),
               let size = attrs[.size] as? Int64 {
                activeBytes += size
            }
            
            // 3. Directory check
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue {
                activeBytes += getFolderSizeInternal(at: url, fm: fm)
            }
            
            // 4. Split archive parts or temp staging files prefix-check
            let baseName = url.deletingPathExtension().lastPathComponent
            let parentDir = url.deletingLastPathComponent()
            if let files = try? fm.contentsOfDirectory(at: parentDir, includingPropertiesForKeys: nil) {
                let prefix = baseName
                for file in files {
                    let name = file.lastPathComponent
                    let isPartOrTemp = name.hasPrefix(prefix) || name.hasPrefix("shrink_temp_") || name.hasPrefix("shrink_staging_")
                    if isPartOrTemp {
                        if file.standardizedFileURL.path != url.standardizedFileURL.path && file.standardizedFileURL.path != tmpPath {
                            if let attrs = try? fm.attributesOfItem(atPath: file.path),
                               let size = attrs[.size] as? Int64 {
                                activeBytes += size
                            }
                        }
                    }
                }
            }
        }
        
        let currentWrite = completedBytesWritten + activeBytes
        
        let instantReadSpeed = Double(max(0, currentRead - lastReadBytes))
        let instantWriteSpeed = Double(max(0, currentWrite - lastWrittenBytes))
        
        lastReadBytes = currentRead
        lastWrittenBytes = currentWrite
        
        // Exponential moving average (EMA) with alpha = 0.5 for smooth transitions
        if smoothedReadSpeed == 0.0 && instantReadSpeed > 0 {
            smoothedReadSpeed = instantReadSpeed
        } else {
            smoothedReadSpeed = 0.5 * instantReadSpeed + 0.5 * smoothedReadSpeed
        }
        
        if smoothedWriteSpeed == 0.0 && instantWriteSpeed > 0 {
            smoothedWriteSpeed = instantWriteSpeed
        } else {
            smoothedWriteSpeed = 0.5 * instantWriteSpeed + 0.5 * smoothedWriteSpeed
        }
        
        return (Int64(round(smoothedReadSpeed)), Int64(round(smoothedWriteSpeed)))
    }
    
    private func getFolderSizeInternal(at folderURL: URL, fm: FileManager) -> Int64 {
        var size: Int64 = 0
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        guard let enumerator = fm.enumerator(at: folderURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return 0
        }
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: Set(keys)) {
                if let isDir = values.isDirectory, isDir {
                    continue
                }
                if let fileSize = values.fileSize {
                    size += Int64(fileSize)
                }
            }
        }
        return size
    }
}
