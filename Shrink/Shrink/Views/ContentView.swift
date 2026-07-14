//
//  ContentView.swift
//  Shrink
//

import SwiftUI

struct ContentView: View {
    var state: AppState
    
    var body: some View {
        ZStack {
            if state.isFinderSyncMode {
                Color.clear
                    .frame(width: 1, height: 1)
            } else if state.selectedFiles.isEmpty {
                EmptyStateView(state: state)
            } else {
                HStack(spacing: 0) {
                    // Left area: selected files list
                    FileListView(state: state)
                    
                    Divider()
                    
                    // Right area: settings panel
                    SidebarView(state: state)
                }
            }
            
            // Modal progress overlay for results
            if !state.isFinderSyncMode && (state.compressionResult != nil || state.compressionError != nil) {
                ProcessingOverlay(state: state)
            }
        }
        .frame(minWidth: state.isFinderSyncMode ? 1 : 750, minHeight: state.isFinderSyncMode ? 1 : 500)
        .onAppear {
            if state.isFinderSyncMode {
                hideMainWindow()
            }
        }
        .onChange(of: state.isFinderSyncMode) { oldValue, newValue in
            if newValue {
                hideMainWindow()
            }
        }
    }
    
    private func hideMainWindow() {
        DispatchQueue.main.async {
            NSApplication.shared.windows.forEach { window in
                if window != FinderSyncWindowManager.shared.window {
                    window.orderOut(nil)
                }
            }
        }
    }
}

#Preview {
    ContentView(state: AppState())
}
