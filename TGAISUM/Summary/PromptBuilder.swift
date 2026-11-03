import Foundation

enum PromptBuilder {
    static func filter(messages: [ArchiveMessage], dayKey: String, slot: SlotRange) -> [ArchiveMessage] {
        let start = DayUtil.dayStart(ofDay: dayKey)
        let startEpoch = DayUtil.epoch(start) + slot.startMinute * 60
        let endEpoch = DayUtil.epoch(start) + slot.endMinute * 60
        return messages.filter { $0.date >= startEpoch && $0.date < endEpoch && !$0.text.isEmpty }
    }

    /// 内置默认模板：纯文本排版、无 Markdown 记号
    static let defaultTemplate = """
    你是一个 Telegram 群聊总结助手。请根据聊天记录输出一份美观、易读的中文总结。

    排版硬性要求（必须遵守）：
    - 只输出纯文本。禁止使用任何 Markdown 记号：不要井号#、不要星号*、不要反引号`
    - 小节标题单独占一行，以「■ 」开头，例如：■ 核心话题
    - 条目以「· 」开头；引用具体聊天记录时，另起一行以「｜」开头并标注时间
    - 段落之间空一行；特别重要的结论用【】标注
    - 总结必须基于聊天记录，不得编造；消息越多写得越细，不设长度上限
    - 不要输出模板说明、免责声明，只输出最终成品

    总结结构（小节标题固定）：
    ■ 核心话题
    每个话题一段：起因 → 发展 → 结论
    ■ 重要事件
    按时间顺序列出关键事件
    ■ 活跃成员与观点
    谁是核心发言人，主要分歧是什么
    ■ 有用信息
    涉及的工具、链接、资源、技术结论
    ■ 待解决问题

    其他风格要求：{style}

    ———— 以下是需要总结的数据 ————

    群组：{group}
    日期：{date}（{slot}）
    消息统计：共 {total} 条，其中文本 {text} 条、媒体 {media} 条

    活跃成员 TOP15：
    {senders}

    聊天记录（按时间顺序）：
    {transcript}
    """

    static func build(groupName: String, dayKey: String, slot: SlotRange, messages: [ArchiveMessage]) -> (system: String, user: String) {
        var lines: [String] = []
        var senderCounts: [String: Int] = [:]
        for m in messages {
            let ts = DayUtil.timeString(m.date)
            let sender = m.sender.hasPrefix("@") ? m.sender : "@" + m.sender
            let text = m.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            lines.append("[\(ts)] \(sender): \(text)")
            senderCounts[sender, default: 0] += 1
        }
        let transcript = lines.joined(separator: "\n")
        let topSenders = senderCounts.sorted { $0.value > $1.value }.prefix(15)
        let senderText = topSenders.map { "- \($0.key)：\($0.value) 条" }.joined(separator: "\n")

        let textCount = messages.filter { !$0.isMedia }.count
        let mediaCount = messages.filter { $0.isMedia }.count
        let totalCount = messages.count

        let template = AppSettings.shared.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let useTemplate = template.isEmpty ? defaultTemplate : template

        let filled = useTemplate
            .replacingOccurrences(of: "{group}", with: groupName)
            .replacingOccurrences(of: "{date}", with: dayKey)
            .replacingOccurrences(of: "{slot}", with: slot.rangeDescription)
            .replacingOccurrences(of: "{style}", with: AppSettings.shared.summaryStyle)
            .replacingOccurrences(of: "{total}", with: "\(totalCount)")
            .replacingOccurrences(of: "{text}", with: "\(textCount)")
            .replacingOccurrences(of: "{media}", with: "\(mediaCount)")
            .replacingOccurrences(of: "{senders}", with: senderText.isEmpty ? "（无）" : senderText)
            .replacingOccurrences(of: "{transcript}", with: transcript.isEmpty ? "（无消息）" : transcript)

        return ("你是专业的中文群聊总结助手，只输出最终成品。", filled)
    }

    /// 清理 AI 输出中残留的 Markdown 记号，用于界面展示与复制
    static func cleanedOutput(_ raw: String) -> String {
        raw.components(separatedBy: "\n").map { line in
            var l = line
            if let r = l.range(of: #"^\s*#{1,6}\s*"#, options: .regularExpression) {
                l = String(l[r.upperBound...])
            }
            l = l
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")
                .replacingOccurrences(of: "`", with: "")
            return l.trimmingCharacters(in: .whitespaces)
        }
        .filter { $0 != "```" && $0 != "```plaintext" }
        .joined(separator: "\n")
    }
}
