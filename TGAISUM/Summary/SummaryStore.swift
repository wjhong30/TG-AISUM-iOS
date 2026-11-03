import Foundation

struct CachedSummary: Codable, Equatable {
    let chatId: Int64
    let dayKey: String
    let slotKey: String
    var text: String
    var msgCount: Int
    var generatedAt: Date
    var model: String
}

@MainActor
final class SummaryStore: ObservableObject {
    static let shared = SummaryStore()

    @Published var summaries: [String: CachedSummary] = [:]
    @Published var generating: Set<String> = []
    @Published var errors: [String: String] = [:]

    private init() {
        let url = Self.fileURL()
        if let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([CachedSummary].self, from: data) {
            summaries = Dictionary(uniqueKeysWithValues: list.map { (Self.key($0.chatId, $0.dayKey, $0.slotKey), $0) })
        }
    }

    private static func fileURL() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("summaries.json")
    }

    static func key(_ chatId: Int64, _ dayKey: String, _ slotKey: String) -> String {
        "\(chatId)|\(dayKey)|\(slotKey)"
    }

    private func persist() {
        let list = Array(summaries.values)
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: Self.fileURL(), options: .atomic)
        }
    }

    func get(_ chatId: Int64, _ dayKey: String, _ slotKey: String) -> CachedSummary? {
        summaries[Self.key(chatId, dayKey, slotKey)]
    }

    func save(_ summary: CachedSummary) {
        summaries[Self.key(summary.chatId, summary.dayKey, summary.slotKey)] = summary
        errors.removeValue(forKey: Self.key(summary.chatId, summary.dayKey, summary.slotKey))
        persist()
    }

    func remove(_ chatId: Int64, _ dayKey: String, _ slotKey: String) {
        summaries.removeValue(forKey: Self.key(chatId, dayKey, slotKey))
        errors.removeValue(forKey: Self.key(chatId, dayKey, slotKey))
        persist()
    }

    func removeAll() {
        summaries.removeAll()
        errors.removeAll()
        persist()
    }

    func setGenerating(_ key: String, _ value: Bool) {
        if value {
            generating.insert(key)
        } else {
            generating.remove(key)
        }
    }

    func setError(_ key: String, _ message: String) {
        errors[key] = message
        setGenerating(key, false)
    }
}

@MainActor
enum SummaryService {
    static func generate(chatId: Int64, chatTitle: String, dayKey: String, slot: SlotRange) async {
        let key = SummaryStore.key(chatId, dayKey, slot.key)
        let all = ArchiveStore.shared.load(chatId)
        let messages = PromptBuilder.filter(messages: all, dayKey: dayKey, slot: slot)
        guard !messages.isEmpty else {
            SummaryStore.shared.setError(key, "该时段没有文本消息")
            return
        }
        SummaryStore.shared.setGenerating(key, true)
        SummaryStore.shared.errors.removeValue(forKey: key)
        do {
            let (system, user) = PromptBuilder.build(
                groupName: chatTitle, dayKey: dayKey, slot: slot, messages: messages)
            let text = try await LLMClient.shared.summarize(system: system, user: user)
            SummaryStore.shared.save(CachedSummary(
                chatId: chatId,
                dayKey: dayKey,
                slotKey: slot.key,
                text: text,
                msgCount: messages.count,
                generatedAt: Date(),
                model: AppSettings.shared.llmNodes.first?.model ?? "?"
            ))
        } catch {
            SummaryStore.shared.setError(key, error.localizedDescription)
        }
        SummaryStore.shared.setGenerating(key, false)
    }
}
