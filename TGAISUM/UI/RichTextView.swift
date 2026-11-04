import SwiftUI

/// 把 AI 输出清理后按段落渲染：段首行作为小标题加粗，整体留白舒适
struct RichTextView: View {
    let raw: String

    private struct Paragraph {
        let lines: [String]
        var isHeaderOnly: Bool { lines.count == 1 }
    }

    private var paragraphs: [Paragraph] {
        let cleaned = PromptBuilder.cleanedOutput(raw)
        var result: [Paragraph] = []
        var current: [String] = []
        for line in cleaned.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty {
                if !current.isEmpty {
                    result.append(Paragraph(lines: current))
                    current = []
                }
            } else {
                current.append(t)
            }
        }
        if !current.isEmpty {
            result.append(Paragraph(lines: current))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(p.lines.enumerated()), id: \.offset) { idx, line in
                        MentionText(
                            text: line,
                            font: idx == 0 ? .callout.weight(.semibold) : .callout,
                            color: idx == 0 ? Color.primary : Color.primary.opacity(0.85))
                    }
                }
            }
        }
    }
}
