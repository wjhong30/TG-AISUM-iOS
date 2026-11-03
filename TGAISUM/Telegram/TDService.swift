import Foundation
import TDLibKit

enum AuthUIState: Equatable {
    case idle
    case connecting
    case waitingPhone
    case waitingCode
    case waitingPassword
    case ready
    case failed(String)
}

@MainActor
final class TDService: ObservableObject {
    static let shared = TDService()

    @Published var authState: AuthUIState = .idle

    private var manager: TDLibClientManager?
    private var client: TDLibClient?
    private var started = false
    private var nameCache: [Int64: String] = [:]

    private var docs: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func start() {
        guard !started else { return }
        guard AppSettings.shared.apiId != 0, !AppSettings.shared.apiHash.isEmpty else {
            authState = .idle
            return
        }
        started = true
        authState = .connecting
        let manager = TDLibClientManager()
        self.manager = manager
        client = manager.createClient { [weak self] data, _ in
            self?.handleUpdate(data)
        }
    }

    private nonisolated func handleUpdate(_ data: Data) {
        guard let update = try? JSONDecoder().decode(Update.self, from: data) else { return }
        guard case .updateAuthorizationState(let s) = update else { return }
        Task { @MainActor [weak self] in
            await self?.apply(state: s.authorizationState)
        }
    }

    private func apply(state: AuthorizationState) async {
        switch state {
        case .authorizationStateWaitTdlibParameters:
            do {
                try await client?.setTdlibParameters(
                    apiHash: AppSettings.shared.apiHash,
                    apiId: AppSettings.shared.apiId,
                    applicationVersion: "0.1.0",
                    databaseDirectory: docs.appendingPathComponent("td-db", isDirectory: true).path,
                    databaseEncryptionKey: nil,
                    deviceModel: "iPhone",
                    filesDirectory: docs.appendingPathComponent("td-files", isDirectory: true).path,
                    systemLanguageCode: "zh",
                    systemVersion: "iOS",
                    useChatInfoDatabase: true,
                    useFileDatabase: true,
                    useMessageDatabase: true,
                    useSecretChats: false,
                    useTestDc: false
                )
            } catch {
                authState = .failed("初始化失败: \(error.localizedDescription)")
            }
        case .authorizationStateWaitPhoneNumber:
            authState = .waitingPhone
        case .authorizationStateWaitCode:
            authState = .waitingCode
        case .authorizationStateWaitPassword:
            authState = .waitingPassword
        case .authorizationStateWaitRegistration:
            authState = .failed("该手机号未注册 Telegram，请先在官方客户端注册")
        case .authorizationStateWaitEmailAddress:
            authState = .failed("该账号开启了邮箱验证，暂不支持，请先用官方客户端处理")
        case .authorizationStateWaitEmailCode:
            authState = .failed("该账号开启了邮箱验证，暂不支持，请先用官方客户端处理")
        case .authorizationStateReady:
            authState = .ready
        case .authorizationStateClosed, .authorizationStateLoggingOut, .authorizationStateClosing:
            if state != .authorizationStateLoggingOut {
                started = false
                client = nil
                authState = .idle
            } else {
                authState = .connecting
            }
        default:
            break
        }
    }

    // MARK: - 登录动作

    func sendPhone(_ phone: String) async {
        authState = .connecting
        do {
            try await client?.setAuthenticationPhoneNumber(phoneNumber: phone, settings: nil)
        } catch {
            authState = .failed("发送验证码失败: \(error.localizedDescription)")
        }
    }

    func submitCode(_ code: String) async {
        do {
            try await client?.checkAuthenticationCode(code: code)
        } catch {
            authState = .failed("验证码错误: \(error.localizedDescription)")
        }
    }

    func submitPassword(_ password: String) async {
        do {
            try await client?.checkAuthenticationPassword(password: password)
        } catch {
            authState = .failed("两步验证密码错误: \(error.localizedDescription)")
        }
    }

    func logout() async {
        authState = .connecting
        try? await client?.logOut()
    }

    // MARK: - 数据接口

    func fetchGroupChats() async -> [(id: Int64, title: String)] {
        var result: [(Int64, String)] = []
        guard let client else { return [] }
        do {
            let chats = try await client.getChats(chatList: nil, limit: 200)
            for chatId in chats.chatIds {
                guard let chat = try? await client.getChat(chatId: chatId) else { continue }
                switch chat.type {
                case .chatTypeBasicGroup, .chatTypeSupergroup:
                    result.append((chat.id, chat.title))
                default:
                    break
                }
            }
        } catch {
            return []
        }
        return result
    }

    func fetchMessages(chatId: Int64, stopBeforeDate: Int, maxMessages: Int = 30000) async -> [ArchiveMessage] {
        guard let client else { return [] }
        var out: [ArchiveMessage] = []
        var fromId: Int64 = 0
        while out.count < maxMessages {
            let batch: Messages
            do {
                batch = try await client.getChatHistory(
                    chatId: chatId, fromMessageId: fromId, limit: 100, offset: 0, onlyLocal: false)
            } catch {
                break
            }
            let msgs = batch.messages ?? []
            if msgs.isEmpty { break }
            var reachedEnd = false
            for m in msgs {
                if m.date < stopBeforeDate {
                    reachedEnd = true
                    continue
                }
                let sender = await displayName(sender: m.senderId)
                let (text, isMedia) = Self.extract(content: m.content)
                out.append(ArchiveMessage(id: m.id, date: m.date, sender: sender, text: text, isMedia: isMedia))
                fromId = m.id
            }
            if reachedEnd { break }
            if msgs.count < 100 { break }
        }
        return out
    }

    private func displayName(sender: MessageSender?) async -> String {
        switch sender {
        case .messageSenderUser(let u):
            if let cached = nameCache[u.userId] { return cached }
            let user = try? await client?.getUser(userId: u.userId)
            var name = [user?.firstName, user?.lastName]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if name.isEmpty {
                name = user?.usernames?.activeUsernames.first ?? "user\(u.userId)"
            }
            nameCache[u.userId] = name
            return name
        case .messageSenderChat(let c):
            if let cached = nameCache[c.chatId] { return cached }
            let chat = try? await client?.getChat(chatId: c.chatId)
            let name = chat?.title ?? "chat\(c.chatId)"
            nameCache[c.chatId] = name
            return name
        case nil:
            return "unknown"
        }
    }

    static func extract(content: MessageContent) -> (text: String, isMedia: Bool) {
        switch content {
        case .messageText(let t):
            return (t.text.text, false)
        case .messagePhoto:
            return ("[图片]", true)
        case .messageVideo:
            return ("[视频]", true)
        case .messageAnimation:
            return ("[动图]", true)
        case .messageAudio:
            return ("[音频]", true)
        case .messageVoiceNote:
            return ("[语音]", true)
        case .messageVideoNote:
            return ("[视频笔记]", true)
        case .messageDocument:
            return ("[文件]", true)
        case .messageSticker:
            return ("[贴纸]", true)
        case .messagePaidMedia:
            return ("[付费媒体]", true)
        default:
            return ("", false)
        }
    }
}
