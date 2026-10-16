import Foundation

struct TranslationHistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let original: String
    let translated: String
    let sourceLanguage: String?
    let targetLanguage: String
    let provider: ProviderType
    let operation: AIOperation
    let timestamp: Date

    init(
        id: UUID = UUID(),
        original: String,
        translated: String,
        sourceLanguage: String? = nil,
        targetLanguage: String,
        provider: ProviderType,
        operation: AIOperation = .translate,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.original = original
        self.translated = translated
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.provider = provider
        self.operation = operation
        self.timestamp = timestamp
    }
}

extension TranslationHistoryEntry: CloudMergeable {
    var mergeTimestamp: Date { timestamp }
}
