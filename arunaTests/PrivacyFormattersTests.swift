import XCTest
@testable import aruna

/// Privacy censor formatting contract (port of `privacy_formatters.dart`).
final class PrivacyFormattersTests: XCTestCase {

    func testCensorDisabledPassesValueThrough() {
        XCTAssertEqual(PrivacyFormatters.sensitiveMoney("$1,000.00", isCensored: false), "$1,000.00")
        XCTAssertEqual(PrivacyFormatters.sensitiveMoney("$1,000.00", isCensored: false, large: true), "$1,000.00")
        XCTAssertEqual(PrivacyFormatters.sensitiveQuantity("10 share", isCensored: false), "10 share")
    }

    func testCensorEnabledMasksMoneyShort() {
        XCTAssertEqual(PrivacyFormatters.sensitiveMoney("Rp16,000,000", isCensored: true), "••••••")
        XCTAssertEqual(PrivacyFormatters.censorMoney(), "••••••")
    }

    func testCensorEnabledMasksMoneyLarge() {
        XCTAssertEqual(PrivacyFormatters.sensitiveMoney("Rp16,000,000", isCensored: true, large: true), "••••••••")
        XCTAssertEqual(PrivacyFormatters.censorMoney(large: true), "••••••••")
    }

    func testCensorEnabledMasksQuantity() {
        XCTAssertEqual(PrivacyFormatters.sensitiveQuantity("10 share", isCensored: true), "••••")
        XCTAssertEqual(PrivacyFormatters.censorQuantity(), "••••")
    }

    func testCensoredRepresentationIsUppercaseBullets() {
        // Flutter uses `••••` glyphs (U+2022), not dots or asterisks.
        XCTAssertEqual(PrivacyFormatters.censorMoney(), "\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}")
        XCTAssertEqual(PrivacyFormatters.censorMoney(large: true), String(repeating: "\u{2022}", count: 8))
        XCTAssertEqual(PrivacyFormatters.censorQuantity(), String(repeating: "\u{2022}", count: 4))
    }
}
