import Foundation
struct TranslationRecord: Equatable {
    let sourceLanguage: String
    let targetLanguage: String
    let original: String
    let translated: String
}
struct TranslationHistory {
    private(set) var records: [TranslationRecord] = []
    private var seen: Set<TranslationRecordKey> = []
    mutating func append(source: String, target: String, original: String, translated: String) {
        let key = TranslationRecordKey(source: source, target: target, original: original, translated: translated)
        guard seen.insert(key).inserted else { return }
        records.append(TranslationRecord(sourceLanguage: source, targetLanguage: target, original: original, translated: translated))
    }
    var plainText: String {
        "Kotoba Overlay — Session translations\n\n" + records.enumerated().map { index, item in
            "\(index + 1). \(item.sourceLanguage) → \(item.targetLanguage)\nOriginal: \(item.original)\nTranslation: \(item.translated)"
        }.joined(separator: "\n\n") + "\n"
    }
}
private struct TranslationRecordKey: Hashable {
    let source: String
    let target: String
    let original: String
    let translated: String
}
