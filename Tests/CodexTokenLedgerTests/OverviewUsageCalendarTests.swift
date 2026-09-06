import AppKit
import SwiftUI
import XCTest
@testable import CodexTokenLedger

final class OverviewUsageCalendarTests: XCTestCase {
    func testDayDetailsUseTheUTCBucketDateAndExactLocalizedTokenCount() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-27T23:30:00Z"))
        XCTAssertEqual(DisplayFormat.dailyTokenUsage(date: date, tokens: 660_000_001, language: .zhHans),
                       "2026年8月27日 使用了 660,000,001 Token")
        XCTAssertEqual(DisplayFormat.dailyTokenUsage(date: date, tokens: 0, language: .english),
                       "Aug 27, 2026 · 0 Token used")
        for language in AppLanguage.allCases {
            let locale = Locale(identifier: language.localeIdentifier)
            let amount = Int64.max.formatted(.number.grouping(.automatic).locale(locale))
            let detail = DisplayFormat.dailyTokenUsage(date: date, tokens: .max, language: language)
            XCTAssertTrue(detail.contains(amount), "\(language): \(detail)")
            XCTAssertTrue(detail.contains("2026"), "\(language): \(detail)")
            XCTAssertFalse(detail.contains("usage.dayDetail"))
            XCTAssertFalse(detail.contains("%@"))
            XCTAssertFalse(detail.contains("$@"))
        }
    }

    @MainActor
    func testShortRangesKeepTheFullSmallCellGrid() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-06T12:00:00Z"))
        let heatmap = TokenUsageHeatmap.make(dailyBuckets: [], referenceDate: now)
        XCTAssertEqual(OverviewUsageCalendar.cellSize, 14.5)
        XCTAssertEqual(OverviewUsageCalendar.gap, 2.25)
        XCTAssertEqual(16 * OverviewUsageCalendar.cellSize + 15 * OverviewUsageCalendar.gap + 34, 299.75)
        for language in AppLanguage.allCases where language != .system {
            var calendar = OverviewUsageRange.calendar
            calendar.locale = Locale(identifier: language.localeIdentifier)
            for weekday in calendar.shortWeekdaySymbols {
                let width = (weekday as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width
                XCTAssertLessThanOrEqual(width, 28, "\(language): \(weekday) would truncate")
            }
        }
        for range in [OverviewUsageRange.monthToDate, .last7Days, .last30Days,
                      .custom(start: heatmap.rangeStart, end: heatmap.rangeStart)] {
            let weeks = range.displayWeeks(in: heatmap)
            XCTAssertEqual(weeks.count, 16)
            XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
            XCTAssertEqual(weeks.flatMap { $0 }.filter { range.resolved(in: heatmap).contains($0.date) }, range.days(in: heatmap))
        }
        let all = OverviewUsageRange.custom(start: heatmap.rangeStart, end: heatmap.today)
        XCTAssertEqual(all.displayWeeks(in: heatmap), heatmap.weeks)
    }

    @MainActor
    func testDailyCalendarAndEditorFitAllLocalesAndRanges() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-06T12:00:00Z"))
        let heatmap = TokenUsageHeatmap.make(dailyBuckets: [
            .init(startDate: "2026-09-01", tokens: 100),
            .init(startDate: "2026-09-02", tokens: 250),
            .init(startDate: "2026-09-03", tokens: 600),
            .init(startDate: "2026-09-04", tokens: 1_000),
        ], referenceDate: now)
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("build/daily-heatmap")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for dark in [false, true] {
            for width in [CGFloat(280), 300, 380] {
                for count in [1, 6, 7, 30, 31, 371] {
                    let days = Array(heatmap.days.filter { !$0.isFuture }.suffix(count))
                    let range = OverviewUsageRange.custom(start: days.first?.date ?? heatmap.today,
                                                          end: days.last?.date ?? heatmap.today)
                    let calendar = OverviewUsageCalendar(weeks: range.displayWeeks(in: heatmap),
                                                         selectedRange: range.resolved(in: heatmap), locale: Locale(identifier: "en"),
                                                         chartLabel: "Usage", dayLabel: { $0.dateKey }, onSelect: { _ in })
                    try render(calendar, width: width, dark: dark,
                               output: output.appendingPathComponent("heatmap-\(count)-\(dark)-\(Int(width)).png"))
                }
                for language in AppLanguage.allCases where language != .system {
                    let editor = OverviewUsageRangeEditor(heatmap: heatmap, selection: .monthToDate,
                                                          language: language, onApply: { _ in }, onCancel: {})
                    try render(editor, width: width, dark: dark,
                               output: output.appendingPathComponent("\(language.rawValue)-editor-\(dark)-\(Int(width)).png"))
                }
            }
        }
    }

    @MainActor
    private func render(_ content: some View, width: CGFloat, dark: Bool, output: URL) throws {
        try autoreleasepool {
            let host = NSHostingView(rootView: content
                .frame(width: width)
                .background(dark ? Color(white: 0.12) : Color(white: 0.96))
                .environment(\.colorScheme, dark ? .dark : .light))
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = NSRect(x: 0, y: 0, width: width, height: OverviewUsageCalendar.height)
            let window = NSWindow(contentRect: host.bounds, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = host.appearance
            window.contentView = host
            defer { window.contentView = nil; window.close() }
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.fittingSize.height, OverviewUsageCalendar.height, accuracy: 0.5)
            XCTAssertEqual(host.fittingSize.width, width, accuracy: 0.5)
            for scroll in descendants(host).compactMap({ $0 as? NSScrollView }) where !scroll.isHiddenOrHasHiddenAncestor {
                let visible = host.convert(scroll.visibleRect, from: scroll)
                let context = "\(output.lastPathComponent): frame=\(scroll.frame), visible=\(visible), document=\(String(describing: scroll.documentView?.frame))"
                // SwiftUI's AppKit scroll wrapper includes its native gutters; verify the visible surface.
                XCTAssertGreaterThanOrEqual(visible.minX, -0.5, context)
                XCTAssertGreaterThanOrEqual(visible.minY, -0.5, context)
                XCTAssertLessThanOrEqual(visible.maxX, width + 0.5, context)
                XCTAssertLessThanOrEqual(visible.maxY, OverviewUsageCalendar.height + 0.5, context)
                if let document = scroll.documentView {
                    XCTAssertLessThanOrEqual(document.frame.height, OverviewUsageCalendar.height + 0.5, context)
                    XCTAssertGreaterThanOrEqual(document.visibleRect.height, document.bounds.height - 0.5, context)
                    if document.frame.width > scroll.contentView.bounds.width {
                        let y = scroll.contentView.bounds.origin.y
                        scroll.contentView.scroll(to: NSPoint(x: document.frame.width - scroll.contentView.bounds.width, y: y))
                        scroll.reflectScrolledClipView(scroll.contentView)
                        XCTAssertGreaterThan(scroll.contentView.bounds.origin.x, 0)
                        XCTAssertEqual(scroll.contentView.bounds.origin.y, y, accuracy: 0.5)
                    }
                }
            }
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output)
        }
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
