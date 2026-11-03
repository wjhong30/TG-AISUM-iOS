import Foundation

struct SlotRange: Equatable {
    let startMinute: Int
    let endMinute: Int
    let key: String
    let label: String

    static let morning = SlotRange(startMinute: 0, endMinute: 12 * 60, key: "am", label: "上午")
    static let afternoon = SlotRange(startMinute: 12 * 60, endMinute: 24 * 60, key: "pm", label: "下午")
    static let full = SlotRange(startMinute: 0, endMinute: 24 * 60, key: "full", label: "全天")

    static func custom(startMinute: Int, endMinute: Int) -> SlotRange {
        SlotRange(
            startMinute: startMinute,
            endMinute: endMinute,
            key: "custom_\(startMinute)_\(endMinute)",
            label: "自定义"
        )
    }

    var timeText: String {
        String(format: "%02d:%02d–%02d:%02d",
               startMinute / 60, startMinute % 60,
               endMinute / 60, endMinute % 60)
    }

    var rangeDescription: String {
        "\(label) \(timeText)"
    }
}

enum DayUtil {
    static let tz = TimeZone(identifier: "Asia/Shanghai")!

    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal
    }

    static func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func dayStart(ofDay dayKey: String) -> Date {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date() }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        return calendar.date(from: comps) ?? Date()
    }

    static func epoch(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970)
    }

    static func timeString(_ epochSeconds: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        let formatter = DateFormatter()
        formatter.timeZone = tz
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    static func minuteOfDay(_ date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
