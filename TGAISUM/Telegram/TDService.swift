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
    @Published var lastEvent: String = ""
    @Published var eventLog: [String] = []

    private var manager: TDLibClientManager?
    private var client: TDLibClient?
    private var started = false
    private var nameCache: [Int64: String] = [:]
    private var connectTimer: Timer?

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
        lastEvent = ""
        eventLog = []
        connectTimer?.invalidate()
        connectTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.authState == .connecting else { return }
                self.appendLog("⏱ 25 秒仍无任何 Telegram 事件")
                self.authState = .failed(
                    "连接超时：25 秒内 TDLib 没有收到任何事件。" +
                    "如果下方事件日志为空，多半是本 App 无法直连 Telegram 服务器" +
                    "（即使官方客户端能连——它可能走了应用内代理）。可在设置里尝试配置代理。")
            }
        }
        let manager = TDLibClientManager()
        self.manager = manager
        client = manager.createClient { [weak self] data, _ in
            self?.handleUpdate(data)
        }
    }

    private nonisolated func appendLog(_ line: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.lastEvent = line
            self.eventLog.append(line)
            if self.eventLog.count > 12 {
                self.eventLog.removeFirst(self.eventLog.count - 12)
            }
        }
    }

    private nonisolated func handleUpdate(_ data: Data) {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            appendLog("⚠️ 无法解析的原始数据（\(data.count) 字节）")
            return
        }
        let type = dict["@type"] as? String ?? "?"
        if type == "updateAuthorizationState" {
            appendLog("📩 \(type)")
            if let update = try? Self.decoder.decode(Update.self, from: data),
               case .updateAuthorizationState(let s) = update {
                Task { @MainActor [weak self] in
                    await self?.apply(state: s.authorizationState)
                }
            } else {
                appendLog("⚠️ 授权状态事件解码失败")
            }
        } else if type.hasPrefix("update") {
            appendLog("· \(type)")
        } else {
            appendLog("· \(type)")
        }
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private func apply(state: AuthorizationState) async {
        switch state {
        case .authorizationStateWaitTdlibParameters:
            do {
                try await client?.setTdlibParameters(
                    apiHash: AppSettings.shared.apiHash,
                    apiId: AppSettings.shared.apiId,
                    applicationVersion: "0.1.1",
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
                await applyProxyIfNeeded()
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
            connectTimer?.invalidate()
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

    private func applyProxyIfNeeded() async {
        let s = AppSettings.shared
        guard s.proxyEnabled, !s.proxyServer.isEmpty, s.proxyPort > 0, let client else { return }
        let type: ProxyType
        if s.proxyType == "http" {
            type = .proxyTypeHttp(ProxyTypeHttp(
                httpOnly: false,
                password: s.proxyPassword,
                username: s.proxyUser))
        } else {
            type = .proxyTypeSocks5(ProxyTypeSocks5(
                password: s.proxyPassword,
                username: s.proxyUser))
        }
        do {
            _ = try await client.addProxy(
                comment: nil, enable: true,
                proxy: Proxy(port: s.proxyPort, server: s.proxyServer, type: type))
            appendLog("🔀 已启用代理 \(s.proxyServer):\(s.proxyPort)")
        } catch {
            appendLog("⚠️ 代理设置失败: \(error.localizedDescription)")
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
        var lastOldestId: Int64 = -1
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
                    break
                }
                let sender = await displayName(sender: m.senderId)
                let (text, isMedia) = Self.extract(content: m.content)
                out.append(ArchiveMessage(id: m.id, date: m.date, sender: sender, text: text, isMedia: isMedia))
                fromId = m.id
            }
            if reachedEnd { break }
            // TDLib 单批常返回少于 limit 但仍有更多历史，不能按数量判断结束；
            // 只有最旧消息 id 不再前进（防死循环）才停
            if let oldest = msgs.last?.id {
                if oldest == lastOldestId { break }
                lastOldestId = oldest
                fromId = oldest
            }
        }
        return out
    }

    /// 下载某条消息里的图片（同步等待完成），返回本地文件路径
    func downloadImage(chatId: Int64, messageId: Int64) async -> String? {
        guard let client else { return nil }
        guard let msg = try? await client.getMessage(chatId: chatId, messageId: messageId) else { return nil }
        var fileId: Int?
        if case .messagePhoto(let p) = msg.content {
            fileId = p.photo.sizes.max(by: { $0.width * $0.height < $1.width * $1.height })?.photo.id
        }
        guard let fid = fileId else { return nil }
        // 已下载过就直接用
        if let cached = imagePaths[fid] { return cached }
        do {
            let file = try await client.downloadFile(
                fileId: fid, limit: 0, offset: 0, priority: 16, synchronous: true)
            if file.local.isDownloadingCompleted, !file.local.path.isEmpty {
                imagePaths[fid] = file.local.path
                return file.local.path
            }
        } catch {
            return nil
        }
        return nil
    }

    private var imagePaths: [Int: String] = [:]

    struct DownloadedFile {
        let url: URL
        let name: String
        let size: Int64
        let mime: String
    }

    /// 下载某条消息里的文件（文档），复制到缓存目录，返回可预览/分享的本地 URL
    func downloadDocument(chatId: Int64, messageId: Int64) async -> DownloadedFile? {
        guard let client else { return nil }
        guard let msg = try? await client.getMessage(chatId: chatId, messageId: messageId) else { return nil }
        guard case .messageDocument(let d) = msg.content else { return nil }
        let doc = d.document
        return await downloadAndStage(
            client: client, fileId: doc.document.id,
            name: doc.fileName, size: doc.document.size > 0 ? doc.document.size : doc.document.expectedSize,
            mime: doc.mimeType)
    }

    /// 下载某条消息里的视频，返回可播放/分享的本地 URL
    func downloadVideo(chatId: Int64, messageId: Int64) async -> DownloadedFile? {
        guard let client else { return nil }
        guard let msg = try? await client.getMessage(chatId: chatId, messageId: messageId) else { return nil }
        guard case .messageVideo(let v) = msg.content else { return nil }
        let vid = v.video
        return await downloadAndStage(
            client: client, fileId: vid.video.id,
            name: vid.fileName.isEmpty ? "video-\(vid.video.id).mp4" : vid.fileName,
            size: vid.video.size > 0 ? vid.video.size : vid.video.expectedSize,
            mime: vid.mimeType.isEmpty ? "video/mp4" : vid.mimeType)
    }

    /// 下载 TDLib 文件并复制一份到缓存目录（按原始文件名），供预览/分享使用
    private func downloadAndStage(client: TDLibClient, fileId: Int, name: String, size: Int64, mime: String) async -> DownloadedFile? {
        if let cached = downloadedFiles[fileId] { return cached }
        do {
            let file = try await client.downloadFile(
                fileId: fileId, limit: 0, offset: 0, priority: 16, synchronous: true)
            guard file.local.isDownloadingCompleted, !file.local.path.isEmpty else { return nil }
            let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("shared", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let rawName = name.isEmpty ? "file-\(fileId)" : name
            var dst = dir.appendingPathComponent(rawName)
            if FileManager.default.fileExists(atPath: dst.path) {
                let ext = dst.pathExtension
                let base = dst.deletingPathExtension().lastPathComponent
                dst = dir.appendingPathComponent(ext.isEmpty ? "\(base)-\(fileId)" : "\(base)-\(fileId).\(ext)")
            }
            try? FileManager.default.copyItem(at: URL(fileURLWithPath: file.local.path), to: dst)
            guard FileManager.default.fileExists(atPath: dst.path) else { return nil }
            let result = DownloadedFile(url: dst, name: rawName, size: size, mime: mime)
            downloadedFiles[fileId] = result
            return result
        } catch {
            return nil
        }
    }

    private var downloadedFiles: [Int: DownloadedFile] = [:]

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
        case .messageVideo(let v):
            let name = v.video.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
            return (name.isEmpty ? "[视频]" : "[视频] \(name)", true)
        case .messageAnimation:
            return ("[动图]", true)
        case .messageAudio:
            return ("[音频]", true)
        case .messageVoiceNote:
            return ("[语音]", true)
        case .messageVideoNote:
            return ("[视频笔记]", true)
        case .messageDocument(let d):
            let name = d.document.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
            return (name.isEmpty ? "[文件]" : "[文件] \(name)", true)
        case .messageSticker:
            return ("[贴纸]", true)
        case .messagePaidMedia:
            return ("[付费媒体]", true)
        default:
            return ("", false)
        }
    }
}
