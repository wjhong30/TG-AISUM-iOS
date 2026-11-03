import SwiftUI

/// 首页：QQ 风格聊天列表（清单里的每个群一行，点开即元宝式总结页）
struct ChatListView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var summaryStore = SummaryStore.shared
    @ObservedObject private var archive = ArchiveStore.shared
    @ObservedObject private var sync = SyncService.shared

    @State private var titles: [Int64: String] = [:]
    @State private var didAutoRun = false

    /// 今天「全天」时段，自动总结按它计数
    private var todayKey: String { DayUtil.dayKey(Date()) }
    private var fullSlot: SlotRange { .full }

    private struct Row: Identifiable {
        let chatId: Int64
        let title: String
        let lastMessage: ArchiveMessage?
        let todayCount: Int
        let newCount: Int
        let generating: Bool
        var id: Int64 { chatId }
    }

    private var rows: [Row] {
        settings.selectedChatIds.map { chatId in
            let all = archive.load(chatId)
            let todayCount = PromptBuilder.filter(messages: all, dayKey: todayKey, slot: fullSlot).count
            let summary = summaryStore.get(chatId, todayKey, fullSlot.key)
            return Row(
                chatId: chatId,
                title: titles[chatId] ?? "群 \(chatId)",
                lastMessage: all.last,
                todayCount: todayCount,
                newCount: summary.map { max(todayCount - $0.msgCount, 0) } ?? 0,
                generating: summaryStore.generating.contains(SummaryStore.key(chatId, todayKey, fullSlot.key))
            )
        }
        .sorted { ($0.lastMessage?.date ?? 0) > ($1.lastMessage?.date ?? 0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if settings.selectedChatIds.isEmpty {
                    emptyState
                } else {
                    List {
                        if sync.syncing {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("正在同步消息…")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        ForEach(rows) { row in
                            NavigationLink(value: SummaryTarget(chatId: row.chatId, title: row.title)) {
                                rowView(row)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("消息")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await runSyncAndSummarize(force: false) }
                    } label: {
                        if sync.syncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(sync.syncing || settings.selectedChatIds.isEmpty)
                }
            }
            .refreshable {
                await runSyncAndSummarize(force: false)
            }
            .navigationDestination(for: SummaryTarget.self) { target in
                GroupSummaryView(chatId: target.chatId, chatTitle: target.title)
            }
            .navigationDestination(for: ChatLogTarget.self) { target in
                ChatLogView(target: target)
            }
            .task {
                if !didAutoRun {
                    didAutoRun = true
                    await runSyncAndSummarize(force: false)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("清单里还没有群")
                .font(.headline)
            Text("去「群组」页勾选要总结的群，回到这里点开即看 AI 总结")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            NavigationLink("去群组页选择") {
                GroupsView()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
    }

    // MARK: - 单行

    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 12) {
            ChatAvatar(name: row.title, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Text(lastTime(row))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 8) {
                    Text(previewText(row))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if row.generating {
                        HStack(spacing: 4) {
                            ProgressView().scaleEffect(0.6)
                            Text("总结中")
                                .font(.caption2)
                                .foregroundStyle(.tint)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                    } else if row.newCount > 0 {
                        Text("\(row.newCount) 条新")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.orange, in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func previewText(_ row: Row) -> String {
        if let m = row.lastMessage {
            let sender = m.sender
            return "\(sender)：\(m.text)"
        }
        return "还没有同步到消息"
    }

    private func lastTime(_ row: Row) -> String {
        guard let m = row.lastMessage else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(m.date))
        let isToday = DayUtil.dayKey(date) == todayKey
        if isToday {
            return DayUtil.clockString(m.date)
        }
        let c = DayUtil.calendarDateComponents(date)
        return "\(c.month ?? 0)/\(c.day ?? 0)"
    }

    // MARK: - 同步 + 自动总结

    private func runSyncAndSummarize(force: Bool) async {
        if titles.isEmpty {
            let chats = await TDService.shared.fetchGroupChats()
            titles = Dictionary(uniqueKeysWithValues: chats.map { ($0.id, $0.title) })
        }
        await sync.syncAll(chatIds: settings.selectedChatIds)
        guard settings.autoSummarize || force else { return }
        for chatId in settings.selectedChatIds {
            let messages = PromptBuilder.filter(messages: archive.load(chatId), dayKey: todayKey, slot: fullSlot)
            let summary = summaryStore.get(chatId, todayKey, fullSlot.key)
            let should = force || SummaryPolicy.shouldAutoRegenerate(summary: summary, currentCount: messages.count)
            if should {
                if force { summaryStore.remove(chatId, todayKey, fullSlot.key) }
                await SummaryService.generate(
                    chatId: chatId,
                    chatTitle: titles[chatId] ?? "群 \(chatId)",
                    dayKey: todayKey,
                    slot: fullSlot)
            }
        }
    }
}

struct SummaryTarget: Hashable {
    let chatId: Int64
    let title: String
}
