// AtomicBool.swift
import Foundation

nonisolated final class AtomicBool: @unchecked Sendable {
    private var _value: Bool
    private let queue = DispatchQueue(label: "AtomicBoolQueue")
    
    init(_ value: Bool = false) {
        self._value = value
    }
    
    var value: Bool {
        return queue.sync { _value }
    }
    
    func set(_ newValue: Bool) {
        queue.sync { _value = newValue }
    }
}
