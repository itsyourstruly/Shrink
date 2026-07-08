//
//  CompressorEngine.swift
//  Shrink
//

import Foundation

nonisolated struct StagingItem: Sendable {
    let sourceURL: URL
    let relativePath: String
    let fileType: FileType
    let originalSize: Int64
}

nonisolated final class ActiveOperations: @unchecked Sendable {
    private let lock = NSLock()
    private var operations: [CancelableOperation] = []
    
    func add(_ op: CancelableOperation) {
        lock.lock()
        defer { lock.unlock() }
        operations.append(op)
    }
    
    func remove(_ op: CancelableOperation) {
        lock.lock()
        defer { lock.unlock() }
        operations.removeAll { $0 === op }
    }
    
    func cancelAll() {
        lock.lock()
        let ops = operations
        operations.removeAll()
        lock.unlock()
        
        for op in ops {
            op.cancel()
        }
    }
}

nonisolated final class ParallelProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private let totalSize: Int64
    private var fileProgresses: [URL: Double] = [:]
    private var completedBytes: Double = 0.0
    private let fileSizes: [URL: Int64]
    private let stats: CompressionStats?
    private let updateHandler: (Double) -> Void
    private let fileProgressHandler: (@Sendable (URL, Double) -> Void)?
    
    private var lastReportedProgress: Double = 0.0
    private var lastReportedTime: Date = Date.distantPast
    
    init(totalSize: Int64, fileSizes: [URL: Int64], stats: CompressionStats?, updateHandler: @escaping (Double) -> Void, fileProgressHandler: (@Sendable (URL, Double) -> Void)? = nil) {
        self.totalSize = totalSize
        self.fileSizes = fileSizes
        self.stats = stats
        self.updateHandler = updateHandler
        self.fileProgressHandler = fileProgressHandler
    }
    
    func updateProgress(for url: URL, progress: Double, logicalWrittenBytes: Int64? = nil, targetURL: URL? = nil) {
        lock.lock()
        let oldProgress = fileProgresses[url] ?? 0.0
        let delta = progress - oldProgress
        fileProgresses[url] = progress
        
        let size = Double(fileSizes[url] ?? 0)
        completedBytes += size * delta
        
        let totalProgress = totalSize > 0 ? (completedBytes / Double(totalSize)) : 0.0
        let clampedProgress = min(0.99, max(0.0, totalProgress))
        
        let now = Date()
        let timeSinceLastReport = now.timeIntervalSince(lastReportedTime)
        let progressChange = abs(clampedProgress - lastReportedProgress)
        
        let shouldReport = clampedProgress >= 0.99 || progressChange >= 0.01 || timeSinceLastReport >= 0.1
        
        let currentCompleted = Int64(completedBytes)
        if let stats = stats {
            Task { @MainActor in
                stats.setRead(currentCompleted)
            }
        }
        
        if let logicalWrittenBytes = logicalWrittenBytes, let targetURL = targetURL, let stats = stats {
            Task { @MainActor in
                stats.setLogicalWritten(for: targetURL, bytes: logicalWrittenBytes)
            }
        }
        
        if shouldReport {
            lastReportedProgress = clampedProgress
            lastReportedTime = now
            lock.unlock()
            updateHandler(clampedProgress)
        } else {
            lock.unlock()
        }
        
        fileProgressHandler?(url, progress)
    }
}

final class CompressorEngine: @unchecked Sendable {
    
    private weak var state: AppState?
    private let archiveCompressor = ArchiveCompressor()
    private let activeOperations = ActiveOperations()
    private let laneManager = CompressionLaneManager()
    private var stagingCache: [String: [StagingItem]] = [:]
    private var isCancelled = false
    private let cancelQueue = DispatchQueue(label: "shrink.engine-cancel")
    
    init(state: AppState) {
        self.state = state
    }
    
    func cancel() {
        cancelQueue.sync {
            isCancelled = true
        }
        archiveCompressor.cancel()
        activeOperations.cancelAll()
    }
    
    private var cancelled: Bool {
        cancelQueue.sync { isCancelled }
    }
    
    func execute(job: CompressionJob) async {
        cancelQueue.sync {
            isCancelled = false
        }
        
        let isAccessingOutput = job.outputDir.startAccessingSecurityScopedResource()
        defer {
            if isAccessingOutput {
                job.outputDir.stopAccessingSecurityScopedResource()
            }
        }
        
        if job.mode == .decompress {
            await runDecompression(job: job)
        } else {
            await runCompression(job: job)
        }
    }
    
    // MARK: - Compression Pipeline
    
    private func runCompression(job: CompressionJob) async {
        switch job.outputStyle {
        case .archive:
            await compressToArchive(job: job)
        case .extractMedia:
            await extractAndCompressMedia(job: job)
        case .individual, .subfolder:
            await compressIndividually(job: job)
        }
    }
    
    private func compressToArchive(job: CompressionJob) async {
        let format = job.archiveSettings.format
        let ext = format.fileExtension
        let archiveName = job.customOutputName.isEmpty ? "archive_shrunk" : job.customOutputName
        let cleanArchiveName = archiveName.hasSuffix(".\(ext)") ? archiveName : "\(archiveName).\(ext)"
        let destinationURL = job.outputDir.appendingPathComponent(cleanArchiveName)
        
        await MainActor.run { [weak self] in
            guard let self = self, let state = self.state else { return }
            state.activeJobTitle = "Creating Archive: \(cleanArchiveName)..."
            state.currentProgress = 0.05
            for i in 0..<state.selectedFiles.count {
                if state.selectedFiles[i].isChecked {
                    state.selectedFiles[i].status = .processing(progress: 0.05)
                }
            }
        }
        
        let splitSize = job.archiveSettings.splitArchive ? job.archiveSettings.splitSize : nil
        let password = job.archiveSettings.passwordEnabled ? job.archiveSettings.password : nil
        
        do {
            // --- Direct Compression: No Staging ---
            // Pass the selected file URLs directly to the archiver.
            let urlsToArchive = job.selectedFiles.map { $0.url }
            
            await MainActor.run { [weak self] in
                self?.state?.compressionStats.registerActiveOutput(destinationURL)
            }
            
            try await archiveCompressor.compress(
                urls: urlsToArchive,
                destinationURL: destinationURL,
                format: format,
                compressionLevel: job.archiveSettings.compressionLevel,
                password: password,
                splitSize: splitSize,
                progressHandler: { progress in
                    Task { @MainActor [weak self] in
                        guard let self = self, let state = self.state else { return }
                        state.currentProgress = progress
                        let readBytes = Int64(Double(state.compressionStartTotalSize) * progress)
                        state.compressionStats.setRead(readBytes)
                         for i in 0..<state.selectedFiles.count {
                             if state.selectedFiles[i].isChecked {
                                 state.setFileStatus(id: state.selectedFiles[i].id, status: .processing(progress: progress))
                             }
                         }
                    }
                }
            )
            
            if cancelled {
                cleanUpOutput(destinationURL: destinationURL, isSplit: job.archiveSettings.splitArchive, splitSize: splitSize)
                return
            }
            
            var calculatedSize: Int64 = 0
            if job.archiveSettings.splitArchive, let _ = splitSize {
                let fileManager = FileManager.default
                let baseName = destinationURL.deletingPathExtension().lastPathComponent
                let parentDir = destinationURL.deletingLastPathComponent()
                if let files = try? fileManager.contentsOfDirectory(at: parentDir, includingPropertiesForKeys: nil) {
                    let parts = files.filter { $0.lastPathComponent.hasPrefix(baseName) }
                    for part in parts {
                        let attrs = try? fileManager.attributesOfItem(atPath: part.path)
                        calculatedSize += attrs?[.size] as? Int64 ?? 0
                    }
                }
            } else {
                let attrs = try? FileManager.default.attributesOfItem(atPath: destinationURL.path)
                calculatedSize = attrs?[.size] as? Int64 ?? 0
            }
            let outputSize = calculatedSize
            
            await MainActor.run { [weak self] in
                guard let self = self, let state = self.state else { return }
                state.currentProgress = 1.0
                state.isProcessing = false
                state.stopTimer()
                state.compressionStats.unregisterActiveOutput(destinationURL, finalSize: outputSize)
                for i in 0..<state.selectedFiles.count {
                    if state.selectedFiles[i].isChecked {
                        if case .failed = state.selectedFiles[i].status {
                            continue
                        }
                        state.setFileStatus(id: state.selectedFiles[i].id, status: .completed(newSize: outputSize, outputURL: destinationURL))
                    }
                }
                let firstCheckedURL = state.selectedFiles.first(where: { $0.isChecked })?.url ?? destinationURL
                state.compressionResult = CompressionResult(
                    originalSize: state.compressionStartTotalSize,
                    newSize: outputSize,
                    elapsedSeconds: state.elapsedSeconds,
                    originalURL: firstCheckedURL,
                    compressedURL: destinationURL
                )
            }
            
        } catch {
            let errorMessage = error.localizedDescription
            let isCancelError = errorMessage.contains("cancelled") || errorMessage.contains("stopped by user")
            cleanUpOutput(destinationURL: destinationURL, isSplit: job.archiveSettings.splitArchive, splitSize: splitSize)
            
            await MainActor.run { [weak self] in
                guard let self = self, let state = self.state else { return }
                state.isProcessing = false
                state.stopTimer()
                state.compressionStats.unregisterActiveOutput(destinationURL, finalSize: 0)
                for i in 0..<state.selectedFiles.count {
                    if state.selectedFiles[i].isChecked {
                        state.setFileStatus(id: state.selectedFiles[i].id, status: .failed(message: errorMessage))
                    }
                }
                if !isCancelError {
                    state.compressionError = errorMessage
                } else {
                    state.showProcessingOverlay = false
                }
            }
        }
    }
    
    private func compressIndividually(job: CompressionJob) async {
        let stagingItems = collectStagingItems(from: job.selectedFiles)
        
        let totalOriginalSize = stagingItems.reduce(0) { $0 + $1.originalSize }
        let fileSizes = Dictionary(uniqueKeysWithValues: stagingItems.map { ($0.sourceURL, $0.originalSize) })
        let stagingItemCount = stagingItems.count
        
        await MainActor.run { [weak self] in
            guard let self = self, let state = self.state else { return }
            state.activeJobTitle = "Compressing files (\(stagingItemCount) items)..."
            state.currentProgress = 0.05
            for i in 0..<state.selectedFiles.count {
                if state.selectedFiles[i].isChecked {
                    state.selectedFiles[i].status = .processing(progress: 0.05)
                }
            }
        }
        
        let stats = await MainActor.run { self.state?.compressionStats }
        let progressTracker = ParallelProgressTracker(
            totalSize: totalOriginalSize,
            fileSizes: fileSizes,
            stats: stats,
            updateHandler: { progress in
                Task { @MainActor [weak self] in
                    guard let self = self, let state = self.state else { return }
                    state.currentProgress = progress
                }
            },
            fileProgressHandler: { [weak self] url, progress in
                Task { @MainActor [weak self] in
                    self?.state?.updateFileProgress(url: url, progress: progress)
                }
            }
        )
        
        let imageItems = stagingItems.filter { $0.fileType == .image }
        let videoItems = stagingItems.filter { $0.fileType == .video }
        let audioItems = stagingItems.filter { $0.fileType == .audio }
        let otherItems = stagingItems.filter { ![.image, .video, .audio].contains($0.fileType) }

        let imageLimit = laneManager.concurrencyLimit(for: .image)
        let videoLimit = laneManager.concurrencyLimit(for: .video)
        let audioLimit = max(1, imageLimit / 2)
        let otherLimit = max(1, imageLimit / 2)

        do {
            async let imageBatch = processItems(imageItems, concurrency: imageLimit) { [self] item in
                try await processIndividualItem(item, job: job, progressTracker: progressTracker)
            }
            async let videoBatch = processItems(videoItems, concurrency: videoLimit) { [self] item in
                try await processIndividualItem(item, job: job, progressTracker: progressTracker)
            }
            async let audioBatch = processItems(audioItems, concurrency: audioLimit) { [self] item in
                try await processIndividualItem(item, job: job, progressTracker: progressTracker)
            }
            async let otherBatch = processItems(otherItems, concurrency: otherLimit) { [self] item in
                try await processIndividualItem(item, job: job, progressTracker: progressTracker)
            }

            let _ = try await (imageBatch, videoBatch, audioBatch, otherBatch)
            
            if cancelled {
                throw NSError(domain: "CompressorEngineError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Operation cancelled."])
            }
            
            var completedSizes: [UUID: Int64] = [:]
            var completedURLs: [UUID: URL] = [:]
            var totalNewSize: Int64 = 0
            for i in 0..<job.selectedFiles.count {
                let fileItem = job.selectedFiles[i]
                if fileItem.isChecked {
                    let fileExt: String
                    switch fileItem.fileType {
                    case .image:
                        fileExt = job.imageSettings.format.lowercased()
                    case .video:
                        fileExt = "mp4"
                    case .audio:
                        fileExt = job.audioSettings.format.lowercased()
                    default:
                        fileExt = fileItem.url.pathExtension
                    }
                    
                    let cleanName = fileItem.url.deletingPathExtension().lastPathComponent
                    if fileItem.isDirectory {
                        let folderName = "\(cleanName)\(job.customSuffix)"
                        let destFolderURL = job.outputDir.appendingPathComponent(folderName)
                        let size = await FileItem.calculateFolderSizeAsync(at: destFolderURL)
                        completedSizes[fileItem.id] = size
                        completedURLs[fileItem.id] = destFolderURL
                    } else {
                        let outputName = "\(cleanName)\(job.customSuffix).\(fileExt)"
                        let destFileURL = job.outputDir.appendingPathComponent(outputName)
                        let attrs = try? FileManager.default.attributesOfItem(atPath: destFileURL.path)
                        let size = attrs?[.size] as? Int64 ?? 0
                        completedSizes[fileItem.id] = size
                        completedURLs[fileItem.id] = destFileURL
                    }
                }
            }
            
            for (_, size) in completedSizes {
                totalNewSize += size
            }
            let completedSizesCopy = completedSizes
            let completedURLsCopy = completedURLs
            let totalNewSizeCopy = totalNewSize
            
            await MainActor.run { [weak self] in
                guard let self = self, let state = self.state else { return }
                state.currentProgress = 1.0
                state.isProcessing = false
                state.stopTimer()
                
                for i in 0..<state.selectedFiles.count {
                    let fileItem = state.selectedFiles[i]
                    if fileItem.isChecked {
                        if case .failed = fileItem.status {
                            continue
                        }
                        let size = completedSizesCopy[fileItem.id] ?? 0
                        let outputURL = completedURLsCopy[fileItem.id] ?? fileItem.url
                        state.setFileStatus(id: fileItem.id, status: .completed(newSize: size, outputURL: outputURL))
                    }
                }
                let firstChecked = state.selectedFiles.first(where: { $0.isChecked })
                let firstCheckedURL = firstChecked?.url ?? state.selectedFiles.first?.url ?? URL(fileURLWithPath: "")
                let firstOutputURL = firstChecked.flatMap { completedURLsCopy[$0.id] } ?? completedURLsCopy.values.first ?? firstCheckedURL
                state.compressionResult = CompressionResult(
                    originalSize: state.compressionStartTotalSize,
                    newSize: totalNewSizeCopy,
                    elapsedSeconds: state.elapsedSeconds,
                    originalURL: firstCheckedURL,
                    compressedURL: firstOutputURL
                )
            }
        } catch {
            let errorMessage = error.localizedDescription
            let isCancelError = errorMessage.contains("cancelled") || errorMessage.contains("stopped by user")
            await MainActor.run { [weak self] in
                guard let self = self, let state = self.state else { return }
                state.isProcessing = false
                state.stopTimer()
                for i in 0..<state.selectedFiles.count {
                    let fileItem = state.selectedFiles[i]
                    if fileItem.isChecked {
                        state.setFileStatus(id: fileItem.id, status: .failed(message: errorMessage))
                    }
                }
                if !isCancelError {
                    state.compressionError = errorMessage
                } else {
                    state.showProcessingOverlay = false
                }
            }
        }
    }
    
    // MARK: - Decompression Pipeline
    
    private func runDecompression(job: CompressionJob) async {
        let totalCount = Double(job.selectedFiles.count)
        
        for i in 0..<job.selectedFiles.count {
            if cancelled { break }
            
            let fileItem = job.selectedFiles[i]
            
            await MainActor.run { [weak self] in
                guard let self = self, let state = self.state else { return }
                state.activeJobTitle = "Extracting: \(fileItem.name) (\(i+1)/\(job.selectedFiles.count))"
                state.selectedFiles[i].status = .processing(progress: 0.2)
            }
            
            var finalExtractDir = job.outputDir
            if job.decompressSettings.createSubfolder {
                let subfolderName = fileItem.url.deletingPathExtension().lastPathComponent
                finalExtractDir = job.outputDir.appendingPathComponent(subfolderName)
            }
            
            await MainActor.run { [weak self] in
                self?.state?.compressionStats.registerActiveOutput(finalExtractDir)
            }
            
            do {
                let password = job.decompressSettings.passwordEnabled ? job.decompressSettings.password : nil
                
                try await archiveCompressor.decompress(
                    archiveURL: fileItem.url,
                    destinationURL: finalExtractDir,
                    password: password,
                    progressHandler: { fileProgress in
                        Task { @MainActor [weak self] in
                            guard let self = self, let state = self.state else { return }
                            let startProg = Double(i) / totalCount
                            let fileWeight = 1.0 / totalCount
                            let currentProgress = startProg + fileProgress * fileWeight
                            state.currentProgress = currentProgress
                            state.compressionStats.setRead(Int64(Double(state.compressionStartTotalSize) * currentProgress))
                            state.selectedFiles[i].status = .processing(progress: fileProgress)
                        }
                    }
                )
                
                let size = getFolderSizeBackground(at: finalExtractDir)
                
                await MainActor.run { [weak self] in
                    guard let self = self, let state = self.state else { return }
                    state.compressionStats.unregisterActiveOutput(finalExtractDir, finalSize: size)
                    state.selectedFiles[i].status = .completed(newSize: 0, outputURL: finalExtractDir)
                    let currentProgress = Double(i + 1) / totalCount
                    state.currentProgress = currentProgress
                    state.compressionStats.setRead(Int64(Double(state.compressionStartTotalSize) * currentProgress))
                }
            } catch {
                let size = getFolderSizeBackground(at: finalExtractDir)
                await MainActor.run { [weak self] in
                    guard let self = self, let state = self.state else { return }
                    state.compressionStats.unregisterActiveOutput(finalExtractDir, finalSize: size)
                    state.selectedFiles[i].status = .failed(message: error.localizedDescription)
                    let currentProgress = Double(i + 1) / totalCount
                    state.currentProgress = currentProgress
                    state.compressionStats.setRead(Int64(Double(state.compressionStartTotalSize) * currentProgress))
                }
            }
        }
        
        await MainActor.run { [weak self] in
            guard let self = self, let state = self.state else { return }
            state.isProcessing = false
            state.stopTimer()
            let firstChecked = state.selectedFiles.first(where: { $0.isChecked })
            let firstCheckedURL = firstChecked?.url ?? state.selectedFiles.first?.url ?? URL(fileURLWithPath: "")
            var firstExtractDir = job.outputDir
            if let first = firstChecked {
                if job.decompressSettings.createSubfolder {
                    let subfolderName = first.url.deletingPathExtension().lastPathComponent
                    firstExtractDir = job.outputDir.appendingPathComponent(subfolderName)
                }
            }
            state.compressionResult = CompressionResult(
                originalSize: state.compressionStartTotalSize,
                newSize: 0,
                elapsedSeconds: state.elapsedSeconds,
                originalURL: firstCheckedURL,
                compressedURL: firstExtractDir
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func targetSizeRatio(for url: URL, job: CompressionJob, defaultRatio: Double) -> Double {
        let standardPath = url.standardizedFileURL.path
        
        // 1. Check if there is a root-level FileItem matching this URL
        if let match = job.selectedFiles.first(where: { $0.url.standardizedFileURL.path == standardPath }) {
            if let customRatio = match.customTargetSizeRatio {
                return customRatio
            }
        }
        
        // 2. Check if this URL is a sub-media item in any of the selected folder items
        for folderItem in job.selectedFiles where folderItem.isDirectory {
            if let subMatch = folderItem.subMediaItems.first(where: { $0.url.standardizedFileURL.path == standardPath }) {
                return subMatch.targetSizeRatio
            }
        }
        
        // 3. Fallback to default
        return defaultRatio
    }
    
    private func targetResolution(for url: URL, job: CompressionJob, defaultW: Int?, defaultH: Int?) -> (Int?, Int?) {
        let standardPath = url.standardizedFileURL.path
        
        // 1. Check if there is a root-level FileItem matching this URL
        if let match = job.selectedFiles.first(where: { $0.url.standardizedFileURL.path == standardPath }) {
            if match.customResolutionWidth != nil || match.customResolutionHeight != nil {
                return (match.customResolutionWidth, match.customResolutionHeight)
            }
        }
        
        // 2. Check if this URL is a sub-media item in any of the selected folder items
        for folderItem in job.selectedFiles where folderItem.isDirectory {
            if let subMatch = folderItem.subMediaItems.first(where: { $0.url.standardizedFileURL.path == standardPath }) {
                if subMatch.customResolutionWidth != nil || subMatch.customResolutionHeight != nil {
                    return (subMatch.customResolutionWidth, subMatch.customResolutionHeight)
                }
            }
        }
        
        // 3. Fallback to default
        return (defaultW, defaultH)
    }
    
    private func resolveVideoSettings(for url: URL, job: CompressionJob) -> VideoSettings {
        var settings = job.videoSettings
        let standardPath = url.standardizedFileURL.path
        
        var customRatio: Double? = nil
        var customMethod: VideoCompressionMethod? = nil
        var customBitrate: Int? = nil
        var customW: Int? = nil
        var customH: Int? = nil
        var customAudMode: String? = nil
        var customAudBitrate: Int? = nil
        
        if let match = job.selectedFiles.first(where: { $0.url.standardizedFileURL.path == standardPath }) {
            customRatio = match.customTargetSizeRatio
            customMethod = match.customCompressionMethod
            customBitrate = match.customTargetBitrateKbps
            customW = match.customResolutionWidth
            customH = match.customResolutionHeight
            customAudMode = match.customAudioMode
            customAudBitrate = match.customAudioBitrate
        } else {
            for folderItem in job.selectedFiles where folderItem.isDirectory {
                if let subMatch = folderItem.subMediaItems.first(where: { $0.url.standardizedFileURL.path == standardPath }) {
                    customRatio = subMatch.targetSizeRatio
                    customMethod = subMatch.customCompressionMethod
                    customBitrate = subMatch.customTargetBitrateKbps
                    customW = subMatch.customResolutionWidth
                    customH = subMatch.customResolutionHeight
                    customAudMode = subMatch.customAudioMode
                    customAudBitrate = subMatch.customAudioBitrate
                    break
                }
            }
        }
        
        if let ratio = customRatio { settings.targetSizeRatio = ratio }
        if let method = customMethod { settings.compressionMethod = method }
        if let bitrate = customBitrate { settings.targetBitrateKbps = bitrate }
        if customW != nil || customH != nil {
            settings.targetResolutionWidth = customW
            settings.targetResolutionHeight = customH
        }
        if let audMode = customAudMode { settings.audioMode = audMode }
        if let audBitrate = customAudBitrate { settings.audioBitrate = audBitrate }
        
        return settings
    }
    
    @MainActor
    private func markStatusFailed(for sourceURL: URL, message: String) {
        guard let state = self.state else { return }
        let standardPath = sourceURL.standardizedFileURL.path
        for i in 0..<state.selectedFiles.count {
            let fileItem = state.selectedFiles[i]
            let itemPath = fileItem.url.standardizedFileURL.path
            if itemPath == standardPath {
                state.selectedFiles[i].status = .failed(message: message)
            } else if fileItem.isDirectory {
                let prefix = itemPath.hasSuffix("/") ? itemPath : itemPath + "/"
                if standardPath.hasPrefix(prefix) {
                    state.selectedFiles[i].status = .failed(message: message)
                }
            }
        }
    }
    
    private func collectStagingItems(from selectedFiles: [FileItem]) -> [StagingItem] {
        // Simple cache key based on selected file URLs and checked states to avoid repeated scans
        let key = selectedFiles.map { "\($0.url.standardizedFileURL.path)|\($0.isChecked)" }.joined(separator: "|")
        if let cached = stagingCache[key] {
            return cached
        }

        var items: [StagingItem] = []
        for fileItem in selectedFiles {
            if fileItem.isChecked {
                let url = fileItem.url
                let baseDir = url.deletingLastPathComponent()
                let prefixLength = baseDir.path.hasSuffix("/") ? baseDir.path.count : baseDir.path.count + 1
                collectStagingItemsRecursive(in: fileItem, prefixLength: prefixLength, items: &items)
            }
        }
        stagingCache[key] = items
        return items
    }
    
    private func collectStagingItemsRecursive(in item: FileItem, prefixLength: Int, items: inout [StagingItem]) {
        if item.isDirectory {
            for subItem in item.subItems {
                if subItem.isChecked {
                    collectStagingItemsRecursive(in: subItem, prefixLength: prefixLength, items: &items)
                }
            }
        } else {
            let relPath = String(item.url.path.dropFirst(prefixLength))
            let staging = StagingItem(
                sourceURL: item.url,
                relativePath: relPath,
                fileType: item.fileType,
                originalSize: item.originalSize
            )
            items.append(staging)
        }
    }
    
    private func getFileType(for url: URL) -> FileType {
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "heic", "heif", "tiff", "gif", "webp", "bmp", "raw"].contains(ext) {
            return .image
        } else if ["mp4", "mov", "m4v", "mkv", "avi", "webm", "flv", "wmv", "3gp"].contains(ext) {
            return .video
        } else if ["mp3", "m4a", "wav", "aac", "flac", "ogg", "wma"].contains(ext) {
            return .audio
        } else if ext == "pdf" {
            return .pdf
        } else if ["zip", "7z", "tar", "gz", "tgz", "rar", "bz2", "xz", "z"].contains(ext) {
            return .archive
        } else {
            return .general
        }
    }
    
    private func processStagingItem(
        _ item: StagingItem,
        stagingDir: URL,
        job: CompressionJob,
        progressTracker: ParallelProgressTracker
    ) async throws {
        if cancelled {
            progressTracker.updateProgress(for: item.sourceURL, progress: 1.0)
            return
        }
        
        let fileManager = FileManager.default
        let targetURL: URL
        

        
        let compressImages = job.imageSettings.compressEnabled && item.fileType == .image
        let compressVideos = job.videoSettings.compressEnabled && item.fileType == .video
        let compressAudio = job.audioSettings.compressEnabled && item.fileType == .audio
        let compressPDF = job.pdfSettings.compressEnabled && item.fileType == .pdf
        
        if compressImages {
            let targetExt = job.imageSettings.format.lowercased()
            let relPathWithoutExt = URL(fileURLWithPath: item.relativePath).deletingPathExtension().path
            targetURL = stagingDir.appendingPathComponent(relPathWithoutExt + "." + targetExt)
        } else if compressVideos {
            let relPathWithoutExt = URL(fileURLWithPath: item.relativePath).deletingPathExtension().path
            targetURL = stagingDir.appendingPathComponent(relPathWithoutExt + ".mp4")
        } else if compressAudio {
            let targetExt = job.audioSettings.format.lowercased()
            let relPathWithoutExt = URL(fileURLWithPath: item.relativePath).deletingPathExtension().path
            targetURL = stagingDir.appendingPathComponent(relPathWithoutExt + "." + targetExt)
        } else {
            targetURL = stagingDir.appendingPathComponent(item.relativePath)
        }
        
        let targetParent = targetURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: targetParent.path) {
            try fileManager.createDirectory(at: targetParent, withIntermediateDirectories: true)
        }
        
        do {
            if compressImages {
                var settings = job.imageSettings
                settings.targetSizeRatio = targetSizeRatio(for: item.sourceURL, job: job, defaultRatio: job.imageSettings.targetSizeRatio)
                let (resW, resH) = targetResolution(for: item.sourceURL, job: job, defaultW: job.imageSettings.targetResolutionWidth, defaultH: job.imageSettings.targetResolutionHeight)
                settings.targetResolutionWidth = resW
                settings.targetResolutionHeight = resH
                
                let source = item.sourceURL
                let target = targetURL
                let finalSettings = settings
                
                _ = try await laneManager.enqueue(lane: .image) {
                    try await Task.detached {
                        let imageComp = ImageCompressor()
                        return try imageComp.compress(inputURL: source, outputURL: target, settings: finalSettings)
                    }.value
                }
                progressTracker.updateProgress(for: item.sourceURL, progress: 1.0)
            } else if compressVideos {
                let videoComp = VideoCompressor()
                activeOperations.add(videoComp)
                defer { activeOperations.remove(videoComp) }
                
                let videoSettings = resolveVideoSettings(for: item.sourceURL, job: job)
                
                _ = try await laneManager.enqueue(lane: .video) {
                    try await videoComp.compress(
                        inputURL: item.sourceURL,
                        outputURL: targetURL,
                        settings: videoSettings,
                        progressHandler: { fileProgress, logicalWrittenBytes in
                            progressTracker.updateProgress(for: item.sourceURL, progress: fileProgress, logicalWrittenBytes: logicalWrittenBytes, targetURL: targetURL)
                        }
                    )
                }
                progressTracker.updateProgress(for: item.sourceURL, progress: 1.0)
            } else if compressAudio {
                let audioComp = AudioCompressor()
                activeOperations.add(audioComp)
                defer { activeOperations.remove(audioComp) }
                
                _ = try await audioComp.compress(inputURL: item.sourceURL, outputURL: targetURL, settings: job.audioSettings)
            } else if compressPDF {
                let pdfComp = PDFCompressor()
                _ = try pdfComp.compress(inputURL: item.sourceURL, outputURL: targetURL)
            } else {
                try copyOrLinkItem(item, stagingDir: stagingDir)
            }
            
            let size = (try? fileManager.attributesOfItem(atPath: targetURL.path)[.size] as? Int64) ?? 0
            await MainActor.run { [weak self] in
                self?.state?.updateFileCompleted(url: item.sourceURL, newSize: size, outputURL: targetURL)
            }
            progressTracker.updateProgress(for: item.sourceURL, progress: 1.0)
        } catch {
            print("[STAGING DEBUG] Failed to process staging file \(item.sourceURL.lastPathComponent): \(error)")
            if fileManager.fileExists(atPath: targetURL.path) {
                try? fileManager.removeItem(at: targetURL)
            }
            if !fileManager.fileExists(atPath: targetURL.path) {
                try? copyOrLinkItem(item, stagingDir: stagingDir)
            }
            await MainActor.run { [weak self] in
                self?.state?.updateFileFailed(url: item.sourceURL, message: error.localizedDescription)
                self?.markStatusFailed(for: item.sourceURL, message: error.localizedDescription)
            }
            progressTracker.updateProgress(for: item.sourceURL, progress: 1.0)
        }
    }
    
    private func copyOrLinkItem(_ item: StagingItem, stagingDir: URL) throws {
        let fileManager = FileManager.default
        let targetURL = stagingDir.appendingPathComponent(item.relativePath)
        let targetParent = targetURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: targetParent.path) {
            try fileManager.createDirectory(at: targetParent, withIntermediateDirectories: true)
        }
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
        do {
            try fileManager.linkItem(at: item.sourceURL, to: targetURL)
        } catch {
            try fileManager.copyItem(at: item.sourceURL, to: targetURL)
        }
    }
    
    private func extractAndCompressMedia(job: CompressionJob) async {
        let folderName = job.customOutputName.isEmpty ? "extracted_media_shrunk" : job.customOutputName
        let destinationURL = job.outputDir.appendingPathComponent(folderName)
        
        await MainActor.run { [weak self] in
            guard let self = self, let state = self.state else { return }
            state.activeJobTitle = "Scanning Folder for Media..."
            state.currentProgress = 0.05
            for i in 0..<state.selectedFiles.count {
                if state.selectedFiles[i].isChecked {
                    state.selectedFiles[i].status = .processing(progress: 0.05)
                }
            }
        }
        
        do {
            try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            
            let stagingItems = collectStagingItems(from: job.selectedFiles)
            let mediaItems = stagingItems.filter { item in
                switch job.mediaFilter {
                case .all:
                    return item.fileType == .image || item.fileType == .video
                case .imagesOnly:
                    return item.fileType == .image
                case .videosOnly:
                    return item.fileType == .video
                case .audioOnly:
                    return item.fileType == .audio
                }
            }
            
            if mediaItems.isEmpty {
                let msg: String
                switch job.mediaFilter {
                case .all: msg = "No images or videos found in the selected folders."
                case .imagesOnly: msg = "No images found in the selected folders."
                case .videosOnly: msg = "No videos found in the selected folders."
                case .audioOnly: msg = "No audio files found in the selected folders."
                }
                throw NSError(domain: "CompressorEngineError", code: 20, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            
            let totalOriginalSize = mediaItems.reduce(0) { $0 + $1.originalSize }
            let fileSizes = Dictionary(uniqueKeysWithValues: mediaItems.map { ($0.sourceURL, $0.originalSize) })
            
            let stats = await MainActor.run { self.state?.compressionStats }
            let progressTracker = ParallelProgressTracker(
                totalSize: totalOriginalSize,
                fileSizes: fileSizes,
                stats: stats,
                updateHandler: { progress in
                    Task { @MainActor [weak self] in
                        guard let self = self, let state = self.state else { return }
                        state.currentProgress = progress
                    }
                },
                fileProgressHandler: { [weak self] url, progress in
                    Task { @MainActor [weak self] in
                        self?.state?.updateFileProgress(url: url, progress: progress)
                    }
                }
            )
            
            await MainActor.run { [weak self] in
                let title: String
                switch job.mediaFilter {
                case .all: title = "Compressing Media (\(mediaItems.count) files)..."
                case .imagesOnly: title = "Compressing Images (\(mediaItems.count) files)..."
                case .videosOnly: title = "Compressing Videos (\(mediaItems.count) files)..."
                case .audioOnly: title = "Compressing Audio (\(mediaItems.count) files)..."
                }
                self?.state?.activeJobTitle = title
            }
            
            let imageItems = mediaItems.filter { $0.fileType == .image }
            let videoItems = mediaItems.filter { $0.fileType == .video }
            let audioItems = mediaItems.filter { $0.fileType == .audio }

            let imageLimit = laneManager.concurrencyLimit(for: .image)
            let videoLimit = laneManager.concurrencyLimit(for: .video)

            async let imageBatch = processItems(imageItems, concurrency: imageLimit) { [self] item in
                try await processMediaItem(item, destDir: destinationURL, job: job, progressTracker: progressTracker)
            }
            async let videoBatch = processItems(videoItems, concurrency: videoLimit) { [self] item in
                try await processMediaItem(item, destDir: destinationURL, job: job, progressTracker: progressTracker)
            }
            async let audioBatch = processItems(audioItems, concurrency: 2) { [self] item in
                try await processMediaItem(item, destDir: destinationURL, job: job, progressTracker: progressTracker)
            }

            let _ = try await (imageBatch, videoBatch, audioBatch)
            
            if cancelled {
                try? FileManager.default.removeItem(at: destinationURL)
                throw NSError(domain: "CompressorEngineError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Operation cancelled."])
            }
            
            let outputSize = await FileItem.calculateFolderSizeAsync(at: destinationURL)
            
            await MainActor.run { [weak self] in
                guard let self = self, let state = self.state else { return }
                state.currentProgress = 1.0
                state.isProcessing = false
                state.stopTimer()
                for i in 0..<state.selectedFiles.count {
                    if state.selectedFiles[i].isChecked {
                        if case .failed = state.selectedFiles[i].status {
                            continue
                        }
                        state.setFileStatus(id: state.selectedFiles[i].id, status: .completed(newSize: outputSize, outputURL: destinationURL))
                    }
                }
                let firstCheckedURL = state.selectedFiles.first(where: { $0.isChecked })?.url ?? destinationURL
                state.compressionResult = CompressionResult(
                    originalSize: state.compressionStartTotalSize,
                    newSize: outputSize,
                    elapsedSeconds: state.elapsedSeconds,
                    originalURL: firstCheckedURL,
                    compressedURL: destinationURL
                )
            }
            
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            let errorMessage = error.localizedDescription
            let isCancelError = errorMessage.contains("cancelled") || errorMessage.contains("stopped by user")
            await MainActor.run { [weak self] in
                guard let self = self, let state = self.state else { return }
                state.isProcessing = false
                state.stopTimer()
                for i in 0..<state.selectedFiles.count {
                    if state.selectedFiles[i].isChecked {
                        state.setFileStatus(id: state.selectedFiles[i].id, status: .failed(message: errorMessage))
                    }
                }
                if !isCancelError {
                    state.compressionError = errorMessage
                } else {
                    state.showProcessingOverlay = false
                }
            }
        }
    }
    
    private func processMediaItem(
        _ item: StagingItem,
        destDir: URL,
        job: CompressionJob,
        progressTracker: ParallelProgressTracker
    ) async throws {
        if cancelled {
            progressTracker.updateProgress(for: item.sourceURL, progress: 1.0)
            return
        }
        
        let fileManager = FileManager.default
        let targetURL: URL
        
        let compressImages = item.fileType == .image
        let compressVideos = item.fileType == .video
        let compressAudio = item.fileType == .audio
        
        if compressImages {
            let targetExt = job.imageSettings.format.lowercased()
            let relPathWithoutExt = URL(fileURLWithPath: item.relativePath).deletingPathExtension().path
            targetURL = destDir.appendingPathComponent(relPathWithoutExt + "." + targetExt)
        } else if compressVideos {
            let relPathWithoutExt = URL(fileURLWithPath: item.relativePath).deletingPathExtension().path
            targetURL = destDir.appendingPathComponent(relPathWithoutExt + ".mp4")
        } else if compressAudio {
            let targetExt = job.audioSettings.format.lowercased()
            let relPathWithoutExt = URL(fileURLWithPath: item.relativePath).deletingPathExtension().path
            targetURL = destDir.appendingPathComponent(relPathWithoutExt + "." + targetExt)
        } else {
            targetURL = destDir.appendingPathComponent(item.relativePath)
        }
        
        let targetParent = targetURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: targetParent.path) {
            try fileManager.createDirectory(at: targetParent, withIntermediateDirectories: true)
        }
        
        do {
            await MainActor.run { [weak self] in
                self?.state?.compressionStats.registerActiveOutput(targetURL)
            }
            defer {
                let size = (try? fileManager.attributesOfItem(atPath: targetURL.path)[.size] as? Int64) ?? 0
                Task { @MainActor [weak self] in
                    self?.state?.compressionStats.unregisterActiveOutput(targetURL, finalSize: size)
                }
            }
            if compressImages {
                var settings = job.imageSettings
                settings.targetSizeRatio = targetSizeRatio(for: item.sourceURL, job: job, defaultRatio: job.imageSettings.targetSizeRatio)
                let (resW, resH) = targetResolution(for: item.sourceURL, job: job, defaultW: job.imageSettings.targetResolutionWidth, defaultH: job.imageSettings.targetResolutionHeight)
                settings.targetResolutionWidth = resW
                settings.targetResolutionHeight = resH
                
                let source = item.sourceURL
                let target = targetURL
                let finalSettings = settings
                
                _ = try await laneManager.enqueue(lane: .image) {
                    try await Task.detached {
                        let imageComp = ImageCompressor()
                        return try imageComp.compress(inputURL: source, outputURL: target, settings: finalSettings)
                    }.value
                }
            } else if compressVideos {
                let videoComp = VideoCompressor()
                activeOperations.add(videoComp)
                defer { activeOperations.remove(videoComp) }
                
                let videoSettings = resolveVideoSettings(for: item.sourceURL, job: job)
 
                _ = try await laneManager.enqueue(lane: .video) {
                    try await videoComp.compress(
                        inputURL: item.sourceURL,
                        outputURL: targetURL,
                        settings: videoSettings,
                        progressHandler: { fileProgress, logicalWrittenBytes in
                            progressTracker.updateProgress(for: item.sourceURL, progress: fileProgress, logicalWrittenBytes: logicalWrittenBytes, targetURL: targetURL)
                        }
                    )
                }
            } else if compressAudio {
                let audioComp = AudioCompressor()
                activeOperations.add(audioComp)
                defer { activeOperations.remove(audioComp) }
                
                _ = try await audioComp.compress(inputURL: item.sourceURL, outputURL: targetURL, settings: job.audioSettings)
            }
            
            let size = (try? fileManager.attributesOfItem(atPath: targetURL.path)[.size] as? Int64) ?? 0
            await MainActor.run { [weak self] in
                self?.state?.updateFileCompleted(url: item.sourceURL, newSize: size, outputURL: targetURL)
            }
            progressTracker.updateProgress(for: item.sourceURL, progress: 1.0)
        } catch {
            print("[STAGING DEBUG] Failed to process media file \(item.sourceURL.lastPathComponent): \(error)")
            if fileManager.fileExists(atPath: targetURL.path) {
                try? fileManager.removeItem(at: targetURL)
            }
            await MainActor.run { [weak self] in
                self?.state?.updateFileFailed(url: item.sourceURL, message: error.localizedDescription)
                self?.markStatusFailed(for: item.sourceURL, message: error.localizedDescription)
            }
            progressTracker.updateProgress(for: item.sourceURL, progress: 1.0)
        }
    }
    
    private func cleanUpOutput(destinationURL: URL, isSplit: Bool, splitSize: Int64?) {
        let fileManager = FileManager.default
        print("[CLEANUP DEBUG] cleanUpOutput called for: \(destinationURL.path) (isSplit: \(isSplit))")
        let isAccessing = destinationURL.deletingLastPathComponent().startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                destinationURL.deletingLastPathComponent().stopAccessingSecurityScopedResource()
            }
        }
        
        if isSplit, let _ = splitSize {
            let baseName = destinationURL.deletingPathExtension().lastPathComponent
            let parentDir = destinationURL.deletingLastPathComponent()
            if let files = try? fileManager.contentsOfDirectory(at: parentDir, includingPropertiesForKeys: nil) {
                let parts = files.filter { $0.lastPathComponent.hasPrefix(baseName) }
                for part in parts {
                    print("[CLEANUP DEBUG] Removing split part: \(part.path)")
                    do {
                        try fileManager.removeItem(at: part)
                    } catch {
                        print("[CLEANUP DEBUG] Failed to remove split part: \(error)")
                    }
                }
            }
        } else {
            if fileManager.fileExists(atPath: destinationURL.path) {
                print("[CLEANUP DEBUG] File exists. Attempting removal...")
                do {
                    try fileManager.removeItem(at: destinationURL)
                    print("[CLEANUP DEBUG] Removal successful.")
                } catch {
                    print("[CLEANUP DEBUG] Removal failed with error: \(error)")
                }
            } else {
                print("[CLEANUP DEBUG] File does not exist at path.")
            }
        }
    }
    
    private func getIndividualTargetURL(item: StagingItem, job: CompressionJob) -> URL {
        let fileExt: String
        switch item.fileType {
        case .image:
            fileExt = job.imageSettings.format.lowercased()
        case .video:
            fileExt = "mp4"
        case .audio:
            fileExt = job.audioSettings.format.lowercased()
        default:
            fileExt = item.sourceURL.pathExtension
        }
        
        let cleanName = item.sourceURL.deletingPathExtension().lastPathComponent
        let outputName = "\(cleanName)\(job.customSuffix).\(fileExt)"
        
        if job.outputStyle == .individual {
            // For "Separate Files" style, output directly into the destination directory, ignoring original folder structure.
            return job.outputDir.appendingPathComponent(outputName)
        }
        
        let pathComponents = item.relativePath.components(separatedBy: "/")
        var processedComponents = pathComponents
        
        if pathComponents.count > 1 {
            // It's inside a folder.
            // Rename the top-level folder component to have the suffix
            processedComponents[0] = processedComponents[0] + job.customSuffix
            // Rename the last file component to have the suffix and new extension
            processedComponents[processedComponents.count - 1] = outputName
        } else {
            // It's a root-level individual file.
            processedComponents[0] = outputName
        }
        
        let targetRelPath = processedComponents.joined(separator: "/")
        return job.outputDir.appendingPathComponent(targetRelPath)
    }
    
    private func processIndividualItem(
        _ item: StagingItem,
        job: CompressionJob,
        progressTracker: ParallelProgressTracker
    ) async throws {
        if cancelled {
            progressTracker.updateProgress(for: item.sourceURL, progress: 1.0)
            return
        }
        
        let fileManager = FileManager.default
        let targetURL = getIndividualTargetURL(item: item, job: job)
        
        let targetParent = targetURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: targetParent.path) {
            try fileManager.createDirectory(at: targetParent, withIntermediateDirectories: true)
        }
        
        let compressImages = job.imageSettings.compressEnabled && item.fileType == .image
        let compressVideos = job.videoSettings.compressEnabled && item.fileType == .video
        let compressAudio = job.audioSettings.compressEnabled && item.fileType == .audio
        let compressPDF = job.pdfSettings.compressEnabled && item.fileType == .pdf
        
        do {
            await MainActor.run { [weak self] in
                self?.state?.compressionStats.registerActiveOutput(targetURL)
            }
            defer {
                let size = (try? fileManager.attributesOfItem(atPath: targetURL.path)[.size] as? Int64) ?? 0
                Task { @MainActor [weak self] in
                    self?.state?.compressionStats.unregisterActiveOutput(targetURL, finalSize: size)
                }
            }
            if compressImages {
                var settings = job.imageSettings
                settings.targetSizeRatio = targetSizeRatio(for: item.sourceURL, job: job, defaultRatio: job.imageSettings.targetSizeRatio)
                let (resW, resH) = targetResolution(for: item.sourceURL, job: job, defaultW: job.imageSettings.targetResolutionWidth, defaultH: job.imageSettings.targetResolutionHeight)
                settings.targetResolutionWidth = resW
                settings.targetResolutionHeight = resH
                
                let source = item.sourceURL
                let target = targetURL
                let finalSettings = settings
                
                _ = try await laneManager.enqueue(lane: .image) {
                    try await Task.detached {
                        let imageComp = ImageCompressor()
                        return try imageComp.compress(inputURL: source, outputURL: target, settings: finalSettings)
                    }.value
                }
                progressTracker.updateProgress(for: item.sourceURL, progress: 1.0)
            } else if compressVideos {
                let videoComp = VideoCompressor()
                activeOperations.add(videoComp)
                defer { activeOperations.remove(videoComp) }
                
                let videoSettings = resolveVideoSettings(for: item.sourceURL, job: job)

                _ = try await laneManager.enqueue(lane: .video) {
                    try await videoComp.compress(
                        inputURL: item.sourceURL,
                        outputURL: targetURL,
                        settings: videoSettings,
                        progressHandler: { fileProgress, logicalWrittenBytes in
                            progressTracker.updateProgress(for: item.sourceURL, progress: fileProgress, logicalWrittenBytes: logicalWrittenBytes, targetURL: targetURL)
                        }
                    )
                }
                progressTracker.updateProgress(for: item.sourceURL, progress: 1.0)
            } else if compressAudio {
                let audioComp = AudioCompressor()
                activeOperations.add(audioComp)
                defer { activeOperations.remove(audioComp) }
                
                _ = try await audioComp.compress(inputURL: item.sourceURL, outputURL: targetURL, settings: job.audioSettings)
            } else if compressPDF {
                let pdfComp = PDFCompressor()
                _ = try pdfComp.compress(inputURL: item.sourceURL, outputURL: targetURL)
            } else {
                if fileManager.fileExists(atPath: targetURL.path) {
                    try fileManager.removeItem(at: targetURL)
                }
                do {
                    try fileManager.linkItem(at: item.sourceURL, to: targetURL)
                } catch {
                    try fileManager.copyItem(at: item.sourceURL, to: targetURL)
                }
            }
            
            let size = (try? fileManager.attributesOfItem(atPath: targetURL.path)[.size] as? Int64) ?? 0
            await MainActor.run { [weak self] in
                self?.state?.updateFileCompleted(url: item.sourceURL, newSize: size, outputURL: targetURL)
            }
            progressTracker.updateProgress(for: item.sourceURL, progress: 1.0)
        } catch {
            print("[STAGING DEBUG] Failed to process individual file \(item.sourceURL.lastPathComponent): \(error)")
            if fileManager.fileExists(atPath: targetURL.path) {
                try? fileManager.removeItem(at: targetURL)
            }
            if !fileManager.fileExists(atPath: targetURL.path) {
                do {
                    try fileManager.linkItem(at: item.sourceURL, to: targetURL)
                } catch {
                    try? fileManager.copyItem(at: item.sourceURL, to: targetURL)
                }
            }
            await MainActor.run { [weak self] in
                self?.state?.updateFileFailed(url: item.sourceURL, message: error.localizedDescription)
                self?.markStatusFailed(for: item.sourceURL, message: error.localizedDescription)
            }
            progressTracker.updateProgress(for: item.sourceURL, progress: 1.0)
        }
    }

    private func processItems(
        _ items: [StagingItem],
        concurrency: Int,
        operation: @Sendable @escaping (StagingItem) async throws -> Void
    ) async throws {
        guard !items.isEmpty else { return }
        try await withThrowingTaskGroup(of: Void.self) { group in
            var inFlight = 0
            for item in items {
                if cancelled { break }
                if inFlight >= concurrency {
                    try await group.next()
                    inFlight -= 1
                }
                group.addTask {
                    try await operation(item)
                }
                inFlight += 1
            }
            while inFlight > 0 {
                try await group.next()
                inFlight -= 1
            }
        }
    }
    
    private func getFolderSizeBackground(at folderURL: URL) -> Int64 {
        let fm = FileManager.default
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

extension VideoCompressor: CancelableOperation {}
extension AudioCompressor: CancelableOperation {}

// MARK: - Multi-Lane OperationQueue Manager

enum CompressionLane {
    case image
    case video
    case archive
}

// Async semaphore to control concurrency without blocking threads
actor AsyncSemaphore: Sendable {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.value = value
    }

    func wait() async {
        if value > 0 {
            value -= 1
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
    }

    func signal() {
        if !waiters.isEmpty {
            let cont = waiters.removeFirst()
            cont.resume()
        } else {
            value += 1
        }
    }
}

final actor CompressionLaneManager: @unchecked Sendable {
    private let imageSemaphore: AsyncSemaphore
    private let videoSemaphore: AsyncSemaphore
    private let archiveSemaphore: AsyncSemaphore

    init() {
        let coreCount = ProcessInfo.processInfo.activeProcessorCount
        let imageCount = max(2, coreCount - 2)
        let videoCount = max(1, min(3, coreCount / 4))

        imageSemaphore = AsyncSemaphore(value: imageCount)
        videoSemaphore = AsyncSemaphore(value: videoCount)
        archiveSemaphore = AsyncSemaphore(value: 1)
    }

    nonisolated func concurrencyLimit(for lane: CompressionLane) -> Int {
        // Compute a sensible limit based on current thermal state and cores
        let coreCount = ProcessInfo.processInfo.activeProcessorCount
        let thermal = ProcessInfo.processInfo.thermalState
        switch lane {
        case .image:
            switch thermal {
            case .nominal: return max(3, coreCount - 2)
            case .fair: return max(2, coreCount / 2)
            case .serious: return max(1, coreCount / 4)
            case .critical: return 1
            @unknown default: return max(1, coreCount / 2)
            }
        case .video:
            switch thermal {
            case .nominal: return max(1, min(4, coreCount / 3))
            case .fair: return max(1, min(3, coreCount / 4))
            case .serious: return 1
            case .critical: return 1
            @unknown default: return 1
            }
        case .archive:
            return 1
        }
    }

    func enqueue<T: Sendable>(lane: CompressionLane, _ work: @Sendable @escaping () async throws -> T) async throws -> T {
        let sem = semaphoreFor(lane)
        await sem.wait()
        do {
            let result = try await work()
            await sem.signal()
            return result
        } catch {
            await sem.signal()
            throw error
        }
    }

    private func semaphoreFor(_ lane: CompressionLane) -> AsyncSemaphore {
        switch lane {
        case .image: return imageSemaphore
        case .video: return videoSemaphore
        case .archive: return archiveSemaphore
        }
    }
}
