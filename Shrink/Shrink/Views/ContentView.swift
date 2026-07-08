//
//  ContentView.swift
//  Shrink
//

import SwiftUI

struct ContentView: View {
    var state: AppState
    
    var body: some View {
        ZStack {
            if state.selectedFiles.isEmpty {
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
            if state.compressionResult != nil || state.compressionError != nil {
                ProcessingOverlay(state: state)
            }
        }
        .frame(minWidth: 750, minHeight: 500)
    }
}

#Preview {
    ContentView(state: AppState())
}
