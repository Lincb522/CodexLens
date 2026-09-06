import SwiftUI

struct OverviewUsageCalendar: View {
    let weeks: [[TokenUsageHeatmapDay]]
    let selectedRange: ClosedRange<Date>
    let locale: Locale
    let chartLabel: String
    let dayLabel: (TokenUsageHeatmapDay) -> String
    let onSelect: (TokenUsageHeatmapDay) -> Void
    static let height: CGFloat = 154
    static let cellSize: CGFloat = 14.5
    static let gap: CGFloat = 2.25

    private var weekdays: [String] {
        var calendar = OverviewUsageRange.calendar
        calendar.locale = locale
        return calendar.shortWeekdaySymbols
    }

    private var monthLabels: [Int: String] {
        let calendar = OverviewUsageRange.calendar
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = .gmt
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        var labels: [Int: String] = [:]
        for (index, week) in weeks.enumerated() {
            guard let first = week.first else { continue }
            if let start = week.first(where: { calendar.component(.day, from: $0.date) == 1 }) {
                labels[index] = formatter.string(from: start.date)
            } else if index == 0 && calendar.component(.day, from: first.date) < 20 {
                labels[index] = formatter.string(from: first.date)
            }
        }
        return labels
    }

    var body: some View {
        let labels = weekdays
        let months = monthLabels
        HStack(alignment: .top, spacing: 6) {
            VStack(spacing: Self.gap) {
                ForEach(0..<7) { index in
                    Text(labels[index]).font(.system(size: 12)).foregroundStyle(PulsePalette.muted)
                        .frame(width: 28, height: Self.cellSize, alignment: .leading)
                }
            }
            .padding(.top, 22)
            .accessibilityHidden(true)
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: Self.gap) {
                        ForEach(weeks.indices, id: \.self) { index in
                            Color.clear.frame(width: Self.cellSize, height: 16)
                                .overlay(alignment: index > weeks.count - 3 ? .trailing : .leading) {
                                    if let month = months[index] {
                                        Text(month).font(.system(size: 12)).foregroundStyle(PulsePalette.muted).fixedSize()
                                    }
                                }
                        }
                    }
                    .accessibilityHidden(true)
                    HStack(spacing: Self.gap) {
                        ForEach(weeks.indices, id: \.self) { column in
                            VStack(spacing: Self.gap) {
                                ForEach(weeks[column]) { day in
                                    if selectedRange.contains(day.date), !day.isFuture {
                                        TokenUsageHeatmapCell(day: day, size: Self.cellSize, selected: false,
                                                              action: onSelect, accessibilityLabel: dayLabel(day))
                                            .accessibilityIdentifier("Overview.UsageDay." + day.dateKey)
                                    } else {
                                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                                            .fill(PulsePalette.heatmapEmpty.opacity(0.45))
                                            .frame(width: Self.cellSize, height: Self.cellSize)
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .defaultScrollAnchor(.topLeading)
            .accessibilityLabel(chartLabel)
            .accessibilityIdentifier("Overview.UsageDays")
        }
        .frame(height: Self.height)
    }
}

struct OverviewUsageRangeEditor: View {
    let heatmap: TokenUsageHeatmap
    let language: AppLanguage
    let onApply: (OverviewUsageRange) -> Void
    let onCancel: () -> Void
    @State private var start: Date
    @State private var end: Date

    init(heatmap: TokenUsageHeatmap, selection: OverviewUsageRange, language: AppLanguage,
         onApply: @escaping (OverviewUsageRange) -> Void, onCancel: @escaping () -> Void) {
        self.heatmap = heatmap
        self.language = language
        self.onApply = onApply
        self.onCancel = onCancel
        let range = selection.resolved(in: heatmap)
        _start = State(initialValue: range.lowerBound)
        _end = State(initialValue: range.upperBound)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                preset("usage.range.month", .monthToDate)
                preset("usage.range.seven", .last7Days)
                preset("usage.range.thirty", .last30Days)
            }
            HStack {
                Text(t("usage.range.start"))
                Spacer(minLength: 8)
                DatePicker(t("usage.range.start"), selection: $start,
                           in: heatmap.rangeStart...end, displayedComponents: .date)
                    .labelsHidden().accessibilityIdentifier("Overview.UsageRange.Start")
            }
            HStack {
                Text(t("usage.range.end"))
                Spacer(minLength: 8)
                DatePicker(t("usage.range.end"), selection: $end,
                           in: start...heatmap.today, displayedComponents: .date)
                    .labelsHidden().accessibilityIdentifier("Overview.UsageRange.End")
            }
            HStack {
                Spacer()
                Button(t("action.cancel"), action: onCancel)
                    .accessibilityIdentifier("Overview.UsageRange.Cancel")
                Button(t("usage.range.apply")) { onApply(.custom(start: start, end: end)) }
                    .accessibilityIdentifier("Overview.UsageRange.Apply")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(PulsePalette.ink)
        .datePickerStyle(.field)
        .controlSize(.small)
        .environment(\.locale, Locale(identifier: language.localeIdentifier))
        .environment(\.calendar, OverviewUsageRange.calendar)
        .environment(\.timeZone, .gmt)
        .frame(height: OverviewUsageCalendar.height, alignment: .top)
        .accessibilityIdentifier("Overview.UsageRange.Editor")
    }

    private func preset(_ key: String, _ range: OverviewUsageRange) -> some View {
        Button { onApply(range) } label: {
            Text(t(key)).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func t(_ key: String) -> String { LocalizationCatalog.text(key, language: language) }
}
