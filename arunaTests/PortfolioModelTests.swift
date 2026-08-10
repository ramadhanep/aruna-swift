import XCTest
@testable import aruna

/// Port checks for `PortfolioHolding`: cash/lot detection, effective quantity,
/// cost, display name, emoji, JSON contract (incl. legacy aliases) and Dart
/// date serialization.
final class PortfolioModelTests: XCTestCase {

    // MARK: - Cash detection

    func testCashDetectedByType() {
        let holding = makeHolding(symbol: "CASH_IDR", type: "cash")
        XCTAssertTrue(holding.isCash)
    }

    func testCashDetectedBySymbolPrefix() {
        let holding = makeHolding(symbol: "CASH_USD", type: "digital")
        XCTAssertTrue(holding.isCash)
    }

    func testDigitalIsNotCash() {
        let holding = makeHolding(symbol: "NVDA", type: "digital")
        XCTAssertFalse(holding.isCash)
    }

    // MARK: - Lot / effective quantity

    func testShareEffectiveQuantityIsQuantity() {
        let holding = makeHolding(symbol: "NVDA", quantity: 10, unit: "share")
        XCTAssertEqual(holding.effectiveQuantity, 10)
    }

    func testLotEffectiveQuantityIsQuantityTimes100() {
        let holding = makeHolding(symbol: "BBCA.JK", quantity: 2, unit: "lot")
        XCTAssertEqual(holding.effectiveQuantity, 200)
    }

    func testCashEffectiveQuantityIsQuantity() {
        let holding = makeHolding(symbol: "CASH_IDR", quantity: 1, type: "cash", unit: "unit")
        XCTAssertEqual(holding.effectiveQuantity, 1)
    }

    func testIsLotOnlyWhenUnitIsLot() {
        XCTAssertTrue(makeHolding(symbol: "BBCA.JK", quantity: 1, unit: "lot").isLot)
        XCTAssertFalse(makeHolding(symbol: "BBCA.JK", quantity: 1, unit: "share").isLot)
    }

    // MARK: - Cost

    func testCostIsEffectiveQuantityTimesAveragePrice() {
        let holding = makeHolding(symbol: "BBCA.JK", quantity: 3, averagePrice: 5_000, unit: "lot")
        XCTAssertEqual(holding.cost, 300 * 5_000)
    }

    func testCostShare() {
        let holding = makeHolding(symbol: "NVDA", quantity: 10, averagePrice: 120)
        XCTAssertEqual(holding.cost, 1_200)
    }

    // MARK: - Display name / emoji

    func testDisplayNamePrecedenceCategoryNameSymbol() {
        let withCategory = makeHolding(symbol: "NVDA", name: "NVIDIA", category: "Rocket")
        XCTAssertEqual(withCategory.displayName, "Rocket")

        let withName = makeHolding(symbol: "NVDA", name: "NVIDIA")
        XCTAssertEqual(withName.displayName, "NVIDIA")

        let bare = makeHolding(symbol: "NVDA")
        XCTAssertEqual(bare.displayName, "NVDA")
    }

    func testCashEmojiDefaults() {
        let noEmoji = makeHolding(symbol: "CASH_IDR", type: "cash", emoji: nil)
        XCTAssertEqual(noEmoji.cashEmoji, "💵")

        let emptyEmoji = makeHolding(symbol: "CASH_IDR", type: "cash", emoji: "")
        XCTAssertEqual(emptyEmoji.cashEmoji, "💵")

        let custom = makeHolding(symbol: "CASH_IDR", type: "cash", emoji: "💰")
        XCTAssertEqual(custom.cashEmoji, "💰")
    }

    // MARK: - toJSON contract (aliases + shape)

    func testToJSONWritesLegacyAliases() {
        let holding = makeHolding(
            symbol: "NVDA",
            quantity: 10,
            averagePrice: 120,
            name: "NVIDIA",
            type: "digital",
            unit: "share",
            currency: "USD",
            market: "US",
            assetType: "stock"
        )
        let json = holding.toJSON()

        XCTAssertEqual(json["symbol"] as? String, "NVDA")
        XCTAssertEqual(json["quantity"] as? Double, 10)
        XCTAssertEqual(json["amount"] as? Double, 10)
        XCTAssertEqual(json["averagePrice"] as? Double, 120)
        XCTAssertEqual(json["avgPrice"] as? Double, 120)
        XCTAssertEqual(json["unit"] as? String, "share")
        XCTAssertEqual(json["type"] as? String, "stock", "digital `type` emits the webType = assetType")
        XCTAssertEqual(json["assetType"] as? String, "stock")
        XCTAssertEqual(json["name"] as? String, "NVIDIA")
        XCTAssertNil(json["category"])
        XCTAssertNil(json["cashCurrency"])
        XCTAssertNil(json["nativeAmount"])
    }

    func testToJSONCashTypeIsCash() {
        let holding = makeHolding(symbol: "CASH_IDR", quantity: 1, averagePrice: 62.5, type: "cash")
        let json = holding.toJSON()
        XCTAssertEqual(json["type"] as? String, "cash")
        XCTAssertEqual(json["unit"] as? String, "share", "unit falls back to `share` for non-cash-typed direct construction")
    }

    func testToJSONOmitsEmptyOptionals() {
        let holding = makeHolding(symbol: "NVDA")
        let json = holding.toJSON()
        XCTAssertNil(json["name"])
        XCTAssertNil(json["currency"])
        XCTAssertNil(json["market"])
        XCTAssertNil(json["assetType"])
        XCTAssertNil(json["category"])
        XCTAssertNil(json["emoji"])
        XCTAssertEqual(json["type"] as? String, "digital")
    }

    func testToJSONDateIsDartIsoString() {
        let holding = makeHolding(symbol: "NVDA", createdAt: ArunaDate.isoParse("2026-08-09T12:00:00.123456")!)
        let json = holding.toJSON()
        XCTAssertEqual(json["createdAt"] as? String, "2026-08-09T12:00:00.123456")
    }

    // MARK: - fromJson

    func testFromJsonUppercasesAndTrimsSymbol() {
        let holding = PortfolioHolding(json: ["symbol": "  nvda  ", "quantity": 5, "averagePrice": 100])
        XCTAssertEqual(holding.symbol, "NVDA")
        XCTAssertEqual(holding.quantity, 5)
        XCTAssertEqual(holding.averagePrice, 100)
        XCTAssertEqual(holding.type, "digital")
    }

    func testFromJsonLegacyAliases() {
        let holding = PortfolioHolding(json: [
            "symbol": "BBCA.JK",
            "amount": 2,
            "avgPrice": 5_000,
            "created_at": "2026-08-09T12:00:00.123456",
        ])
        XCTAssertEqual(holding.quantity, 2)
        XCTAssertEqual(holding.averagePrice, 5_000)
        XCTAssertEqual(holding.createdAt, ArunaDate.isoParse("2026-08-09T12:00:00.123456"))
        XCTAssertEqual(holding.unit, "lot", ".JK defaults to lot")
    }

    func testFromJsonNumericStrings() {
        let holding = PortfolioHolding(json: [
            "symbol": "NVDA",
            "quantity": "1,000",
            "averagePrice": "150.5",
        ])
        XCTAssertEqual(holding.quantity, 1_000)
        XCTAssertEqual(holding.averagePrice, 150.5)
    }

    func testFromJsonCashCurrencyInferredFromSymbol() {
        let holding = PortfolioHolding(json: ["symbol": "CASH_IDR", "type": "cash"])
        XCTAssertEqual(holding.cashCurrency, "IDR")
        XCTAssertEqual(holding.unit, "unit")
        XCTAssertEqual(holding.type, "cash")
    }

    func testFromJsonLegacyAssetTypeFallback() {
        let jk = PortfolioHolding(json: ["symbol": "BBCA.JK", "type": "digital"])
        XCTAssertEqual(jk.assetType, "stock")
        let crypto = PortfolioHolding(json: ["symbol": "BTC-USD", "type": "digital"])
        XCTAssertEqual(crypto.assetType, "crypto")
    }

    func testFromJsonTypeNormalizesToDigitalForAssetType() {
        let holding = PortfolioHolding(json: ["symbol": "NVDA", "type": "stock"])
        XCTAssertEqual(holding.type, "digital")
    }

    func testFromJsonGeneratesIdWhenMissing() {
        let holding = PortfolioHolding(json: ["symbol": "NVDA"])
        XCTAssertTrue(holding.id.hasPrefix("NVDA_"))
    }

    // MARK: - Codable round-trip (local persistence)

    func testCodableRoundTrip() throws {
        let holding = makeHolding(
            symbol: "BBCA.JK",
            quantity: 2,
            averagePrice: 5_000,
            name: "Bank BCA",
            type: "digital",
            unit: "lot",
            currency: "IDR",
            market: "IDX",
            assetType: "stock",
            createdAt: ArunaDate.isoParse("2026-08-09T12:00:00.123456")!
        )
        let data = try ArunaStorage.jsonEncoder.encode([holding])
        let decoded = try ArunaStorage.jsonDecoder.decode([PortfolioHolding].self, from: data)

        XCTAssertEqual(decoded, [holding])
    }

    func testCodableDecodesLegacyJSON() throws {
        let json = """
        [{"id":"x1","symbol":"BBCA.JK","amount":2,"avgPrice":5000,"name":"BCA","unit":"lot","type":"stock","created_at":"2026-08-09T12:00:00.123456"}]
        """
        let data = Data(json.utf8)
        let decoded = try ArunaStorage.jsonDecoder.decode([PortfolioHolding].self, from: data)

        XCTAssertEqual(decoded.count, 1)
        let holding = decoded[0]
        XCTAssertEqual(holding.id, "x1")
        XCTAssertEqual(holding.symbol, "BBCA.JK")
        XCTAssertEqual(holding.quantity, 2)
        XCTAssertEqual(holding.averagePrice, 5_000)
        XCTAssertEqual(holding.unit, "lot")
        XCTAssertEqual(holding.createdAt, ArunaDate.isoParse("2026-08-09T12:00:00.123456"))
    }

    func testCodableRoundTripViaStorage() throws {
        let storage = ArunaStorage(defaults: UserDefaults(suiteName: "Model-\(UUID().uuidString)")!)
        let holding = makeHolding(
            symbol: "NVDA", quantity: 3, averagePrice: 100,
            type: "digital", unit: "share", assetType: "stock",
            createdAt: ArunaDate.isoParse("2026-08-09T12:00:00.123456")!
        )

        try storage.setJSON([holding], forKey: ArunaStorage.Key.portfolio)
        let loaded = try storage.jsonObject([PortfolioHolding].self, forKey: ArunaStorage.Key.portfolio)

        XCTAssertEqual(loaded, [holding])
    }

    // MARK: - Helpers

    private func makeHolding(
        symbol: String,
        quantity: Double = 1,
        averagePrice: Double = 100,
        name: String? = nil,
        type: String? = "digital",
        unit: String? = "share",
        currency: String? = nil,
        market: String? = nil,
        assetType: String? = nil,
        category: String? = nil,
        cashCurrency: String? = nil,
        nativeAmount: Double? = nil,
        emoji: String? = nil,
        createdAt: Date? = nil
    ) -> PortfolioHolding {
        PortfolioHolding(
            id: "\(symbol)_test",
            symbol: symbol,
            quantity: quantity,
            averagePrice: averagePrice,
            name: name,
            type: type,
            unit: unit,
            currency: currency,
            market: market,
            assetType: assetType,
            category: category,
            cashCurrency: cashCurrency,
            nativeAmount: nativeAmount,
            emoji: emoji,
            createdAt: createdAt
        )
    }
}
