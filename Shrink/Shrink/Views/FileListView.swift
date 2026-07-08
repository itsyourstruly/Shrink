//
//  FileListView.swift
//  Shrink
//

import SwiftUI
import QuickLookThumbnailing
import Combine

struct FileListView: View {
    @Bindable var state: AppState
    @State private var isDragOver = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center, spacing: 8) {
                // Select/Deselect All Checkbox
                if !state.selectedFiles.isEmpty {
                    let checkedCount = state.selectedFiles.filter { $0.isChecked }.count
                    Button(action: toggleAllChecked) {
                        Text("\(checkedCount)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(state.isProcessing ? .secondary : (checkedCount > 0 ? .blue : .secondary))
                    }
                    .buttonStyle(.plain)
                    .disabled(state.isProcessing)
                }
                
                Text(FileItem.formatBytes(state.totalSize))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Cancel/Stop button during background processing
                if state.isProcessing {
                    Button(action: state.cancelShrinking) {
                        Text("Stop")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
                
                // Add more button
                Button(action: addMoreFiles) {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(state.isProcessing)
                
                // Clear all button
                Button(action: state.clearFiles) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
                .disabled(state.isProcessing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
            
            // List of items
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(state.selectedFiles) { file in
                        FileRowGroupView(
                            state: state,
                            file: file,
                            level: 0
                        )
                    }
                }
                .padding(16)
            }
            .dropDestination(for: URL.self) { items, location in
                state.addFiles(urls: items)
                return true
            } isTargeted: { targeted in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDragOver = targeted
                }
            }
            .overlay(
                Group {
                    if isDragOver {
                        Rectangle()
                            .fill(Color.blue.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [6]))
                                    .padding(8)
                            )
                    }
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
    
    private var areAllChecked: Bool {
        state.selectedFiles.allSatisfy { isCheckedRecursive($0) }
    }
    
    private var areAnyChecked: Bool {
        let allChecked = areAllChecked
        return state.selectedFiles.contains { hasAnyCheckedRecursive($0) } && !allChecked
    }
    
    private func isCheckedRecursive(_ item: FileItem) -> Bool {
        guard item.isChecked else { return false }
        if item.isDirectory {
            return item.subItems.allSatisfy { isCheckedRecursive($0) }
        }
        return true
    }
    
    private func hasAnyCheckedRecursive(_ item: FileItem) -> Bool {
        if item.isChecked { return true }
        if item.isDirectory {
            return item.subItems.contains { hasAnyCheckedRecursive($0) }
        }
        return false
    }
    
    private func toggleAllChecked() {
        let target = !areAllChecked
        state.toggleAllChecked(target: target)
    }
    
    private func addMoreFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            state.addFiles(urls: panel.urls)
        }
    }
}

struct FileRowView: View {
    @Bindable var state: AppState
    let file: FileItem
    let isSelected: Bool
    let isProcessing: Bool
    let onToggleCheck: () -> Void
    let onSelect: () -> Void
    let onRemove: () -> Void
    var level: Int = 0
    @State private var isHovered = false
       var body: some View {
        HStack(spacing: 12) {
            if level > 0 {
                Spacer()
                    .frame(width: CGFloat(level) * 16)
            }
            // Expand/Collapse Chevron for directories
            if file.isDirectory {
                Image(systemName: file.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        state.toggleFileExpanded(id: file.id)
                    }
            } else {
                Spacer()
                    .frame(width: 12, height: 12)
            }
            
            // Checkbox for selection/compression (shown for all items)
            let checkboxImageName: String = {
                if !file.isDirectory {
                    return file.isChecked ? "checkmark.square.fill" : "square"
                } else {
                    if file.isAllCheckedRecursive {
                        return "checkmark.square.fill"
                    } else if file.hasAnyCheckedRecursive {
                        return "minus.square.fill"
                    } else {
                        return "square"
                    }
                }
            }()
            
            let checkboxColor: Color = {
                if !file.isDirectory {
                    return file.isChecked ? .blue : .secondary
                } else {
                    return file.hasAnyCheckedRecursive ? .blue : .secondary
                }
            }()
            
            Image(systemName: checkboxImageName)
                .font(.system(size: 14))
                .foregroundColor(checkboxColor)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isProcessing {
                        onToggleCheck()
                    }
                }
            
            // The rest of the row is tap-target for active selection
            HStack(spacing: 12) {
                // Type Icon (with QuickLook Thumbnail support)
                FileThumbnailView(url: file.url, fileType: file.fileType, size: 32)
                
                // Info text
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    let descriptionString: String = {
                        var details: [String] = []
                        if file.fileType == .video {
                            details.append("video")
                            if let codec = file.customCodec {
                                details.append(codec)
                            }
                            if let w = file.customResolutionWidth, let h = file.customResolutionHeight {
                                details.append("\(w)x\(h)")
                            }
                            if let fps = file.frameRate {
                                details.append("\(Int(round(fps)))fps")
                            }
                            if let audio = file.customAudioMode {
                                if audio == "Mute" {
                                    details.append("mute audio")
                                } else if audio == "Compress" {
                                    details.append("compress audio")
                                }
                            }
                            if let ratio = file.customTargetSizeRatio {
                                let pct = Int(round((1.0 - ratio) * 100))
                                if pct > 0 {
                                    details.append("\(pct)% shrink")
                                }
                            }
                        } else if file.fileType == .image {
                            details.append("image")
                            if let w = file.customResolutionWidth, let h = file.customResolutionHeight {
                                details.append("\(w)x\(h)")
                            }
                            if let format = file.customImageFormat {
                                details.append(format.uppercased())
                            }
                            if let ratio = file.customTargetSizeRatio {
                                let pct = Int(round((1.0 - ratio) * 100))
                                if pct > 0 {
                                    details.append("\(pct)% shrink")
                                }
                            }
                        } else {
                            details.append(file.fileType == .general ? file.url.pathExtension.uppercased() : file.fileType.rawValue)
                        }
                        return details.joined(separator: "   ")
                    }()
                    
                    Text(descriptionString)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Quick Convert Dropdown and Quick Shrink Button
                HStack(spacing: 8) {
                    quickConvertMenu
                    
                    if !file.isDirectory && (file.fileType == .video || file.fileType == .image) {
                        let shrinkColor = quickShrinkColor(for: file.fileType)
                        Button(action: {
                            state.startShrinkingSingleItem(file)
                        }) {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(shrinkColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(shrinkColor.opacity(0.1))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .disabled(isProcessing)
                    }
                }
                
                // Status and Size
                VStack(alignment: .trailing, spacing: 2) {
                    Text(FileItem.formatBytes(file.originalSize))
                        .font(.system(size: 12, weight: .medium))
                        
                    switch file.status {
                    case .processing(let progress):
                        Text(String(format: "%.0f%%", progress * 100))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        
                    case .completed(let newSize, let outputURL):
                        HStack(spacing: 8) {
                            if newSize > 0, (file.fileType == .image || file.fileType == .video) {
                                Button("Compare") {
                                    openCompareWindow(original: file.url, compressed: outputURL, type: file.fileType)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                                )
                            }
                            
                            if newSize > 0 {
                                let savings = Double(file.originalSize - newSize) / Double(file.originalSize)
                                HStack(spacing: 4) {
                                    Text("-\(String(format: "%.0f%%", savings * 100))")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundColor(.green)
                                        
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 12))
                                }
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 12))
                            }
                        }
                        
                    case .failed(let message):
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 12))
                            .help(message)
                    default:
                        EmptyView()
                    }
                }
                
                // Delete button
                if isHovered && !isProcessing {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if !isProcessing {
                    onSelect()
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                
                if isSelected {
                    Color.blue.opacity(0.06)
                }
                
                GeometryReader { geometry in
                    if case .processing(let progress) = file.status {
                        // Transparent progress container with a solid blue vertical line at the edge
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: 2)
                            .offset(x: max(0, geometry.size.width * progress - 2))
                    }
                }
            }
        )
        .cornerRadius(8)
        .overlay(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue, lineWidth: 2)
                }
            }
        )
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hover
            }
        }
        .contextMenu {
            if file.fileType == .video {
                Menu("Resolution") {
                    Button("Auto (Original)") {
                        state.updateFileItem(id: file.id) {
                            $0.customResolutionWidth = nil
                            $0.customResolutionHeight = nil
                        }
                    }
                    Button("4K (3840x2160)") {
                        state.updateFileItem(id: file.id) {
                            $0.customResolutionWidth = 3840
                            $0.customResolutionHeight = 2160
                        }
                    }
                    Button("1080p (1920x1080)") {
                        state.updateFileItem(id: file.id) {
                            $0.customResolutionWidth = 1920
                            $0.customResolutionHeight = 1080
                        }
                    }
                    Button("720p (1280x720)") {
                        state.updateFileItem(id: file.id) {
                            $0.customResolutionWidth = 1280
                            $0.customResolutionHeight = 720
                        }
                    }
                    Button("480p (854x480)") {
                        state.updateFileItem(id: file.id) {
                            $0.customResolutionWidth = 854
                            $0.customResolutionHeight = 480
                        }
                    }
                }
                
                Menu("Codec") {
                    Button("HEVC (H.265)") {
                        state.updateFileItem(id: file.id) { $0.customCodec = "HEVC" }
                    }
                    Button("H.264") {
                        state.updateFileItem(id: file.id) { $0.customCodec = "H264" }
                    }
                    Button("ProRes 422") {
                        state.updateFileItem(id: file.id) { $0.customCodec = "ProRes422" }
                    }
                    Button("ProRes 422 HQ") {
                        state.updateFileItem(id: file.id) { $0.customCodec = "ProRes422HQ" }
                    }
                    Button("ProRes 422 LT") {
                        state.updateFileItem(id: file.id) { $0.customCodec = "ProRes422LT" }
                    }
                    Button("ProRes 422 Proxy") {
                        state.updateFileItem(id: file.id) { $0.customCodec = "ProRes422Proxy" }
                    }
                    Button("ProRes 4444") {
                        state.updateFileItem(id: file.id) { $0.customCodec = "ProRes4444" }
                    }
                }
                
                Menu("Audio") {
                    Button("Keep Audio") {
                        state.updateFileItem(id: file.id) { $0.customAudioMode = "Keep" }
                    }
                    Button("Compress Audio") {
                        state.updateFileItem(id: file.id) { $0.customAudioMode = "Compress" }
                    }
                    Button("Mute Audio") {
                        state.updateFileItem(id: file.id) { $0.customAudioMode = "Mute" }
                    }
                }
                
                Menu("Shrink Amount") {
                    ForEach([10, 20, 30, 40, 50, 60, 70, 80, 90], id: \.self) { pct in
                        Button("\(pct)%") {
                            state.updateFileItem(id: file.id) {
                                $0.customTargetSizeRatio = 1.0 - (Double(pct) / 100.0)
                            }
                        }
                    }
                }
                
                Divider()
                
                Button("Shrink") {
                    state.startShrinkingSingleItem(file)
                }
                .disabled(isProcessing)
            } else if file.fileType == .image {
                Menu("Resolution") {
                    Button("Original") {
                        state.updateFileItem(id: file.id) {
                            $0.customResolutionWidth = nil
                            $0.customResolutionHeight = nil
                        }
                    }
                    Button("Max 4K (3840)") {
                        state.updateFileItem(id: file.id) {
                            $0.customResolutionWidth = 3840
                            $0.customResolutionHeight = 2160
                        }
                    }
                    Button("Max 1080p (1920)") {
                        state.updateFileItem(id: file.id) {
                            $0.customResolutionWidth = 1920
                            $0.customResolutionHeight = 1080
                        }
                    }
                    Button("Max 720p (1280)") {
                        state.updateFileItem(id: file.id) {
                            $0.customResolutionWidth = 1280
                            $0.customResolutionHeight = 720
                        }
                    }
                }
                
                Menu("Format") {
                    Button("JPEG") {
                        state.updateFileItem(id: file.id) { $0.customImageFormat = "jpeg" }
                    }
                    Button("PNG") {
                        state.updateFileItem(id: file.id) { $0.customImageFormat = "png" }
                    }
                    Button("WEBP") {
                        state.updateFileItem(id: file.id) { $0.customImageFormat = "webp" }
                    }
                    Button("HEIC") {
                        state.updateFileItem(id: file.id) { $0.customImageFormat = "heic" }
                    }
                    Button("TIFF") {
                        state.updateFileItem(id: file.id) { $0.customImageFormat = "tiff" }
                    }
                }
                
                Menu("Shrink Amount") {
                    ForEach([10, 20, 30, 40, 50, 60, 70, 80, 90], id: \.self) { pct in
                        Button("\(pct)%") {
                            state.updateFileItem(id: file.id) {
                                $0.customTargetSizeRatio = 1.0 - (Double(pct) / 100.0)
                            }
                        }
                    }
                }
                
                Divider()
                
                Button("Shrink") {
                    state.startShrinkingSingleItem(file)
                }
                .disabled(isProcessing)
            } else {
                Button("Shrink") {
                    state.startShrinkingSingleItem(file)
                }
                .disabled(isProcessing)
            }
        }
    }
    
    private var quickConvertMenu: some View {
        Group {
            if file.isDirectory {
                let extensions = Array(file.extensionCounts.keys).sorted()
                if !extensions.isEmpty {
                    Menu {
                        ForEach(extensions, id: \.self) { ext in
                            let targetOptions = FileConverter.enabledTargetFormats(forExtension: ext)
                            if !targetOptions.isEmpty {
                                Menu("Convert .\(ext.uppercased()) to") {
                                    ForEach(targetOptions, id: \.self) { format in
                                        let tool = FileConverter.toolRequired(from: ext, to: format)
                                        let isAvailable = tool == nil ? true : ExternalToolManager.isToolAvailable(tool!)
                                        
                                        Button(format.uppercased()) {
                                            state.convertFolderFiles(in: file, sourceExtension: ext, targetFormat: format)
                                        }
                                        .disabled(!isAvailable)
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(isProcessing)
                }
            } else if file.parentArchiveURL == nil {
                // Only show convert for real filesystem files (not virtual archive entries)
                let ext = file.url.pathExtension
                let targetOptions = FileConverter.enabledTargetFormats(forExtension: ext)
                if !targetOptions.isEmpty {
                    Menu {
                        ForEach(targetOptions, id: \.self) { format in
                            let tool = FileConverter.toolRequired(from: ext, to: format)
                            let isAvailable = tool == nil ? true : ExternalToolManager.isToolAvailable(tool!)
                            
                            Button(format.uppercased()) {
                                state.convertFileItem(file, targetFormat: format)
                            }
                            .disabled(!isAvailable)
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(isProcessing)
                }
            }
        }
    }
    
    private func quickShrinkColor(for type: FileType) -> Color {
        switch type {
        case .image: return .orange
        case .video: return .teal
        case .audio: return .cyan
        case .pdf: return .red
        case .archive: return .green
        default: return .blue
        }
    }
}

struct FileRowGroupView: View {
    @Bindable var state: AppState
    let file: FileItem
    let level: Int
    
    var body: some View {
        VStack(spacing: 8) {
            FileRowView(
                state: state,
                file: file,
                isSelected: file.isChecked,
                isProcessing: state.isProcessing,
                onToggleCheck: {
                    state.toggleFileChecked(id: file.id)
                },
                onSelect: {
                    state.selectSingleFile(id: file.id)
                },
                onRemove: {
                    state.removeFile(id: file.id)
                },
                level: level
            )
            
            if file.isDirectory && file.isExpanded {
                LazyVStack(spacing: 8) {
                    ForEach(file.subItems) { subItem in
                        FileRowGroupView(
                            state: state,
                            file: subItem,
                            level: level + 1
                        )
                    }
                }
            }
        }
    }
}

@MainActor
class WindowManager {
    static let shared = WindowManager()
    private var windows: [NSWindow] = []
    
    private init() {}
    
    func addWindow(_ window: NSWindow) {
        windows.append(window)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }
    
    @objc private func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            windows.removeAll { $0 === window }
        }
    }
}

@MainActor
func openCompareWindow(original: URL, compressed: URL, type: FileType) {
    let compareView = CompareView(originalURL: original, compressedURL: compressed, fileType: type)
    
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 850, height: 600),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.title = "Compare: \(original.lastPathComponent)"
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: compareView)
    window.center()
    window.makeKeyAndOrderFront(nil)
    
    WindowManager.shared.addWindow(window)
}

@MainActor
class ThumbnailLoader: ObservableObject {
    @Published var image: NSImage? = nil
    private static let cache = NSCache<NSURL, NSImage>()
    
    func loadThumbnail(for url: URL, size: CGSize) {
        let nsURL = url as NSURL
        if let cachedImage = Self.cache.object(forKey: nsURL) {
            self.image = cachedImage
            return
        }
        
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .all
        )
        
        QLThumbnailGenerator.shared.generateRepresentations(for: request) { representation, type, error in
            if let representation = representation {
                let nsImage = representation.nsImage
                Self.cache.setObject(nsImage, forKey: nsURL)
                Task { @MainActor in
                    self.image = nsImage
                }
            }
        }
    }
}

struct FileThumbnailView: View {
    let url: URL
    let fileType: FileType
    let size: CGFloat
    
    @StateObject private var loader = ThumbnailLoader()
    
    var body: some View {
        Group {
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(iconColor(for: fileType).opacity(0.12))
                        .frame(width: size, height: size)
                    
                    Image(systemName: fileType.systemIcon)
                        .font(.system(size: size * 0.5))
                        .foregroundColor(iconColor(for: fileType))
                }
            }
        }
        .onAppear {
            loader.loadThumbnail(for: url, size: CGSize(width: size, height: size))
        }
    }
    
    private func iconColor(for type: FileType) -> Color {
        switch type {
        case .image: return .blue
        case .video: return .blue
        case .audio: return .pink
        case .pdf: return .orange
        case .archive: return .blue
        case .general: return .gray
        }
    }
}

