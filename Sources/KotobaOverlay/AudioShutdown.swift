import Foundation

/// Concurrent stop callers await the same teardown, including final cue delivery.
@MainActor final class AudioShutdown {
    private var task: Task<Void, Never>?
    func run(_ operation: @escaping @MainActor () async -> Void) async {
        if let task { await task.value; return }
        let task = Task { await operation() }
        self.task = task
        await task.value
        self.task = nil
    }
}
