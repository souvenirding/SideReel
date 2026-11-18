import Foundation

enum TimeSchedule {
    static let dayEnd = 23 * 60 + 59

    static func isActive(at date: Date = Date()) -> Bool {
        let defaults = UserDefaults.standard
        return isActive(
            start: defaults.integer(forKey: ConfigKeys.scheduleStart),
            end: defaults.integer(forKey: ConfigKeys.scheduleEnd),
            at: date
        )
    }

    static func isActive(start: Int, end: Int, at date: Date) -> Bool {
        if start <= 0 && end >= dayEnd { return true }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        // 结束分钟整分钟仍生效（如 18:00 结束则 18:00:59 仍在窗口内）
        return minute >= start && minute <= end
    }
}