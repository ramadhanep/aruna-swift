import Foundation

/// Port of Flutter `PrivacyFormatters` (`lib/core/privacy/privacy_formatters.dart`).
/// Backed by the `privacy_censor_enabled` storage key; Portfolio and Stock
/// Detail will use `sensitiveMoney`/`sensitiveQuantity` to mask values.
enum PrivacyFormatters {
    private static let shortMoney = "\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}" // ••••••
    private static let largeMoney = "\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}" // ••••••••
    private static let quantity = "\u{2022}\u{2022}\u{2022}\u{2022}" // ••••

    static func censorMoney(large: Bool = false) -> String {
        large ? largeMoney : shortMoney
    }

    static func censorQuantity() -> String {
        quantity
    }

    static func sensitiveMoney(_ value: String, isCensored: Bool, large: Bool = false) -> String {
        isCensored ? censorMoney(large: large) : value
    }

    static func sensitiveQuantity(_ value: String, isCensored: Bool) -> String {
        isCensored ? censorQuantity() : value
    }
}
