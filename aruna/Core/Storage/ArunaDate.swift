import Foundation

/// Dart-compatible ISO-8601 date handling.
///
/// Flutter persists `DateTime.toIso8601String()` (microsecond precision,
/// UTC emits no `Z` in some paths) and parses with `DateTime.tryParse`, which
/// accepts fractional seconds and `Z`/`±HH:MM`/`±HHMM` timezones. Swift's
/// default ISO formatters do not round-trip that representation, so dates are
/// handled explicitly.
enum ArunaDate {
    private static let isoFormat = "yyyy-MM-dd'T'HH:mm:ss"

    /// Mirrors Dart `toIso8601String()` for a UTC date: six fractional digits,
    /// no `Z`. `DateFormatter` caps fractional seconds at milliseconds, so the
    /// microsecond part is appended manually.
    static func isoString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = isoFormat
        let seconds = date.timeIntervalSince1970
        let micros = Int((seconds - floor(seconds)) * 1_000_000 + 0.5)
        return String(format: "%@.%06d", formatter.string(from: date), micros)
    }

    /// Tolerant parser mirroring Dart `DateTime.tryParse`. Returns `nil` on
    /// any unrecognized format. `DateFormatter` caps fractional seconds at
    /// milliseconds, so the sub-millisecond fraction is parsed manually and
    /// re-applied to preserve Dart's microsecond round-trip.
    static func isoParse(_ string: String) -> Date? {
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        // Split off the fractional-seconds block so DateFormatter never
        // truncates it: "2026-08-09T12:00:00.123456+07:00" ->
        // remainder "2026-08-09T12:00:00+07:00", fraction 0.123456.
        var remainder = value
        var fraction: Double = 0
        if let dot = value.firstIndex(of: ".") {
            let afterDot = value.index(after: dot)
            var end = afterDot
            while end < value.endIndex, value[end].isNumber {
                end = value.index(after: end)
            }
            if end > afterDot {
                fraction = Double("0." + value[afterDot..<end]) ?? 0
                remainder = String(value[..<dot]) + String(value[end...])
            }
        }

        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            if let date = formatter.date(from: remainder) {
                return date.addingTimeInterval(fraction)
            }
        }
        return nil
    }

    /// Whole-second + timezone patterns (no fractional field; the fraction is
    /// applied separately by `isoParse`).
    private static let formats = [
        "yyyy-MM-dd'T'HH:mm:ssXXX",
        "yyyy-MM-dd'T'HH:mm:ssXX",
        "yyyy-MM-dd'T'HH:mm:ssX",
        "yyyy-MM-dd'T'HH:mm:ss",
    ]
}
