//
//  EmptyStateView.swift
//  Shrink
//

import SwiftUI

struct EmptyStateView: View {
    @Bindable var state: AppState
    @State private var isHovered = false
    @State private var isDragOver = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Plus button with clean, gray styling
            Button(action: browseFiles) {
                VStack(spacing: 16) {
                    Image(systemName: "plus")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundColor(isDragOver ? .blue : (isHovered ? .primary : .secondary))
                        .scaleEffect(isHovered ? 1.05 : 1.0)
                    
                    Text("Tap to browse or drop in your files")
                        .font(.system(size: 14))
                        .foregroundColor(isHovered ? .primary : .secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .dropDestination(for: URL.self) { items, location in
            state.addFiles(urls: items)
            return true
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.2)) {
                isDragOver = targeted
            }
        }
    }
    
    // File browsing panel
    private func browseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Select"
        panel.message = "Choose files or folders to compress/decompress"
        
        if panel.runModal() == .OK {
            state.addFiles(urls: panel.urls)
        }
    }
}
