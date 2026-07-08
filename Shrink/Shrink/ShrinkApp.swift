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
        }
        Settings {
            SettingsView(state: state)
        }
    }
}
