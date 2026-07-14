//
//  UserDefaults+Shared.swift
//  Shrink
//

import Foundation

extension UserDefaults {
    static let sharedSuiteName = "group.amo.Shrink"
    
    static var shared: UserDefaults {
        return UserDefaults(suiteName: sharedSuiteName) ?? .standard
    }
}
