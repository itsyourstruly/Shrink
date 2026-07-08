//
//  ProcessingOverlay.swift
//  Shrink
//

import SwiftUI

struct ProcessingOverlay: View {
    @Bindable var state: AppState
    @State private var isHoveredLocation = false
    
    var body: some View {
        ZStack {
            // Semi-transparent background blur
            Color.black.opacity(0.15)
                .background(.ultraThinMaterial)
            
            // Central card
            Group {
                if let result = state.compressionResult {
                    completionCard(result: result)
                } else if let error = state.compressionError {
                    errorCard(message: error)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }
    
    // MARK: - Completion Card
    
    private func completionCard(result: CompressionResult) -> some View {
        let firstCheckedItem = state.selectedFiles.first(where: { $0.isChecked })
        let originalType = firstCheckedItem?.fileType ?? .general
        
        let originalName = result.originalURL.lastPathComponent
        let originalSizeString = FileItem.formatBytes(result.originalSize)
        let compressedName = result.compressedURL.lastPathComponent
        let compressedSizeString = FileItem.formatBytes(result.newSize)
        let compressedDestination = result.compressedURL.deletingLastPathComponent().path
        
        let timeString: String = {
            let seconds = result.elapsedSeconds
            if seconds < 60 {
                return "\(seconds)s"
            } else {
                let minutes = seconds / 60
                let remainingSeconds = seconds % 60
                return "\(minutes)m \(remainingSeconds)s"
            }
        }()
        
        let compressedType: FileType = {
            let ext = result.compressedURL.pathExtension.lowercased()
            if ["zip", "tar", "gz", "tgz", "7z", "rar", "bz2", "xz"].contains(ext) {
                return .archive
            }
            if ext == result.originalURL.pathExtension.lowercased() {
                return originalType
            }
            if ["png", "jpg", "jpeg", "heic", "webp", "gif"].contains(ext) {
                return .image
            }
            if ["mp4", "mov", "mkv", "avi", "webm"].contains(ext) {
                return .video
            }
            if ["mp3", "m4a", "wav", "aac"].contains(ext) {
                return .audio
            }
            if ext == "pdf" {
                return .pdf
            }
            return .general
        }()
        
        return VStack(spacing: 24) {
            // Comparison Row
            HStack(alignment: .top, spacing: 28) {
                // Original column
                VStack(spacing: 8) {
                    FileThumbnailView(url: result.originalURL, fileType: originalType, size: 84)
                        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
                    
                    VStack(spacing: 2) {
                        Text(originalName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 120)
                        
                        Text(originalSizeString)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Green Arrow (centered vertically with the thumbnails)
                Image(systemName: "arrow.right")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.green)
                    .frame(height: 84)
                
                // Compressed column
                VStack(spacing: 8) {
                    FileThumbnailView(url: result.compressedURL, fileType: compressedType, size: 84)
                        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
                    
                    VStack(spacing: 2) {
                        Text(compressedName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.blue)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 120)
                        
                        Text(compressedSizeString)
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.top, 8)
            
            // Location, duration, and action button grouped with tight spacing
            VStack(spacing: 10) {
                Button(action: {
                    NSWorkspace.shared.selectFile(result.compressedURL.path, inFileViewerRootedAtPath: "")
                }) {
                    Text("in \(compressedDestination)")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                        .underline(isHoveredLocation)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHoveredLocation = hovering
                }
                
                Text("Took \(timeString)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                
                // Done Button (Nice)
                Button(action: state.dismissCompletion) {
                    Text("Nice")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(28)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.15), radius: 24, y: 8)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - Error Card
    
    private func errorCard(message: String) -> some View {
        VStack(spacing: 20) {
            // Error icon
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 56, height: 56)
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.red)
            }
            
            VStack(spacing: 6) {
                Text("Compression Failed")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                
                Text(simplifiedErrorMessage(message))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .lineLimit(4)
            }
            
            Button(action: state.dismissCompletion) {
                Text("Dismiss")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 10)
                    .background(Color.red)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(28)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.15), radius: 24, y: 8)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - Helpers
    
    private func formatSeconds(_ totalSeconds: Int) -> String {
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    private func simplifiedErrorMessage(_ message: String) -> String {
        // Strip long NSError domain prefixes and internal details
        if message.contains("Operation stopped by user") || message.contains("cancelled") {
            return "Operation was cancelled by the user."
        }
        // Truncate very long error messages
        if message.count > 200 {
            return String(message.prefix(200)) + "..."
        }
        return message
    }
}
