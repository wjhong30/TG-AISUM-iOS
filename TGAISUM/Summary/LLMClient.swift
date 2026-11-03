import Foundation

enum LLMError: LocalizedError {
    case noNodes
    case allNodesFailed(String)

    var errorDescription: String? {
        switch self {
        case .noNodes:
            return "尚未配置 LLM 节点，请到「设置」添加"
        case .allNodesFailed(let detail):
            return "所有 LLM 节点均失败：\(detail)"
        }
    }
}

final class LLMClient {
    static let shared = LLMClient()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 600
        session = URLSession(configuration: config)
    }

    func summarize(system: String, user: String) async throws -> String {
        let nodes = AppSettings.shared.llmNodes
        guard !nodes.isEmpty else { throw LLMError.noNodes }
        var lastError: String = "未知错误"
        for node in nodes {
            do {
                let text = try await call(node, system: system, user: user)
                if !text.isEmpty { return text }
                lastError = "节点 \(node.name) 返回空内容"
            } catch {
                lastError = "节点 \(node.name): \(error.localizedDescription)"
            }
        }
        throw LLMError.allNodesFailed(lastError)
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        struct Message: Encodable {
            let role: String
            let content: String
        }
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Msg: Decodable {
                let content: String?
            }
            let message: Msg
        }
        let choices: [Choice]?
        let error: ApiError?
        struct ApiError: Decodable {
            let message: String?
        }
    }

    private func call(_ node: LLMNode, system: String, user: String) async throws -> String {
        var base = node.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/chat/completions") else {
            throw LLMError.allNodesFailed("无效的 Base URL: \(node.baseUrl)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(node.apiKey)", forHTTPHeaderField: "Authorization")
        let body = ChatRequest(model: node.model, messages: [
            .init(role: "system", content: system),
            .init(role: "user", content: user),
        ])
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let resp = try? JSONDecoder().decode(ChatResponse.self, from: data)
            let msg = resp?.error?.message ?? String(data: data.prefix(300), encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw LLMError.allNodesFailed("HTTP \(http.statusCode): \(msg)")
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        return decoded.choices?.first?.message.content ?? ""
    }
}
