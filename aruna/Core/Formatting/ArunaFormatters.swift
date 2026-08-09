import Foundation

/// Port of Flutter `ArunaFormatters` (`lib/core/utils/formatters.dart`).
///
/// Uses `en_US_POSIX` for deterministic output independent of device locale,
/// matching `intl`'s default behavior in the Flutter app.
enum ArunaFormatters {
    private static let posix = Locale(identifier: "en_US_POSIX")

    private static let plainFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.locale = posix
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let moneyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.locale = posix
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let wholeMoneyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.locale = posix
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    /// Mirrors Flutter `number`: plain `#,##0.##` or intl `compact()`.
    static func number(_ value: Double?, compact: Bool = false) -> String {
        guard let value, value.isFinite else { return "-" }
        if compact {
            return Self.compact(value)
        }
        return plainFormatter.string(from: NSNumber(value: value)) ?? "-"
    }

    /// Mirrors Flutter `money`: currency symbols, IDR whole-number, otherwise
    /// two decimals, grouping on. Missing/non-finite → "-".
    static func money(_ value: Double?, currency: String?) -> String {
        guard let value, value.isFinite else { return "-" }
        let code = currency?.uppercased()
        let symbol: String
        switch code {
        case "IDR": symbol = "Rp"
        case "USD": symbol = "$"
        case "SGD": symbol = "S$"
        default: symbol = code == nil ? "" : "\(code!) "
        }
        let formatter = code == "IDR" ? wholeMoneyFormatter : moneyFormatter
        let formatted = formatter.string(from: NSNumber(value: value)) ?? ""
        return symbol + formatted.trimmingCharacters(in: .whitespaces)
    }

    /// Mirrors Flutter `percent`: two decimals, `+` prefix for positive.
    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "-" }
        let sign = value > 0 ? "+" : ""
        let body = String(format: "%.2f", locale: posix, value)
        return "\(sign)\(body)%"
    }

    /// Mirrors Flutter `signedMoney`: sign then `money(abs)`.
    static func signedMoney(_ value: Double?, currency: String?) -> String {
        guard let value, value.isFinite else { return "-" }
        let sign = value > 0 ? "+" : value < 0 ? "-" : ""
        return sign + money(abs(value), currency: currency)
    }

    /// Manual compact formatter matching `intl` `NumberFormat.compact()`
    /// (1 fractional digit, `K`/`M`/`B`/`T`, trailing `.0` stripped).
    private static func compact(_ value: Double) -> String {
        let suffixes: [(divisor: Double, suffix: String)] = [
            (1e12, "T"),
            (1e9, "B"),
            (1e6, "M"),
            (1_000, "K"),
        ]
        let absolute = abs(value)
        let entry = suffixes.first { absolute >= $0.divisor }
        let scaled = value / (entry?.divisor ?? 1)
        let text = String(format: "%.1f", locale: posix, scaled)
        let trimmed = text.hasSuffix(".0") ? String(text.dropLast(2)) : text
        return trimmed + (entry?.suffix ?? "")
    }
}
