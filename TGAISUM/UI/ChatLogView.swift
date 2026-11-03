import SwiftUI

/// 引用跳转目标：群 + 天 + 时段 + 要高亮的消息
struct ChatLogTarget: Hashable {
    let chatId: Int64
    let title: String
    let dayKey: String
    let startMinute: Int
    let endMinute: Int
    let highlight: Int64?
}

/// 某群某天某时段的原始消息，气泡式列表，可定位到被引用的那条
struct ChatLogView: View {
    let target: ChatLogTarget

    @ObservedObject private var archive = ArchiveStore.shared

    private var messages: [ArchiveMessage] {
        let slot = SlotRange.custom(startMinute: target.startMinute, endMinute: target.endMinute)
        return PromptBuilder.filter(messages: archive.load(target.chatId), dayKey: target.dayKey, slot: slot)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { m in
                        bubble(m).id(m.id)
                    }
                    if messages.isEmpty {
                        Text("该时段没有文本消息")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .onAppear {
                if let h = target.highlight, messages.contains(where: { $0.id == h }) {
                    proxy.scrollTo(h, anchor: .center)
                }
            }
        }
        .navigationTitle("\(target.dayKey) 群聊记录")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bubble(_ m: ArchiveMessage) -> some View {
        let isHighlight = m.id == target.highlight
        return HStack(alignment: .top, spacing: 8) {
            ChatAvatar(name: m.sender, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(m.sender)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(DayUtil.clockString(m.date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(m.text)
                    .font(.subheadline)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(
                        (isHighlight ? Color.accentColor.opacity(0.16) : Color(uiColor: .secondarySystemGroupedBackground)),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .overlay(alignment: .topLeading) {
                        if isHighlight {
                            Image(systemName: "arrow.turn.up.left")
                                .font(.caption2)
                                .foregroundStyle(.tint)
                                .offset(x: -14, y: 4)
                        }
                    }
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
    }
}
