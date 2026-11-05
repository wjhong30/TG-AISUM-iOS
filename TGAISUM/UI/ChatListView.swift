import SwiftUI

/// 首页：QQ 风格聊天列表（清单里的每个群一行，点开即元宝式总结页）
/// 顶部可切换日期：列表行与「已总结/未总结」状态按所选日期展示
struct ChatListView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var summaryStore = SummaryStore.shared
    @ObservedObject private var archive = ArchiveStore.shared
    @ObservedObject private var sync = SyncService.shared

    @State private var titles: [Int64: String] = [:]
    @State private var didAutoRun = false
    @State private var selectedDay = Date()

    private var dayKey: String { DayUtil.dayKey(selectedDay) }
    private var fullSlot: SlotRange { .full }

    private struct Row: Identifiable {
        let chatId: Int64
        let title: String
        let lastMessage: ArchiveMessage?
        let dayCount: Int
        let newCount: Int
        let generating: Bool
        let summarized: Bool
        var id: Int64 { chatId }
    }

    private var rows: [Row] {
        settings.selectedChatIds.map { chatId in
            let all = archive.load(chatId)
            let dayCount = PromptBuilder.filter(messages: all, dayKey: dayKey, slot: fullSlot).count
            let summary = summaryStore.get(chatId, dayKey, fullSlot.key)
            return Row(
                chatId: chatId,
                title: titles[chatId] ?? "群 \(chatId)",
                lastMessage: all.last,
                dayCount: dayCount,
                newCount: summary.map { max(dayCount - $0.msgCount, 0) } ?? 0,
                generating: summaryStore.generating.contains(SummaryStore.key(chatId, dayKey, fullSlot.key)),
                summarized: summary != nil
            )
        }
        .sorted { ($0.lastMessage?.date ?? 0) > ($1.lastMessage?.date ?? 0) }
    }

    /// 最近 7 天的日期条
    private var recentDays: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if settings.selectedChatIds.isEmpty {
                    emptyState
                } else {
                    List {
                        dayBar
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
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
                            NavigationLink(value: SummaryTarget(chatId: row.chatId, title: row.title, day: selectedDay)) {
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
                GroupSummaryView(chatId: target.chatId, chatTitle: target.title, initialDay: target.day)
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

    /// 日期条：最近 7 天胶囊，选中的高亮；行的总结状态跟随所选日期
    private var dayBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(recentDays, id: \.timeIntervalSince1970) { d in
                    let key = DayUtil.dayKey(d)
                    Button {
                        selectedDay = d
                    } label: {
                        Text(dayLabel(d))
                            .font(.footnote.weight(isSelected(d) ? .semibold : .regular))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 6)
                            .background(
                                isSelected(d) ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground),
                                in: Capsule())
                            .foregroundStyle(isSelected(d) ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .id(key)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    private func isSelected(_ d: Date) -> Bool {
        DayUtil.dayKey(d) == dayKey
    }

    private func dayLabel(_ d: Date) -> String {
        let key = DayUtil.dayKey(d)
        if key == DayUtil.dayKey(Date()) { return "今天" }
        if key == DayUtil.dayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()) { return "昨天" }
        let c = DayUtil.calendarDateComponents(d)
        return "\(c.month ?? 0)/\(c.day ?? 0)"
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
                        statusCapsule("总结中", color: .accentColor)
                    } else if row.dayCount == 0 {
                        Text("无消息")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else if row.summarized {
                        statusCapsule("已总结", color: .green)
                        if row.newCount > 0 {
                            Text("\(row.newCount) 条新")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.orange, in: Capsule())
                        }
                    } else {
                        statusCapsule("未总结 \(row.dayCount) 条", color: .orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func statusCapsule(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
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
        let isToday = DayUtil.dayKey(date) == DayUtil.dayKey(Date())
        if isToday {
            return DayUtil.clockString(m.date)
        }
        let c = DayUtil.calendarDateComponents(date)
        return "\(c.month ?? 0)/\(c.day ?? 0)"
    }

    // MARK: - 同步 + 自动总结（按所选日期）

    private func runSyncAndSummarize(force: Bool) async {
        if titles.isEmpty {
            let chats = await TDService.shared.fetchGroupChats()
            titles = Dictionary(uniqueKeysWithValues: chats.map { ($0.id, $0.title) })
        }
        await sync.syncAll(chatIds: settings.selectedChatIds)
        guard settings.autoSummarize || force else { return }
        for chatId in settings.selectedChatIds {
            let messages = PromptBuilder.filter(messages: archive.load(chatId), dayKey: dayKey, slot: fullSlot)
            let summary = summaryStore.get(chatId, dayKey, fullSlot.key)
            let should = force || SummaryPolicy.shouldAutoRegenerate(summary: summary, currentCount: messages.count)
            if should {
                if force { summaryStore.remove(chatId, dayKey, fullSlot.key) }
                await SummaryService.generate(
                    chatId: chatId,
                    chatTitle: titles[chatId] ?? "群 \(chatId)",
                    dayKey: dayKey,
                    slot: fullSlot)
            }
        }
    }
}

struct SummaryTarget: Hashable {
    let chatId: Int64
    let title: String
    let day: Date
}
