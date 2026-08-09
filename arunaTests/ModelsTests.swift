import XCTest
@testable import aruna

@MainActor
final class ModelsTests: XCTestCase {
    func testStockQuoteNumericStringsAndFallbacks() {
        let quote = StockQuote(json: [
            "symbol": "bbc.jk",
            "name": "",
            "price": "10,150",
            "change": 50,
            "changePercent": "0.50%",
            "logo": "http://l/bca.svg",
            "meta": ["currency": "IDR"],
        ])

        XCTAssertEqual(quote.symbol, "BBC.JK")
        XCTAssertEqual(quote.name, "BBC.JK") // empty name falls back to symbol
        XCTAssertEqual(quote.price, 10_150)
        XCTAssertEqual(quote.change, 50)
        XCTAssertEqual(quote.changePercent, 0.5)
        XCTAssertEqual(quote.logoURL, "http://l/bca.svg")
        XCTAssertEqual(quote.currency, "IDR")
    }

    func testStockQuoteLogoUrlAndCurrencyFallbacks() {
        let quote = StockQuote(json: [
            "symbol": "NVDA",
            "logoUrl": "http://l/nvda.png",
            "currency": "USD",
        ])
        XCTAssertEqual(quote.logoURL, "http://l/nvda.png")
        XCTAssertEqual(quote.currency, "USD")
        XCTAssertNil(quote.price)
        XCTAssertEqual(quote.chartData, [])
    }

    func testStockQuoteNonFiniteBecomesNil() {
        let quote = StockQuote(json: [
            "symbol": "X",
            "price": "nan",
            "change": "Infinity",
        ])
        XCTAssertNil(quote.price)
        XCTAssertNil(quote.change)
    }

    func testSymbolSearchResultFallbacks() {
        let result = SymbolSearchResult(json: [
            "symbol": "aapl",
            "longname": "Apple",
            "type": "EQUITY",
        ])
        XCTAssertEqual(result.symbol, "AAPL")
        XCTAssertEqual(result.name, "Apple")
        XCTAssertEqual(result.type, "EQUITY")

        let fallback = SymbolSearchResult(json: ["symbol": "qqq"])
        XCTAssertEqual(fallback.name, "QQQ")
    }

    func testPricePointParsing() {
        let point = PricePoint(json: [
            "date": "2026-08-09T12:00:00.000",
            "close": "150.5",
        ])
        XCTAssertEqual(point.price, 150.5)
        XCTAssertEqual(point.date, ArunaDate.isoParse("2026-08-09T12:00:00.000"))

        let adjClose = PricePoint(json: ["adjclose": 99.9])
        XCTAssertEqual(adjClose.price, 99.9)

        let invalidDate = PricePoint(json: ["date": "garbage", "price": 5])
        XCTAssertEqual(invalidDate.price, 5)
        // Flutter falls back to DateTime.now() when the date cannot be parsed.
        XCTAssertLessThan(abs(invalidDate.date.timeIntervalSinceNow), 60)
    }

    func testFundamentalsSummaryNested() {
        let summary = FundamentalsSummary(json: [
            "profile": ["sector": "Financials", "industry": "Banks", "marketState": "CLOSED"],
            "valuations": ["marketCap": 1_000_000, "trailingPe": "15.5", "priceToBook": 3.2],
            "dividendInfo": ["dividendYield": "2.1%"],
            "recommendations": ["details": ["recommendationKey": "buy"]],
        ])

        XCTAssertEqual(summary.sector, "Financials")
        XCTAssertEqual(summary.industry, "Banks")
        XCTAssertEqual(summary.marketState, "CLOSED")
        XCTAssertEqual(summary.marketCap, 1_000_000)
        XCTAssertEqual(summary.trailingPe, 15.5)
        XCTAssertEqual(summary.priceToBook, 3.2)
        XCTAssertEqual(summary.dividendYield, 2.1)
        XCTAssertEqual(summary.recommendationKey, "buy")
    }
}
