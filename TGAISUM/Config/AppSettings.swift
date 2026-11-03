import Foundation

struct LLMNode: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var baseUrl: String
    var apiKey: String
    var model: String
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var apiId: Int { didSet { d.set(apiId, forKey: "apiId") } }
    @Published var apiHash: String { didSet { d.set(apiHash, forKey: "apiHash") } }
    @Published var phone: String { didSet { d.set(phone, forKey: "phone") } }
    @Published var llmNodes: [LLMNode] {
        didSet {
            if let data = try? JSONEncoder().encode(llmNodes) {
                d.set(data, forKey: "llmNodes")
            }
        }
    }
    @Published var summaryStyle: String { didSet { d.set(summaryStyle, forKey: "summaryStyle") } }
    @Published var autoSummarize: Bool { didSet { d.set(autoSummarize, forKey: "autoSummarize") } }
    @Published var selectedChatIds: [Int64] {
        didSet { d.set(selectedChatIds.map(String.init), forKey: "selectedChatIds") }
    }
    @Published var proxyEnabled: Bool { didSet { d.set(proxyEnabled, forKey: "proxyEnabled") } }
    @Published var proxyType: String { didSet { d.set(proxyType, forKey: "proxyType") } }
    @Published var proxyServer: String { didSet { d.set(proxyServer, forKey: "proxyServer") } }
    @Published var proxyPort: Int { didSet { d.set(proxyPort, forKey: "proxyPort") } }
    @Published var proxyUser: String { didSet { d.set(proxyUser, forKey: "proxyUser") } }
    @Published var proxyPassword: String { didSet { d.set(proxyPassword, forKey: "proxyPassword") } }

    private init() {
        d.register(defaults: [
            "summaryStyle": "请用中文输出，结构清晰，重点优先。",
            "autoSummarize": true,
        ])
        apiId = d.integer(forKey: "apiId")
        apiHash = d.string(forKey: "apiHash") ?? ""
        phone = d.string(forKey: "phone") ?? ""
        llmNodes = (d.data(forKey: "llmNodes")).flatMap { try? JSONDecoder().decode([LLMNode].self, from: $0) } ?? []
        summaryStyle = d.string(forKey: "summaryStyle") ?? "请用中文输出，结构清晰，重点优先。"
        autoSummarize = d.bool(forKey: "autoSummarize")
        selectedChatIds = (d.stringArray(forKey: "selectedChatIds") ?? []).compactMap { Int64($0) }
        proxyEnabled = d.bool(forKey: "proxyEnabled")
        proxyType = d.string(forKey: "proxyType") ?? "socks5"
        proxyServer = d.string(forKey: "proxyServer") ?? ""
        proxyPort = d.object(forKey: "proxyPort") as? Int ?? 0
        proxyUser = d.string(forKey: "proxyUser") ?? ""
        proxyPassword = d.string(forKey: "proxyPassword") ?? ""
    }
}
