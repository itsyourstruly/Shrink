//
//  ShrinkApp.swift
//  Shrink
//
//  Created by Matthew Nakhel on 6/20/26.
//

import SwiftUI

@main
struct ShrinkApp: App {
    @State private var state = AppState()
    
    init() {
        // Prevent macOS from restoring previous window state/files across launches
        UserDefaults.standard.set(true, forKey: "ApplePersistenceIgnoreState")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(state: state)
                .defaultAppStorage(UserDefaults.shared)
                .onOpenURL { url in
                    state.handleIncomingURL(url)
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    state.checkForUpdates()
                }
                .disabled(!state.canCheckForUpdates)
            }
        }
        Settings {
            SettingsView(state: state)
                .defaultAppStorage(UserDefaults.shared)
        }
    }
}
