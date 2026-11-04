import Foundation

struct ArchiveMessage: Codable, Identifiable, Equatable {
    let id: Int64
    let date: Int
    let sender: String
    let text: String
    let isMedia: Bool
}

@MainActor
final class ArchiveStore: ObservableObject {
    static let shared = ArchiveStore()

    @Published var syncState: [Int64: String] = [:]

    private var cache: [Int64: [ArchiveMessage]] = [:]

    private var dir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("archive", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func fileURL(_ chatId: Int64) -> URL {
        dir.appendingPathComponent("chat_\(chatId).json")
    }

    func load(_ chatId: Int64) -> [ArchiveMessage] {
        if let cached = cache[chatId] { return cached }
        guard let data = try? Data(contentsOf: fileURL(chatId)),
              let msgs = try? JSONDecoder().decode([ArchiveMessage].self, from: data) else {
            return []
        }
        cache[chatId] = msgs
        return msgs
    }

    func merge(_ chatId: Int64, _ incoming: [ArchiveMessage]) {
        guard !incoming.isEmpty else { return }
        var byId: [Int64: ArchiveMessage] = [:]
        for m in load(chatId) { byId[m.id] = m }
        for m in incoming { byId[m.id] = m }
        let merged = byId.values.sorted { $0.id < $1.id }
        cache[chatId] = merged
        if let data = try? JSONEncoder().encode(merged) {
            try? data.write(to: fileURL(chatId), options: .atomic)
        }
    }

    func deleteAll(_ chatId: Int64) {
        cache[chatId] = nil
        try? FileManager.default.removeItem(at: fileURL(chatId))
    }

    func deleteEverything() {
        for (chatId, _) in cache {
            try? FileManager.default.removeItem(at: fileURL(chatId))
        }
        cache.removeAll()
        try? FileManager.default.removeItem(at: dir)
    }
}

@MainActor
final class SyncService: ObservableObject {
    static let shared = SyncService()

    @Published var syncing = false
    @Published var lastSync: [Int64: Date] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: "lastSync"),
           let dict = try? JSONDecoder().decode([String: Date].self, from: data) {
            lastSync = dict.reduce(into: [:]) { acc, kv in
                acc[Int64(kv.key) ?? 0] = kv.value
            }
        }
    }

    private func persistLastSync() {
        let dict = lastSync.mapKeys { String($0) }
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: "lastSync")
        }
    }

    /// 清空归档后调用：断点归零，下次同步重新回抓近 7 天
    func resetCheckpoints() {
        lastSync.removeAll()
        UserDefaults.standard.removeObject(forKey: "lastSync")
    }

    /// 同步指定群：首次抓近 7 天，此后增量（多回看 1 小时防边界遗漏）
    func syncAll(chatIds: [Int64]) async {
        guard !syncing else { return }
        // v0.5.1 一次性全量重抓 7 天：修复历史版本翻页截断留下的缺口
        if !UserDefaults.standard.bool(forKey: "resync7d.v1") {
            UserDefaults.standard.set(true, forKey: "resync7d.v1")
            lastSync.removeAll()
        }
        syncing = true
        defer { syncing = false }
        for chatId in chatIds {
            ArchiveStore.shared.syncState[chatId] = "同步中…"
            let last = lastSync[chatId] ?? Date().addingTimeInterval(-7 * 86400)
            let windowStart = Int(last.addingTimeInterval(-3600).timeIntervalSince1970)
            let msgs = await TDService.shared.fetchMessages(chatId: chatId, stopBeforeDate: windowStart)
            ArchiveStore.shared.merge(chatId, msgs)
            let archived = ArchiveStore.shared.load(chatId)
            // 断点取实际归档的最新一条消息时间：同步被截断/失败时缺口会在下次自动回补
            if let newest = archived.map(\.date).max() {
                lastSync[chatId] = Date(timeIntervalSince1970: TimeInterval(newest))
            }
            ArchiveStore.shared.syncState[chatId] = "已归档 \(archived.count) 条\(msgs.isEmpty ? "" : "（本次新增 \(msgs.count) 条）")"
            persistLastSync()
        }
    }
}

extension Dictionary {
    func mapKeys<K>(_ transform: (Key) -> K) -> [K: Value] {
        var out: [K: Value] = [:]
        for (k, v) in self { out[transform(k)] = v }
        return out
    }
}
