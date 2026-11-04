import SwiftUI

/// 正文渲染：@昵称 主题色加粗；URL 链接下划线，点按直接跳 Safari
struct MentionText: View {
    let text: String
    var font: Font = .callout
    var color: Color = .primary

    var body: some View {
        Text(attributed)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            // 显式接管链接点按：保证直接跳 Safari，避免默认行为被手势拦截
            .environment(\.openURL, OpenURLAction { url in
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                return .handled
            })
    }

    /// @昵称 与 URL 一起按出现顺序切分渲染；分段各自建 AttributedString，避免跨段索引换算
    private var attributed: AttributedString {
        let ns = text as NSString
        guard let re = try? NSRegularExpression(pattern: #"@[^\s，。；、：:！!？?（）()【】\[\]《》]{1,30}|https?://[^\s，。；、：:！!？?（）()【】\[\]《》"'']+""#) else {
            return styled(ns.substring(with: NSRange(location: 0, length: ns.length)), isLink: false)
        }
        var out = AttributedString()
        var loc = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > loc {
                out += styled(ns.substring(with: NSRange(location: loc, length: m.range.location - loc)), isLink: false)
            }
            out += styled(ns.substring(with: m.range), isLink: true)
            loc = m.range.location + m.range.length
        }
        if loc < ns.length {
            out += styled(ns.substring(from: loc), isLink: false)
        }
        return out
    }

    private func styled(_ chunk: String, isLink: Bool) -> AttributedString {
        var a = AttributedString(chunk)
        a.font = font
        a.foregroundColor = color
        if isLink {
            if chunk.hasPrefix("http"), let url = URL(string: chunk) {
                a.link = url
                a.underlineStyle = .single
            }
            a.font = font.weight(.semibold)
            a.foregroundColor = Color.accentColor
        }
        return a
    }
}
