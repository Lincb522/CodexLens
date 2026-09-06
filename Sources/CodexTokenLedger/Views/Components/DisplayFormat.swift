import Foundation

enum DisplayFormat {
    static func tokens(_ value: Int64, abbreviated: Bool, locale: Locale) -> String {
        if abbreviated {
            for (scale, suffix, decimals) in [(1_000_000_000_000, "T", 2), (1_000_000_000, "B", 2),
                                              (1_000_000, "M", 2), (1_000, "K", 1)] {
                if value.magnitude >= UInt64(scale) {
                    let amount = (Double(value) / Double(scale))
                        .formatted(.number.grouping(.never).precision(.fractionLength(decimals)).locale(locale))
                    return amount + suffix
                }
            }
        }
        return integer(value, locale: locale)
    }

    static func integer(_ value: Int64, locale: Locale = .current) -> String {
        value.formatted(.number.grouping(.automatic).locale(locale))
    }

    static func dailyTokenUsage(date: Date, tokens: Int64, language: AppLanguage, abbreviated: Bool = false) -> String {
        let locale = Locale(identifier: language.localeIdentifier)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        // Match the account service's UTC day buckets, not the device's local date.
        formatter.timeZone = .gmt
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        let amount = Self.tokens(tokens, abbreviated: abbreviated, locale: locale)
        return LocalizationCatalog.text("usage.dayDetail", language: language, arguments: [formatter.string(from: date), amount])
    }

    static func usd(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        return currencyFormatter.string(from: number) ?? "$\(number.stringValue)"
    }

    static func compactUSD(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        let magnitude = abs(number)
        if magnitude >= 999_500 {
            let scaled = number / 1_000_000
            return String(format: abs(scaled) >= 100 ? "$%.0fM" : "$%.1fM", scaled)
        }
        if magnitude >= 1_000 {
            let scaled = number / 1_000
            return String(format: abs(scaled) >= 100 ? "$%.0fK" : "$%.1fK", scaled)
        }
        if magnitude >= 100 {
            return String(format: "$%.0f", number)
        }
        if magnitude >= 1 {
            return String(format: "$%.2f", number)
        }
        return String(format: "$%.4f", number)
    }

    static func quotaUSD(_ value: Double) -> String {
        apiEquivalentUSD(Decimal(value))
    }

    static func apiEquivalentUSD(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        let magnitude = abs(number.doubleValue)
        let formatter = magnitude < 1
            ? apiEquivalentSmallNumberFormatter
            : (magnitude < 100 ? apiEquivalentDecimalNumberFormatter : apiEquivalentWholeNumberFormatter)
        let formatted = formatter.string(from: number) ?? number.stringValue
        return "US$\(formatted)"
    }

    static func compactEstimatedTokens(_ value: Int64) -> String {
        if value >= 999_500_000_000 {
            let scaled = Double(value) / 1_000_000_000_000
            return String(format: scaled >= 100 ? "%.0fT" : "%.1fT", scaled)
        }
        if value >= 999_500_000 {
            let scaled = Double(value) / 1_000_000_000
            return String(format: scaled >= 100 ? "%.0fB" : "%.1fB", scaled)
        }
        if value >= 999_500 {
            let scaled = Double(value) / 1_000_000
            return String(format: scaled >= 100 ? "%.0fM" : "%.1fM", scaled)
        }
        if value >= 1_000 {
            return String(format: "%.0fK", Double(value) / 1_000)
        }
        return value.formatted()
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

    private static func apiEquivalentNumberFormatter(
        minimumFractionDigits: Int,
        maximumFractionDigits: Int
    ) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter
    }

    private static let apiEquivalentWholeNumberFormatter = apiEquivalentNumberFormatter(
        minimumFractionDigits: 0,
        maximumFractionDigits: 0
    )
    private static let apiEquivalentDecimalNumberFormatter = apiEquivalentNumberFormatter(
        minimumFractionDigits: 0,
        maximumFractionDigits: 2
    )
    private static let apiEquivalentSmallNumberFormatter = apiEquivalentNumberFormatter(
        minimumFractionDigits: 2,
        maximumFractionDigits: 4
    )

}
