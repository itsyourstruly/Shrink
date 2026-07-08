//
//  ExternalToolManager.swift
//  Shrink
//

import Foundation

enum ExternalTool: String, CaseIterable, Sendable {
    case ffmpeg = "ffmpeg"
    case pandoc = "pandoc"
    case magick = "magick"
    case sevenZip = "7zz"
    
    nonisolated var name: String { rawValue }
    
    nonisolated var homebrewFormula: String {
        switch self {
        case .ffmpeg: return "ffmpeg"
        case .pandoc: return "pandoc"
        case .magick: return "imagemagick"
        case .sevenZip: return "sevenzip"
        }
    }
}

nonisolated final class ExternalToolManager: Sendable {
    
    static func isToolAvailable(_ tool: ExternalTool) -> Bool {
        return findToolPath(tool) != nil
    }
    
    static func findToolPath(_ tool: ExternalTool) -> String? {
        let name = tool.rawValue
        
        // 1. Check bundled resource first
        if let bundled = getBundledToolPath(name) {
            return bundled
        }
        
        // 2. Check common locations
        let paths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)"
        ]
        for path in paths {
            if isExecutable(atPath: path) {
                return path
            }
        }
        
        // 3. Check current environment PATH
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
    
    static func getBundledToolPath(_ name: String) -> String? {
        if let url = Bundle.main.url(forResource: name, withExtension: nil),
           isExecutable(atPath: url.path) {
            return url.path
        }
        
        // Fallback to checking bundle url directory (e.g. during debug)
        let localPath = Bundle.main.bundleURL.appendingPathComponent(name).path
        if isExecutable(atPath: localPath) {
            return localPath
        }
        
        // Fallback to source directory next to executable (for previews/testing)
        let localDir = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(name).path
        if isExecutable(atPath: localDir) {
            return localDir
        }
        
        // Fallback to project root directory
        let workspaceDir = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(name).path
        if isExecutable(atPath: workspaceDir) {
            return workspaceDir
        }
        
        return nil
    }
    
    private static func isExecutable(atPath path: String) -> Bool {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        return url.isFileURL && access(url.path, X_OK) == 0
    }
    
    static func findBrewPath() -> String? {
        let paths = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
            "/usr/bin/brew"
        ]
        for path in paths {
            if isExecutable(atPath: path) {
                return path
            }
        }
        return nil
    }
    
    static func install(_ tool: ExternalTool, progressHandler: @escaping @Sendable (String) -> Void) async throws {
        guard let brewPath = findBrewPath() else {
            throw NSError(domain: "ExternalToolManagerError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Homebrew ('brew') was not found on your system. Please install Homebrew (https://brew.sh) or install '\(tool.name)' manually."])
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = ["install", tool.homebrewFormula]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                outputPipe.fileHandleForReading.readabilityHandler = nil
            } else if let chunk = String(data: data, encoding: .utf8) {
                let lines = chunk.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        progressHandler(trimmed)
                    }
                }
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                errorPipe.fileHandleForReading.readabilityHandler = nil
            } else if let chunk = String(data: data, encoding: .utf8) {
                let lines = chunk.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        progressHandler(trimmed)
                    }
                }
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(domain: "ExternalToolManagerError", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Installation failed with exit code \(proc.terminationStatus)"]))
                }
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    static func uninstall(_ tool: ExternalTool, progressHandler: @escaping @Sendable (String) -> Void) async throws {
        guard let brewPath = findBrewPath() else {
            throw NSError(domain: "ExternalToolManagerError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Homebrew ('brew') was not found on your system. Please install Homebrew (https://brew.sh) or uninstall '\(tool.name)' manually."])
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = ["uninstall", tool.homebrewFormula]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                outputPipe.fileHandleForReading.readabilityHandler = nil
            } else if let chunk = String(data: data, encoding: .utf8) {
                let lines = chunk.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        progressHandler(trimmed)
                    }
                }
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                errorPipe.fileHandleForReading.readabilityHandler = nil
            } else if let chunk = String(data: data, encoding: .utf8) {
                let lines = chunk.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        progressHandler(trimmed)
                    }
                }
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(domain: "ExternalToolManagerError", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Uninstallation failed with exit code \(proc.terminationStatus)"]))
                }
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
