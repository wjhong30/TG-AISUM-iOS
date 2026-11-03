import SwiftUI
import UIKit

enum SlotMode: String, CaseIterable, Identifiable {
    case dawn = "凌晨"
    case morning = "上午"
    case afternoon = "下午"
    case evening = "晚上"
    case full = "全天"
    case custom = "自定义"
    var id: String { rawValue }
}

struct SummaryView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var summaryStore = SummaryStore.shared
    @ObservedObject var sync = SyncService.shared
    @ObservedObject var archive = ArchiveStore.shared

    @State private var day: Date = Date()
    @State private var slotMode: SlotMode = .full
    @State private var customStart: Date = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var customEnd: Date = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var didAutoRun = false

    private var dayKey: String { DayUtil.dayKey(day) }

    private var slot: SlotRange {
        switch slotMode {
        case .dawn: return .dawn
        case .morning: return .morning
        case .afternoon: return .afternoon
        case .evening: return .evening
        case .full: return .full
        case .custom:
            return .custom(
                startMinute: DayUtil.minuteOfDay(customStart),
                endMinute: min(DayUtil.minuteOfDay(customEnd), 24 * 60)
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    controls
                    if settings.selectedChatIds.isEmpty {
                        emptyGroups
                    } else {
                        ForEach(groupCards, id: \.id) { card in
                            cardView(card)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle("AI 总结")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        runSyncAndSummarize(force: true)
                    } label: {
                        if sync.syncing || !summaryStore.generating.isEmpty {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(sync.syncing || settings.selectedChatIds.isEmpty)
                }
            }
            .task {
                if !didAutoRun && settings.autoSummarize {
                    didAutoRun = true
                    runSyncAndSummarize(force: false)
                }
            }
        }
    }

    private var controls: some View {
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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var emptyGroups: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.3")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("还没有选择群组")
            NavigationLink("去「群组」页选择") {
                GroupsView()
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 60)
    }

    private struct Card: Identifiable {
        let id: Int64
        let title: String
        let count: Int
        let summary: CachedSummary?
        let generating: Bool
        let error: String?
    }

    private var groupCards: [Card] {
        settings.selectedChatIds.map { chatId in
            let messages = PromptBuilder.filter(
                messages: archive.load(chatId), dayKey: dayKey, slot: slot)
            let key = SummaryStore.key(chatId, dayKey, slot.key)
            return Card(
                id: chatId,
                title: chatTitle(chatId),
                count: messages.count,
                summary: summaryStore.get(chatId, dayKey, slot.key),
                generating: summaryStore.generating.contains(key),
                error: summaryStore.errors[key]
            )
        }
    }

    @State private var titles: [Int64: String] = [:]

    private func chatTitle(_ chatId: Int64) -> String {
        titles[chatId] ?? "群 \(chatId)"
    }

    @State private var titleLoaded = false

    private func loadTitlesIfNeeded() {
        guard !titleLoaded else { return }
        titleLoaded = true
        Task {
            let chats = await TDService.shared.fetchGroupChats()
            var map: [Int64: String] = [:]
            for c in chats { map[c.id] = c.title }
            titles = map
        }
    }

    private func cardView(_ card: Card) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(card.title)
                    .font(.headline)
                Spacer()
                Text("\(card.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let summary = card.summary, summary.msgCount != card.count {
                Text("区间内有 \(card.count - summary.msgCount) 条新消息，建议重新总结")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if card.generating {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在生成总结…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
            } else if let error = card.error, card.summary == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                    Button("重试") {
                        Task {
                            await SummaryService.generate(
                                chatId: card.id, chatTitle: card.title,
                                dayKey: dayKey, slot: slot)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else if card.count == 0 {
                Text("该时段没有文本消息")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let summary = card.summary {
                RichTextView(raw: summary.text)
                HStack {
                    Text("生成于 \(summary.generatedAt.formatted(.dateTime.month().day().hour().minute())) · \(summary.model)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("复制") {
                        UIPasteboard.general.string = PromptBuilder.cleanedOutput(summary.text)
                    }
                    .font(.caption)
                    Button("重新总结") {
                        SummaryStore.shared.remove(card.id, dayKey, slot.key)
                        Task {
                            await SummaryService.generate(
                                chatId: card.id, chatTitle: card.title,
                                dayKey: dayKey, slot: slot)
                        }
                    }
                    .font(.caption)
                }
            } else {
                Button("生成总结") {
                    Task {
                        await SummaryService.generate(
                            chatId: card.id, chatTitle: card.title,
                            dayKey: dayKey, slot: slot)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { loadTitlesIfNeeded() }
    }

    private func runSyncAndSummarize(force: Bool) {
        Task {
            if titles.isEmpty {
                let chats = await TDService.shared.fetchGroupChats()
                var map: [Int64: String] = [:]
                for c in chats { map[c.id] = c.title }
                titles = map
            }
            await sync.syncAll(chatIds: settings.selectedChatIds)
            guard settings.autoSummarize || force else { return }
            for chatId in settings.selectedChatIds {
                let title = chatTitle(chatId)
                if force {
                    SummaryStore.shared.remove(chatId, dayKey, slot.key)
                }
                if summaryStore.get(chatId, dayKey, slot.key) == nil {
                    await SummaryService.generate(
                        chatId: chatId, chatTitle: title, dayKey: dayKey, slot: slot)
                }
            }
        }
    }
}
