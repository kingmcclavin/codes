import Foundation

enum DateText {
    /// "Today", "Tomorrow", "Yesterday", "in 13 days", "3 days ago".
    static func relativeDay(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = dayDifference(from: now, to: date, calendar: calendar)
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...: return "in \(days) days"
        default: return "\(-days) days ago"
        }
    }

    /// Whole calendar days between two dates (ignores time of day).
    static func dayDifference(from start: Date, to end: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }

    /// "9:00 AM" style string for minutes after midnight.
    static func time(minutes: Int, calendar: Calendar = .current) -> String {
        let base = calendar.startOfDay(for: Date())
        let date = base.addingTimeInterval(TimeInterval(minutes * 60))
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func weekdayName(_ weekday: Int, short: Bool = true, calendar: Calendar = .current) -> String {
        let symbols = short ? calendar.shortWeekdaySymbols : calendar.weekdaySymbols
        guard (1...symbols.count).contains(weekday) else { return "?" }
        return symbols[weekday - 1]
    }

    /// Weekdays in the user's preferred order (e.g. Sunday or Monday first).
    static func orderedWeekdays(calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }
}

enum SemesterSuggestion {
    /// A sensible semester for a date: Spring (Jan–May), Summer (Jun–Jul), Fall (Aug–Dec).
    static func suggested(for date: Date, calendar: Calendar = .current) -> Semester {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        func make(_ name: String, _ startMonth: Int, _ endMonth: Int, _ endDay: Int) -> Semester {
            let start = calendar.date(from: DateComponents(year: year, month: startMonth, day: 1)) ?? date
            let endDayStart = calendar.date(from: DateComponents(year: year, month: endMonth, day: endDay)) ?? date
            let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: endDayStart) ?? endDayStart
            return Semester(name: "\(name) \(year)", startDate: start, endDate: end)
        }
        switch month {
        case 1...5: return make("Spring", 1, 5, 31)
        case 6...7: return make("Summer", 6, 7, 31)
        default: return make("Fall", 8, 12, 31)
        }
    }
}
