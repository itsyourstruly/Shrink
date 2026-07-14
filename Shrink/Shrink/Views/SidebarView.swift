//
//  SidebarView.swift
//  Shrink
//

import SwiftUI

struct SidebarView: View {
    @Bindable var state: AppState
    @AppStorage("use_sevenzip_for_archive") private var useSevenZip = true
    
    private var isSevenZipAvailable: Bool {
        ArchiveCompressor.isSevenZipAvailable() && useSevenZip
    }
    
    enum SidebarSection: String, CaseIterable, Identifiable {
        case general = "General"
        case pdf = "PDF"
        case images = "Images"
        case videos = "Videos"
        case audio = "Audio"
        case conversion = "Conversion"
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .general: return "General Shrinking"
            case .pdf: return "PDF Shrinking"
            case .images: return "Images Shrinking"
            case .videos: return "Videos Shrinking"
            case .audio: return "Audio Shrinking"
            case .conversion: return "Conversion Shrinking"
            }
        }
    }
    
    @State private var activeSection: SidebarSection = .general
    @State private var isDropdownExpanded: Bool = false
    @State private var showIndividualImageOptions: Bool = false
    @State private var showIndividualVideoOptions: Bool = false
    @State private var expandedResolutionItemID: UUID? = nil
    @State private var expandedAudioItemID: UUID? = nil
    @State private var folderConvertTargets: [String: String] = [:]
    
    @State private var editingGeneralName = false
    @State private var editingPdfName = false
    @State private var editingPdfSuffix = false
    @State private var editingImageName = false
    @State private var editingVideoName = false
    @State private var editingAudioName = false
    @State private var editingConvertName = false
    @State private var editingConvertSuffix = false
    @State private var editingImageSuffix = false
    @State private var editingVideoSuffix = false
    @State private var editingAudioSuffix = false
    
    private var showModeToggle: Bool {
        let types = state.aggregateDetectedTypes
        return types.contains(.archive) && types.count > 1
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header summary with dropdown
            VStack(alignment: .leading, spacing: 8) {
                // Dropdown Toggle Button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isDropdownExpanded.toggle()
                    }
                }) {
                    HStack {
                        Text(activeSection.title)
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                        Text(isDropdownExpanded ? "▲" : "▼")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(state.isProcessing)
                
                if isDropdownExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("You can choose a specific type of compression depending on what you're looking for")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 4)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        ForEach(SidebarSection.allCases) { section in
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    activeSection = section
                                    isDropdownExpanded = false
                                }
                            }) {
                                HStack {
                                    Text(section.rawValue)
                                        .font(.system(size: 12, weight: activeSection == section ? .semibold : .regular))
                                        .foregroundColor(activeSection == section ? .blue : .primary)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .background(activeSection == section ? Color.blue.opacity(0.08) : Color.clear)
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .padding(.top, 2)
                    .transition(.opacity)
                }
                
                Text("\(state.selectedFiles.count) files selected • \(FileItem.formatBytes(state.totalSize))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            // Scrollable configuration panel
            ScrollView {
                VStack(spacing: 16) {
                    switch activeSection {
                    case .general:
                        VStack(alignment: .leading, spacing: 16) {
                            if showModeToggle {
                                Picker("", selection: $state.mode) {
                                    ForEach(AppMode.allCases) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .disabled(state.isProcessing)
                                
                                if state.mode == .compress {
                                    Picker("", selection: $state.archiveHandlingMode) {
                                        ForEach(ArchiveHandlingMode.allCases) { mode in
                                            Text(mode.rawValue).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                    .disabled(state.isProcessing)
                                }
                            }
                            
                            if state.mode == .decompress {
                                decompressionSettingsSection
                            } else {
                                // Archive/General settings at the top
                                VStack(alignment: .leading, spacing: 10) {
                                    Picker("Format", selection: $state.archiveSettings.format) {
                                        Text("ZIP").tag(ArchiveFormat.zip)
                                        Text("TAR").tag(ArchiveFormat.tar)
                                        Text("TAR.GZ (tgz)").tag(ArchiveFormat.tgz)
                                        if isSevenZipAvailable {
                                            Text("7-Zip (7z)").tag(ArchiveFormat.sevenZip)
                                        } else {
                                            Text("7-Zip (7z) [Unavailable]").tag(ArchiveFormat.sevenZip)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    
                                    if state.archiveSettings.format == .sevenZip && !isSevenZipAvailable {
                                        Text("⚠️ 7-Zip CLI not found. Install via Homebrew.")
                                            .font(.system(size: 9))
                                            .foregroundColor(.red)
                                    }
                                }
                                
                                // Sliders at the bottom of options
                                if state.outputStyle == .archive && state.archiveSettings.format != .tar {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("Compression Level")
                                                .font(.system(size: 11, weight: .medium))
                                            Spacer()
                                            Text(compressionLevelLabel(state.archiveSettings.compressionLevel))
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(.secondary)
                                        }
                                        Slider(value: Binding(
                                            get: { Double(state.archiveSettings.compressionLevel) },
                                            set: { state.archiveSettings.compressionLevel = Int($0) }
                                        ), in: 0...9, step: 1)
                                        
                                        HStack {
                                            Text("Fastest")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text("Most Compressed")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                
                            }
                            
                            Divider()
                                .padding(.vertical, 4)
                            
                            // Destination options (sentence layout)
                            VStack(alignment: .leading, spacing: 6) {
                                if state.mode == .compress {
                                    HStack(alignment: .center, spacing: 4) {
                                        if editingGeneralName {
                                            Text("Creating")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.primary)
                                            
                                            TextField("", text: $state.customOutputName)
                                                .textFieldStyle(.plain)
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(.blue)
                                                .onSubmit {
                                                    editingGeneralName = false
                                                }
                                                .frame(maxWidth: 150)
                                        } else {
                                            Text("Creating")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.primary)
                                            
                                            Text(state.customOutputName.isEmpty ? "Archive" : state.customOutputName)
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(.blue)
                                                .onTapGesture {
                                                    editingGeneralName = true
                                                }
                                        }
                                        
                                        Text("as")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.primary)
                                        
                                        Menu {
                                            Button("ZIP") { state.archiveSettings.format = .zip }
                                            Button("TAR") { state.archiveSettings.format = .tar }
                                            Button("TAR.GZ") { state.archiveSettings.format = .tgz }
                                            if isSevenZipAvailable {
                                                Button("7-Zip") { state.archiveSettings.format = .sevenZip }
                                            }
                                        } label: {
                                            Text(state.archiveSettings.format.rawValue.uppercased())
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(.blue)
                                        }
                                        .menuStyle(.button)
                                        .buttonStyle(.plain)
                                    }
                                } else {
                                    Text("Extracting files")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.primary)
                                }
                                
                                HStack(alignment: .center, spacing: 4) {
                                    Text("in")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.primary)
                                    
                                    Text(state.resolvedOutputDirectory?.path ?? "Choose Folder...")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.blue)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .onTapGesture {
                                            chooseCustomFolder()
                                        }
                                }
                            }
                            .padding(.vertical, 4)
                            
                            // Shrink Button (consistent prominent style)
                            Button(action: { state.startShrinking() }) {
                                HStack {
                                    Spacer()
                                    Text(state.mode == .compress ? "Shrink" : "Decompress")
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                            .tint(.blue)
                            .disabled(state.isProcessing)
                            .padding(.top, 8)
                        }
                        
                    case .pdf:
                        pdfCompressorPanel
                        
                    case .images:
                        imageCompressorPanel
                        
                    case .videos:
                        videoCompressorPanel
                        
                    case .audio:
                        audioCompressorPanel
                        
                    case .conversion:
                        if !state.selectedFiles.isEmpty {
                            conversionSettingsSection
                        } else {
                            Text("Select files to convert formats.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
            }
            .disabled(state.isProcessing)
            
        }
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .onAppear {
            // Status checked dynamically via computed properties
        }
        .onChange(of: state.outputStyle) {
            state.validateOutputStyles()
        }
        .onChange(of: state.imageOutputStyle) {
            state.validateOutputStyles()
        }
        .onChange(of: state.videoOutputStyle) {
            state.validateOutputStyles()
        }
        .onChange(of: state.pdfOutputStyle) {
            state.validateOutputStyles()
        }
    }
    
    // MARK: - Smart Compression Panels
    private var imageCompressorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Options at the top
            Picker("Format", selection: $state.imageSettings.format) {
                Text("HEIC (Optimized)").tag("HEIC")
                Text("JPEG (Compatible)").tag("JPEG")
                Text("PNG (Lossless)").tag("PNG")
            }
            
            Picker("Resolution", selection: imageResolutionSelectionBinding) {
                Text("Original Size").tag("original")
                Text("4K (3840 max)").tag("3840x3840")
                Text("1080p (1920 max)").tag("1920x1920")
                Text("720p (1280 max)").tag("1280x1280")
                Text("480p (640 max)").tag("640x640")
            }
            
            Toggle("Strip EXIF/GPS Metadata", isOn: $state.imageSettings.stripMetadata)
            
            // 2. Sliders below options
            VStack(alignment: .leading, spacing: 4) {
                let imageItems = getIndividualMediaItems(type: .image)
                
                if imageItems.count == 1, let singleItem = imageItems.first {
                    HStack {
                        Text("Target Size")
                        Spacer()
                        Text(String(format: "%.1f MB", singleItem.currentMb))
                            .font(.system(size: 11, design: .monospaced))
                    }
                    Slider(value: singleItem.binding, in: singleItem.minMb...singleItem.maxMb)
                    
                    Text("Original: \(FileItem.formatBytes(Int64(singleItem.maxMb * 1024 * 1024)))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else if imageItems.count > 1 {
                    HStack {
                        Text("Overall Shrink")
                        Spacer()
                        Text("\(Int(state.imageSettings.targetSizeRatio * 100))%")
                            .font(.system(size: 11, design: .monospaced))
                    }
                    Slider(value: overallImageCompressionBinding, in: 0.05...1.0, step: 0.05)
                    
                    let imageOriginalSize = state.totalSize(for: .image)
                    Text("Est: \(FileItem.formatBytes(Int64(Double(imageOriginalSize) * state.imageSettings.targetSizeRatio)))")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    
                    Button(action: { showIndividualImageOptions.toggle() }) {
                        HStack {
                            Text("Individual Options")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Image(systemName: showIndividualImageOptions ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9))
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    
                    if showIndividualImageOptions {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(imageItems, id: \.id) { item in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(item.name)
                                                .font(.system(size: 10))
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                                .foregroundColor(.primary)
                                                .contextMenu {
                                                    Button(action: {
                                                        if expandedResolutionItemID == item.id {
                                                            expandedResolutionItemID = nil
                                                        } else {
                                                            expandedResolutionItemID = item.id
                                                            expandedAudioItemID = nil
                                                        }
                                                    }) {
                                                        Label("Adjust Resolution", systemImage: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                                                    }
                                                }
                                            Spacer()
                                            Text(String(format: "%.1f MB", item.currentMb))
                                                .font(.system(size: 10, design: .monospaced))
                                        }
                                        Slider(value: item.binding, in: item.minMb...item.maxMb)
                                        
                                        if expandedResolutionItemID == item.id {
                                            HStack {
                                                Text("Res:")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.secondary)
                                                Picker("", selection: item.resolutionBinding) {
                                                    Text("Original").tag("original")
                                                    Text("4K").tag("3840x3840")
                                                    Text("1080p").tag("1920x1920")
                                                    Text("720p").tag("1280x1280")
                                                    Text("480p").tag("640x640")
                                                }
                                                .pickerStyle(.menu)
                                                .controlSize(.mini)
                                                .labelsHidden()
                                            }
                                            .padding(.leading, 8)
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                        .padding(.top, 4)
                    }
                }
            }
            
            // 3. Destination options above the button
            Divider()
                .padding(.vertical, 4)
            
            // Destination options (sentence layout)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 4) {
                    Menu {
                        Button("Separate Files") {
                            state.imageOutputStyle = .individual
                            editingImageName = false
                        }
                        Button("Folder") {
                            state.imageOutputStyle = .subfolder
                        }
                        Button("Archive") {
                            state.imageOutputStyle = .archive
                        }
                    } label: {
                        Text("Creating")
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    
                    if state.imageOutputStyle == .individual {
                        Menu {
                            Button("Separate Files") {
                                state.imageOutputStyle = .individual
                                editingImageName = false
                            }
                            Button("Folder") {
                                state.imageOutputStyle = .subfolder
                            }
                            Button("Archive") {
                                state.imageOutputStyle = .archive
                            }
                        } label: {
                            Text("separate files")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                    } else {
                        if editingImageName {
                            TextField("", text: $state.imageCustomOutputName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)
                                .onSubmit {
                                    editingImageName = false
                                }
                                .frame(maxWidth: 150)
                        } else {
                            Text(state.imageCustomOutputName.isEmpty ? "Images" : state.imageCustomOutputName)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)
                                .onTapGesture {
                                    editingImageName = true
                                }
                        }
                        
                        if state.imageOutputStyle == .archive {
                            Text("as")
                                .font(.system(size: 11))
                                .foregroundStyle(.primary)
                            
                            Menu {
                                Button("ZIP") { state.imageArchiveFormat = .zip }
                                Button("TAR") { state.imageArchiveFormat = .tar }
                                Button("TAR.GZ") { state.imageArchiveFormat = .tgz }
                                if isSevenZipAvailable {
                                    Button("7-Zip") { state.imageArchiveFormat = .sevenZip }
                                }
                            } label: {
                                Text(state.imageArchiveFormat.rawValue.uppercased())
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.blue)
                            }
                            .menuStyle(.button)
                            .buttonStyle(.plain)
                        } else if state.imageOutputStyle == .subfolder {
                            Text("folder")
                                .font(.system(size: 11))
                                .foregroundStyle(.primary)
                        }
                    }
                }
                
                if state.imageOutputStyle == .individual {
                    HStack(alignment: .center, spacing: 4) {
                        Text("with suffix")
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                        
                        if editingImageSuffix {
                            TextField("", text: $state.imageCustomSuffix)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)
                                .onSubmit {
                                    editingImageSuffix = false
                                }
                                .frame(maxWidth: 80)
                        } else {
                            Text(state.imageCustomSuffix.isEmpty ? "\"none\"" : "\"\(state.imageCustomSuffix)\"")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)
                                .onTapGesture {
                                    editingImageSuffix = true
                                }
                        }
                    }
                }
                
                HStack(alignment: .center, spacing: 4) {
                    Text("in")
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                    
                    Text(state.resolvedOutputDirectory(for: .imagesOnly)?.path ?? "Choose Folder...")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .onTapGesture {
                            chooseImageCustomFolder()
                        }
                }
            }
            .padding(.vertical, 4)
            
            // 4. Shrink Button (at the bottom)
            Button(action: { state.startShrinking(filter: .imagesOnly) }) {
                HStack {
                    Spacer()
                    Text("Shrink")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(.blue)
            .disabled(state.isProcessing || !state.aggregateDetectedTypes.contains(.image))
            .padding(.top, 8)
        }
    }
    
    private var videoCompressorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Options at the top
            Picker("Codec", selection: $state.videoSettings.codec) {
                Text("HEVC (H.265)").tag("HEVC")
                Text("H.264 (Legacy)").tag("H264")
            }
            
            Picker("Resolution", selection: videoResolutionSelectionBinding) {
                Text(originalResolutionLabel).tag("original")
                
                if let maxRes = maxOriginalResolution {
                    let maxW = Int(maxRes.width)
                    let standardPresets = [
                        (name: "4K (3840x2160)", tag: "3840x2160", w: 3840, h: 2160),
                        (name: "1080p (1920x1080)", tag: "1920x1080", w: 1920, h: 1080),
                        (name: "720p (1280x720)", tag: "1280x720", w: 1280, h: 720),
                        (name: "540p (960x540)", tag: "960x540", w: 960, h: 540),
                        (name: "480p (640x480)", tag: "640x480", w: 640, h: 480)
                    ]
                    
                    ForEach(standardPresets, id: \.tag) { preset in
                        if preset.w < maxW {
                            Text(preset.name).tag(preset.tag)
                        }
                    }
                }
            }
            
            Picker("Audio", selection: $state.videoSettings.audioMode) {
                Text("Shrink AAC").tag("Compress")
                Text("Keep Original").tag("Keep")
                Text("Mute Audio").tag("Mute")
            }
            
            // 2. Sliders below Options
            VStack(alignment: .leading, spacing: 4) {
                let videoItems = getIndividualMediaItems(type: .video)
                
                if videoItems.count == 1, let singleItem = videoItems.first {
                    HStack {
                        Text(state.videoSettings.compressionMethod == .targetSize ? "Target Size" : "Video Bitrate")
                            .fontWeight(.medium)
                        Spacer()
                        if state.videoSettings.compressionMethod == .targetSize {
                            Text(String(format: "%.1f MB", singleItem.currentMb))
                                .font(.system(size: 11, design: .monospaced))
                        } else {
                            let kbps = singleItem.bitrateBinding.wrappedValue
                            Text(String(format: "%.1f Mbps", kbps / 1000.0))
                                .font(.system(size: 11, design: .monospaced))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if state.videoSettings.compressionMethod == .targetSize {
                            state.videoSettings.compressionMethod = .bitrate
                            
                            let originalSize = Double(singleItem.originalSize)
                            let duration = singleItem.duration ?? 30.0
                            let ratio = singleItem.currentMb / (originalSize / (1024.0 * 1024.0))
                            let audioBitrate = Double(state.videoSettings.audioBitrate)
                            let audioMode = state.videoSettings.audioMode
                            let audioBytes = (audioMode == "Mute" ? 0.0 : audioBitrate / 8.0) * duration
                            let targetSizeBytes = originalSize * ratio
                            let videoBytes = max(targetSizeBytes - audioBytes, targetSizeBytes * 0.15)
                            let kbps = Int((videoBytes * 8.0) / (duration * 1000.0))
                            let clampedKbps = max(200, min(kbps, 100000))
                            
                            if let idx = state.selectedFiles.firstIndex(where: { $0.id == singleItem.id }) {
                                state.selectedFiles[idx].customTargetBitrateKbps = clampedKbps
                                state.selectedFiles[idx].customCompressionMethod = .bitrate
                            }
                            state.videoSettings.targetBitrateKbps = clampedKbps
                        } else {
                            state.videoSettings.compressionMethod = .targetSize
                            
                            if let idx = state.selectedFiles.firstIndex(where: { $0.id == singleItem.id }) {
                                state.selectedFiles[idx].customCompressionMethod = .targetSize
                            }
                        }
                    }
                    
                    if state.videoSettings.compressionMethod == .targetSize {
                        Slider(value: singleItem.binding, in: singleItem.minMb...singleItem.maxMb)
                        Text("Original: \(FileItem.formatBytes(Int64(singleItem.maxMb * 1024 * 1024)))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else {
                        Slider(value: singleItem.bitrateBinding, in: 200.0...50000.0, step: 100.0)
                        if let estOrig = singleItem.estimatedOriginalBitrateMbps {
                            Text("Original Est Bitrate: \(String(format: "%.1f Mbps", estOrig))")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Direct Bitrate Control")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if videoItems.count > 1 {
                    HStack {
                        Text(state.videoSettings.compressionMethod == .targetSize ? "Overall Shrink" : "Overall Bitrate")
                            .fontWeight(.medium)
                        Spacer()
                        if state.videoSettings.compressionMethod == .targetSize {
                            Text("\(Int(state.videoSettings.targetSizeRatio * 100))%")
                                .font(.system(size: 11, design: .monospaced))
                        } else {
                            Text(String(format: "%.1f Mbps", Double(state.videoSettings.targetBitrateKbps) / 1000.0))
                                .font(.system(size: 11, design: .monospaced))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if state.videoSettings.compressionMethod == .targetSize {
                            state.videoSettings.compressionMethod = .bitrate
                            
                            var representativeSize = 50 * 1024 * 1024
                            var representativeDuration = 30.0
                            let checkedVideos = state.selectedFiles.filter { $0.isChecked && $0.fileType == .video }
                            if let firstVideo = checkedVideos.first {
                                representativeSize = Int(firstVideo.originalSize)
                                representativeDuration = firstVideo.duration ?? 30.0
                            }
                            let audioBitrate = Double(state.videoSettings.audioBitrate)
                            let audioMode = state.videoSettings.audioMode
                            let audioBytes = (audioMode == "Mute" ? 0.0 : audioBitrate / 8.0) * representativeDuration
                            let targetSizeBytes = Double(representativeSize) * state.videoSettings.targetSizeRatio
                            let videoBytes = max(targetSizeBytes - audioBytes, targetSizeBytes * 0.15)
                            let kbps = Int((videoBytes * 8.0) / (representativeDuration * 1000.0))
                            state.videoSettings.targetBitrateKbps = max(200, min(kbps, 100000))
                            
                            for folderIdx in 0..<state.selectedFiles.count {
                                if state.selectedFiles[folderIdx].isChecked {
                                    if state.selectedFiles[folderIdx].isDirectory {
                                        for subIdx in 0..<state.selectedFiles[folderIdx].subMediaItems.count {
                                            if state.selectedFiles[folderIdx].subMediaItems[subIdx].fileType == .video {
                                                state.selectedFiles[folderIdx].subMediaItems[subIdx].customCompressionMethod = .bitrate
                                            }
                                        }
                                    } else if state.selectedFiles[folderIdx].fileType == .video {
                                        state.selectedFiles[folderIdx].customCompressionMethod = .bitrate
                                    }
                                }
                            }
                        } else {
                            state.videoSettings.compressionMethod = .targetSize
                            
                            for folderIdx in 0..<state.selectedFiles.count {
                                if state.selectedFiles[folderIdx].isChecked {
                                    if state.selectedFiles[folderIdx].isDirectory {
                                        for subIdx in 0..<state.selectedFiles[folderIdx].subMediaItems.count {
                                            if state.selectedFiles[folderIdx].subMediaItems[subIdx].fileType == .video {
                                                state.selectedFiles[folderIdx].subMediaItems[subIdx].customCompressionMethod = .targetSize
                                            }
                                        }
                                    } else if state.selectedFiles[folderIdx].fileType == .video {
                                        state.selectedFiles[folderIdx].customCompressionMethod = .targetSize
                                    }
                                }
                            }
                        }
                    }
                    
                    if state.videoSettings.compressionMethod == .targetSize {
                        Slider(value: overallVideoCompressionBinding, in: 0.05...1.0, step: 0.05)
                        
                        let videoOriginalSize = state.totalSize(for: .video)
                        Text("Est: \(FileItem.formatBytes(Int64(Double(videoOriginalSize) * state.videoSettings.targetSizeRatio)))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                    } else {
                        Slider(value: overallVideoBitrateBinding, in: 200.0...50000.0, step: 100.0)
                        
                        Text("Est: \(FileItem.formatBytes(estimatedVideoBitrateSize))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    
                    Button(action: { showIndividualVideoOptions.toggle() }) {
                        HStack {
                            Text("Individual Options")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Image(systemName: showIndividualVideoOptions ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9))
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    
                    if showIndividualVideoOptions {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(videoItems, id: \.id) { item in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(item.name)
                                                .font(.system(size: 10))
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                                .foregroundColor(.primary)
                                                .contextMenu {
                                                    Button(action: {
                                                        if expandedResolutionItemID == item.id {
                                                            expandedResolutionItemID = nil
                                                        } else {
                                                            expandedResolutionItemID = item.id
                                                            expandedAudioItemID = nil
                                                        }
                                                    }) {
                                                        Label("Adjust Resolution", systemImage: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                                                    }
                                                    
                                                    Button(action: {
                                                        if expandedAudioItemID == item.id {
                                                            expandedAudioItemID = nil
                                                        } else {
                                                            expandedAudioItemID = item.id
                                                            expandedResolutionItemID = nil
                                                        }
                                                    }) {
                                                        Label("Adjust Audio", systemImage: "waveform")
                                                    }
                                                }
                                            Spacer()
                                            if state.videoSettings.compressionMethod == .targetSize {
                                                Text(String(format: "%.1f MB", item.currentMb))
                                                    .font(.system(size: 10, design: .monospaced))
                                            } else {
                                                let kbps = item.bitrateBinding.wrappedValue
                                                Text(String(format: "%.1f Mbps", kbps / 1000.0))
                                                    .font(.system(size: 10, design: .monospaced))
                                            }
                                        }
                                        
                                        if state.videoSettings.compressionMethod == .targetSize {
                                            Slider(value: item.binding, in: item.minMb...item.maxMb)
                                        } else {
                                            Slider(value: item.bitrateBinding, in: 200.0...50000.0, step: 100.0)
                                        }
                                        
                                        if expandedResolutionItemID == item.id {
                                            HStack {
                                                Text("Res:")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.secondary)
                                                Picker("", selection: item.resolutionBinding) {
                                                    Text("Original").tag("original")
                                                    Text("4K").tag("3840x2160")
                                                    Text("1080p").tag("1920x1080")
                                                    Text("720p").tag("1280x720")
                                                    Text("540p").tag("960x540")
                                                    Text("480p").tag("640x480")
                                                }
                                                .pickerStyle(.menu)
                                                .controlSize(.mini)
                                                .labelsHidden()
                                            }
                                            .padding(.leading, 8)
                                        }
                                        
                                        if expandedAudioItemID == item.id {
                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack {
                                                    Text("Audio:")
                                                        .font(.system(size: 9))
                                                        .foregroundColor(.secondary)
                                                    Picker("", selection: item.audioModeBinding) {
                                                        Text("Shrink").tag("Compress")
                                                        Text("Keep").tag("Keep")
                                                        Text("Mute").tag("Mute")
                                                    }
                                                    .pickerStyle(.menu)
                                                    .controlSize(.mini)
                                                    .labelsHidden()
                                                }
                                                
                                                if item.audioModeBinding.wrappedValue == "Compress" {
                                                    Picker("Bitrate", selection: item.audioBitrateBinding) {
                                                        Text("64 kbps").tag(64000)
                                                        Text("96 kbps").tag(96000)
                                                        Text("128 kbps").tag(128000)
                                                        Text("192 kbps").tag(192000)
                                                        Text("256 kbps").tag(256000)
                                                        Text("320 kbps").tag(320000)
                                                    }
                                                    .pickerStyle(.menu)
                                                    .controlSize(.mini)
                                                }
                                            }
                                            .padding(.leading, 8)
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                        .padding(.top, 4)
                    }
                }
            }
            
            // 3. Destination settings above the button
            Divider()
                .padding(.vertical, 4)
            
            // Destination options (sentence layout)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 4) {
                    Menu {
                        Button("Separate Files") {
                            state.videoOutputStyle = .individual
                            editingVideoName = false
                        }
                        Button("Folder") {
                            state.videoOutputStyle = .subfolder
                        }
                        Button("Archive") {
                            state.videoOutputStyle = .archive
                        }
                    } label: {
                        Text("Creating")
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    
                    if state.videoOutputStyle == .individual {
                        Menu {
                            Button("Separate Files") {
                                state.videoOutputStyle = .individual
                                editingVideoName = false
                            }
                            Button("Folder") {
                                state.videoOutputStyle = .subfolder
                            }
                            Button("Archive") {
                                state.videoOutputStyle = .archive
                            }
                        } label: {
                            Text("separate files")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                    } else {
                        if editingVideoName {
                            TextField("", text: $state.videoCustomOutputName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)
                                .onSubmit {
                                    editingVideoName = false
                                }
                                .frame(maxWidth: 150)
                        } else {
                            Text(state.videoCustomOutputName.isEmpty ? "Videos" : state.videoCustomOutputName)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)
                                .onTapGesture {
                                    editingVideoName = true
                                }
                        }
                        
                        if state.videoOutputStyle == .archive {
                            Text("as")
                                .font(.system(size: 11))
                                .foregroundStyle(.primary)
                            
                            Menu {
                                Button("ZIP") { state.videoArchiveFormat = .zip }
                                Button("TAR") { state.videoArchiveFormat = .tar }
                                Button("TAR.GZ") { state.videoArchiveFormat = .tgz }
                                if isSevenZipAvailable {
                                    Button("7-Zip") { state.videoArchiveFormat = .sevenZip }
                                }
                            } label: {
                                Text(state.videoArchiveFormat.rawValue.uppercased())
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.blue)
                            }
                            .menuStyle(.button)
                            .buttonStyle(.plain)
                        } else if state.videoOutputStyle == .subfolder {
                            Text("folder")
                                .font(.system(size: 11))
                                .foregroundStyle(.primary)
                        }
                    }
                }
                
                if state.videoOutputStyle == .individual {
                    HStack(alignment: .center, spacing: 4) {
                        Text("with suffix")
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                        
                        if editingVideoSuffix {
                            TextField("", text: $state.videoCustomSuffix)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)
                                .onSubmit {
                                    editingVideoSuffix = false
                                }
                                .frame(maxWidth: 80)
                        } else {
                            Text(state.videoCustomSuffix.isEmpty ? "\"none\"" : "\"\(state.videoCustomSuffix)\"")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)
                                .onTapGesture {
                                    editingVideoSuffix = true
                                }
                        }
                    }
                }
                
                HStack(alignment: .center, spacing: 4) {
                    Text("in")
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                    
                    Text(state.resolvedOutputDirectory(for: .videosOnly)?.path ?? "Choose Folder...")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .onTapGesture {
                            chooseVideoCustomFolder()
                        }
                }
            }
            .padding(.vertical, 4)
            
            // 4. Shrink Button (consistent prominent style)
            Button(action: { state.startShrinking(filter: .videosOnly) }) {
                HStack {
                    Spacer()
                    Text("Shrink")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(.blue)
            .disabled(state.isProcessing || !state.aggregateDetectedTypes.contains(.video))
            .padding(.top, 8)
        }
    }
    
    private var audioCompressorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Options
            Picker("Format", selection: $state.audioSettings.format) {
                Text("M4A (AAC)").tag("M4A")
            }
            
            Picker("Bitrate", selection: $state.audioSettings.bitrate) {
                Text("64 kbps (Low)").tag(64000)
                Text("128 kbps (Normal)").tag(128000)
                Text("192 kbps (High)").tag(192000)
                Text("256 kbps (Ultra)").tag(256000)
            }
            
            // 2. Destination options above the button
            Divider()
                .padding(.vertical, 4)
            
            // Destination options (sentence layout)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 4) {
                    Menu {
                        Button("Separate Files") {
                            state.audioOutputStyle = .individual
                            editingAudioName = false
                        }
                        Button("Folder") {
                            state.audioOutputStyle = .subfolder
                        }
                        Button("Archive") {
                            state.audioOutputStyle = .archive
                        }
                    } label: {
                        Text("Creating")
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    
                    if state.audioOutputStyle == .individual {
                        Menu {
                            Button("Separate Files") {
                                state.audioOutputStyle = .individual
                                editingAudioName = false
                            }
                            Button("Folder") {
                                state.audioOutputStyle = .subfolder
                            }
                            Button("Archive") {
                                state.audioOutputStyle = .archive
                            }
                        } label: {
                            Text("separate files")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                    } else {
                        if editingAudioName {
                            TextField("", text: $state.audioCustomOutputName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)
                                .onSubmit {
                                    editingAudioName = false
                                }
                                .frame(maxWidth: 150)
                        } else {
                            Text(state.audioCustomOutputName.isEmpty ? "Audio" : state.audioCustomOutputName)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)
                                .onTapGesture {
                                    editingAudioName = true
                                }
                        }
                        
                        if state.audioOutputStyle == .archive {
                            Text("as")
                                .font(.system(size: 11))
                                .foregroundStyle(.primary)
                            
                            Menu {
                                Button("ZIP") { state.audioArchiveFormat = .zip }
                                Button("TAR") { state.audioArchiveFormat = .tar }
                                Button("TAR.GZ") { state.audioArchiveFormat = .tgz }
                                if isSevenZipAvailable {
                                    Button("7-Zip") { state.audioArchiveFormat = .sevenZip }
                                }
                            } label: {
                                Text(state.audioArchiveFormat.rawValue.uppercased())
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.blue)
                            }
                            .menuStyle(.button)
                            .buttonStyle(.plain)
                        } else if state.audioOutputStyle == .subfolder {
                            Text("folder")
                                .font(.system(size: 11))
                                .foregroundStyle(.primary)
                        }
                    }
                }
                
                if state.audioOutputStyle == .individual {
                    HStack(alignment: .center, spacing: 4) {
                        Text("with suffix")
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                        
                        if editingAudioSuffix {
                            TextField("", text: $state.audioCustomSuffix)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)
                                .onSubmit {
                                    editingAudioSuffix = false
                                }
                                .frame(maxWidth: 80)
                        } else {
                            Text(state.audioCustomSuffix.isEmpty ? "\"none\"" : "\"\(state.audioCustomSuffix)\"")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)
                                .onTapGesture {
                                    editingAudioSuffix = true
                                }
                        }
                    }
                }
                
                HStack(alignment: .center, spacing: 4) {
                    Text("in")
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                    
                    Text(state.resolvedOutputDirectory(for: .audioOnly)?.path ?? "Choose Folder...")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .onTapGesture {
                            chooseAudioCustomFolder()
                        }
                }
            }
            .padding(.vertical, 4)
            
            // 3. Shrink Button (consistent prominent style)
            Button(action: { state.startShrinking(filter: .audioOnly) }) {
                HStack {
                    Spacer()
                    Text("Shrink")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(.blue)
            .disabled(state.isProcessing || !state.aggregateDetectedTypes.contains(.audio))
            .padding(.top, 8)
        }
    }
    
    private var pdfCompressorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Settings / Toggle
            Toggle("Optimize PDF Documents", isOn: $state.pdfSettings.compressEnabled)
                .font(.system(size: 12, weight: .semibold))
                
            if state.pdfSettings.compressEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PDF Optimization")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    
                    Text("Standard PDF Size Reduction")
                        .font(.system(size: 12, weight: .semibold))
                    
                    Text("Shrink will re-process fonts, optimize internal resource tables, and compress embedded graphic streams using native PDFKit routines.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
                .padding(.leading, 16)
            }
            
            Divider()
                .padding(.vertical, 4)
            
            // Destination options (sentence layout)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 4) {
                    Menu {
                        Button("Separate Files") {
                            state.pdfOutputStyle = .individual
                            editingPdfName = false
                        }
                        Button("Folder") {
                            state.pdfOutputStyle = .subfolder
                        }
                        Button("Archive") {
                            state.pdfOutputStyle = .archive
                        }
                    } label: {
                        Text("Creating")
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    
                    if state.pdfOutputStyle == .individual {
                        Menu {
                            Button("Separate Files") {
                                state.pdfOutputStyle = .individual
                                editingPdfName = false
                            }
                            Button("Folder") {
                                state.pdfOutputStyle = .subfolder
                            }
                            Button("Archive") {
                                state.pdfOutputStyle = .archive
                            }
                        } label: {
                            Text("separate files")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                    } else {
                        if editingPdfName {
                            TextField("", text: $state.pdfCustomOutputName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)
                                .onSubmit {
                                    editingPdfName = false
                                }
                                .frame(maxWidth: 150)
                        } else {
                            Text(state.pdfCustomOutputName.isEmpty ? "PDFs" : state.pdfCustomOutputName)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)
                                .onTapGesture {
                                    editingPdfName = true
                                }
                        }
                        
                        if state.pdfOutputStyle == .archive {
                            Text("as")
                                .font(.system(size: 11))
                                .foregroundStyle(.primary)
                            
                            Menu {
                                Button("ZIP") { state.pdfArchiveFormat = .zip }
                                Button("TAR") { state.pdfArchiveFormat = .tar }
                                Button("TAR.GZ") { state.pdfArchiveFormat = .tgz }
                                if isSevenZipAvailable {
                                    Button("7-Zip") { state.pdfArchiveFormat = .sevenZip }
                                }
                            } label: {
                                Text(state.pdfArchiveFormat.rawValue.uppercased())
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.blue)
                            }
                            .menuStyle(.button)
                            .buttonStyle(.plain)
                        } else if state.pdfOutputStyle == .subfolder {
                            Text("folder")
                                .font(.system(size: 11))
                                .foregroundStyle(.primary)
                        }
                    }
                }
                
                if state.pdfOutputStyle == .individual {
                    HStack(alignment: .center, spacing: 4) {
                        Text("with suffix")
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                        
                        if editingPdfSuffix {
                            TextField("", text: $state.pdfCustomSuffix)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)
                                .onSubmit {
                                    editingPdfSuffix = false
                                }
                                .frame(maxWidth: 80)
                        } else {
                            Text(state.pdfCustomSuffix.isEmpty ? "\"none\"" : "\"\(state.pdfCustomSuffix)\"")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)
                                .onTapGesture {
                                    editingPdfSuffix = true
                                }
                        }
                    }
                }
                
                HStack(alignment: .center, spacing: 4) {
                    Text("in")
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                    
                    Text(state.resolvedOutputDirectory(for: .pdfOnly)?.path ?? "Choose Folder...")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .onTapGesture {
                            choosePdfFolder()
                        }
                }
            }
            .padding(.vertical, 4)
            
            // 3. Shrink Button (at the bottom)
            Button(action: { state.startShrinking(filter: .pdfOnly) }) {
                HStack {
                    Spacer()
                    Text("Shrink")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(.blue)
            .disabled(state.isProcessing || !state.aggregateDetectedTypes.contains(.pdf))
            .padding(.top, 8)
        }
        .padding(.vertical, 6)
    }
    
    private var archiveCompressorPanel: some View {
        GroupBox(label: Label("Archive Compression", systemImage: "archivebox.fill").font(.system(size: 11, weight: .semibold))) {
            VStack(alignment: .leading, spacing: 12) {
                // Format Selection
                Picker("Format", selection: $state.archiveSettings.format) {
                    Text("ZIP").tag(ArchiveFormat.zip)
                    Text("TAR").tag(ArchiveFormat.tar)
                    Text("TAR.GZ (tgz)").tag(ArchiveFormat.tgz)
                    
                    if isSevenZipAvailable {
                        Text("7-Zip (7z)").tag(ArchiveFormat.sevenZip)
                    } else {
                        Text("7-Zip (7z) [Unavailable]").tag(ArchiveFormat.sevenZip)
                    }
                    

                }
                
                // Warning if format chosen but not available
                if state.archiveSettings.format == .sevenZip && !isSevenZipAvailable {
                    Text("⚠️ 7-Zip CLI not found. Install it via Homebrew to enable ('brew install p7zip').")
                        .font(.system(size: 9))
                        .foregroundColor(.red)
                }
                
                // Password Encryption
                Toggle("Encrypt with Password", isOn: $state.archiveSettings.passwordEnabled)
                
                if state.archiveSettings.passwordEnabled {
                    SecureField("Password", text: $state.archiveSettings.password)
                        .textFieldStyle(.roundedBorder)
                }
                
                // Split Archives
                Toggle("Split Archive", isOn: $state.archiveSettings.splitArchive)
                
                if state.archiveSettings.splitArchive {
                    Picker("Part Size", selection: $state.archiveSettings.splitSize) {
                        Text("10 MB").tag(Int64(10 * 1024 * 1024))
                        Text("50 MB").tag(Int64(50 * 1024 * 1024))
                        Text("100 MB").tag(Int64(100 * 1024 * 1024))
                        Text("500 MB").tag(Int64(500 * 1024 * 1024))
                        Text("1 GB").tag(Int64(1024 * 1024 * 1024))
                    }
                }
                
                // Compression level
                if state.archiveSettings.format != .tar {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Level")
                            Spacer()
                            Text(compressionLevelLabel(state.archiveSettings.compressionLevel))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(state.archiveSettings.compressionLevel) },
                            set: { state.archiveSettings.compressionLevel = Int($0) }
                        ), in: 0...9, step: 1)
                        
                        HStack {
                            Text("Fastest")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Most Compressed")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }
    
    // MARK: - Decompression Settings Panel
    
    private var decompressionSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Extraction Options")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            
            Toggle("Extract into subfolder", isOn: $state.decompressSettings.createSubfolder)
            
            Toggle("Overwrite existing files", isOn: $state.decompressSettings.overwriteExisting)
            
            Toggle("Archive requires password", isOn: $state.decompressSettings.passwordEnabled)
            
            if state.decompressSettings.passwordEnabled {
                SecureField("Password", text: $state.decompressSettings.password)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(.vertical, 6)
    }
    
    // MARK: - Helper Methods
    
    private func chooseCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        
        if panel.runModal() == .OK, let folder = panel.url {
            state.customOutputFolder = folder
            state.outputLocationType = .custom
        }
    }
    
    private func chooseImageCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        
        if panel.runModal() == .OK, let folder = panel.url {
            state.imageCustomOutputFolder = folder
            state.imageOutputLocationType = .custom
        }
    }
    
    private func chooseVideoCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        
        if panel.runModal() == .OK, let folder = panel.url {
            state.videoCustomOutputFolder = folder
            state.videoOutputLocationType = .custom
        }
    }
    
    private func chooseConvertCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        
        if panel.runModal() == .OK, let folder = panel.url {
            state.convertCustomOutputFolder = folder
            state.convertOutputLocationType = .custom
        }
    }
    
    private func chooseAudioCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        
        if panel.runModal() == .OK, let folder = panel.url {
            state.audioCustomOutputFolder = folder
            state.audioOutputLocationType = .custom
        }
    }
    
    private func choosePdfFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        
        if panel.runModal() == .OK, let folder = panel.url {
            state.pdfCustomOutputFolder = folder
            state.pdfOutputLocationType = .custom
        }
    }
    
    private func compressionLevelLabel(_ val: Int) -> String {
        switch val {
        case 0: return "Store"
        case 1...2: return "Fastest"
        case 3...4: return "Fast"
        case 5...6: return "Balanced"
        case 7...8: return "Maximum"
        case 9: return "Ultra"
        default: return "Normal"
        }
    }
    
    // MARK: - Dynamic Resolution Helpers
    
    private var maxOriginalResolution: CGSize? {
        if let singleFile = activeSingleFile, !singleFile.isDirectory, singleFile.fileType == .video {
            if let w = singleFile.width, let h = singleFile.height {
                return CGSize(width: w, height: h)
            }
        }
        
        // Fallback to checking checked files
        var maxW = 0
        var maxH = 0
        for file in state.selectedFiles {
            if file.isChecked, let w = file.width, let h = file.height {
                if w > maxW {
                    maxW = w
                    maxH = h
                }
            }
        }
        return maxW > 0 ? CGSize(width: maxW, height: maxH) : nil
    }
    
    private var originalResolutionLabel: String {
        if let original = maxOriginalResolution {
            return "Original (\(Int(original.width))x\(Int(original.height)))"
        } else {
            return "Original"
        }
    }
    
    private var activeSingleFile: FileItem? {
        if let selectedID = state.selectedFileID,
           let file = state.findFile(id: selectedID) {
            return file
        }
        
        // Collect all checked leaf files recursively
        let checked = collectCheckedLeafFilesRecursive(in: state.selectedFiles)
        if checked.count == 1 {
            return checked.first
        } else if checked.count > 1 {
            return nil
        }
        
        let allFiles = collectAllLeafFilesRecursive(in: state.selectedFiles)
        return allFiles.count == 1 ? allFiles.first : nil
    }
    
    private func collectCheckedLeafFilesRecursive(in list: [FileItem]) -> [FileItem] {
        var files: [FileItem] = []
        for item in list {
            if item.isChecked {
                if !item.isDirectory {
                    files.append(item)
                } else {
                    files.append(contentsOf: collectCheckedLeafFilesRecursive(in: item.subItems))
                }
            }
        }
        return files
    }
    
    private func collectAllLeafFilesRecursive(in list: [FileItem]) -> [FileItem] {
        var files: [FileItem] = []
        for item in list {
            if !item.isDirectory {
                files.append(item)
            } else {
                files.append(contentsOf: collectAllLeafFilesRecursive(in: item.subItems))
            }
        }
        return files
    }
    
    private var imageTargetSizeMbBinding: Binding<Double> {
        Binding(
            get: {
                guard let singleFile = activeSingleFile, !singleFile.isDirectory, singleFile.fileType == .image else { return 0.0 }
                let originalMb = Double(singleFile.originalSize) / (1024 * 1024)
                return state.imageSettings.targetSizeRatio * originalMb
            },
            set: { val in
                guard let singleFile = activeSingleFile, !singleFile.isDirectory, singleFile.fileType == .image else { return }
                let originalMb = Double(singleFile.originalSize) / (1024 * 1024)
                if originalMb > 0 {
                    state.imageSettings.targetSizeRatio = max(0.05, min(1.0, val / originalMb))
                }
            }
        )
    }
    
    private var videoTargetSizeMbBinding: Binding<Double> {
        Binding(
            get: {
                guard let singleFile = activeSingleFile, !singleFile.isDirectory, singleFile.fileType == .video else { return 0.0 }
                let originalMb = Double(singleFile.originalSize) / (1024 * 1024)
                return state.videoSettings.targetSizeRatio * originalMb
            },
            set: { val in
                guard let singleFile = activeSingleFile, !singleFile.isDirectory, singleFile.fileType == .video else { return }
                let originalMb = Double(singleFile.originalSize) / (1024 * 1024)
                if originalMb > 0 {
                    state.videoSettings.targetSizeRatio = max(0.05, min(1.0, val / originalMb))
                }
            }
        )
    }
    
    private var videoResolutionSelectionBinding: Binding<String> {
        Binding(
            get: {
                if let w = state.videoSettings.targetResolutionWidth, let h = state.videoSettings.targetResolutionHeight {
                    return "\(w)x\(h)"
                }
                return "original"
            },
            set: { val in
                if val == "original" {
                    state.videoSettings.targetResolutionWidth = nil
                    state.videoSettings.targetResolutionHeight = nil
                } else {
                    let parts = val.split(separator: "x")
                    if parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) {
                        state.videoSettings.targetResolutionWidth = w
                        state.videoSettings.targetResolutionHeight = h
                    }
                }
            }
        )
    }
    
    private var imageResolutionSelectionBinding: Binding<String> {
        Binding(
            get: {
                if let w = state.imageSettings.targetResolutionWidth, let h = state.imageSettings.targetResolutionHeight {
                    return "\(w)x\(h)"
                }
                return "original"
            },
            set: { val in
                if val == "original" {
                    state.imageSettings.targetResolutionWidth = nil
                    state.imageSettings.targetResolutionHeight = nil
                } else {
                    let parts = val.split(separator: "x")
                    if parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) {
                        state.imageSettings.targetResolutionWidth = w
                        state.imageSettings.targetResolutionHeight = h
                    }
                }
            }
        )
    }
    // MARK: - Individual UI Items & Custom Cascading Bindings
    
    private struct IndividualMediaUIItem: Identifiable {
        let id: UUID
        let name: String
        let currentMb: Double
        let minMb: Double
        let maxMb: Double
        let binding: Binding<Double>
        let bitrateBinding: Binding<Double>
        let resolutionBinding: Binding<String>
        let audioModeBinding: Binding<String>
        let audioBitrateBinding: Binding<Int>
        let originalSize: Int64
        let duration: Double?
        
        var estimatedOriginalBitrateMbps: Double? {
            guard let duration = duration, duration > 0 else { return nil }
            return Double(originalSize * 8) / (duration * 1000000.0)
        }
    }
    
    private func getIndividualMediaItems(type: FileType) -> [IndividualMediaUIItem] {
        // 1. If a folder is selected recursively
        if let selectedID = state.selectedFileID,
           let folderItem = state.findFile(id: selectedID),
           folderItem.isDirectory {
            var items: [IndividualMediaUIItem] = []
            let folderId = folderItem.id
            let folderDuration = folderItem.duration
            for subItem in folderItem.subMediaItems {
                if subItem.fileType == type {
                    let originalMb = max(0.01, Double(subItem.originalSize) / (1024 * 1024))
                    let binding = Binding<Double>(
                        get: {
                            subItem.targetSizeRatio * originalMb
                        },
                        set: { newMb in
                            let ratio = max(0.05, min(1.0, newMb / originalMb))
                            state.updateSubMediaItem(folderId: folderId, subItemId: subItem.id) { sub in
                                sub.targetSizeRatio = ratio
                                sub.isManuallyAdjusted = true
                                
                                if type == .video {
                                    let duration = folderDuration ?? 30.0
                                    let audioBitrate = Double(sub.customAudioBitrate ?? state.videoSettings.audioBitrate)
                                    let audioMode = sub.customAudioMode ?? state.videoSettings.audioMode
                                    let audioBytes = (audioMode == "Mute" ? 0.0 : audioBitrate / 8.0) * duration
                                    let targetSizeBytes = Double(sub.originalSize) * ratio
                                    let videoBytes = max(targetSizeBytes - audioBytes, targetSizeBytes * 0.15)
                                    let kbps = Int((videoBytes * 8.0) / (duration * 1000.0))
                                    sub.customTargetBitrateKbps = max(200, min(kbps, 100000))
                                }
                            }
                        }
                    )
                    
                    let bitrateBinding = Binding<Double>(
                        get: {
                            Double(subItem.customTargetBitrateKbps ?? state.videoSettings.targetBitrateKbps)
                        },
                        set: { newKbps in
                            let kbps = Int(newKbps)
                            state.updateSubMediaItem(folderId: folderId, subItemId: subItem.id) { sub in
                                sub.customTargetBitrateKbps = kbps
                                sub.customCompressionMethod = .bitrate
                                
                                let duration = folderDuration ?? 30.0
                                let originalSize = Double(sub.originalSize)
                                let audioBitrate = Double(sub.customAudioBitrate ?? state.videoSettings.audioBitrate)
                                let audioMode = sub.customAudioMode ?? state.videoSettings.audioMode
                                let audioBytes = (audioMode == "Mute" ? 0.0 : audioBitrate / 8.0) * duration
                                let videoBytes = (Double(kbps * 1000) / 8.0) * duration
                                let totalBytes = videoBytes + audioBytes
                                sub.targetSizeRatio = max(0.05, min(1.0, totalBytes / originalSize))
                            }
                        }
                    )
                    
                    let resolutionBinding = Binding<String>(
                        get: {
                            if let customW = subItem.customResolutionWidth, let customH = subItem.customResolutionHeight {
                                return "\(customW)x\(customH)"
                            }
                            return "original"
                        },
                        set: { val in
                            state.updateSubMediaItem(folderId: folderId, subItemId: subItem.id) { sub in
                                if val == "original" {
                                    sub.customResolutionWidth = nil
                                    sub.customResolutionHeight = nil
                                } else {
                                    let parts = val.split(separator: "x")
                                    if parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) {
                                        sub.customResolutionWidth = w
                                        sub.customResolutionHeight = h
                                    }
                                }
                            }
                        }
                    )
                    
                    let audioModeBinding = Binding<String>(
                        get: {
                            subItem.customAudioMode ?? "Compress"
                        },
                        set: { val in
                            state.updateSubMediaItem(folderId: folderId, subItemId: subItem.id) { sub in
                                sub.customAudioMode = val
                            }
                        }
                    )
                    
                    let audioBitrateBinding = Binding<Int>(
                        get: {
                            subItem.customAudioBitrate ?? 128000
                        },
                        set: { val in
                            state.updateSubMediaItem(folderId: folderId, subItemId: subItem.id) { sub in
                                sub.customAudioBitrate = val
                            }
                        }
                    )
                    
                    let minMb = 0.05 * originalMb
                    let maxMb = max(minMb + 0.01, originalMb)
                    items.append(IndividualMediaUIItem(
                        id: subItem.id,
                        name: subItem.name,
                        currentMb: subItem.targetSizeRatio * originalMb,
                        minMb: minMb,
                        maxMb: maxMb,
                        binding: binding,
                        bitrateBinding: bitrateBinding,
                        resolutionBinding: resolutionBinding,
                        audioModeBinding: audioModeBinding,
                        audioBitrateBinding: audioBitrateBinding,
                        originalSize: subItem.originalSize,
                        duration: folderDuration
                    ))
                }
            }
            return items
        } else {
            // 2. Otherwise, look at all checked files of this type recursively
            return collectAllIndividualMediaItems(in: state.selectedFiles, type: type)
        }
    }
    
    private func collectAllIndividualMediaItems(in list: [FileItem], type: FileType) -> [IndividualMediaUIItem] {
        var items: [IndividualMediaUIItem] = []
        for item in list {
            guard item.isChecked else { continue }
            if !item.isDirectory {
                if item.fileType == type {
                    let originalMb = max(0.01, Double(item.originalSize) / (1024 * 1024))
                    let binding = Binding<Double>(
                        get: {
                            let ratio = item.customTargetSizeRatio ?? (type == .image ? state.imageSettings.targetSizeRatio : state.videoSettings.targetSizeRatio)
                            return ratio * originalMb
                        },
                        set: { newMb in
                            let ratio = max(0.05, min(1.0, newMb / originalMb))
                            state.updateFileItem(id: item.id) { file in
                                file.customTargetSizeRatio = ratio
                                file.isManuallyAdjusted = true
                                
                                if type == .video {
                                    let duration = item.duration ?? 30.0
                                    let audioBitrate = Double(file.customAudioBitrate ?? state.videoSettings.audioBitrate)
                                    let audioMode = file.customAudioMode ?? state.videoSettings.audioMode
                                    let audioBytes = (audioMode == "Mute" ? 0.0 : audioBitrate / 8.0) * duration
                                    let targetSizeBytes = Double(file.originalSize) * ratio
                                    let videoBytes = max(targetSizeBytes - audioBytes, targetSizeBytes * 0.15)
                                    let kbps = Int((videoBytes * 8.0) / (duration * 1000.0))
                                    file.customTargetBitrateKbps = max(200, min(kbps, 100000))
                                }
                            }
                        }
                    )
                    
                    let bitrateBinding = Binding<Double>(
                        get: {
                            Double(item.customTargetBitrateKbps ?? state.videoSettings.targetBitrateKbps)
                        },
                        set: { newKbps in
                            let kbps = Int(newKbps)
                            state.updateFileItem(id: item.id) { file in
                                file.customTargetBitrateKbps = kbps
                                file.customCompressionMethod = .bitrate
                                
                                let duration = file.duration ?? 30.0
                                let originalSize = Double(file.originalSize)
                                let audioBitrate = Double(file.customAudioBitrate ?? state.videoSettings.audioBitrate)
                                let audioMode = file.customAudioMode ?? state.videoSettings.audioMode
                                let audioBytes = (audioMode == "Mute" ? 0.0 : audioBitrate / 8.0) * duration
                                let videoBytes = (Double(kbps * 1000) / 8.0) * duration
                                let totalBytes = videoBytes + audioBytes
                                file.customTargetSizeRatio = max(0.05, min(1.0, totalBytes / originalSize))
                            }
                        }
                    )
                    
                    let resolutionBinding = Binding<String>(
                        get: {
                            if let customW = item.customResolutionWidth, let customH = item.customResolutionHeight {
                                return "\(customW)x\(customH)"
                            }
                            return "original"
                        },
                        set: { val in
                            state.updateFileItem(id: item.id) { file in
                                if val == "original" {
                                    file.customResolutionWidth = nil
                                    file.customResolutionHeight = nil
                                } else {
                                    let parts = val.split(separator: "x")
                                    if parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) {
                                        file.customResolutionWidth = w
                                        file.customResolutionHeight = h
                                    }
                                }
                            }
                        }
                    )
                    
                    let audioModeBinding = Binding<String>(
                        get: {
                            item.customAudioMode ?? "Compress"
                        },
                        set: { val in
                            state.updateFileItem(id: item.id) { file in
                                file.customAudioMode = val
                            }
                        }
                    )
                    
                    let audioBitrateBinding = Binding<Int>(
                        get: {
                            item.customAudioBitrate ?? 128000
                        },
                        set: { val in
                            state.updateFileItem(id: item.id) { file in
                                file.customAudioBitrate = val
                            }
                        }
                    )
                    
                    let minMb = 0.05 * originalMb
                    let maxMb = max(minMb + 0.01, originalMb)
                    
                    items.append(IndividualMediaUIItem(
                        id: item.id,
                        name: item.name,
                        currentMb: (item.customTargetSizeRatio ?? (type == .image ? state.imageSettings.targetSizeRatio : state.videoSettings.targetSizeRatio)) * originalMb,
                        minMb: minMb,
                        maxMb: maxMb,
                        binding: binding,
                        bitrateBinding: bitrateBinding,
                        resolutionBinding: resolutionBinding,
                        audioModeBinding: audioModeBinding,
                        audioBitrateBinding: audioBitrateBinding,
                        originalSize: item.originalSize,
                        duration: item.duration
                    ))
                }
            } else {
                if item.subItems.isEmpty {
                    // Unexpanded folder: collect from its flat subMediaItems list
                    let folderId = item.id
                    let folderDuration = item.duration
                    for subItem in item.subMediaItems {
                        if subItem.fileType == type {
                            let originalMb = max(0.01, Double(subItem.originalSize) / (1024 * 1024))
                            let binding = Binding<Double>(
                                get: {
                                    subItem.targetSizeRatio * originalMb
                                },
                                set: { newMb in
                                    let ratio = max(0.05, min(1.0, newMb / originalMb))
                                    state.updateSubMediaItem(folderId: folderId, subItemId: subItem.id) { sub in
                                        sub.targetSizeRatio = ratio
                                        sub.isManuallyAdjusted = true
                                        
                                        if type == .video {
                                            let duration = folderDuration ?? 30.0
                                            let audioBitrate = Double(sub.customAudioBitrate ?? state.videoSettings.audioBitrate)
                                            let audioMode = sub.customAudioMode ?? state.videoSettings.audioMode
                                            let audioBytes = (audioMode == "Mute" ? 0.0 : audioBitrate / 8.0) * duration
                                            let targetSizeBytes = Double(sub.originalSize) * ratio
                                            let videoBytes = max(targetSizeBytes - audioBytes, targetSizeBytes * 0.15)
                                            let kbps = Int((videoBytes * 8.0) / (duration * 1000.0))
                                            sub.customTargetBitrateKbps = max(200, min(kbps, 100000))
                                        }
                                    }
                                }
                            )
                            
                            let bitrateBinding = Binding<Double>(
                                get: {
                                    Double(subItem.customTargetBitrateKbps ?? state.videoSettings.targetBitrateKbps)
                                },
                                set: { newKbps in
                                    let kbps = Int(newKbps)
                                    state.updateSubMediaItem(folderId: folderId, subItemId: subItem.id) { sub in
                                        sub.customTargetBitrateKbps = kbps
                                        sub.customCompressionMethod = .bitrate
                                        
                                        let duration = folderDuration ?? 30.0
                                        let originalSize = Double(sub.originalSize)
                                        let audioBitrate = Double(sub.customAudioBitrate ?? state.videoSettings.audioBitrate)
                                        let audioMode = sub.customAudioMode ?? state.videoSettings.audioMode
                                        let audioBytes = (audioMode == "Mute" ? 0.0 : audioBitrate / 8.0) * duration
                                        let videoBytes = (Double(kbps * 1000) / 8.0) * duration
                                        let totalBytes = videoBytes + audioBytes
                                        sub.targetSizeRatio = max(0.05, min(1.0, totalBytes / originalSize))
                                    }
                                }
                            )
                            
                            let resolutionBinding = Binding<String>(
                                get: {
                                    if let customW = subItem.customResolutionWidth, let customH = subItem.customResolutionHeight {
                                        return "\(customW)x\(customH)"
                                    }
                                    return "original"
                                },
                                set: { val in
                                    state.updateSubMediaItem(folderId: folderId, subItemId: subItem.id) { sub in
                                        if val == "original" {
                                            sub.customResolutionWidth = nil
                                            sub.customResolutionHeight = nil
                                        } else {
                                            let parts = val.split(separator: "x")
                                            if parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) {
                                                sub.customResolutionWidth = w
                                                sub.customResolutionHeight = h
                                            }
                                        }
                                    }
                                }
                            )
                            
                            let audioModeBinding = Binding<String>(
                                get: {
                                    subItem.customAudioMode ?? "Compress"
                                },
                                set: { val in
                                    state.updateSubMediaItem(folderId: folderId, subItemId: subItem.id) { sub in
                                        sub.customAudioMode = val
                                    }
                                }
                            )
                            
                            let audioBitrateBinding = Binding<Int>(
                                get: {
                                    subItem.customAudioBitrate ?? 128000
                                },
                                set: { val in
                                    state.updateSubMediaItem(folderId: folderId, subItemId: subItem.id) { sub in
                                        sub.customAudioBitrate = val
                                    }
                                }
                            )
                            
                            let minMb = 0.05 * originalMb
                            let maxMb = max(minMb + 0.01, originalMb)
                            
                            items.append(IndividualMediaUIItem(
                                id: subItem.id,
                                name: subItem.name,
                                currentMb: subItem.targetSizeRatio * originalMb,
                                minMb: minMb,
                                maxMb: maxMb,
                                binding: binding,
                                bitrateBinding: bitrateBinding,
                                resolutionBinding: resolutionBinding,
                                audioModeBinding: audioModeBinding,
                                audioBitrateBinding: audioBitrateBinding,
                                originalSize: subItem.originalSize,
                                duration: folderDuration
                            ))
                        }
                    }
                } else {
                    // Expanded folder: recurse into subItems
                    items.append(contentsOf: collectAllIndividualMediaItems(in: item.subItems, type: type))
                }
            }
        }
        return items
    }
    
    private func collectAllCheckedFilesRecursive(in list: [FileItem], type: FileType) -> [FileItem] {
        var files: [FileItem] = []
        for item in list {
            if item.isChecked {
                if !item.isDirectory {
                    if item.fileType == type {
                        files.append(item)
                    }
                } else {
                    files.append(contentsOf: collectAllCheckedFilesRecursive(in: item.subItems, type: type))
                }
            }
        }
        return files
    }
    
    private var estimatedVideoBitrateSize: Int64 {
        let checkedVideos = state.selectedFiles.filter { $0.isChecked && $0.fileType == .video }
        var totalDuration = 0.0
        var totalAudioBytes = 0.0
        for item in checkedVideos {
            let dur = item.duration ?? 30.0
            totalDuration += dur
            let audioBitrate = Double(item.customAudioBitrate ?? state.videoSettings.audioBitrate)
            let audioMode = item.customAudioMode ?? state.videoSettings.audioMode
            let audioBytes = (audioMode == "Mute" ? 0.0 : audioBitrate / 8.0) * dur
            totalAudioBytes += audioBytes
        }
        let estVideoBytes = (Double(state.videoSettings.targetBitrateKbps * 1000) / 8.0) * totalDuration
        return Int64(estVideoBytes + totalAudioBytes)
    }
    
    private var overallImageCompressionBinding: Binding<Double> {
        Binding(
            get: {
                state.imageSettings.targetSizeRatio
            },
            set: { newValue in
                state.cascadeImageSettings(ratio: newValue)
            }
        )
    }
    
    private var overallVideoCompressionBinding: Binding<Double> {
        Binding(
            get: {
                state.videoSettings.targetSizeRatio
            },
            set: { newValue in
                state.cascadeVideoSettings(ratio: newValue)
            }
        )
    }
    
    private var overallVideoBitrateBinding: Binding<Double> {
        Binding(
            get: {
                Double(state.videoSettings.targetBitrateKbps)
            },
            set: { newValue in
                state.cascadeVideoBitrateSettings(kbps: Int(newValue))
            }
        )
    }
    
    private var conversionSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let singleFile = activeSingleFile {
                if singleFile.isDirectory {
                    let extensions = Array(singleFile.extensionCounts.keys).sorted()
                    if extensions.isEmpty {
                        Text("No files inside folder to convert.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Convert by file type in folder:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            
                            ForEach(extensions, id: \.self) { ext in
                                let count = singleFile.extensionCounts[ext] ?? 0
                                let targetOptions = FileConverter.enabledTargetFormats(forExtension: ext)
                                
                                if !targetOptions.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(".\(ext.uppercased()) files (\(count))")
                                                .font(.system(size: 11, weight: .medium))
                                            Spacer()
                                        }
                                        
                                        let selectedFormat = folderConvertTargets[ext] ?? targetOptions.first ?? ""
                                        
                                        HStack(spacing: 8) {
                                            Picker("", selection: Binding(
                                                get: { selectedFormat },
                                                set: { folderConvertTargets[ext] = $0 }
                                            )) {
                                                ForEach(targetOptions, id: \.self) { opt in
                                                    Text(opt.uppercased()).tag(opt)
                                                }
                                            }
                                            .pickerStyle(.menu)
                                            .labelsHidden()
                                            .controlSize(.small)
                                            .frame(maxWidth: .infinity)
                                            
                                            let tool = FileConverter.toolRequired(from: ext, to: selectedFormat)
                                            let isAvailable = tool == nil ? true : ExternalToolManager.isToolAvailable(tool!)
                                            
                                            if isAvailable {
                                                Button("Convert") {
                                                    state.convertFolderFiles(in: singleFile, sourceExtension: ext, targetFormat: selectedFormat)
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.small)
                                                .tint(.blue)
                                                .disabled(state.isProcessing)
                                            } else if let t = tool {
                                                if state.installingTool == t.name {
                                                    HStack(spacing: 4) {
                                                        ProgressView().controlSize(.small)
                                                        Text("Installing...")
                                                            .font(.system(size: 9))
                                                    }
                                                } else {
                                                    Button("Install \(t.name)") {
                                                        Task {
                                                            await state.installTool(t)
                                                        }
                                                    }
                                                    .buttonStyle(.bordered)
                                                    .controlSize(.small)
                                                    .tint(.blue)
                                                }
                                            }
                                        }
                                    }
                                    Divider()
                                }
                            }
                            
                            convertDestinationSettingsBlock
                        }
                    }
                } else {
                    let ext = singleFile.url.pathExtension
                    let targetOptions = FileConverter.enabledTargetFormats(forExtension: ext)
                    
                    if targetOptions.isEmpty {
                        Text("No conversions available for .\(ext.uppercased())")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Current format:")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(ext.uppercased())
                                    .font(.system(size: 11, weight: .bold))
                            }
                            
                            let selectedFormat = singleFile.targetConvertFormat ?? targetOptions.first ?? ""
                            
                            Picker("Convert to:", selection: Binding(
                                get: { selectedFormat },
                                set: { newFormat in
                                    if let idx = state.selectedFiles.firstIndex(where: { $0.id == singleFile.id }) {
                                        state.selectedFiles[idx].targetConvertFormat = newFormat
                                    }
                                }
                            )) {
                                ForEach(targetOptions, id: \.self) { opt in
                                    Text(opt.uppercased()).tag(opt)
                                }
                            }
                            .pickerStyle(.menu)
                            
                            let tool = FileConverter.toolRequired(from: ext, to: selectedFormat)
                            let isAvailable = tool == nil ? true : ExternalToolManager.isToolAvailable(tool!)
                            
                            if !isAvailable, let t = tool {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("⚠️ Requires \(t.name) to convert.")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.red)
                                    
                                    if state.installingTool == t.name {
                                        HStack(spacing: 4) {
                                            ProgressView().controlSize(.small)
                                            Text(state.installProgressText)
                                                .font(.system(size: 9))
                                        }
                                    } else {
                                        Button("Install \(t.name) via Homebrew") {
                                            Task {
                                                await state.installTool(t)
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                }
                            }
                            
                            Divider()
                                .padding(.vertical, 4)
                            
                            convertDestinationSettingsBlock
                            
                            Button(action: {
                                state.convertFileItem(singleFile, targetFormat: selectedFormat)
                            }) {
                                HStack {
                                    Spacer()
                                    Text("Convert")
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                            .tint(.blue)
                            .disabled(state.isProcessing || !isAvailable)
                            .padding(.top, 8)
                        }
                    }
                }
            } else {
                Text("Select a file/folder to convert formats.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
    
    @ViewBuilder
    private var convertDestinationSettingsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 4) {
                Menu {
                    Button("Separate Files") {
                        state.convertOutputStyle = .individual
                        editingConvertName = false
                    }
                    Button("Folder") {
                        state.convertOutputStyle = .subfolder
                    }
                    Button("Archive") {
                        state.convertOutputStyle = .archive
                    }
                } label: {
                    Text("Creating")
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                
                if state.convertOutputStyle == .individual {
                    Menu {
                        Button("Separate Files") {
                            state.convertOutputStyle = .individual
                            editingConvertName = false
                        }
                        Button("Folder") {
                            state.convertOutputStyle = .subfolder
                        }
                        Button("Archive") {
                            state.convertOutputStyle = .archive
                        }
                    } label: {
                        Text("converted files")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.blue)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                } else {
                    if editingConvertName {
                        TextField("", text: $state.convertCustomOutputName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.blue)
                            .onSubmit {
                                editingConvertName = false
                            }
                            .frame(maxWidth: 150)
                    } else {
                        Text(state.convertCustomOutputName.isEmpty ? "Converted" : state.convertCustomOutputName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.blue)
                            .onTapGesture {
                                editingConvertName = true
                            }
                    }
                    
                    if state.convertOutputStyle == .archive {
                        Text("as")
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                        
                        Menu {
                            Button("ZIP") { state.convertArchiveFormat = .zip }
                            Button("TAR") { state.convertArchiveFormat = .tar }
                            Button("TAR.GZ") { state.convertArchiveFormat = .tgz }
                            if isSevenZipAvailable {
                                Button("7-Zip") { state.convertArchiveFormat = .sevenZip }
                            }
                        } label: {
                            Text(state.convertArchiveFormat.rawValue.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                    } else if state.convertOutputStyle == .subfolder {
                        Text("folder")
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                    }
                }
            }
            
            if state.convertOutputStyle == .individual {
                HStack(alignment: .center, spacing: 4) {
                    Text("with suffix")
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                    
                    if editingConvertSuffix {
                        TextField("", text: $state.convertCustomSuffix)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.blue)
                            .onSubmit {
                                editingConvertSuffix = false
                            }
                            .frame(maxWidth: 80)
                    } else {
                        Text(state.convertCustomSuffix.isEmpty ? "\"none\"" : "\"\(state.convertCustomSuffix)\"")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.blue)
                            .onTapGesture {
                                editingConvertSuffix = true
                            }
                    }
                }
            }
            
            HStack(alignment: .center, spacing: 4) {
                Text("in")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                
                Text(state.resolvedConvertOutputDirectory?.path ?? "Choose Folder...")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .onTapGesture {
                        chooseConvertCustomFolder()
                    }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var mainButtonColor: Color {
        let types = state.aggregateDetectedTypes
        if types.count == 1, let firstType = types.first {
            switch firstType {
            case .image: return .orange
            case .video: return .teal
            case .audio: return .cyan
            case .pdf: return .red
            case .archive: return .green
            default: return .blue
            }
        }
        return .blue
    }
}
