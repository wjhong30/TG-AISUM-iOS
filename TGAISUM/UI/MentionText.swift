import SwiftUI

/// 把正文里的 @昵称 渲染成主题色加粗，其余文字保持原样式
struct MentionText: View {
    let text: String
    var font: Font = .callout
    var color: Color = .primary

    var body: some View {
        composed
            .foregroundStyle(color)
            .lineSpacing(3)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var composed: Text {
        var result = Text(verbatim: "")
        var rest = text
        while true {
            guard let r = rest.range(
                of: #"@[^\s，。；、：:！!？?（）()【】\[\]《》]{1,30}"#,
                options: .regularExpression) else {
                result = result + Text(verbatim: rest)
                break
            }
            if r.lowerBound != rest.startIndex {
                result = result + Text(verbatim: String(rest[rest.startIndex..<r.lowerBound]))
            }
            result = result + Text(verbatim: String(rest[r]))
                .font(font.weight(.semibold))
                .foregroundColor(Color.accentColor)
            rest = String(rest[r.upperBound...])
        }
        return result
    }
}
