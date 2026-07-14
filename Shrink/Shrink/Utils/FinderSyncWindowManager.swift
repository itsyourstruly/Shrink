//
//  FinderSyncWindowManager.swift
//  Shrink
//

import Cocoa
import SwiftUI

class FinderSyncWindowManager: NSObject {
    static let shared = FinderSyncWindowManager()
    
    var window: NSPanel?
    
    func showProgressWindow(state: AppState) {
        guard window == nil else { return }
        
        let contentView = NSHostingView(rootView: FinderSyncPopupView(state: state).defaultAppStorage(UserDefaults.shared))
        
        // NSPanel allows non-activating panel (won't steal focus from Finder)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 160),
            styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Shrink"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.contentView = contentView
        panel.isReleasedWhenClosed = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        
        // Set size & positions
        let width: CGFloat = 340
        let height: CGFloat = 160
        panel.minSize = NSSize(width: width, height: height)
        panel.maxSize = NSSize(width: width, height: height)
        
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.maxX - width - 20
            let y = screenRect.minY + 20
            panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }
        
        panel.makeKeyAndOrderFront(nil)
        self.window = panel
        
        // Hide dock icon/menubar during this operation
        NSApp.setActivationPolicy(.accessory)
    }
    
    func closeProgressWindow() {
        window?.orderOut(nil)
        window = nil
    }
}
