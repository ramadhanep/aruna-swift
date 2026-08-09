import XCTest
@testable import aruna

@MainActor
final class StorageTests: XCTestCase {
    private struct EncodableDate: Codable, Equatable {
        let name: String
        let date: Date
    }

    private var suiteName: String!
    private var storage: ArunaStorage!

    override func setUp() {
        super.setUp()
        suiteName = "ArunaTests.\(UUID().uuidString)"
        storage = ArunaStorage(defaults: UserDefaults(suiteName: suiteName)!)
    }

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testKeysMatchFlutter() {
        XCTAssertEqual(ArunaStorage.Key.watchlist, "aruna.watchlist.v1")
        XCTAssertEqual(ArunaStorage.Key.portfolio, "aruna.portfolio.v1")
        XCTAssertEqual(ArunaStorage.Key.portfolioSort, "aruna.portfolio.sort.v1")
        XCTAssertEqual(ArunaStorage.Key.portfolioCurrency, "portfolio_currency")
        XCTAssertEqual(ArunaStorage.Key.themeMode, "aruna_theme_mode")
        XCTAssertEqual(ArunaStorage.Key.privacyCensorEnabled, "privacy_censor_enabled")
    }

    func testStringAndBoolRoundTrip() {
        storage.set("dark", forKey: ArunaStorage.Key.themeMode)
        XCTAssertEqual(storage.string(forKey: ArunaStorage.Key.themeMode), "dark")

        storage.set(true, forKey: ArunaStorage.Key.privacyCensorEnabled)
        XCTAssertTrue(storage.bool(forKey: ArunaStorage.Key.privacyCensorEnabled))
        XCTAssertFalse(storage.bool(forKey: "missing.key"))
    }

    func testJSONRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_782_000_000)
        let original = EncodableDate(name: "BBCA.JK", date: date)

        try storage.setJSON(original, forKey: ArunaStorage.Key.watchlist)
        let decoded = try storage.jsonObject(EncodableDate.self, forKey: ArunaStorage.Key.watchlist)

        XCTAssertEqual(decoded, original)
    }

    func testDateEncodingMatchesDartFormat() throws {
        let date = ArunaDate.isoParse("2026-08-09T12:00:00.123456")!
        try storage.setJSON(EncodableDate(name: "x", date: date), forKey: ArunaStorage.Key.portfolio)

        let data = try XCTUnwrap(storage.defaults.data(forKey: ArunaStorage.Key.portfolio))
        let string = try XCTUnwrap(String(data: data, encoding: .utf8))
        // yyyy-MM-ddTHH:mm:ss.SSSSSS, no Z (Dart toIso8601String for UTC).
        let range = string.range(of: #""\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}""#, options: .regularExpression)
        XCTAssertNotNil(range, "unexpected encoded date in: \(string)")
    }

    func testMissingKeyReturnsNil() throws {
        XCTAssertNil(try storage.jsonObject(EncodableDate.self, forKey: "missing"))
    }

    func testIsoParseAcceptsDartVariants() {
        XCTAssertNotNil(ArunaDate.isoParse("2026-08-09T12:00:00.123456Z"))
        XCTAssertNotNil(ArunaDate.isoParse("2026-08-09T19:25:00.123456+07:00"))
        XCTAssertNotNil(ArunaDate.isoParse("2026-08-09T19:25:00.123456+0700"))
        XCTAssertNotNil(ArunaDate.isoParse("2026-08-09T12:00:00.000"))
        XCTAssertNotNil(ArunaDate.isoParse("2026-08-09T12:00:00"))
        XCTAssertNil(ArunaDate.isoParse("garbage"))
        XCTAssertNil(ArunaDate.isoParse(""))
    }

    func testIsoStringRoundTrips() {
        let date = Date(timeIntervalSince1970: 1_782_000_000)
        let string = ArunaDate.isoString(from: date)
        XCTAssertEqual(ArunaDate.isoParse(string), date)
    }
}
