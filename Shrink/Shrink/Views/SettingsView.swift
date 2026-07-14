//
//  SettingsView.swift
//  Shrink
//

import SwiftUI
import FinderSync

struct SettingsView: View {
    var state: AppState
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            
            ArchiveFormatsSettingsView()
                .tabItem {
                    Label("Archive Formats", systemImage: "archivebox")
                }
            
            ConversionSettingsView()
                .tabItem {
                    Label("Conversion", systemImage: "arrow.triangle.2.circlepath")
                }
            
            PluginsSettingsView(state: state)
                .tabItem {
                    Label("Plugins", systemImage: "puzzlepiece")
                }
            
            FinderExtensionSettingsView()
                .tabItem {
                    Label("Finder Extension", systemImage: "contextualmenu")
                }
            
            UpdateSettingsView(state: state)
                .tabItem {
                    Label("Update", systemImage: "arrow.down.circle")
                }
        }
        .frame(width: 520, height: 420)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("default_suffix") private var defaultSuffix = "_shrunk"
    @AppStorage("decompress_create_subfolder") private var decompressCreateSubfolder = true
    @AppStorage("decompress_overwrite_existing") private var decompressOverwriteExisting = false
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Default Suffix")
                        .font(.headline)
                    Text("Appended to the file name of compressed or converted files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextField("Suffix", text: $defaultSuffix)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .onChange(of: defaultSuffix) {
                            notifySettingsChanged()
                        }
                }
                .padding(.vertical, 8)
            }
            
            Divider()
                .padding(.vertical, 8)
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Extraction Options")
                        .font(.headline)
                    
                    Toggle(isOn: $decompressCreateSubfolder) {
                        VStack(alignment: .leading) {
                            Text("Create subfolder for extracted contents")
                            Text("Puts the contents of each archive in its own folder.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: decompressCreateSubfolder) {
                        notifySettingsChanged()
                    }
                    
                    Toggle(isOn: $decompressOverwriteExisting) {
                        VStack(alignment: .leading) {
                            Text("Overwrite existing files")
                            Text("Replace files in the output directory if they match names.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: decompressOverwriteExisting) {
                        notifySettingsChanged()
                    }
                }
                .padding(.vertical, 8)
            }
            
            Spacer()
        }
        .padding(24)
    }
    
    private func notifySettingsChanged() {
        NotificationCenter.default.post(name: .archiveSettingsChanged, object: nil)
    }
}

struct ArchiveFormatsSettingsView: View {
    @AppStorage("compress_zip_enabled") private var compressZip = true
    @AppStorage("compress_tar_enabled") private var compressTar = true
    @AppStorage("compress_tgz_enabled") private var compressTgz = true
    @AppStorage("compress_sevenZip_enabled") private var compressSevenZip = true
    @AppStorage("compress_gzip_enabled") private var compressGzip = true
    @AppStorage("compress_bzip2_enabled") private var compressBzip2 = true
    @AppStorage("compress_xz_enabled") private var compressXz = true
    
    @AppStorage("use_sevenzip_for_archive") private var useSevenZip = true
    
    private var visibleDecompressionFormats: [ArchiveFormat] {
        ArchiveFormat.allCases.filter { format in
            switch format {
            case .sevenZip:
                return useSevenZip
            case .rar:
                return true
            default:
                return true
            }
        }
    }
    
    private func compressionBinding(for format: ArchiveFormat) -> Binding<Bool> {
        Binding(
            get: { ArchiveSettingsManager.isCompressionEnabled(for: format) },
            set: { ArchiveSettingsManager.setCompressionEnabled(for: format, enabled: $0) }
        )
    }
    
    private func decompressionBinding(for format: ArchiveFormat) -> Binding<Bool> {
        Binding(
            get: { ArchiveSettingsManager.isDecompressionEnabled(for: format) },
            set: { ArchiveSettingsManager.setDecompressionEnabled(for: format, enabled: $0) }
        )
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Section: Compress Into
                VStack(alignment: .leading, spacing: 12) {
                    Text("Compression Formats (Compress Into)")
                        .font(.headline)
                        .foregroundStyle(.blue)
                    
                    Text("Select which formats are allowed as compression targets in output option pickers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 8) {
                        formatToggleRow(title: "ZIP (.zip)", icon: "doc.zipper", isEnabled: $compressZip, color: .orange, backendLabel: compressionBackendLabel(for: .zip), isAvailable: isCompressionActuallyAvailable(for: .zip))
                        formatToggleRow(title: "TAR (.tar)", icon: "doc.fill", isEnabled: $compressTar, color: .gray, backendLabel: compressionBackendLabel(for: .tar), isAvailable: isCompressionActuallyAvailable(for: .tar))
                        formatToggleRow(title: "TAR.GZ (.tar.gz)", icon: "doc.zipper", isEnabled: $compressTgz, color: .brown, backendLabel: compressionBackendLabel(for: .tgz), isAvailable: isCompressionActuallyAvailable(for: .tgz))
                        
                        if useSevenZip {
                            formatToggleRow(title: "7-Zip (.7z)", icon: "doc.archive.fill", isEnabled: $compressSevenZip, color: .green, backendLabel: compressionBackendLabel(for: .sevenZip), isAvailable: isCompressionActuallyAvailable(for: .sevenZip))
                        }
                        
                        formatToggleRow(title: "RAR (.rar)", icon: "doc.archive.fill", isEnabled: .constant(false), color: .blue, backendLabel: "Not supported", isAvailable: false)
                        
                        formatToggleRow(title: "GZIP (.gz)", icon: "doc.zipper", isEnabled: $compressGzip, color: .blue, backendLabel: compressionBackendLabel(for: .gzip), isAvailable: isCompressionActuallyAvailable(for: .gzip))
                        formatToggleRow(title: "BZIP2 (.bz2)", icon: "doc.zipper", isEnabled: $compressBzip2, color: .blue, backendLabel: compressionBackendLabel(for: .bzip2), isAvailable: isCompressionActuallyAvailable(for: .bzip2))
                        formatToggleRow(title: "XZ (.xz)", icon: "doc.zipper", isEnabled: $compressXz, color: .blue, backendLabel: compressionBackendLabel(for: .xz), isAvailable: isCompressionActuallyAvailable(for: .xz))
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                Divider()
                
                // Section: Decompress From
                VStack(alignment: .leading, spacing: 12) {
                    Text("Decompression Formats (Decompress From)")
                        .font(.headline)
                        .foregroundStyle(.green)
                    
                    Text("Select which archive formats the app is allowed to extract.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 8) {
                        ForEach(visibleDecompressionFormats) { format in
                            formatToggleRow(
                                title: "\(format.rawValue) (.\(format.fileExtension))",
                                icon: format.iconName,
                                isEnabled: decompressionBinding(for: format),
                                color: format.iconColor,
                                backendLabel: decompressionBackendLabel(for: format),
                                isAvailable: isDecompressionActuallyAvailable(for: format)
                            )
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
            .padding(24)
        }
    }
    
    @ViewBuilder
    private func formatToggleRow(title: String, icon: String, isEnabled: Binding<Bool>, color: Color, backendLabel: String, isAvailable: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(backendLabel)
                    .font(.caption)
                    .foregroundColor(isAvailable ? .secondary : .red)
            }
            
            Spacer()
            
            Toggle("", isOn: isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!isAvailable)
                .onChange(of: isEnabled.wrappedValue) {
                    NotificationCenter.default.post(name: .archiveSettingsChanged, object: nil)
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
    
    private func compressionBackendLabel(for format: ArchiveFormat) -> String {
        switch format {
        case .zip:
            return ArchiveCompressor.isSevenZipEnabled() ? "Using 7-Zip (7zz) to compress" : "Using built-in ditto to compress"
        case .tar, .tgz:
            return "Using built-in macOS tar to compress"
        case .sevenZip:
            return ArchiveCompressor.isSevenZipEnabled() ? "Using 7-Zip (7zz) to compress" : "Unavailable (Requires 7-Zip enabled)"
        case .rar:
            return "Not supported"
        case .gzip, .bzip2, .xz:
            return "Using built-in macOS tar to compress"
        default:
            return "Not supported"
        }
    }
    
    private func decompressionBackendLabel(for format: ArchiveFormat) -> String {
        switch format {
        case .zip:
            return "Using built-in unzip/ditto to decompress"
        case .tar, .tgz:
            return "Using built-in macOS tar to decompress"
        case .sevenZip:
            if ArchiveCompressor.isSevenZipEnabled() {
                return "Using 7-Zip (7zz) to decompress"
            } else if ArchiveCompressor.unarPath != nil {
                return "Using built-in unar to decompress"
            } else {
                return "Unavailable"
            }
        case .rar:
            if ArchiveCompressor.isSevenZipEnabled() {
                return "Using 7-Zip (7zz) to decompress"
            } else if ArchiveCompressor.unarPath != nil {
                return "Using built-in unar to decompress"
            } else {
                return "Using built-in macOS tar to decompress"
            }
        case .gzip, .bzip2, .xz:
            if ArchiveCompressor.isSevenZipEnabled() {
                return "Using 7-Zip (7zz) to decompress"
            } else if ArchiveCompressor.unarPath != nil {
                return "Using built-in unar to decompress"
            } else {
                return "Using built-in macOS tar to decompress"
            }
        default:
            if ArchiveCompressor.isSevenZipEnabled() {
                return "Using 7-Zip (7zz) to decompress"
            } else if ArchiveCompressor.unarPath != nil {
                return "Using built-in unar to decompress"
            } else {
                return "Unavailable"
            }
        }
    }
    
    private func isCompressionActuallyAvailable(for format: ArchiveFormat) -> Bool {
        switch format {
        case .sevenZip:
            return ArchiveCompressor.isSevenZipEnabled()
        case .rar:
            return false
        default:
            return true
        }
    }
    
    private func isDecompressionActuallyAvailable(for format: ArchiveFormat) -> Bool {
        switch format {
        case .sevenZip:
            return ArchiveCompressor.isSevenZipEnabled() || ArchiveCompressor.unarPath != nil
        default:
            return true
        }
    }
}

struct PluginsSettingsView: View {
    var state: AppState
    
    @State private var ffmpegAvailable = false
    @State private var magickAvailable = false
    @State private var pandocAvailable = false
    
    @AppStorage("use_ffmpeg") private var useFFmpeg = false
    @AppStorage("use_magick") private var useMagick = false
    @AppStorage("use_pandoc") private var usePandoc = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tool Preferences")
                        .font(.headline)
                        .foregroundStyle(.blue)
                    
                    Text("Select whether to use high-performance external tools or default macOS libraries.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Divider()
                
                VStack(spacing: 16) {
                    toolRow(
                        title: "FFmpeg",
                        description: "Enables the use of FFmpeg for video/audio compression and conversion (supports MP4, MOV, MKV, AVI, WebM, FLV, ProRes, MP3, WAV, M4A, FLAC, AAC, OGG).",
                        activeText: "Video and audio compression/conversion will use FFmpeg.",
                        selection: $useFFmpeg,
                        isInstalled: ffmpegAvailable,
                        tool: .ffmpeg
                    )
                    
                    Divider()
                    
                    toolRow(
                        title: "ImageMagick",
                        description: "Enables the use of ImageMagick for image compression and conversion (supports PNG, JPEG, WebP, HEIC, AVIF, TIFF, GIF, BMP, PSD, TGA, DDS, EXR, HDR, PCX, EPS, ICO).",
                        activeText: "Image compression and conversion will use ImageMagick.",
                        selection: $useMagick,
                        isInstalled: magickAvailable,
                        tool: .magick
                    )
                    
                    Divider()
                    
                    toolRow(
                        title: "Pandoc",
                        description: "Enables the use of Pandoc for document conversion (supports PDF, DOCX, TXT, RTF, ePub, HTML, ODT, Markdown).",
                        activeText: "Document conversion will use Pandoc.",
                        selection: $usePandoc,
                        isInstalled: pandocAvailable,
                        tool: .pandoc
                    )
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            .padding(20)
        }
        .onAppear {
            checkAvailability()
        }
        .onChange(of: state.installingTool) { _ in
            checkAvailability()
        }
    }
    
    private func checkAvailability() {
        ffmpegAvailable = ExternalToolManager.isToolAvailable(.ffmpeg)
        magickAvailable = ExternalToolManager.isToolAvailable(.magick)
        pandocAvailable = ExternalToolManager.isToolAvailable(.pandoc)
    }
    
    @ViewBuilder
    private func toolRow(
        title: String,
        description: String,
        activeText: String,
        selection: Binding<Bool>,
        isInstalled: Bool,
        tool: ExternalTool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                            .font(.headline)
                        
                        if isInstalled {
                            Text("Installed")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        } else {
                            Text("Not Installed")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.gray.opacity(0.15))
                                .foregroundColor(.secondary)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: selection)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: selection.wrappedValue) {
                        NotificationCenter.default.post(name: .archiveSettingsChanged, object: nil)
                    }
            }
            
            if selection.wrappedValue {
                VStack(alignment: .leading, spacing: 4) {
                    if isInstalled {
                        Text("✓ \(activeText)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                    } else {
                        Text("⚠️ Plugin is enabled but not installed. Install via Homebrew below.")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                }
            }
            
            // Installation / Uninstallation controls
            if state.installingTool == tool.name {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Processing \(tool.name)...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
                
                if !state.installProgressText.isEmpty {
                    Text(state.installProgressText)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack {
                    if !isInstalled {
                        Button("Install \(tool.name)") {
                            Task {
                                await state.installTool(tool)
                                checkAvailability()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Button("Uninstall \(tool.name)") {
                            Task {
                                await state.uninstallTool(tool)
                                checkAvailability()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 6)
    }
}

extension ArchiveFormat {
    var iconName: String {
        switch self {
        case .zip, .tgz, .gzip, .bzip2, .xz, .lzma: return "doc.zipper"
        case .tar: return "doc.fill"
        default: return "doc.archive.fill"
        }
    }
    
    var iconColor: Color {
        switch self {
        case .zip: return .orange
        case .tar: return .gray
        case .tgz: return .brown
        case .sevenZip: return .green
        case .rar: return .blue
        case .gzip, .bzip2, .xz, .lzma: return .blue
        default: return .blue
        }
    }
}

struct ConversionSettingsView: View {
    @AppStorage("use_ffmpeg") private var useFFmpeg = false
    @AppStorage("use_magick") private var useMagick = false
    @AppStorage("use_pandoc") private var usePandoc = false
    
    @State private var ffmpegAvailable = false
    @State private var magickAvailable = false
    @State private var pandocAvailable = false
    
    private var imageFormats: [String] {
        if useMagick {
            return ["PNG", "JPEG", "WebP", "HEIC", "AVIF", "TIFF", "GIF", "BMP", "PSD", "TGA", "DDS", "EXR", "HDR", "PCX", "EPS", "ICO"]
        } else {
            return ["PNG", "JPEG", "WebP", "HEIC", "TIFF", "GIF", "BMP", "PDF"]
        }
    }
    
    private var videoFormats: [String] {
        if useFFmpeg {
            return ["MP4", "MOV", "MKV", "AVI", "WebM", "FLV", "ProRes"]
        } else {
            return ["MP4", "MOV"]
        }
    }
    
    private var audioFormats: [String] {
        if useFFmpeg {
            return ["MP3", "WAV", "M4A", "FLAC", "AAC", "OGG"]
        } else {
            return ["WAV", "M4A", "FLAC", "AAC"]
        }
    }
    
    private var documentFormats: [String] {
        if usePandoc {
            return ["PDF", "DOCX", "TXT", "RTF", "ePub", "HTML", "ODT", "Markdown"]
        } else {
            return ["PDF", "DOCX", "TXT", "RTF"]
        }
    }
    
    private func conversionBinding(for format: String) -> Binding<Bool> {
        Binding(
            get: {
                let key = "convert_\(format.lowercased())_enabled"
                return UserDefaults.standard.bool(forKey: key)
            },
            set: {
                let key = "convert_\(format.lowercased())_enabled"
                UserDefaults.standard.set($0, forKey: key)
                NotificationCenter.default.post(name: .archiveSettingsChanged, object: nil)
            }
        )
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Section: Images
                VStack(alignment: .leading, spacing: 12) {
                    Text("Image Conversion Formats")
                        .font(.headline)
                        .foregroundStyle(.blue)
                    
                    Text("Select which image formats are enabled as conversion targets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 8) {
                        ForEach(imageFormats, id: \.self) { format in
                            formatToggleRow(
                                title: format,
                                isEnabled: conversionBinding(for: format),
                                backendLabel: conversionBackendLabel(category: "image"),
                                color: .blue
                            )
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                Divider()
                
                // Section: Videos
                VStack(alignment: .leading, spacing: 12) {
                    Text("Video Conversion Formats")
                        .font(.headline)
                        .foregroundStyle(.blue)
                    
                    Text("Select which video formats are enabled as conversion targets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 8) {
                        ForEach(videoFormats, id: \.self) { format in
                            formatToggleRow(
                                title: format,
                                isEnabled: conversionBinding(for: format),
                                backendLabel: conversionBackendLabel(category: "video"),
                                color: .blue
                            )
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                Divider()
                
                // Section: Audio
                VStack(alignment: .leading, spacing: 12) {
                    Text("Audio Conversion Formats")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    
                    Text("Select which audio formats are enabled as conversion targets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 8) {
                        ForEach(audioFormats, id: \.self) { format in
                            formatToggleRow(
                                title: format,
                                isEnabled: conversionBinding(for: format),
                                backendLabel: conversionBackendLabel(category: "audio"),
                                color: .orange
                            )
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                Divider()
                
                // Section: Documents
                VStack(alignment: .leading, spacing: 12) {
                    Text("Document Conversion Formats")
                        .font(.headline)
                        .foregroundStyle(.green)
                    
                    Text("Select which document formats are enabled as conversion targets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 8) {
                        ForEach(documentFormats, id: \.self) { format in
                            formatToggleRow(
                                title: format,
                                isEnabled: conversionBinding(for: format),
                                backendLabel: conversionBackendLabel(category: "document"),
                                color: .green
                            )
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
            .padding(24)
        }
        .onAppear {
            checkAvailability()
        }
    }
    
    private func checkAvailability() {
        ffmpegAvailable = ExternalToolManager.isToolAvailable(.ffmpeg)
        magickAvailable = ExternalToolManager.isToolAvailable(.magick)
        pandocAvailable = ExternalToolManager.isToolAvailable(.pandoc)
    }
    
    @ViewBuilder
    private func formatToggleRow(title: String, isEnabled: Binding<Bool>, backendLabel: String, color: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(backendLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .onChange(of: isEnabled.wrappedValue) {
                    NotificationCenter.default.post(name: .archiveSettingsChanged, object: nil)
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
    
    private func conversionBackendLabel(category: String) -> String {
        switch category {
        case "image":
            return (useMagick && magickAvailable) ? "Using ImageMagick to convert" : "Using built-in ImageIO to convert"
        case "video":
            return (useFFmpeg && ffmpegAvailable) ? "Using FFmpeg to convert" : "Using built-in AVFoundation to convert"
        case "audio":
            return (useFFmpeg && ffmpegAvailable) ? "Using FFmpeg to convert" : "Using built-in AVFoundation to convert"
        case "document":
            return (usePandoc && pandocAvailable) ? "Using Pandoc to convert" : "Using built-in textutil & PDFKit to convert"
        default:
            return "Using built-in libraries to convert"
        }
    }
}

struct UpdateSettingsView: View {
    var state: AppState
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Updates")
                        .font(.headline)
                    
                    Toggle(isOn: Binding(
                        get: { state.automaticallyChecksForUpdates },
                        set: { state.automaticallyChecksForUpdates = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatically check for updates")
                                .font(.body)
                            Text("Keep Shrink up-to-date with new features and bug fixes.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Toggle(isOn: Binding(
                        get: { state.automaticallyDownloadsUpdates },
                        set: { state.automaticallyDownloadsUpdates = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatically download updates")
                                .font(.body)
                            Text("Download updates in the background and notify you when ready to install.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!state.automaticallyChecksForUpdates)
                }
                .padding(.vertical, 8)
            }
            
            Divider()
                .padding(.vertical, 8)
            
            Section {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Check for Updates")
                            .font(.headline)
                        Text("Manually query the update server for a newer version of Shrink.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        state.checkForUpdates()
                    }) {
                        Text("Check Now")
                            .frame(minWidth: 80)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!state.canCheckForUpdates)
                }
                .padding(.vertical, 8)
            }
            
            Spacer()
        }
        .padding(24)
    }
}

struct FinderExtensionSettingsView: View {
    // MARK: - Soft in-app toggle (controls menu visibility in FinderSync.swift)
    @AppStorage("finder_extension_enabled", store: .shared) private var isMenuEnabled = false
    
    // MARK: - Individual context menu item visibility
    @AppStorage("finder_show_compress_archive", store: .shared) private var showCompressArchive = true
    @AppStorage("finder_show_compress_image", store: .shared) private var showCompressImage = true
    @AppStorage("finder_show_compress_video", store: .shared) private var showCompressVideo = true
    @AppStorage("finder_show_compress_audio", store: .shared) private var showCompressAudio = true
    @AppStorage("finder_show_convert_file", store: .shared) private var showConvertFile = true
    
    // MARK: - Default quality settings
    @AppStorage("default_image_shrink_ratio", store: .shared) private var imageShrinkRatio = 0.8
    @AppStorage("default_video_shrink_ratio", store: .shared) private var videoShrinkRatio = 0.7
    @AppStorage("default_audio_bitrate", store: .shared) private var audioBitrate = 128000
    @AppStorage("default_archive_compression_level", store: .shared) private var archiveLevel = 5
    
    // MARK: - OS-level extension state
    /// Reflects whether macOS has the ShrinkExtensions Finder Sync extension
    /// enabled in System Settings. Read from FIFinderSyncController — note this
    /// can be briefly stale after app launch; we refresh on appear and foreground.
    @State private var isSystemEnabled: Bool = false
    
    /// True while we're polling after sending the user to System Settings,
    /// waiting for them to flip the switch.
    @State private var isAwaitingUserEnable: Bool = false
    
    /// Whether the app is running from Xcode DerivedData (not a stable /Applications install).
    /// Used to show a dev-only warning that registration may be flaky.
    private var isRunningFromDerivedData: Bool {
        Bundle.main.bundlePath.contains("/DerivedData/")
    }
    
    // MARK: - Body
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                
                // MARK: Section 1: Master Toggle Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .frame(width: 32)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text("Finder Integration")
                                    .font(.headline)
                                statusBadge
                            }
                            Text("Right-click files in Finder to quickly compress or convert them.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        // Toggle is disabled until system-level extension is enabled
                        Toggle("", isOn: $isMenuEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(!isSystemEnabled)
                            .onChange(of: isMenuEnabled) { _, _ in
                                notifySettingsChanged()
                            }
                    }
                    
                    // Call-to-action when not yet set up in System Settings
                    if !isSystemEnabled {
                        Divider()
                            .padding(.top, 4)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ShrinkExtensions must be enabled in System Settings before the Finder context menu can appear.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Button(action: openSystemSettings) {
                                HStack(spacing: 6) {
                                    if isAwaitingUserEnable {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .frame(width: 14, height: 14)
                                        Text("Waiting for you to enable it…")
                                    } else {
                                        Image(systemName: "macwindow.and.gearshape")
                                        Text("Open System Settings to Enable Extension")
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(isAwaitingUserEnable)
                        }
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                // MARK: DerivedData dev warning (debug builds only)
                #if DEBUG
                if isRunningFromDerivedData {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Development Build")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text("Running from Xcode may prevent ShrinkExtensions from appearing in System Settings. Copy the app to /Applications and run it once for reliable extension registration.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                }
                #endif
                
                // MARK: Section 2 & 3: Only shown when fully active
                if isSystemEnabled && isMenuEnabled {
                    // Context Menu Actions
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Context Menu Actions")
                                .font(.headline)
                                .foregroundStyle(.blue)
                            Text("Choose which options appear in the 'Shrink' right-click submenu.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Divider()
                            .padding(.vertical, 2)
                        
                        VStack(spacing: 8) {
                            menuToggleRow(title: "Compress as Archive", icon: "archivebox", isEnabled: $showCompressArchive)
                                .onChange(of: showCompressArchive) { notifySettingsChanged() }
                            
                            menuToggleRow(title: "Compress Image", icon: "photo", isEnabled: $showCompressImage)
                                .onChange(of: showCompressImage) { notifySettingsChanged() }
                            
                            menuToggleRow(title: "Compress Video", icon: "video", isEnabled: $showCompressVideo)
                                .onChange(of: showCompressVideo) { notifySettingsChanged() }
                            
                            menuToggleRow(title: "Compress Audio", icon: "waveform", isEnabled: $showCompressAudio)
                                .onChange(of: showCompressAudio) { notifySettingsChanged() }
                            
                            menuToggleRow(title: "Convert File...", icon: "arrow.2.squarepath", isEnabled: $showConvertFile)
                                .onChange(of: showConvertFile) { notifySettingsChanged() }
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    
                    // Default Quality & Shrink Amounts
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Default Quality & Shrink Amounts")
                                .font(.headline)
                                .foregroundStyle(.blue)
                            Text("Configure the default compression levels when launching jobs from the Finder context menu.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Divider()
                            .padding(.vertical, 2)
                        
                        // Image Ratio
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label("Default Image Quality", systemImage: "photo.on.rectangle")
                                    .font(.body)
                                Spacer()
                                Text("\(Int(imageShrinkRatio * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $imageShrinkRatio, in: 0.05...1.0, step: 0.05)
                                .onChange(of: imageShrinkRatio) { notifySettingsChanged() }
                        }
                        
                        // Video Ratio
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label("Default Video Quality", systemImage: "film")
                                    .font(.body)
                                Spacer()
                                Text("\(Int(videoShrinkRatio * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $videoShrinkRatio, in: 0.05...1.0, step: 0.05)
                                .onChange(of: videoShrinkRatio) { notifySettingsChanged() }
                        }
                        
                        // Audio Bitrate
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label("Default Audio Bitrate", systemImage: "waveform.path")
                                    .font(.body)
                                Spacer()
                                Text("\(audioBitrate / 1000) kbps")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: Binding(
                                get: { Double(audioBitrate) },
                                set: { audioBitrate = Int($0) }
                            ), in: 64000...320000, step: 32000)
                            .onChange(of: audioBitrate) { notifySettingsChanged() }
                        }
                        
                        // Archive Level
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label("Default Archive Level", systemImage: "doc.zipper")
                                    .font(.body)
                                Spacer()
                                Text(archiveLevelLabel(archiveLevel))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: Binding(
                                get: { Double(archiveLevel) },
                                set: { archiveLevel = Int($0) }
                            ), in: 1...9, step: 1)
                            .onChange(of: archiveLevel) { notifySettingsChanged() }
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                // MARK: Section 4: Troubleshooting
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Troubleshooting")
                            .font(.headline)
                            .foregroundStyle(.blue)
                        Text("If the context menu does not appear, use the button below to open the correct System Settings page. If that doesn't work, go to System Settings → General → Login Items & Extensions → Extensions → Finder and ensure ShrinkExtensions is checked.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    Button(action: openSystemSettings) {
                        Label("Open Extension Settings...", systemImage: "macwindow.and.gearshape")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            .padding(24)
        }
        .onAppear {
            refreshSystemEnabledState()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            // User may have returned from System Settings — refresh real OS state
            refreshSystemEnabledState()
        }
    }
    
    // MARK: - Status Badge
    
    @ViewBuilder
    private var statusBadge: some View {
        if isSystemEnabled && isMenuEnabled {
            Label("Active", systemImage: "circle.fill")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        } else if isSystemEnabled && !isMenuEnabled {
            Label("Registered", systemImage: "circle.fill")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.yellow)
                .labelStyle(.titleAndIcon)
        } else {
            Label("Not Set Up", systemImage: "circle.fill")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.red)
                .labelStyle(.titleAndIcon)
        }
    }
    
    // MARK: - Actions
    
    private func openSystemSettings() {
        // Use the official API — navigates to the correct section in System Settings
        FIFinderSyncController.showExtensionManagementInterface()
        
        // Start polling: check every 1.5s for up to 45s for the user to enable the extension
        isAwaitingUserEnable = true
        pollForExtensionEnabled(attemptsRemaining: 30)
    }
    
    private func refreshSystemEnabledState() {
        isSystemEnabled = FIFinderSyncController.isExtensionEnabled
        // If system is now enabled and we were awaiting, stop polling
        if isSystemEnabled {
            isAwaitingUserEnable = false
        }
    }
    
    /// Recursively polls `FIFinderSyncController.isExtensionEnabled` every 1.5 seconds.
    /// Stops when the extension becomes enabled or after `attemptsRemaining` checks.
    private func pollForExtensionEnabled(attemptsRemaining: Int) {
        guard attemptsRemaining > 0, isAwaitingUserEnable else {
            isAwaitingUserEnable = false
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            refreshSystemEnabledState()
            if !isSystemEnabled {
                pollForExtensionEnabled(attemptsRemaining: attemptsRemaining - 1)
            }
        }
    }
    
    // MARK: - Helpers
    
    @ViewBuilder
    private func menuToggleRow(title: String, icon: String, isEnabled: Binding<Bool>) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.body)
            Spacer()
            Toggle("", isOn: isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }
    
    private func archiveLevelLabel(_ level: Int) -> String {
        switch level {
        case 1: return "1 (Fastest)"
        case 9: return "9 (Maximum)"
        default: return "\(level)"
        }
    }
    
    private func notifySettingsChanged() {
        NotificationCenter.default.post(name: .archiveSettingsChanged, object: nil)
    }
}
