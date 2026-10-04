import Foundation

@MainActor
final class PhotoImageRequest {
    private var cancellation: (() -> Void)?

    init(cancel: @escaping () -> Void = {}) {
        cancellation = cancel
    }

    func cancel() {
        let action = cancellation
        cancellation = nil
        action?()
    }
}

/// Transfers small transaction results between PhotoKit's change and completion queues.
nonisolated final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
    }
}
