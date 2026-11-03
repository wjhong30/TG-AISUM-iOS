import Foundation

enum PromptBuilder {
    static func filter(messages: [ArchiveMessage], dayKey: String, slot: SlotRange) -> [ArchiveMessage] {
        let start = DayUtil.dayStart(ofDay: dayKey)
        let startEpoch = DayUtil.epoch(start) + slot.startMinute * 60
        let endEpoch = DayUtil.epoch(start) + slot.endMinute * 60
        return messages.filter { $0.date >= startEpoch && $0.date < endEpoch && !$0.text.isEmpty }
    }

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

        let style = AppSettings.shared.summaryStyle.trimmingCharacters(in: .whitespacesAndNewlines)
        let styleLine = style.isEmpty ? "" : "\n- 输出风格要求：\(style)"

        let system = """
        你是 Telegram 群聊周期性分析助手。
        现在给你的是一个群在指定日期、指定时间段内的聊天记录，请做一份【总结报告】。

        必须严格按下列模板输出，头部格式不能改：

        图表 \(groupName) 总结
        日期 \(dayKey)
        时间 统计区间：\(slot.rangeDescription) (Asia/Shanghai)
        ```plaintext
        总消息：\(totalCount)
        文本：\(textCount)
        媒体：\(mediaCount)
        ```

        头部之后是正文，正文必须包含以下部分：

        1. 核心话题梳理：讨论的主要话题有哪些，每个话题的起因、发展、结论
        2. 重要事件时间线：按时间顺序列出关键事件
        3. 活跃成员与观点：谁是核心发言人，主要观点分歧是什么
        4. 技术/产品信息汇总：涉及的产品、工具、技术方案的结论和变化
        5. 待解决问题：群里提出但未解决的问题清单

        硬性规则：
        - 消息统计必须放在 ```plaintext 代码框中
        - 引用具体聊天记录时必须放在 ``` 代码框中，并标注时间
        - 正文必须有分析深度：不是流水账式复述，要归纳、对比、提炼
        - 数据越多，正文必须写得越细：禁止为了简短而压缩信息
        - 不设长度上限：优先完整性与细节
        - 分析必须基于提供的聊天记录，不得编造
        - 中文、条理清晰、结构化、重点优先\(styleLine)
        - 不要输出模板说明、免责声明、额外注释，只输出最终报告成品。
        """

        let user = """
        群组：\(groupName)
        统计范围：\(dayKey) \(slot.timeText) (Asia/Shanghai)
        总消息数：\(totalCount)
        文本消息数：\(textCount)
        媒体消息数：\(mediaCount)

        活跃发言人 TOP15：
        \(senderText)

        消息记录（全量，按时间序）：
        \(transcript)
        """

        return (system, user)
    }
}
