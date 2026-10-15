import Foundation

struct TimedSubtitle: Identifiable, Equatable {
    let id: UUID
    let start: Double
    let end: Double
    let original: String
    var translationFailure: String?
    var translated: String?
    init(start: Double, end: Double, original: String, translated: String? = nil) {
        self.id = UUID(); self.start = start; self.end = end
        self.original = original; self.translated = translated
    }
}
enum SubtitleTextMode: String, CaseIterable { case translated = "Translation", original = "Original", both = "Both" }
enum SubtitleExportError: LocalizedError {
    case invalidTime, missingTranslations, invalidCue
    var errorDescription: String? {
        switch self {
        case .invalidCue: return "A subtitle has an invalid time range or empty text. It cannot be exported as SRT."
        case .invalidTime: return "Enter a valid time as HH:MM:SS,mmm (for example 00:01:20,000)."
        case .missingTranslations: return "Some cues are still untranslated. Finish translation or export Original."
        }
    }
}
enum SubtitleTimeline {
    static func parse(_ text: String) throws -> Double {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ".", with: ",").split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.prefix(2).allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }), let hours = Int(parts[0]), hours >= 0, hours <= 999,
              let minutes = Int(parts[1]), (0..<60).contains(minutes) else { throw SubtitleExportError.invalidTime }
        let seconds = parts[2].split(separator: ",", omittingEmptySubsequences: false)
        guard seconds.count == 2, seconds[1].count == 3,
              seconds.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let whole = Int(seconds[0]), (0..<60).contains(whole), let ms = Int(seconds[1]), (0..<1000).contains(ms) else { throw SubtitleExportError.invalidTime }
        return Double(hours * 3600 + minutes * 60 + whole) + Double(ms) / 1000
    }
    static func timestamp(_ value: Double) -> String {
        guard value.isFinite, value >= 0, value <= 3_599_999.999 else { return "00:00:00,000" }
        let ms = Int((value * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }
    static func srt(_ cues: [TimedSubtitle], firstStart: Double?, mode: SubtitleTextMode) throws -> String {
        guard !cues.isEmpty else { return "" }
        guard cues.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start && $0.end <= 3_599_999.999 && !$0.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw SubtitleExportError.invalidCue }
        if let firstStart, !firstStart.isFinite || firstStart < 0 || firstStart > 3_599_999.999 { throw SubtitleExportError.invalidTime }
        let cues = cues.sorted { $0.start < $1.start }
        let first = cues[0]
        let offset = (firstStart ?? first.start) - first.start
        if mode != .original && cues.contains(where: { ($0.translated ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { throw SubtitleExportError.missingTranslations }
        guard cues.allSatisfy({ $0.end + offset <= 3_599_999.999 && (($0.start + offset) * 1000).rounded() < 3_599_999_999 }) else { throw SubtitleExportError.invalidTime }
        return cues.enumerated().map { index, cue in
            let text: String
            switch mode {
            case .original: text = cue.original
            case .translated: text = cue.translated ?? ""
            case .both: text = cue.original + "\n" + (cue.translated ?? "")
            }
            let clean = text.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n")
            return "\(index + 1)\n\(timestamp(cue.start + offset)) --> \(timestamp(max(cue.end + offset, ((cue.start + offset) * 1000).rounded() / 1000 + 0.001)))\n\(clean)\n"
        }.joined(separator: "\n")
    }
}

/// Stable cue indices stay pending until translation succeeds, including across stop/retry.
struct PendingCueQueue {
    private var indices: [Int] = []
    private var head = 0
    var count: Int { indices.count - head }
    var first: Int? { head < indices.count ? indices[head] : nil }
    mutating func append(_ index: Int) { indices.append(index) }
    mutating func finishFirst() {
        guard head < indices.count else { return }
        head += 1
        if head >= 256 && head * 2 >= indices.count {
            indices.removeFirst(head); head = 0
        }
    }
}

func validatedSubtitleTranslation(_ text: String) throws -> String {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else {
        throw NSError(domain: "KotobaTranslation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Translation returned empty text. The cue is kept pending; retry capture or export Original."])
    }
    return clean
}

/// A bad cue must not prevent later cues from being translated.
@MainActor func translateWithRetry(_ operation: () async throws -> String,
                                  pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(250)) }) async throws -> String {
    for attempt in 0..<3 {
        try Task.checkCancellation()
        do { return try validatedSubtitleTranslation(try await operation()) }
        catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            if attempt == 2 { throw error }
            try await pause()
        }
    }
    throw CancellationError()
}
