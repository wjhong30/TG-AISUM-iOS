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

/// 某群某天某时段的原始消息，气泡式列表，可定位到被引用的那条；图片消息可点开大图
struct ChatLogView: View {
    let target: ChatLogTarget

    @ObservedObject private var archive = ArchiveStore.shared
    @State private var fullscreenImage: UIImage?

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
        .fullScreenCover(item: Binding(
            get: { fullscreenImage.map { ImagePayload(image: $0) } },
            set: { fullscreenImage = $0?.image })) { payload in
            ImageViewer(image: payload.image) { fullscreenImage = nil }
        }
    }

    private struct ImagePayload: Identifiable {
        let image: UIImage
        var id: Int { image.hashValue }
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
                if m.isImage {
                    ImageBubble(chatId: target.chatId, messageId: m.id) { fullscreenImage = $0 }
                } else {
                    Text(m.text)
                        .font(.subheadline)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            (isHighlight ? Color.accentColor.opacity(0.16) : Color(uiColor: .secondarySystemGroupedBackground)),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

extension ArchiveMessage {
    var isImage: Bool { text == "[图片]" }
}

/// 图片气泡：懒加载下载，加载完成显示缩略图，点击全屏
private struct ImageBubble: View {
    let chatId: Int64
    let messageId: Int64
    let onOpen: (UIImage) -> Void

    @State private var image: UIImage?
    @State private var loading = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 200, maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { onOpen(image) }
            } else if loading {
                ProgressView()
                    .frame(width: 120, height: 90)
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 12))
            } else {
                Button {
                    Task {
                        loading = true
                        defer { loading = false }
                        if let path = await TDService.shared.downloadImage(
                            chatId: chatId, messageId: messageId),
                           let img = UIImage(contentsOfFile: path) {
                            image = img
                        }
                    }
                } label: {
                    Label("加载图片", systemImage: "photo")
                        .font(.subheadline)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .task {
            // 进入视口自动预载一次（失败则退回手动按钮）
            if image == nil, !loading {
                loading = true
                if let path = await TDService.shared.downloadImage(
                    chatId: chatId, messageId: messageId),
                   let img = UIImage(contentsOfFile: path) {
                    image = img
                }
                loading = false
            }
        }
    }
}

/// 全屏图片查看器：点任意处关闭，可缩放
private struct ImageViewer: View {
    let image: UIImage
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .onTapGesture { onClose() }
            VStack {
                Spacer()
                Text("轻点关闭")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 12)
            }
        }
    }
}
