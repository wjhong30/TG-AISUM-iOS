import Foundation

enum PromptBuilder {
    /// 取某天某时段的文本消息；顺序稳定（时间→id），保证提示词里的编号与回溯一致
    static func filter(messages: [ArchiveMessage], dayKey: String, slot: SlotRange) -> [ArchiveMessage] {
        let start = DayUtil.dayStart(ofDay: dayKey)
        let startEpoch = DayUtil.epoch(start) + slot.startMinute * 60
        let endEpoch = DayUtil.epoch(start) + slot.endMinute * 60
        return messages
            .filter { $0.date >= startEpoch && $0.date < endEpoch && !$0.text.isEmpty }
            .sorted { ($0.date, $0.id) < ($1.date, $1.id) }
    }

    /// 引用编号 → 原消息（1 基，与 transcript 编号一致）
    static func message(at index: Int, in messages: [ArchiveMessage]) -> ArchiveMessage? {
        guard index >= 1, index <= messages.count else { return nil }
        return messages[index - 1]
    }

    /// 内置默认模板：桌面版六板块深度报告 + 消息编号引用，供元宝式卡片解析
    static let defaultTemplate = """
    你是 Telegram 群聊总结助手。下面给你的聊天记录每条消息都带编号（#n），总结时用编号引用。

    输出格式（纯文本，严格遵守；禁止 Markdown 记号：不要 #、*、反引号）。正文必须包含以下六个板块，
    每个板块用「■ 板块名」开头，板块内用「·」逐条列点：

    ■ 消息统计
    共 N 条消息，其中文本 X 条、媒体 Y 条、活跃发言 S 人（数字照实写）

    ■ 核心话题梳理
    · 话题名：起因→发展→结论 (n)(m)

    ■ 重要事件时间线
    · HH:MM 事件：发生了什么、影响是什么 (n)

    ■ 活跃成员与观点
    · @成员（N 条）：核心观点；与其他人的分歧点 (n)

    ■ 技术与产品信息汇总
    · 产品/工具/技术方案：结论与变化 (n)

    ■ 趋势与变化
    · 与这段聊天早前相比，讨论方向有什么迁移

    ■ 待解决问题
    · 问题：现状与卡点 (n)

    硬性规则：
    - 正文必须有分析深度：归纳、对比、提炼，不是流水账式复述
    - 数据越多写得越细：禁止为了简短而压缩信息；不设长度上限，优先完整性与细节
    - 某板块确实没有内容时该板块写「无」，不要硬凑，但板块标题必须保留
    - 引用标记 (n) 的 n 对应消息编号 #n，编号必须真实存在，禁止编造；引用要精准
    - 分析必须基于提供的聊天记录，不得编造
    - 中文、条理清晰、结构化、重点优先；只输出成品，不要模板说明、免责声明

    其他风格要求：{style}

    ———— 以下是需要总结的数据 ————

    群组：{group}
    日期：{date}（{slot}）
    消息统计：共 {total} 条，其中文本 {text} 条、媒体 {media} 条

    活跃成员 TOP15：
    {senders}

    聊天记录（按时间顺序，每行开头是编号）：
    {transcript}
    """

    static func build(groupName: String, dayKey: String, slot: SlotRange, messages: [ArchiveMessage]) -> (system: String, user: String) {
        var lines: [String] = []
        var senderCounts: [String: Int] = [:]
        for (idx, m) in messages.enumerated() {
            let ts = DayUtil.clockString(m.date)
            let sender = m.sender.hasPrefix("@") ? m.sender : "@" + m.sender
            let text = m.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            lines.append("#\(idx + 1) [\(ts)] \(sender): \(text)")
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
            if let r = l.range(of: #"^\s*#{1,6}\s+"#, options: .regularExpression) {
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

    // MARK: - 分节解析（元宝式卡片，桌面版六板块）

    struct SummarySection: Identifiable {
        let id: Int
        var title: String
        var bullets: [String]
        var citations: [Int]
    }

    struct ParsedSummary {
        var stats: String?
        var sections: [SummarySection]
        var plain: String
    }

    /// 把模型输出按「■ 板块名」切成章节；消息统计单独抽出，切不出章节时回退纯文本渲染
    static func parseSummary(_ raw: String) -> ParsedSummary {
        let cleaned = cleanedOutput(raw)
        var blocks: [(title: String, lines: [String])] = []
        for line in cleaned.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if isSectionHeader(t) {
                blocks.append((cleanSectionTitle(t), []))
            } else if blocks.isEmpty {
                blocks.append(("", [t]))
            } else {
                blocks[blocks.count - 1].lines.append(t)
            }
        }

        var stats: String?
        var sections: [SummarySection] = []
        for (i, block) in blocks.enumerated() {
            if block.title.contains("消息统计") && stats == nil {
                stats = block.lines.joined(separator: "，")
                continue
            }
            sections.append(makeSection(id: i, title: block.title, lines: block.lines))
        }
        sections.removeAll { $0.title.isEmpty && $0.bullets.isEmpty }

        // 模型完全没按「■」输出时，回退纯文本渲染
        if sections.count == 1 && sections[0].title.isEmpty {
            return ParsedSummary(stats: nil, sections: [], plain: cleaned)
        }
        return ParsedSummary(stats: stats, sections: sections, plain: cleaned)
    }

    /// 分节头识别：「■ 标题」或「一、标题」「1、标题」式中文序号
    private static func isSectionHeader(_ line: String) -> Bool {
        if line.hasPrefix("■") { return true }
        guard line.range(of: #"^[（(]?(\d{1,2}|[一二三四五六七八九十]{1,3})[、.．)）]\s*\S"#, options: .regularExpression) != nil else {
            return false
        }
        // 序号式标题通常较短且不带引用编号
        return line.count <= 30 && line.range(of: #"[（(]\d{1,4}[)）]"#, options: .regularExpression) == nil
    }

    /// 剥掉标题前的「■」与序号（"一、" "1." 之类）
    private static func cleanSectionTitle(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespaces)
        while t.hasPrefix("■") {
            t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        while let r = t.range(of: #"^\s*(\d{1,2}|[一二三四五六七八九十]+)[.、．)）]\s*"#, options: .regularExpression) {
            t = String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return t
    }

    private static func makeSection(id: Int, title: String, lines: [String]) -> SummarySection {
        var rawBullets: [String] = []
        for line in lines {
            var t = line
            let isBullet = t.hasPrefix("·") || t.hasPrefix("-") || t.hasPrefix("•")
            if isBullet { t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces) }
            // 剥掉条目自身的序号前缀（"1. " "（2）" 之类）
            if let r = t.range(of: #"^\s*[（(]?(\d{1,2}|[一二三四五六七八九十]{1,3})[）)、.．]\s*"#, options: .regularExpression) {
                t = String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            if let r = t.range(of: #"^(要点|内容|话题|事件|问题)\s*[:：]\s*"#, options: .regularExpression) {
                t = String(t[r.upperBound...])
            }
            if t.isEmpty { continue }
            if !isBullet && !rawBullets.isEmpty {
                rawBullets[rawBullets.count - 1] += " " + t
            } else {
                rawBullets.append(t)
            }
        }

        let citations = parseCitations(rawBullets.joined(separator: "\n"))
        // 展示层剥离行内引用编号，编号只保留在底部圆片里
        let bullets = rawBullets.map { stripInlineCitations($0) }.filter { !$0.isEmpty }
        return SummarySection(id: id, title: title, bullets: bullets, citations: citations)
    }

    /// 去掉行内引用标记 (n)（含前置空白），只留正文
    static func stripInlineCitations(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s*[（(]\d{1,4}[)）]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// 从文本里抽引用编号：(3) / （12），支持 (3)(7) 连写；越界由调用方按消息数过滤
    static func parseCitations(_ text: String) -> [Int] {
        var result: [Int] = []
        guard let regex = try? NSRegularExpression(pattern: "[（(](\\d{1,4})[)）]") else { return [] }
        let ns = text as NSString
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if let n = Int(ns.substring(with: m.range(at: 1))), !result.contains(n) {
                result.append(n)
            }
        }
        return result
    }
}
