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
