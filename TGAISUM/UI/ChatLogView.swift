import SwiftUI
import AVKit

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
        .navigationTitle("\(target.dayKey) \(SlotRange.custom(startMinute: target.startMinute, endMinute: target.endMinute).timeText)")
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
                } else if m.isVideo {
                    VideoBubble(chatId: target.chatId, messageId: m.id, archivedName: m.archivedFileName)
                } else if m.isFile {
                    FileBubble(chatId: target.chatId, messageId: m.id, archivedName: m.archivedFileName)
                } else {
                    MentionText(text: m.text, font: .subheadline)
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
    var isVideo: Bool { text.hasPrefix("[视频]") }
    var isFile: Bool { text.hasPrefix("[文件]") }
    /// 归档文本里带的原始文件名（v0.5.4 起才带；旧数据为空，点按下载后仍能拿到真名）
    var archivedFileName: String {
        let prefix = isVideo ? "[视频]" : "[文件]"
        return String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }
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

/// 文件气泡：点按下载，下载完成后直接弹系统分享面板（可保存到「文件」、隔空投送等）
private struct FileBubble: View {
    let chatId: Int64
    let messageId: Int64
    let archivedName: String

    @State private var file: TDService.DownloadedFile?
    @State private var loading = false
    @State private var failed = false
    @State private var showShare = false

    private var displayName: String {
        file?.name ?? (archivedName.isEmpty ? "文件" : archivedName)
    }

    var body: some View {
        Button {
            if file != nil {
                showShare = true
            } else {
                load()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    // 完整展示文件名，不截断
                    Text(displayName)
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if loading {
                    ProgressView()
                } else {
                    Image(systemName: file == nil ? "arrow.down.circle" : "square.and.arrow.up")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: 250, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showShare) {
            if let file {
                ActivityShareView(items: [file.url])
            }
        }
    }

    private var subtitle: String {
        if loading { return "下载中…" }
        if let f = file {
            let fmt = ByteCountFormatter()
            fmt.countStyle = .file
            return fmt.string(fromByteCount: f.size)
        }
        if failed { return "下载失败，点按重试" }
        return "点按下载分享"
    }

    private func load() {
        guard !loading else { return }
        loading = true
        failed = false
        Task {
            let f = await TDService.shared.downloadDocument(chatId: chatId, messageId: messageId)
            loading = false
            if let f {
                file = f
                showShare = true
            } else {
                failed = true
            }
        }
    }
}

/// 视频气泡：点按下载后进 Telegram 式全屏播放器（进度条/暂停/±10秒），
/// 播放器内可保存到相册或「文件」
private struct VideoBubble: View {
    let chatId: Int64
    let messageId: Int64
    let archivedName: String

    @State private var file: TDService.DownloadedFile?
    @State private var loading = false
    @State private var failed = false
    @State private var playingURL: URL?

    private var displayName: String {
        file?.name ?? (archivedName.isEmpty ? "视频" : archivedName)
    }

    var body: some View {
        Button {
            if file != nil {
                playingURL = file!.url
            } else {
                load()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "video.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if loading {
                    ProgressView()
                } else {
                    Image(systemName: file == nil ? "arrow.down.circle" : "play.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: 250, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .fullScreenCover(item: Binding(
            get: { playingURL.map { URLPayload(url: $0) } },
            set: { playingURL = $0?.url })) { p in
            VideoPlayerScreen(url: p.url) { playingURL = nil }
        }
    }

    private var subtitle: String {
        if loading { return "下载中…" }
        if let f = file {
            let fmt = ByteCountFormatter()
            fmt.countStyle = .file
            return fmt.string(fromByteCount: f.size)
        }
        if failed { return "下载失败，点按重试" }
        return "点按下载观看"
    }

    private func load() {
        guard !loading else { return }
        loading = true
        failed = false
        Task {
            let f = await TDService.shared.downloadVideo(chatId: chatId, messageId: messageId)
            loading = false
            if let f {
                file = f
                playingURL = f.url
            } else {
                failed = true
            }
        }
    }
}

/// Telegram 式全屏视频播放器：AVKit 原生控制（进度条/播放暂停/±10秒/画中画），
/// 关闭与分享按钮固定在安全区内，不与状态栏重叠
private struct VideoPlayerScreen: View {
    let url: URL
    let onClose: () -> Void

    @State private var player: AVPlayer?
    @State private var showShare = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            if let player {
                AVPlayerView(player: player)
                    .ignoresSafeArea()
            } else {
                Color.black
                    .ignoresSafeArea()
                    .overlay(ProgressView().tint(.white))
            }
            HStack {
                Button {
                    player?.pause()
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(11)
                        .background(.black.opacity(0.45), in: Circle())
                }
                Spacer()
                Button {
                    showShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(11)
                        .background(.black.opacity(0.45), in: Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .onAppear {
            let p = AVPlayer(url: url)
            p.play()
            player = p
        }
        .onDisappear { player?.pause() }
        .sheet(isPresented: $showShare) {
            ActivityShareView(items: [url])
        }
    }
}

/// AVKit 播放器封装：自带完整播放控制
private struct AVPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}
}

struct URLPayload: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// 系统分享面板：含「保存到文件」、拷贝、隔空投送等
struct ActivityShareView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
