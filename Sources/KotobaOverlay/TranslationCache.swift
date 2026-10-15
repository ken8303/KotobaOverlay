import Foundation

struct TranslationCache {
    private var values: [String: String] = [:]
    private var order: [String] = []
    var capacity = 400

    subscript(_ text: String) -> String? { values[text] }

    mutating func insert(_ translation: String, for text: String, protecting visible: Set<String>) {
        if values[text] == nil { order.append(text) }
        values[text] = translation
        // A single unusually large frame may exceed capacity until it leaves the screen.
        while values.count > capacity,
              let index = order.firstIndex(where: { !visible.contains($0) && $0 != text }) {
            values.removeValue(forKey: order.remove(at: index))
        }
    }

    mutating func removeAll() { values.removeAll(); order.removeAll() }
}

struct OCRRetryState {
    private var deadlines: [String: Date] = [:]
    private(set) var lastError: String?
    private(set) var failedThisPass = false
    mutating func begin(visible: Set<String>) {
        deadlines = deadlines.filter { visible.contains($0.key) }
        failedThisPass = false
        if deadlines.isEmpty { lastError = nil }
    }
    func canAttempt(_ text: String, now: Date) -> Bool { (deadlines[text] ?? .distantPast) <= now }
    mutating func fail(_ text: String, message: String, now: Date) {
        deadlines[text] = now.addingTimeInterval(10)
        lastError = message; failedThisPass = true
    }
    mutating func succeed(_ text: String) {
        deadlines.removeValue(forKey: text)
        if deadlines.isEmpty { lastError = nil }
    }
    var passDelay: TimeInterval { failedThisPass ? 1 : 0 }
}
