import SwiftUI
import UIKit

/// 群详情页（元宝式）：头部统计 + 话题卡片（时间/成员/要点/引用编号）
struct GroupSummaryView: View {
    let chatId: Int64
    let chatTitle: String

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var summaryStore = SummaryStore.shared
    @ObservedObject private var archive = ArchiveStore.shared
    @ObservedObject private var sync = SyncService.shared

    @State private var day = Date()
    @State private var slotMode: SlotMode = .full
    @State private var customStart = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var customEnd = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var fetchingDay = false
    /// 已尝试补抓过的日期（避免无消息的日期反复触发抓取）
    @State private var fetchedDays: Set<String> = []

    private var dayKey: String { DayUtil.dayKey(day) }
    private var slot: SlotRange { slotMode.range(customStart: customStart, customEnd: customEnd) }
    private var key: String { SummaryStore.key(chatId, dayKey, slot.key) }

    /// 该时段文本消息（编号与提示词一致）
    private var messages: [ArchiveMessage] {
        PromptBuilder.filter(messages: archive.load(chatId), dayKey: dayKey, slot: slot)
    }
    private var summary: CachedSummary? { summaryStore.get(chatId, dayKey, slot.key) }
    private var generating: Bool { summaryStore.generating.contains(key) }
    private var newCount: Int {
        guard let s = summary else { return 0 }
        return max(messages.count - s.msgCount, 0)
    }
    private var parsed: PromptBuilder.ParsedSummary? {
        guard let s = summary else { return nil }
        return PromptBuilder.parseSummary(s.text)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                headerCard
                controlsCard
                summarySection
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(chatTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    regenerate()
                } label: {
                    if generating || sync.syncing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(generating || sync.syncing)
            }
        }
        .task(id: dayKey) {
            await ensureDayFetched()
            guard settings.autoSummarize else { return }
            if generating { return }
            if SummaryPolicy.shouldAutoRegenerate(summary: summary, currentCount: messages.count) {
                await SummaryService.generate(
                    chatId: chatId, chatTitle: chatTitle, dayKey: dayKey, slot: slot)
            }
        }
    }

    /// 按需补抓：所选日期在归档里没有任何消息时，现场抓取那一天（前后各放宽 1 小时）
    private func ensureDayFetched() async {
        guard !fetchingDay, !fetchedDays.contains(dayKey) else { return }
        let all = archive.load(chatId)
        let start = DayUtil.epoch(DayUtil.dayStart(ofDay: dayKey))
        if all.contains(where: { $0.date >= start && $0.date < start + 86400 }) { return }
        fetchingDay = true
        ArchiveStore.shared.syncState[chatId] = "抓取 \(dayKey) 的记录…"
        let msgs = await TDService.shared.fetchMessages(
            chatId: chatId, stopBeforeDate: start - 3600)
        let dayEnd = start + 86400 + 3600
        let dayMsgs = msgs.filter { $0.date >= start && $0.date < dayEnd }
        archive.merge(chatId, dayMsgs)
        fetchedDays.insert(dayKey)
        ArchiveStore.shared.syncState[chatId] = dayMsgs.isEmpty
            ? "已抓取 \(dayKey)：当日无消息"
            : "已补抓 \(dayKey) 的 \(dayMsgs.count) 条消息"
        fetchingDay = false
    }

    // MARK: - 头部

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if generating {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("\(messages.count) 条消息总结中")
                        .font(.title3.weight(.semibold))
                    Spacer()
                }
            } else if let s = summary {
                Text("已总结 \(s.msgCount) 条消息")
                    .font(.title3.weight(.semibold))
                if newCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                        Text(newCount > SummaryPolicy.autoRegenThreshold
                             ? "有 \(newCount) 条新消息，点右上角重新总结"
                             : "有 \(newCount) 条新消息，满 \(SummaryPolicy.autoRegenThreshold) 条才自动重算")
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)
                }
            } else if messages.isEmpty {
                Text("该时段没有文本消息")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text("\(messages.count) 条消息待总结")
                    .font(.title3.weight(.semibold))
            }

            HStack {
                if let s = summary {
                    Text("生成于 \(s.generatedAt.formatted(.dateTime.month().day().hour().minute())) · \(s.model)")
                } else {
                    Text("统计区间：\(slot.rangeDescription)")
                }
                Spacer()
                NavigationLink(value: ChatLogTarget(
                    chatId: chatId, title: chatTitle, dayKey: dayKey,
                    startMinute: slot.startMinute, endMinute: slot.endMinute, highlight: nil)) {
                    Text("查看记录")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if let error = summaryStore.errors[key], !generating {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                    Button("重试") { regenerate() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14))
    }

    private var controlsCard: some View {
        VStack(spacing: 8) {
            DatePicker("日期", selection: $day, displayedComponents: .date)
                .datePickerStyle(.compact)
            Picker("时段", selection: $slotMode) {
                ForEach(SlotMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            if slotMode == .custom {
                HStack {
                    DatePicker("从", selection: $customStart, displayedComponents: .hourAndMinute)
                    DatePicker("到", selection: $customEnd, displayedComponents: .hourAndMinute)
                }
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 总结正文

    @ViewBuilder
    private var summarySection: some View {
        if generating {
            generatingCard
        } else if let s = summary, let p = parsed {
            if p.topics.isEmpty && p.overview == nil {
                card { RichTextView(raw: p.plain) }
            } else {
                if let o = p.overview {
                    overviewCard(o)
                }
                ForEach(p.topics) { topic in
                    topicCard(topic)
                }
            }
            HStack {
                Spacer()
                Button {
                    UIPasteboard.general.string = PromptBuilder.cleanedOutput(s.text)
                } label: {
                    Label("复制全文", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        } else if !messages.isEmpty {
            Button {
                Task { await SummaryService.generate(
                    chatId: chatId, chatTitle: chatTitle, dayKey: dayKey, slot: slot) }
            } label: {
                Label("生成总结", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
    }

    private var generatingCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text("总结中")
                        .font(.callout.weight(.medium))
                    Text("正在把 \(messages.count) 条消息交给 \(AppSettings.shared.llmNodes.first?.name ?? "LLM")…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14))
    }

    private func overviewCard(_ topic: PromptBuilder.SummaryTopic) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(topic.bullets.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.callout.weight(.medium))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if topic.bullets.isEmpty, !topic.title.isEmpty {
                Text(topic.title).font(.callout.weight(.medium))
            }
            viewLogLink(citations: topic.citations)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }

    private func topicCard(_ topic: PromptBuilder.SummaryTopic) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(topic.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if let tr = topic.timeRange {
                    if let target = topicLogTarget(topic) {
                        NavigationLink(value: target) {
                            Text(tr)
                                .font(.caption)
                                .foregroundStyle(.tint)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(tr)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ForEach(Array(topic.bullets.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(Color.accentColor.opacity(0.6))
                        .frame(width: 5, height: 5)
                        .padding(.top, 7)
                    Text(line)
                        .font(.callout)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            viewLogLink(citations: topic.citations)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14))
    }

    /// 「查看记录」入口：跳该话题引用消息所在的原始记录（高亮第一条引用）
    @ViewBuilder
    private func viewLogLink(citations: [Int]) -> some View {
        let firstValid = citations.first { PromptBuilder.message(at: $0, in: messages) != nil }
        if firstValid != nil || !messages.isEmpty {
            HStack {
                Spacer()
                NavigationLink(value: ChatLogTarget(
                    chatId: chatId, title: chatTitle, dayKey: dayKey,
                    startMinute: slot.startMinute, endMinute: slot.endMinute,
                    highlight: firstValid.flatMap { PromptBuilder.message(at: $0, in: messages)?.id })) {
                    Label("查看记录", systemImage: "bubble.left.and.bubble.right")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    /// 话题时间区间 → 该时段的原始记录页
    private func topicLogTarget(_ topic: PromptBuilder.SummaryTopic) -> ChatLogTarget? {
        guard let tr = topic.timeRange else { return nil }
        let parts = tr.components(separatedBy: CharacterSet(charactersIn: "–—~－-至到"))
        guard parts.count == 2,
              let start = parseClock(parts[0]),
              let end = parseClock(parts[1]),
              end > start else { return nil }
        return ChatLogTarget(chatId: chatId, title: chatTitle, dayKey: dayKey,
                             startMinute: start, endMinute: end, highlight: nil)
    }

    private func parseClock(_ s: String) -> Int? {
        let bits = s.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard bits.count == 2, let h = Int(bits[0]), let m = Int(bits[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    private func card<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14))
    }

    private func regenerate() {
        SummaryStore.shared.remove(chatId, dayKey, slot.key)
        Task {
            await SummaryService.generate(
                chatId: chatId, chatTitle: chatTitle, dayKey: dayKey, slot: slot)
        }
    }
}
