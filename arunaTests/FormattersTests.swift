import XCTest
@testable import aruna

@MainActor
final class FormattersTests: XCTestCase {
    // money
    func testMoneyIDRUsesWholeNumbers() {
        XCTAssertEqual(ArunaFormatters.money(1_000_000, currency: "IDR"), "Rp1,000,000")
        XCTAssertEqual(ArunaFormatters.money(1234, currency: "IDR"), "Rp1,234")
    }

    func testMoneyUSDTwoDecimals() {
        XCTAssertEqual(ArunaFormatters.money(1234.5, currency: "USD"), "$1,234.50")
        XCTAssertEqual(ArunaFormatters.money(1000, currency: "USD"), "$1,000.00")
    }

    func testMoneySGD() {
        XCTAssertEqual(ArunaFormatters.money(1234.5, currency: "SGD"), "S$1,234.50")
        XCTAssertEqual(ArunaFormatters.money(1234.5, currency: "sgd"), "S$1,234.50")
    }

    func testMoneyNoCurrencyAndUnknownCurrency() {
        XCTAssertEqual(ArunaFormatters.money(1234.5, currency: nil), "1,234.50")
        XCTAssertEqual(ArunaFormatters.money(1234.5, currency: "GBP"), "GBP 1,234.50")
    }

    func testMoneyMissingValues() {
        XCTAssertEqual(ArunaFormatters.money(nil, currency: "USD"), "-")
        XCTAssertEqual(ArunaFormatters.money(.infinity, currency: "USD"), "-")
    }

    // percent
    func testPercent() {
        XCTAssertEqual(ArunaFormatters.percent(0.5), "+0.50%")
        XCTAssertEqual(ArunaFormatters.percent(-0.5), "-0.50%")
        XCTAssertEqual(ArunaFormatters.percent(0), "0.00%")
        XCTAssertEqual(ArunaFormatters.percent(1.234), "+1.23%")
        XCTAssertEqual(ArunaFormatters.percent(nil), "-")
    }

    // signed money
    func testSignedMoney() {
        XCTAssertEqual(ArunaFormatters.signedMoney(1000, currency: "USD"), "+$1,000.00")
        XCTAssertEqual(ArunaFormatters.signedMoney(-1000, currency: "USD"), "-$1,000.00")
        XCTAssertEqual(ArunaFormatters.signedMoney(0, currency: "USD"), "$0.00")
        XCTAssertEqual(ArunaFormatters.signedMoney(nil, currency: "USD"), "-")
    }

    // number
    func testNumber() {
        XCTAssertEqual(ArunaFormatters.number(1234.5), "1,234.5")
        XCTAssertEqual(ArunaFormatters.number(1234), "1,234")
        XCTAssertEqual(ArunaFormatters.number(0.5), "0.5")
        XCTAssertEqual(ArunaFormatters.number(nil), "-")
    }

    // compact
    func testCompact() {
        XCTAssertEqual(ArunaFormatters.number(1500, compact: true), "1.5K")
        XCTAssertEqual(ArunaFormatters.number(1_234_567, compact: true), "1.2M")
        XCTAssertEqual(ArunaFormatters.number(1_000_000, compact: true), "1M")
        XCTAssertEqual(ArunaFormatters.number(999, compact: true), "999")
        XCTAssertEqual(ArunaFormatters.number(-1500, compact: true), "-1.5K")
    }
}
