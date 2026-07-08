//
//  ArchiveCompressor.swift
//  Shrink
//

import Foundation
import Darwin

nonisolated enum ArchiveFormat: String, CaseIterable, Identifiable, Sendable {
    case zip = "ZIP"
    case tar = "TAR"
    case tgz = "TAR.GZ"
    case sevenZip = "7-Zip (7z)"
    case rar = "RAR"
    case gzip = "Gzip"
    case bzip2 = "Bzip2"
    case xz = "XZ"
    case lzma = "LZMA"
    case cab = "CAB"
    case msi = "MSI"
    case iso = "ISO"
    case sit = "StuffIt"
    case sitx = "StuffIt X"
    case dd = "DD"
    case cpt = "Compact Pro"
    case arj = "ARJ"
    case arc = "ARC"
    case zoo = "ZOO"
    case lzh = "LZH"
    
    var id: String { rawValue }
    
    var fileExtension: String {
        switch self {
        case .zip: return "zip"
        case .tar: return "tar"
        case .tgz: return "tar.gz"
        case .sevenZip: return "7z"
        case .rar: return "rar"
        case .gzip: return "gz"
        case .bzip2: return "bz2"
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
    
    static func fromExtension(_ ext: String) -> ArchiveFormat {
        switch ext.lowercased() {
        case "zip": return .zip
        case "tar": return .tar
        case "tgz": return .tgz
        case "7z": return .sevenZip
        case "rar": return .rar
        case "gz": return .gzip
        case "bz2": return .bzip2
        case "xz": return .xz
        case "lzma": return .lzma
        case "cab": return .cab
        case "msi": return .msi
        case "iso": return .iso
        case "sit": return .sit
        case "sitx": return .sitx
        case "dd": return .dd
        case "cpt": return .cpt
        case "arj": return .arj
        case "arc": return .arc
        case "zoo": return .zoo
        case "lzh": return .lzh
        default: return .zip
        }
    }
}

protocol CancelableOperation: AnyObject {
    nonisolated func cancel()
}

nonisolated final class ArchiveCompressor: CancelableOperation, @unchecked Sendable {
    
    private var activeProcess: Process?
    private var isCancelled = false
    private let processQueue = DispatchQueue(label: "shrink.archive-process")
    
    func cancel() {
        print("[ARCHIVE DEBUG] cancel() called. isCancelled was \(isCancelled), activeProcess is nil? \(activeProcess == nil)")
        processQueue.sync {
            isCancelled = true
            if let proc = activeProcess {
                print("[ARCHIVE DEBUG] activeProcess PID: \(proc.processIdentifier). Terminating...")
                proc.terminate()
            } else {
                print("[ARCHIVE DEBUG] No activeProcess found to terminate.")
            }
        }
    }
    
    // Cache/lookup paths dynamically.
    static var sevenZipPath: String? { findBundledExecutable(name: "7zz") }
    static var unarPath: String? { findBundledExecutable(name: "unar") }
    static var pigzPath: String? { findBundledExecutable(name: "pigz") }

    // Check if 7z CLI is available on the system
    static func isSevenZipAvailable() -> Bool {
        return sevenZipPath != nil
    }

    static func isSevenZipEnabled() -> Bool {
        return sevenZipPath != nil && UserDefaults.standard.bool(forKey: "use_sevenzip_for_archive")
    }
    
    // Helper to find a bundled executable.
    private static func findBundledExecutable(name: String) -> String? {
        // The executables should be placed in the app's Resources folder.
        if let path = Bundle.main.path(forResource: name, ofType: nil) {
            if isExecutable(atPath: path) {
                return path
            }
        }
        return nil
    }

    // Helper to find a system-installed executable, falling back to bundled.
    private static func findSystemExecutable(name: String) -> String? {
        if let bundled = findBundledExecutable(name: name) {
            return bundled
        }
        
        let commonPaths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)"
        ]
        for path in commonPaths {
            if isExecutable(atPath: path) {
                return path
            }
        }
        
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            let dirs = envPath.components(separatedBy: ":")
            for dir in dirs {
                let path = URL(fileURLWithPath: dir).appendingPathComponent(name).path
                if isExecutable(atPath: path) {
                    return path
                }
            }
        }
        
        return nil
    }
    
    // Asynchronous wrapper for listing contents
    static func listContents(archiveURL: URL) async -> [(String, Int64, Bool)] {
        return await Task.detached(priority: .userInitiated) {
            return listContentsSync(archiveURL: archiveURL)
        }.value
    }
    
    // Synchronously list archive contents for common archive formats
    // Returns tuples of (path, size, isDirectory)
    static func listContentsSync(archiveURL: URL) -> [(String, Int64, Bool)] {
        func runCommand(_ exe: String, _ args: [String]) -> String? {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: exe)
            proc.arguments = args
            let out = Pipe()
            proc.standardOutput = out
            proc.standardError = Pipe() // Ignore errors for listing
            do {
                try proc.run()
                proc.waitUntilExit()
                let data = out.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)
            } catch {
                return nil
            }
        }

        // Prioritize bundled 7zz for detailed, machine-readable output.
        if let seven = sevenZipPath {
            if let output = runCommand(seven, ["l", "-slt", archiveURL.path]) {
                var results: [(String, Int64, Bool)] = []
                let fileBlocks = output.components(separatedBy: "\n\n")
                
                for block in fileBlocks {
                    var path: String?
                    var size: Int64 = 0
                    var isDir = false
                    
                    let lines = block.components(separatedBy: .newlines)
                    for line in lines {
                        let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                        if parts.count == 2 {
                            let key = parts[0]
                            let value = parts[1]
                            
                            if key == "Path" {
                                path = value
                            } else if key == "Size" {
                                size = Int64(value) ?? 0
                            } else if key == "Attributes" {
                                isDir = value.contains("D")
                            }
                        }
                    }
                    
                    if let p = path, !p.isEmpty {
                        results.append((p, size, isDir))
                    }
                }
                if !results.isEmpty {
                    return results
                }
            }
        }

        // Fallback to system tools if 7zz is not available or fails.
        let ext = archiveURL.pathExtension.lowercased()
        var results: [(String, Int64, Bool)] = []

        if ["zip"].contains(ext) {
            if let output = runCommand("/usr/bin/unzip", ["-l", archiveURL.path]) {
                let lines = output.components(separatedBy: .newlines)
                var contentStarted = false
                for line in lines {
                    if line.contains("----------") {
                        if contentStarted { break } // second separator, end of list
                        contentStarted = true
                        continue
                    }
                    if !contentStarted || line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                    
                    let components = line.split(separator: " ", maxSplits: 3)
                    if components.count >= 4, let size = Int64(components[0]) {
                        let path = String(components[3])
                        let isDir = path.hasSuffix("/")
                        results.append((path, size, isDir))
                    }
                }
            }
            return results
        }
        
        if ["tar", "tgz", "gz"].contains(ext) {
            if let output = runCommand("/usr/bin/tar", ["-tvf", archiveURL.path]) {
                for line in output.components(separatedBy: "\n") where !line.isEmpty {
                    let components = line.split(separator: " ", maxSplits: 8)
                    if components.count > 5 {
                        let size = Int64(components[4]) ?? 0
                        let path = components.last.map(String.init) ?? ""
                        let isDir = line.hasPrefix("d") || path.hasSuffix("/")
                        results.append((path, size, isDir))
                    }
                }
            }
            return results
        }

        return []
    }
    
    private static func isExecutable(atPath path: String) -> Bool {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        return url.isFileURL && access(url.path, X_OK) == 0
    }
    
    // Compress multiple files/folders into an archive asynchronously
    func compress(
        urls: [URL],
        destinationURL: URL,
        format: ArchiveFormat,
        compressionLevel: Int,
        password: String?,
        splitSize: Int64?,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        let fileManager = FileManager.default
        
        processQueue.sync {
            isCancelled = false
            activeProcess = nil
        }
        
        guard !urls.isEmpty else {
            throw NSError(domain: "ArchiveCompressorError", code: 10, userInfo: [NSLocalizedDescriptionKey: "No files or folders selected for archiving."])
        }
        
        // Clamp compression level 0-9, default 5 (balanced)
        let level = max(0, min(9, compressionLevel))
        
        let standardizedURLs = urls.map { $0.standardizedFileURL }
        
        // Start accessing all input URLs and the destination folder
        var accessedURLs: [URL] = []
        for url in standardizedURLs {
            if url.startAccessingSecurityScopedResource() {
                accessedURLs.append(url)
            }
        }
        defer {
            for url in accessedURLs {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        let destDir = destinationURL.deletingLastPathComponent()
        let isAccessingDest = destDir.startAccessingSecurityScopedResource()
        defer {
            if isAccessingDest {
                destDir.stopAccessingSecurityScopedResource()
            }
        }
        
        // --- Smart Compression Strategy ---
        // Find the common parent directory of all selected items to create clean archive paths.
        // If no common parent (e.g., files from different volumes), fall back to home directory
        // and use absolute paths.
        var commonParent = standardizedURLs.first?.deletingLastPathComponent()
        if standardizedURLs.count > 1 {
            for url in standardizedURLs.dropFirst() {
                while let parent = commonParent, !url.path.hasPrefix(parent.path) {
                    commonParent = parent.deletingLastPathComponent()
                }
            }
        }
        
        let archiveWorkingDir = commonParent ?? FileManager.default.homeDirectoryForCurrentUser
        let pathsToArchive = standardizedURLs.map { $0.path.replacingOccurrences(of: archiveWorkingDir.path + "/", with: "") }
        
        // Target split handling: if we need to split but it is NOT 7z (7z splits natively),
        // we compress to a temporary file first, then split it.
        let needsPostSplit = (splitSize != nil && splitSize! > 0 && format != .sevenZip)
        let actualDestURL = needsPostSplit ? destDir.appendingPathComponent("shrink_temp_" + UUID().uuidString + "." + format.fileExtension) : destinationURL
        
        defer {
            if needsPostSplit {
                try? fileManager.removeItem(at: actualDestURL)
            }
        }
        
        // Perform compression based on format
        switch format {
        case .zip:
            // Use bundled 7zz for zip creation if enabled. It's fast, multi-threaded, and provides progress.
            if Self.isSevenZipEnabled() {
                try await runSevenZipForZip(sourceDir: archiveWorkingDir, relativePaths: pathsToArchive, destURL: actualDestURL, compressionLevel: level, password: password, totalFiles: 0, progressHandler: progressHandler)
            } else {
                // Fallback to native `ditto` if 7zz is not bundled/enabled. This is fast but provides no progress.
                try await runDitto(sourceDir: archiveWorkingDir, relativePaths: pathsToArchive, destURL: actualDestURL, compress: true, compressionLevel: level, password: password, totalFiles: 0, progressHandler: progressHandler)
            }
        case .tar:
            try await runTar(sourceDir: archiveWorkingDir, relativePaths: pathsToArchive, destURL: actualDestURL, compress: false, compressionLevel: level, totalFiles: 0, progressHandler: progressHandler)
        case .tgz:
            try await runTar(sourceDir: archiveWorkingDir, relativePaths: pathsToArchive, destURL: actualDestURL, compress: true, compressionLevel: level, totalFiles: 0, progressHandler: progressHandler)
        case .sevenZip:
            if Self.isSevenZipEnabled() {
                try await runSevenZip(sourceDir: archiveWorkingDir, relativePaths: pathsToArchive, destURL: actualDestURL, compressionLevel: level, password: password, splitSize: splitSize, totalFiles: 0, progressHandler: progressHandler)
            } else {
                throw NSError(domain: "ArchiveCompressorError", code: 100, userInfo: [NSLocalizedDescriptionKey: "7-Zip compression requires the 7zz utility to be enabled."])
            }
        case .rar:
            throw NSError(domain: "ArchiveCompressorError", code: 100, userInfo: [NSLocalizedDescriptionKey: "RAR compression is not supported."])
        default:
            throw NSError(domain: "ArchiveCompressorError", code: 100, userInfo: [NSLocalizedDescriptionKey: "Compression for this format is not yet supported."])
        }
        
        // Handle split size after compression if needed (for zip/tar/tgz)
        if needsPostSplit, let size = splitSize {
            try splitFile(at: actualDestURL, chunkSize: size, destinationPrefixURL: destinationURL)
        }
    }
    
    // Extract archive asynchronously
    func decompress(
        archiveURL: URL,
        destinationURL: URL,
        password: String?,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        let fileManager = FileManager.default
        
        processQueue.sync {
            isCancelled = false
            activeProcess = nil
        }
        
        // Resolve security-scoped urls
        let isAccessingArchive = archiveURL.startAccessingSecurityScopedResource()
        let isAccessingDest = destinationURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessingArchive { archiveURL.stopAccessingSecurityScopedResource() }
            if isAccessingDest { destinationURL.stopAccessingSecurityScopedResource() }
        }
        
        // Ensure destination folder exists
        if !fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        let pathExtension = archiveURL.pathExtension.lowercased()
        var resolvedArchiveURL = archiveURL
        var tempConcatURL: URL?
        
        // Check for split parts (e.g., archive.zip.001)
        if pathExtension == "001" || pathExtension.range(of: "^\\d{3}$", options: .regularExpression) != nil {
            let baseName = archiveURL.deletingPathExtension().deletingPathExtension().lastPathComponent
            let targetExt = archiveURL.deletingPathExtension().pathExtension
            let parentDir = archiveURL.deletingLastPathComponent()
            
            let allFiles = try fileManager.contentsOfDirectory(at: parentDir, includingPropertiesForKeys: nil)
            let parts = allFiles.filter {
                let name = $0.lastPathComponent
                return name.hasPrefix(baseName) && $0.pathExtension.range(of: "^\\d{3}$", options: .regularExpression) != nil
            }.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            
            if !parts.isEmpty {
                let concatURL = destinationURL.appendingPathComponent("shrink_decompress_temp_" + UUID().uuidString + "." + targetExt)
                tempConcatURL = concatURL
                try concatenateFiles(partURLs: parts, outputURL: concatURL)
                resolvedArchiveURL = concatURL
            }
        }
        
        defer {
            if let temp = tempConcatURL {
                try? fileManager.removeItem(at: temp)
            }
        }
        
        let format = ArchiveFormat.fromExtension(resolvedArchiveURL.pathExtension)
        
        switch format {
        case .zip:
            if let password = password, !password.isEmpty {
                try await runUnzip(archiveURL: resolvedArchiveURL, destURL: destinationURL, password: password, progressHandler: progressHandler)
            } else {
                try await runDittoExtract(archiveURL: resolvedArchiveURL, destURL: destinationURL, progressHandler: progressHandler)
            }
        case .tar, .tgz:
            try await runTarExtract(archiveURL: resolvedArchiveURL, destURL: destinationURL, progressHandler: progressHandler)
        case .sevenZip:
            if Self.isSevenZipEnabled() {
                try await runSevenZipExtract(archiveURL: resolvedArchiveURL, destURL: destinationURL, password: password, progressHandler: progressHandler)
            } else if Self.unarPath != nil {
                try await runUnarExtract(archiveURL: resolvedArchiveURL, destURL: destinationURL, password: password, progressHandler: progressHandler)
            } else {
                throw NSError(domain: "ArchiveCompressorError", code: 100, userInfo: [NSLocalizedDescriptionKey: "7-Zip decompression requires either 7-Zip or unar utility."])
            }
        case .rar:
            if Self.isSevenZipEnabled() {
                try await runSevenZipExtract(archiveURL: resolvedArchiveURL, destURL: destinationURL, password: password, progressHandler: progressHandler)
            } else if Self.unarPath != nil {
                try await runUnarExtract(archiveURL: resolvedArchiveURL, destURL: destinationURL, password: password, progressHandler: progressHandler)
            } else {
                // Fallback to native macOS tar/bsdtar
                try await runTarExtract(archiveURL: resolvedArchiveURL, destURL: destinationURL, progressHandler: progressHandler)
            }
        default:
            // Fallback to 7-Zip if enabled, otherwise unar, otherwise throw
            if Self.isSevenZipEnabled() {
                try await runSevenZipExtract(archiveURL: resolvedArchiveURL, destURL: destinationURL, password: password, progressHandler: progressHandler)
            } else if Self.unarPath != nil {
                try await runUnarExtract(archiveURL: resolvedArchiveURL, destURL: destinationURL, password: password, progressHandler: progressHandler)
            } else {
                throw NSError(domain: "ArchiveCompressorError", code: 100, userInfo: [NSLocalizedDescriptionKey: "No extractor available for format: \(format.rawValue)"])
            }
        }
    }
    
    // MARK: - Process Execution Helpers
    
    private func parse7zPercentage(from line: String) -> Double? {
        guard let percentIndex = line.firstIndex(of: "%") else {
            return nil
        }
        let prefix = line[..<percentIndex]
        var digitString = ""
        for char in prefix.reversed() {
            if char.isNumber {
                digitString.insert(char, at: digitString.startIndex)
            } else if !digitString.isEmpty {
                break
            }
        }
        if let percentageVal = Double(digitString) {
            return percentageVal / 100.0
        }
        return nil
    }
    
    private func runProcess(
        executablePath: String,
        arguments: [String],
        currentDirectoryURL: URL,
        environment: [String: String]? = nil,
        totalFiles: Int,
        progressParser: @escaping @Sendable (String, Int, SafeProgress) -> Double?,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.standardInput = Pipe()
        
        var env = ProcessInfo.processInfo.environment
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + currentPath
        if let customEnv = environment {
            for (key, val) in customEnv {
                env[key] = val
            }
        }
        process.environment = env
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        let processedCount = SafeProgress()
        let outputBuffer = SafeString()
        let errorBuffer = SafeString()
        let cleanErrorLog = SafeString()
        let errorData = SafeData()
        
        // Define handlers once to be used for both live reading and final read.
        let outputHandler: @Sendable (FileHandle) -> Void = { handle in
            let data = handle.availableData
            if !data.isEmpty, let chunk = String(data: data, encoding: .utf8) {
                outputBuffer.append(chunk)
                let lines = outputBuffer.valueAndClearLines
                for line in lines {
                    if let progress = progressParser(line, totalFiles, processedCount) {
                        progressHandler(progress)
                    }
                }
            }
        }
        outputPipe.fileHandleForReading.readabilityHandler = outputHandler
        
        let errorHandler: @Sendable (FileHandle) -> Void = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                errorData.append(data)
                if let chunk = String(data: data, encoding: .utf8) {
                    errorBuffer.append(chunk)
                    let lines = errorBuffer.valueAndClearLines
                    for line in lines {
                        if let progress = progressParser(line, totalFiles, processedCount) {
                            progressHandler(progress)
                        } else {
                            cleanErrorLog.append(line + "\n")
                        }
                    }
                }
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = errorHandler
        
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                print("[ARCHIVE DEBUG] Process terminationHandler invoked for PID \(proc.processIdentifier). exitStatus: \(proc.terminationStatus)")
                
                // Perform a final read to catch any remaining data that wasn't followed by a newline.
                outputHandler(outputPipe.fileHandleForReading)
                errorHandler(errorPipe.fileHandleForReading)
                
                // Flush remaining text from buffers that did not end in newlines.
                let remainingOutput = outputBuffer.currentValue
                if !remainingOutput.isEmpty {
                    if let progress = progressParser(remainingOutput, totalFiles, processedCount) {
                        progressHandler(progress)
                    }
                }
                
                let remainingError = errorBuffer.currentValue
                if !remainingError.isEmpty {
                    if let progress = progressParser(remainingError, totalFiles, processedCount) {
                        progressHandler(progress)
                    } else {
                        cleanErrorLog.append(remainingError)
                    }
                }
                
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                
                let cancelled = self.processQueue.sync { () -> Bool in
                    self.activeProcess = nil
                    return self.isCancelled
                }
                
                print("[ARCHIVE DEBUG] isCancelled value: \(cancelled)")
                if proc.terminationStatus == 0 {
                    progressHandler(1.0)
                    continuation.resume()
                } else {
                    if cancelled {
                        print("[ARCHIVE DEBUG] Continuation throwing stopped by user error")
                        continuation.resume(throwing: NSError(domain: "ArchiveCompressorError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Operation stopped by user"]))
                    } else {
                        var errorMsg = cleanErrorLog.currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if errorMsg.isEmpty {
                            errorMsg = String(data: errorData.currentData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Subprocess failed with code \(proc.terminationStatus)"
                        }
                        continuation.resume(throwing: NSError(domain: "ArchiveCompressorError", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorMsg]))
                    }
                }
            }
            
            do {
                try self.processQueue.sync {
                    if self.isCancelled {
                        throw NSError(domain: "ArchiveCompressorError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Operation stopped by user"])
                    }
                    self.activeProcess = process
                }

                try process.run()
            } catch {
                if (error as NSError).code == 99 {
                    continuation.resume(throwing: NSError(domain: "ArchiveCompressorError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Operation stopped by user"]))
                    return
                }
                self.processQueue.sync {
                    self.activeProcess = nil
                }

                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func runDecompressProcess(
        executablePath: String,
        arguments: [String],
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardInput = Pipe()
        
        var env = ProcessInfo.processInfo.environment
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + currentPath
        process.environment = env
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        let errorData = SafeData()
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                errorPipe.fileHandleForReading.readabilityHandler = nil
            } else {
                errorData.append(data)
            }
        }
        
        let isDone = SafeBool(false)
        let timerTask = Task {
            var elapsed = 0.0
            while !isDone.value {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if isDone.value { break }
                elapsed += 0.1
                let prog = 1.0 - exp(-elapsed / 5.0) * 0.99
                progressHandler(prog)
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                isDone.setValue(true)
                timerTask.cancel()
                errorPipe.fileHandleForReading.readabilityHandler = nil
                
                let cancelled = self.processQueue.sync { () -> Bool in
                    self.activeProcess = nil
                    return self.isCancelled
                }
                
                if proc.terminationStatus == 0 {
                    progressHandler(1.0)
                    continuation.resume()
                } else {
                    if cancelled {
                        continuation.resume(throwing: NSError(domain: "ArchiveCompressorError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Operation stopped by user"]))
                    } else {
                        let errorMsg = String(data: errorData.currentData, encoding: .utf8) ?? "Extraction failed with code \(proc.terminationStatus)"
                        continuation.resume(throwing: NSError(domain: "ArchiveCompressorError", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorMsg]))
                    }
                }
            }
            
            do {
                let alreadyCancelled = self.processQueue.sync { () -> Bool in
                    if self.isCancelled {
                        return true
                    }
                    self.activeProcess = process
                    return false
                }
                if alreadyCancelled {
                    isDone.setValue(true)
                    timerTask.cancel()
                    continuation.resume(throwing: NSError(domain: "ArchiveCompressorError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Operation stopped by user"]))
                    return
                }

                try process.run()
            } catch {
                isDone.setValue(true)
                timerTask.cancel()
                self.processQueue.sync {
                    self.activeProcess = nil
                }

                errorPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func runProcessWithFauxProgress(
        executablePath: String,
        arguments: [String],
        currentDirectoryURL: URL,
        environment: [String: String]? = nil,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.standardInput = Pipe()
        
        var env = ProcessInfo.processInfo.environment
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + currentPath
        if let customEnv = environment {
            for (key, val) in customEnv {
                env[key] = val
            }
        }
        process.environment = env
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        let errorData = SafeData()
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                errorPipe.fileHandleForReading.readabilityHandler = nil
            } else {
                errorData.append(data)
            }
        }
        
        let isDone = SafeBool(false)
        let timerTask = Task {
            var elapsed = 0.0
            while !isDone.value {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if isDone.value { break }
                elapsed += 0.1
                // Asymptotic progress curve that feels more natural for long operations
                let prog = 1.0 - exp(-elapsed / 10.0) * 0.99
                progressHandler(prog)
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                isDone.setValue(true)
                timerTask.cancel()
                errorPipe.fileHandleForReading.readabilityHandler = nil
                
                let cancelled = self.processQueue.sync { () -> Bool in
                    self.activeProcess = nil
                    return self.isCancelled
                }
                
                if proc.terminationStatus == 0 {
                    progressHandler(1.0)
                    continuation.resume()
                } else {
                    if cancelled {
                        continuation.resume(throwing: NSError(domain: "ArchiveCompressorError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Operation stopped by user"]))
                    } else {
                        let errorMsg = String(data: errorData.currentData, encoding: .utf8) ?? "Subprocess failed with code \(proc.terminationStatus)"
                        continuation.resume(throwing: NSError(domain: "ArchiveCompressorError", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorMsg]))
                    }
                }
            }
            
            do {
                try self.processQueue.sync {
                    if self.isCancelled { throw NSError(domain: "ArchiveCompressorError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Operation stopped by user"]) }
                    self.activeProcess = process
                }
                try process.run()
            } catch {
                isDone.setValue(true)
                timerTask.cancel()
                self.processQueue.sync { self.activeProcess = nil }
                errorPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func runDitto(
        sourceDir: URL,
        relativePaths: [String],
        destURL: URL,
        compress: Bool,
        compressionLevel: Int,
        password: String?,
        totalFiles: Int,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        // `ditto` is a fast, native tool for creating ZIP archives.
        var args = ["-c", "--sequesterRsrc"]
        if compress { // ZIP
            args.append("-k")
        }
        
        // `ditto` doesn't support password-protected zips. If 7zz is not available and a password is set, we must fail.
        if let password = password, !password.isEmpty {
            throw NSError(domain: "ArchiveCompressorError", code: 101, userInfo: [NSLocalizedDescriptionKey: "Password-protected ZIP creation requires the bundled 7zz utility, which was not found."])
        }
        
        // Add source paths, then destination archive path
        args += relativePaths
        args.append(destURL.path)
        
        // `ditto` does not provide progress, so we use a faux progress handler to give the user feedback.
        try await runProcessWithFauxProgress(
            executablePath: "/usr/bin/ditto",
            arguments: args,
            currentDirectoryURL: sourceDir,
            progressHandler: progressHandler
        )
    }
    
    private func runTar(
        sourceDir: URL,
        relativePaths: [String],
        destURL: URL,
        compress: Bool,
        compressionLevel: Int,
        totalFiles: Int,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        var args = ["-cvf", destURL.path] + relativePaths
        var customEnv: [String: String]? = nil
        
        if compress {
            // Use bundled pigz for multi-threaded gzip if available, otherwise fallback to standard gzip
            if let pigzPath = Self.pigzPath {
                // Use pigz for parallel compression. The compression level is passed to pigz.
                args = ["--use-compress-program", "\(pigzPath) -\(max(1, min(9, compressionLevel)))"] + args
            } else {
                args.insert("-z", at: 0) // Use standard single-threaded gzip
                customEnv = ["GZIP": "-\(max(1, min(9, compressionLevel)))"]
            }
        }
        
        // `tar` does not provide reliable progress, so we use a faux progress handler.
        try await runProcessWithFauxProgress(
            executablePath: "/usr/bin/tar",
            arguments: args,
            currentDirectoryURL: sourceDir,
            environment: customEnv,
            progressHandler: progressHandler
        )
    }
    
    private func runSevenZip(
        sourceDir: URL,
        relativePaths: [String],
        destURL: URL,
        compressionLevel: Int,
        password: String?,
        splitSize: Int64?,
        totalFiles: Int,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let binPath = Self.sevenZipPath else {
            throw NSError(domain: "ArchiveCompressorError", code: 404, userInfo: [NSLocalizedDescriptionKey: "7-Zip utility not found. Install via 'brew install p7zip'."])
        }
        
        // --- Simple, Direct Compression Strategy ---
        // Create a single archive with all files using the specified compression level.
        // This is the most straightforward and reliable method.
        // We achieve selective compression by storing media files and compressing the rest.
        let threadCount = max(1, ProcessInfo.processInfo.activeProcessorCount)
        var args = ["a", "-mmt=\(threadCount)", "-y", "-bsp2"]
        
        // --- 7z Optimization ---
        // Use -ax! (exclude) to skip compression for these file types, effectively "storing" them.
        // This tells 7z to not waste time trying to compress them.
        let storeExtensions = ["*.jpg", "*.jpeg", "*.png", "*.gif", "*.webp", "*.heic", "*.mp4", "*.mov", "*.mkv", "*.mp3", "*.zip", "*.gz", "*.rar", "*.pdf"]
        for ext in storeExtensions {
            args.append("-ax!\(ext)")
        }
        
        // For all other files, apply the user-selected compression level with the efficient LZMA2 algorithm.
        args.append("-m0=LZMA2")
        args.append("-mx=\(compressionLevel)")
        
        if let password = password, !password.isEmpty {
            args.append("-p\(password)")
            args.append("-mhe=on") // Encrypt headers
        }

        if let size = splitSize, size > 0 {
            let sizeInMb = size / (1024 * 1024)
            args.append("-v\(sizeInMb)m")
        }
        
        // Add destination and source files
        args.append(destURL.path)
        args += relativePaths
        
        try await runProcess(
            executablePath: binPath,
            arguments: args,
            currentDirectoryURL: sourceDir,
            totalFiles: totalFiles,
            progressParser: { line, total, processedCount in
                if let percent = self.parse7zPercentage(from: line) {
                    return min(0.99, percent)
                }
                return nil
            },
            progressHandler: progressHandler
        )
    }
    
    private func runSevenZipForZip(
        sourceDir: URL,
        relativePaths: [String],
        destURL: URL,
        compressionLevel: Int,
        password: String?,
        totalFiles: Int,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let binPath = Self.sevenZipPath else {
            // This should not happen if we check before calling
            throw NSError(domain: "ArchiveCompressorError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Bundled 7zz utility not found."])
        }
        
        let threadCount = max(1, ProcessInfo.processInfo.activeProcessorCount)
        // 'a' for add, '-tzip' for zip format, '-bsp2' for progress reporting
        var args = ["a", "-tzip", "-mmt=\(threadCount)", "-y", "-bsp2"]
        
        // 7z for zip uses -mx=0-9 for Deflate/Deflate64 level. 0=store, 9=max. This maps well.
        args.append("-mx=\(compressionLevel)")
        
        if let password = password, !password.isEmpty {
            // Use AES-256 for zip if available, which is more secure than standard ZipCrypto.
            args.append("-p\(password)")
            args.append("-mem=AES256")
        }
        
        // Add destination and source files
        args.append(destURL.path)
        args += relativePaths
        
        try await runProcess(
            executablePath: binPath,
            arguments: args,
            currentDirectoryURL: sourceDir,
            totalFiles: totalFiles,
            progressParser: { line, total, processedCount in
                return self.parse7zPercentage(from: line)
            },
            progressHandler: progressHandler
        )
    }

    
    // MARK: - Extraction Process Invokers
    
    private func runDittoExtract(
        archiveURL: URL,
        destURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        try await runDecompressProcess(executablePath: "/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, destURL.path], progressHandler: progressHandler)
    }
    
    private func runUnzip(
        archiveURL: URL,
        destURL: URL,
        password: String,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        try await runDecompressProcess(executablePath: "/usr/bin/unzip", arguments: ["-P", password, archiveURL.path, "-d", destURL.path], progressHandler: progressHandler)
    }
    
    private func runTarExtract(
        archiveURL: URL,
        destURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        try await runDecompressProcess(executablePath: "/usr/bin/tar", arguments: ["-xf", archiveURL.path, "-C", destURL.path], progressHandler: progressHandler)
    }
    
    private func runSevenZipExtract(
        archiveURL: URL,
        destURL: URL,
        password: String?,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let binPath = Self.sevenZipPath else {
            throw NSError(domain: "ArchiveCompressorError", code: 404, userInfo: [NSLocalizedDescriptionKey: "7-Zip utility not found. Install via 'brew install p7zip'."])
        }
        
        var args = ["x", archiveURL.path, "-o\(destURL.path)", "-y", "-bsp2"]
        if let password = password, !password.isEmpty {
            args.append("-p\(password)")
        }
        
        try await runProcess(
            executablePath: binPath,
            arguments: args,
            currentDirectoryURL: destURL.deletingLastPathComponent(),
            totalFiles: 0,
            progressParser: { line, total, processedCount in
                if let percent = self.parse7zPercentage(from: line) {
                    return min(0.99, percent)
                }
                return nil
            },
            progressHandler: progressHandler
        )
    }


    private func runUnarExtract(
        archiveURL: URL,
        destURL: URL,
        password: String?,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let binPath = Self.unarPath else {
            throw NSError(domain: "ArchiveCompressorError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Bundled unar utility not found."])
        }
        var args = ["-o", destURL.path, "-f", archiveURL.path]
        if let password = password, !password.isEmpty {
            args += ["-p", password]
        }
        try await runDecompressProcess(executablePath: binPath, arguments: args, progressHandler: progressHandler)
    }
    
    // MARK: - Binary Splitting and Merging
    
    private func splitFile(at fileURL: URL, chunkSize: Int64, destinationPrefixURL: URL) throws {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? fileHandle.close()
        }
        
        let fileManager = FileManager.default
        var partNumber = 1
        
        let prefixURL = destinationPrefixURL
        
        let bufferSize = 8 * 1024 * 1024 // 8 MB read buffer
        var bytesReadForCurrentChunk: Int64 = 0
        
        var currentOutputHandle: FileHandle?
        
        func closeCurrentHandle() {
            if let handle = currentOutputHandle {
                try? handle.close()
                currentOutputHandle = nil
            }
        }
        
        defer {
            closeCurrentHandle()
        }
        
        while true {
            let bytesToRead = min(Int64(bufferSize), chunkSize - bytesReadForCurrentChunk)
            guard bytesToRead > 0 else {
                // Chunk boundary met, cycle chunk
                closeCurrentHandle()
                bytesReadForCurrentChunk = 0
                partNumber += 1
                continue
            }
            
            let data: Data
            if let d = try fileHandle.read(upToCount: Int(bytesToRead)), !d.isEmpty {
                data = d
            } else {
                break // EOF
            }
            
            if currentOutputHandle == nil {
                let partName = String(format: "%@.%03d", prefixURL.lastPathComponent, partNumber)
                let partURL = prefixURL.deletingLastPathComponent().appendingPathComponent(partName)
                
                if fileManager.fileExists(atPath: partURL.path) {
                    try fileManager.removeItem(at: partURL)
                }
                
                fileManager.createFile(atPath: partURL.path, contents: nil, attributes: nil)
                currentOutputHandle = try FileHandle(forWritingTo: partURL)
            }
            
            try currentOutputHandle?.write(contentsOf: data)
            bytesReadForCurrentChunk += Int64(data.count)
            
            if bytesReadForCurrentChunk >= chunkSize {
                closeCurrentHandle()
                bytesReadForCurrentChunk = 0
                partNumber += 1
            }
        }
    }
    
    private func concatenateFiles(partURLs: [URL], outputURL: URL) throws {
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        
        fileManager.createFile(atPath: outputURL.path, contents: nil, attributes: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer {
            try? outputHandle.close()
        }
        
        for url in partURLs {
            let inputHandle = try FileHandle(forReadingFrom: url)
            
            while let data = try? inputHandle.read(upToCount: 8 * 1024 * 1024), !data.isEmpty {
                try outputHandle.write(contentsOf: data)
            }
            
            try? inputHandle.close()
        }
    }
}

// MARK: - Thread-Safe Concurrency Wrappers

nonisolated private final class SafeProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

nonisolated private final class SafeData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    
    func append(_ other: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(other)
    }
    
    var currentData: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

nonisolated private final class SafeString: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""
    
    func append(_ other: String) {
        lock.lock()
        defer { lock.unlock() }
        value.append(other)
    }
    
    var currentValue: String {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    
    var valueAndClearLines: [String] {
        lock.lock()
        defer { lock.unlock() }
        
        // Split by any newline character. `\r` is common for in-place progress updates.
        let components = value.components(separatedBy: CharacterSet(charactersIn: "\n\r"))
        
        // If there's only one component, it means no newline was found.
        // The buffer might contain an incomplete line, so we wait for more data.
        guard components.count > 1 else {
            return []
        }
        
        // The last component is the potentially incomplete line part. Keep it.
        value = components.last ?? ""
        
        // Return all the complete lines, filtering out empty strings that can result from `\r\n` or leading/trailing newlines.
        return components.dropLast().filter { !$0.isEmpty }
    }
}

nonisolated private final class SafeBool: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    
    init(_ value: Bool) {
        self._value = value
    }
    
    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
    
    func setValue(_ newValue: Bool) {
        lock.lock()
        defer { lock.unlock() }
        _value = newValue
    }
}
