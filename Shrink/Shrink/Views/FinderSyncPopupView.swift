//
//  FinderSyncPopupView.swift
//  Shrink
//

import SwiftUI
import AppKit

struct FinderSyncPopupView: View {
    @Bindable var state: AppState
    @State private var isHoveredCancel = false
    @State private var isHoveredAction = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Header: Title & Status Indicator
            HStack {
                Text(state.activeJobTitle.isEmpty ? "Processing..." : state.activeJobTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if state.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                } else if state.compressionResult != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 15))
                } else if state.compressionError != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 15))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            
            Divider()
                .padding(.horizontal, 12)
            
            // Content Card Area
            VStack(spacing: 10) {
                if let result = state.compressionResult {
                    // Completed View
                    let originalSizeStr = FileItem.formatBytes(result.originalSize)
                    let compressedSizeStr = FileItem.formatBytes(result.newSize)
                    let ratio = result.originalSize > 0 ? Double(result.originalSize - result.newSize) / Double(result.originalSize) : 0.0
                    let percentStr = String(format: "%.0f%%", ratio * 100)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(result.compressedURL.lastPathComponent)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        HStack(spacing: 4) {
                            Text("Shrunk from \(originalSizeStr) to \(compressedSizeStr)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("-\(percentStr)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    Spacer(minLength: 0)
                    
                    // Done / Reveal actions
                    HStack(spacing: 8) {
                        Button(action: {
                            NSWorkspace.shared.selectFile(result.compressedURL.path, inFileViewerRootedAtPath: "")
                        }) {
                            Label("Reveal", systemImage: "magnifyingglass")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Color.primary.opacity(0.08))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            state.dismissCompletion()
                        }) {
                            Text("Done")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Color.blue)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    
                } else if let error = state.compressionError {
                    // Failed View
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Operation Failed")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 16)
                    
                    Spacer(minLength: 0)
                    
                    Button(action: {
                        state.dismissCompletion()
                    }) {
                        Text("Dismiss")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.red)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    
                } else {
                    // Active Processing View
                    VStack(spacing: 6) {
                        HStack {
                            if let first = state.selectedFiles.first(where: {
                                if case .processing = $0.status { return true }
                                return false
                            }) {
                                Text(first.name)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text("Preparing files...")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if !state.throughputText.isEmpty {
                                Text(state.throughputText)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        
                        // Progress bar with smooth animation
                        ProgressView(value: state.currentProgress)
                            .progressViewStyle(.linear)
                            .padding(.horizontal, 16)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: state.currentProgress)
                        
                        HStack {
                            let elapsedStr = formatSeconds(state.elapsedSeconds)
                            Text("Elapsed: \(elapsedStr)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            
                            if let remaining = state.estimatedSecondsRemaining {
                                Text("• Remaining: \(formatSeconds(remaining))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                state.cancelShrinking()
                            }) {
                                Text("Cancel")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(isHoveredCancel ? Color.red.opacity(0.12) : Color.clear)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .onHover { isHoveredCancel = $0 }
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(width: 340, height: 160)
        .background(.ultraThinMaterial)
    }
    
    private func formatSeconds(_ totalSeconds: Int) -> String {
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
