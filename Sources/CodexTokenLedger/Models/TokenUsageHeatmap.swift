import Foundation

struct TokenUsageHeatmapDay: Hashable, Identifiable, Sendable {
    var id: String { dateKey }

    let date: Date
    let dateKey: String
    let tokens: Int64
    let intensity: Int
    let isFuture: Bool
}

struct TokenUsageHeatmap: Hashable, Sendable {
    let weeks: [[TokenUsageHeatmapDay]]
    let monthStarts: [Date]
    let rangeStart: Date
    let rangeEnd: Date
    let today: Date
    let totalTokens: Int64
    let last30DaysTokens: Int64
    let activeDays: Int
    let peakTokens: Int64

    var days: [TokenUsageHeatmapDay] { weeks.flatMap { $0 } }

    static func make(
        dailyBuckets: [CodexAccountDailyTokenUsage],
        referenceDate: Date = Date()
    ) -> TokenUsageHeatmap {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let today = calendar.startOfDay(for: referenceDate)
        let weekday = calendar.component(.weekday, from: today)
        let daysUntilSaturday = 7 - weekday
        let rangeEnd = calendar.date(byAdding: .day, value: daysUntilSaturday, to: today) ?? today
        let rangeStart = calendar.date(byAdding: .day, value: -370, to: rangeEnd) ?? today
        let last30Start = calendar.date(byAdding: .day, value: -29, to: today) ?? today

        var tokensByDay: [String: Int64] = [:]
        for bucket in dailyBuckets {
            let key = String(bucket.startDate.prefix(10))
            guard key.count == 10, Self.date(from: key, calendar: calendar) != nil else { continue }
            tokensByDay[key] = max(tokensByDay[key] ?? 0, max(0, bucket.tokens))
        }

        let rawDays: [(date: Date, key: String, tokens: Int64, isFuture: Bool)] = (0..<371).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: rangeStart) else { return nil }
            let key = Self.dateKey(date, calendar: calendar)
            return (date, key, tokensByDay[key] ?? 0, date > today)
        }
        let peak = rawDays.lazy.filter { !$0.isFuture }.map(\.tokens).max() ?? 0

        let days = rawDays.map { day in
            TokenUsageHeatmapDay(
                date: day.date,
                dateKey: day.key,
                tokens: day.tokens,
                intensity: Self.intensity(tokens: day.tokens, peak: peak),
                isFuture: day.isFuture
            )
        }
        let visibleDays = days.filter { !$0.isFuture }
        let total = visibleDays.reduce(Int64(0)) { Self.safeAdd($0, $1.tokens) }
        let last30 = visibleDays
            .filter { $0.date >= last30Start && $0.date <= today }
            .reduce(Int64(0)) { Self.safeAdd($0, $1.tokens) }

        let firstMonth = calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: calendar.component(.year, from: today),
                month: calendar.component(.month, from: today),
                day: 1
            )
        ) ?? today
        let monthStarts = (-11...0).compactMap {
            calendar.date(byAdding: .month, value: $0, to: firstMonth)
        }

        return TokenUsageHeatmap(
            weeks: stride(from: 0, to: days.count, by: 7).map {
                Array(days[$0..<min($0 + 7, days.count)])
            },
            monthStarts: monthStarts,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            today: today,
            totalTokens: total,
            last30DaysTokens: last30,
            activeDays: visibleDays.filter { $0.tokens > 0 }.count,
            peakTokens: peak
        )
    }

    private static func intensity(tokens: Int64, peak: Int64) -> Int {
        guard tokens > 0, peak > 0 else { return 0 }
        guard tokens < peak else { return 4 }
        let normalized = log1p(Double(tokens)) / log1p(Double(peak))
        switch normalized {
        case ..<0.40: return 1
        case ..<0.62: return 2
        case ..<0.82: return 3
        default: return 4
        }
    }

    private static func date(from key: String, calendar: Calendar) -> Date? {
        let values = key.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3 else { return nil }
        return calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: values[0],
                month: values[1],
                day: values[2]
            )
        )
    }

    private static func dateKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func safeAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : sum
    }
}
