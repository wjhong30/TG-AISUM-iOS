import SwiftUI

/// 存储空间：分类统计占用，支持全选/部分清理（参考微信/Telegram 的存储管理）
struct StorageView: View {
    @StateObject private var storage = StorageCleaner()
    @State private var showCleanConfirm = false

    private var totalBytes: Int64 {
        storage.categories.reduce(0) { $0 + $1.size }
    }
    private var selectedBytes: Int64 {
        storage.categories.filter { storage.selected.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("已占用")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    proportionBar
                    if storage.scanning {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("正在统计…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                Text("事件日志只存在内存中，不占用磁盘；TDLib 数据库（登录态）不可在此清理，退出登录时会自动删除。")
            }

            Section("可清理项目（点按勾选）") {
                ForEach(storage.categories) { c in
                    row(c)
                }
            }

            Section {
                Button(role: .destructive) {
                    showCleanConfirm = true
                } label: {
                    HStack {
                        Spacer()
                        if storage.cleaning {
                            ProgressView().padding(.trailing, 6)
                        }
                        Text(storage.selected.isEmpty
                             ? "清理所选"
                             : "清理所选（\(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file))）")
                        Spacer()
                    }
                }
                .disabled(storage.selected.isEmpty || storage.cleaning || storage.scanning)
            }
        }
        .navigationTitle("存储空间")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(storage.allSelected ? "取消全选" : "全选") {
                    storage.toggleSelectAll()
                }
                .disabled(storage.scanning || storage.cleaning)
            }
        }
        .confirmationDialog(cleanConfirmText, isPresented: $showCleanConfirm, titleVisibility: .visible) {
            Button("确认清理", role: .destructive) {
                Task { await storage.cleanSelected() }
            }
        } message: {
            Text("清理后对应的缓存/数据将被删除，相关内容需要重新下载或重新生成。")
        }
        .onAppear { storage.reload() }
        .refreshable { storage.reload() }
    }

    private var cleanConfirmText: String {
        let names = storage.categories
            .filter { storage.selected.contains($0.id) }
            .map(\.name)
            .joined(separator: "、")
        return "清理 \(names.isEmpty ? "—" : names)？"
    }

    /// 占用比例条（各分类按占比着色）
    private var proportionBar: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(storage.categories.filter { $0.size > 0 }) { c in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(c.tint)
                        .frame(width: max(4, geo.size.width * CGFloat(c.size) / CGFloat(max(totalBytes, 1)) - 2))
                }
                if totalBytes == 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(uiColor: .tertiarySystemFill))
                }
            }
        }
        .frame(height: 8)
    }

    @ViewBuilder
    private func row(_ c: StorageCleaner.Category) -> some View {
        Button {
            if c.cleanable {
                storage.toggle(c.id)
            }
        } label: {
            HStack(spacing: 12) {
                if c.cleanable {
                    Image(systemName: storage.selected.contains(c.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(storage.selected.contains(c.id) ? Color.accentColor : Color.secondary)
                        .font(.title3)
                } else {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.tertiary)
                        .font(.title3)
                }
                Image(systemName: c.icon)
                    .foregroundStyle(c.tint)
                    .font(.title3)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name)
                        .foregroundStyle(.primary)
                    Text(c.consequence)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ByteCountFormatter.string(fromByteCount: c.size, countStyle: .file))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    if let n = c.count {
                        Text("\(n) 个文件")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!c.cleanable)
    }
}

@MainActor
final class StorageCleaner: ObservableObject {
    enum Kind: Hashable {
        case tdFiles, sharedCopies, summaries, archives, tdlibDb
    }

    struct Category: Identifiable {
        let id: Kind
        let name: String
        let icon: String
        let tint: Color
        let consequence: String
        var size: Int64 = 0
        var count: Int?
        let cleanable: Bool
    }

    @Published var categories: [Category] = StorageCleaner.baseCategories
    @Published var selected: Set<Kind> = []
    @Published var scanning = false
    @Published var cleaning = false

    private static let baseCategories: [Category] = [
        Category(id: .tdFiles, name: "图片与媒体文件",
                 icon: "photo.on.rectangle.angled", tint: .blue,
                 consequence: "TDLib 下载的图片/视频/文件原件；清理后查看需重新下载", cleanable: true),
        Category(id: .sharedCopies, name: "文件预览副本",
                 icon: "doc.fill", tint: .orange,
                 consequence: "预览/分享时拷贝出的文件副本；清理后点按文件可重新生成", cleanable: true),
        Category(id: .summaries, name: "总结缓存",
                 icon: "sparkles", tint: .purple,
                 consequence: "所有已生成的 AI 总结；清理后需重新生成（会消耗 LLM 额度）", cleanable: true),
        Category(id: .archives, name: "聊天记录归档",
                 icon: "archivebox.fill", tint: .green,
                 consequence: "离线归档的原始消息；清理后自动回抓近 7 天，更早的可进对应日期补抓", cleanable: true),
        Category(id: .tdlibDb, name: "TDLib 数据库",
                 icon: "cylinder.split.1x2", tint: .gray,
                 consequence: "登录态与消息索引；退出登录时自动清理", cleanable: false),
    ]

    var allSelected: Bool {
        let ids = Set(categories.filter(\.cleanable).map(\.id))
        return ids.isSubset(of: selected) && !ids.isEmpty
    }

    func toggle(_ kind: Kind) {
        if selected.contains(kind) {
            selected.remove(kind)
        } else {
            selected.insert(kind)
        }
    }

    func toggleSelectAll() {
        if allSelected {
            selected.removeAll()
        } else {
            selected = Set(categories.filter(\.cleanable).map(\.id))
        }
    }

    func reload() {
        guard !scanning else { return }
        scanning = true
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let paths: [(Kind, URL)] = [
            (.tdFiles, docs.appendingPathComponent("td-files", isDirectory: true)),
            (.sharedCopies, caches.appendingPathComponent("shared", isDirectory: true)),
            (.summaries, docs.appendingPathComponent("summaries.json")),
            (.archives, docs.appendingPathComponent("archive", isDirectory: true)),
            (.tdlibDb, docs.appendingPathComponent("td-db", isDirectory: true)),
        ]
        Task.detached { [weak self] in
            let stats = Self.computeStats(paths)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.categories = self.categories.map { c in
                    var c = c
                    let s = stats[c.id] ?? (0, 0)
                    c.size = s.bytes
                    c.count = s.count
                    return c
                }
                self.scanning = false
            }
        }
    }

    nonisolated private static func computeStats(_ paths: [(Kind, URL)]) -> [Kind: (bytes: Int64, count: Int)] {
        var stats: [Kind: (bytes: Int64, count: Int)] = [:]
        for (kind, url) in paths {
            if kind == .summaries {
                let v = try? url.resourceValues(forKeys: [.fileSizeKey])
                stats[kind] = (Int64(v?.fileSize ?? 0), 1)
            } else {
                stats[kind] = dirStats(url)
            }
        }
        return stats
    }

    func cleanSelected() async {
        cleaning = true
        defer { cleaning = false }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        for kind in selected {
            switch kind {
            case .tdFiles:
                Self.clearDirectory(docs.appendingPathComponent("td-files", isDirectory: true))
            case .sharedCopies:
                try? FileManager.default.removeItem(at: caches.appendingPathComponent("shared", isDirectory: true))
            case .summaries:
                SummaryStore.shared.removeAll()
            case .archives:
                ArchiveStore.shared.deleteEverything()
                SyncService.shared.resetCheckpoints()
            case .tdlibDb:
                break
            }
        }
        selected.removeAll()
        reload()
    }

    // MARK: - 磁盘统计

    nonisolated private static func dirStats(_ url: URL) -> (bytes: Int64, count: Int) {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else {
            return (0, 0)
        }
        var bytes: Int64 = 0
        var n = 0
        for case let f as URL in en {
            guard let v = try? f.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  v.isRegularFile == true else { continue }
            bytes += Int64(v.fileSize ?? 0)
            n += 1
        }
        return (bytes, n)
    }

    nonisolated private static func clearDirectory(_ url: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return }
        for item in items {
            try? fm.removeItem(at: item)
        }
    }
}
