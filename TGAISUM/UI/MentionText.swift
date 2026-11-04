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

    /// @昵称 用正则、URL 用系统 NSDataDetector 识别，按位置合并后切分渲染
    private var attributed: AttributedString {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        var tokens: [(range: NSRange, isURL: Bool)] = []
        if let re = try? NSRegularExpression(pattern: #"@[^\s，。；、：:！!？?（）()【】\[\]《》]{1,30}"#) {
            for m in re.matches(in: text, range: full) {
                tokens.append((m.range, false))
            }
        }
        // 系统级链接识别：比手写正则可靠（Unicode 域名、标点截断等都由系统处理）
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for m in detector.matches(in: text, range: full) {
                if m.range.location != NSNotFound, m.range.length > 0 {
                    tokens.append((m.range, true))
                }
            }
        }

        var out = AttributedString()
        var loc = 0
        for (range, isURL) in tokens.sorted(by: { $0.range.location < $1.range.location }) {
            if range.location < loc { continue }
            if range.location > loc {
                out += styled(ns.substring(with: NSRange(location: loc, length: range.location - loc)), isLink: false)
            }
            out += styled(ns.substring(with: range), isLink: true)
            loc = range.location + range.length
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
