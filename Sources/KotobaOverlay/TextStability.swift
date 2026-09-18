import Foundation
struct TextStability {
    private var candidate = ""
    private var count = 0
    private(set) var emitted = ""
    mutating func update(_ text: String, confidence: Float = 0) -> String? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean == candidate { count += 1 } else { candidate = clean; count = 1 }
        let required = clean.isEmpty ? 3 : (confidence >= 0.8 ? 1 : 2)
        guard count >= required, clean != emitted else { return nil }
        emitted = clean
        return clean
    }
}
