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

    /// 内置默认模板：话题化结构 + 消息编号引用，供元宝式卡片解析
    static let defaultTemplate = """
    你是 Telegram 群聊总结助手。下面给你的聊天记录每条消息都带编号（#n），总结时必须用编号引用。

    输出格式（纯文本，严格遵守；禁止 Markdown 记号：不要 #、*、反引号）：

    ■ 总览
    一句话概括这段聊天（30 字内），句末给出最主要的引用，如 (3)(12)

    ■ 标题（HH:MM–HH:MM）
    · 要点：这个话题聊了什么、得出什么结论 (n)(m)
    · 要点：另一条要点 (k)

    「标题」要替换成概括该话题的短语（不超过 12 个字，如「风控升级讨论」「新版本测试反馈」），
    严禁把「标题」二字或占位符原样输出。
    话题写 2~6 个，按时间顺序；没有实质讨论就不要硬凑。

    硬性规则：
    - 时间区间取该话题首末消息的时间
    - 要点里凡涉及具体发言、结论、链接、文件，句末加引用标记 (n)，n 对应消息编号 #n；可多个，如 (3)(7)
    - 编号必须真实存在，禁止编造；引用要精准，指向支持该结论的那条消息
    - 要点写结论和信息，不要复述寒暄；消息越多写得越细，不设长度上限
    - 只输出成品，不要模板说明、免责声明

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

    // MARK: - 话题解析（元宝式卡片）

    struct SummaryTopic: Identifiable {
        let id: Int
        var title: String
        var timeRange: String?
        var members: [String]
        var bullets: [String]
        var citations: [Int]
    }

    struct ParsedSummary {
        var overview: SummaryTopic?
        var topics: [SummaryTopic]
        var plain: String
    }

    /// 把模型输出解析成「总览 + 话题」结构；解析不出话题时回退纯文本渲染
    static func parseSummary(_ raw: String) -> ParsedSummary {
        let cleaned = cleanedOutput(raw)
        var blocks: [(title: String, lines: [String])] = []
        for line in cleaned.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if t.hasPrefix("■") {
                blocks.append((String(t.dropFirst()).trimmingCharacters(in: .whitespaces), []))
            } else if blocks.isEmpty {
                blocks.append(("", [t]))
            } else {
                blocks[blocks.count - 1].lines.append(t)
            }
        }

        var overview: SummaryTopic?
        var topics: [SummaryTopic] = []
        for (i, block) in blocks.enumerated() {
            let isOverview = i == 0 && (block.title.contains("总览") || block.title.isEmpty) && blocks.count > 1
            let topic = makeTopic(id: i, title: block.title, lines: block.lines)
            if isOverview && topics.isEmpty && overview == nil {
                overview = topic
            } else {
                topics.append(topic)
            }
        }
        // 模型完全没按「■ 话题」输出时，回退纯文本渲染
        if overview == nil && topics.count == 1 && topics[0].title.isEmpty && topics[0].timeRange == nil {
            return ParsedSummary(overview: nil, topics: [], plain: cleaned)
        }
        return ParsedSummary(overview: overview, topics: topics, plain: cleaned)
    }

    private static func makeTopic(id: Int, title: String, lines: [String]) -> SummaryTopic {
        var displayTitle = title
        var timeRange: String?

        // 从标题里抠时间区间：15:20–16:08 / 15:20 - 16:08
        if let r = displayTitle.range(of: #"\d{1,2}:\d{2}\s*[–—~\-至到]\s*\d{1,2}:\d{2}"#, options: .regularExpression) {
            timeRange = String(displayTitle[r])
            displayTitle = (String(displayTitle[..<r.lowerBound]) + String(displayTitle[r.upperBound...]))
                .trimmingCharacters(in: CharacterSet(charactersIn: " （）()·-–—~　"))
        }

        var members: [String] = []
        var rawBullets: [String] = []
        for line in lines {
            var t = line
            let isBullet = t.hasPrefix("·") || t.hasPrefix("-") || t.hasPrefix("•")
            if isBullet { t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces) }
            if let r = t.range(of: #"^(要点|内容)\s*[:：]\s*"#, options: .regularExpression) {
                t = String(t[r.upperBound...])
            }
            if let r = t.range(of: #"^(成员|参与成员|发言人)\s*[:：]\s*"#, options: .regularExpression) {
                let body = String(t[r.upperBound...])
                members.append(contentsOf: body
                    .split(whereSeparator: { "、,， ".contains($0) })
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty })
            } else if isBullet {
                rawBullets.append(t)
            } else if !rawBullets.isEmpty {
                rawBullets[rawBullets.count - 1] += " " + t
            } else if displayTitle.isEmpty {
                displayTitle = t
            } else {
                rawBullets.append(t)
            }
        }

        let citations = parseCitations((rawBullets + [displayTitle]).joined(separator: "\n"))
        // 展示层剥离行内引用编号与残留前后缀，编号只保留在底部圆片里
        let bullets = rawBullets.map { stripInlineCitations($0) }
        displayTitle = fallbackTitleIfNeeded(displayTitle, bullets: bullets, id: id)
        return SummaryTopic(id: id, title: displayTitle, timeRange: timeRange,
                            members: members, bullets: bullets, citations: citations)
    }

    /// 去掉行内引用标记 (n)（含前置空白），只留正文
    static func stripInlineCitations(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s*[（(]\d{1,4}[)）]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// 模型把占位符原样抄下来时，用第一条要点生成标题；再不行给个序号标题
    private static func fallbackTitleIfNeeded(_ title: String, bullets: [String], id: Int) -> String {
        let t = stripInlineCitations(title).trimmingCharacters(in: .whitespaces)
        let isPlaceholder = t.isEmpty || t.contains("话题标题") || t == "标题" || t == "话题" || t.hasPrefix("<")
        guard isPlaceholder else { return t }
        guard let first = bullets.first(where: { !$0.isEmpty }) else { return "话题 \(id)" }
        let head = String(first.prefix(16))
        if let r = head.rangeOfCharacter(from: CharacterSet(charactersIn: "，。；、：,.;:")) {
            let cut = String(head[..<r.lowerBound])
            if cut.count >= 4 { return cut }
        }
        return head
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
