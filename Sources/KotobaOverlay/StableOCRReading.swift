import Foundation

/// Retains accepted lines through transient empty or low-confidence frames.
struct StableOCRReading {
    private var stability = TextStability()
    private(set) var lines: [OCRLine] = []

    mutating func update(_ reading: OCRReading) -> Bool {
        let changed = stability.update(reading.text, confidence: reading.confidence) != nil
        if changed || reading.text.trimmingCharacters(in: .whitespacesAndNewlines) == stability.emitted {
            lines = reading.lines
        }
        return changed
    }
}
