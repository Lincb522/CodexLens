import Foundation

enum DisplayFormat {
    static func tokens(_ value: Int64) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.2fB", Double(value) / 1_000_000_000)
        }
        if value >= 1_000_000 {
            return String(format: "%.2fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return value.formatted()
    }

    static func integer(_ value: Int64) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    static func usd(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        return currencyFormatter.string(from: number) ?? "$\(number.stringValue)"
    }

    static func duration(_ interval: TimeInterval, localeIdentifier: String) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.calendar?.locale = Locale(identifier: localeIdentifier)
        if interval >= 24 * 60 * 60 {
            formatter.allowedUnits = [.day, .hour]
        } else if interval >= 60 * 60 {
            formatter.allowedUnits = [.hour, .minute]
        } else {
            formatter.allowedUnits = [.minute]
        }
        return formatter.string(from: max(60, interval)) ?? "—"
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        return formatter
    }()

}
