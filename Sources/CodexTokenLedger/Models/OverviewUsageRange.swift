import Foundation

enum OverviewUsageRange: Hashable, Sendable {
    case monthToDate
    case last7Days
    case last30Days
    case custom(start: Date, end: Date)

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        // The account service supplies UTC day buckets, independently of device time zone.
        calendar.timeZone = .gmt
        return calendar
    }

    func resolved(in heatmap: TokenUsageHeatmap) -> ClosedRange<Date> {
        let calendar = Self.calendar
        let start: Date
        let end: Date
        switch self {
        case .monthToDate:
            start = calendar.dateInterval(of: .month, for: heatmap.today)?.start ?? heatmap.today
            end = heatmap.today
        case .last7Days, .last30Days:
            let offset = self == .last7Days ? -6 : -29
            start = calendar.date(byAdding: .day, value: offset, to: heatmap.today) ?? heatmap.today
            end = heatmap.today
        case let .custom(first, last):
            start = calendar.startOfDay(for: min(first, last))
            end = calendar.startOfDay(for: max(first, last))
        }
        let lower = min(max(start, heatmap.rangeStart), heatmap.today)
        let upper = min(max(end, lower), heatmap.today)
        return lower...upper
    }

    func days(in heatmap: TokenUsageHeatmap) -> [TokenUsageHeatmapDay] {
        let range = resolved(in: heatmap)
        return heatmap.days.filter { !($0.isFuture) && range.contains($0.date) }
    }

    func displayWeeks(in heatmap: TokenUsageHeatmap) -> [[TokenUsageHeatmapDay]] {
        let range = resolved(in: heatmap)
        let selected = heatmap.weeks.indices.filter { index in
            heatmap.weeks[index].contains { range.contains($0.date) }
        }
        guard let first = selected.first, let last = selected.last else { return [] }
        // Filtering changes the active days, not the established 16-column viewport.
        let start = max(0, min(first, last - 15))
        let end = min(heatmap.weeks.count - 1, max(last, start + 15))
        return Array(heatmap.weeks[start...end])
    }
}

extension TokenUsageHeatmap {
    func showsRecentHalf(for day: TokenUsageHeatmapDay) -> Bool {
        guard let firstRecentDay = weeks.suffix(27).first?.first else { return true }
        return day.date >= firstRecentDay.date
    }
}
