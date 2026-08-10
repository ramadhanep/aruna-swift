//
//  arunaUITests.swift
//  arunaUITests
//
//  Phase 2 + 3 UI tests. Deterministic: local mode by default (Supabase forced
//  unconfigured via launch environment), the API is stubbed through
//  `-uitest-api-mock`, and no production credentials/network are ever used.
//

import XCTest

final class arunaUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches the app.
    /// - `reset`: wipes persisted settings via `-uitest-reset`.
    /// - `supabaseConfigured`: injects fake (non-secret) config so the app boots
    ///   into the configured-but-signed-out gate; otherwise Supabase is forced
    ///   unconfigured so the app lands in local mode regardless of local config.
    /// - `apiMock`: routes all API traffic through the deterministic
    ///   `UITestURLProtocol` stub (`-uitest-api-mock`).
    /// - `apiMode`: `UITEST_API_MODE` scenario for the stub.
    /// - `watchlistMode`: repository override launch argument.
    private func launchApp(
        reset: Bool = false,
        supabaseConfigured: Bool = false,
        apiMock: Bool = false,
        apiMode: String? = nil,
        watchlistMode: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments: [String] = []
        if reset { arguments.append("-uitest-reset") }
        if apiMock { arguments.append("-uitest-api-mock") }
        if let watchlistMode { arguments.append(watchlistMode) }
        app.launchArguments = arguments

        if supabaseConfigured {
            app.launchEnvironment["SUPABASE_URL"] = "https://fake-project.supabase.co"
            app.launchEnvironment["SUPABASE_ANON_KEY"] = "fake-anon-key"
        } else {
            app.launchEnvironment["SUPABASE_URL"] = "https://<your-project>.supabase.co"
            app.launchEnvironment["SUPABASE_ANON_KEY"] = "<your-anon-key>"
        }
        if let apiMode {
            app.launchEnvironment["UITEST_API_MODE"] = apiMode
        }
        app.launch()
        return app
    }

    private func openWatchlist(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Portfolio"].waitForExistence(timeout: 10))
        let watchlistTab = app.tabBars.buttons["Watchlist"]
        XCTAssertTrue(watchlistTab.exists, "Native Watchlist tab must exist")
        watchlistTab.tap()
    }

    private func openAddSymbolSheet(_ app: XCUIApplication) {
        openWatchlist(app)
        XCTAssertTrue(app.staticTexts["BBCA.JK"].waitForExistence(timeout: 10))
        app.buttons["Add symbol"].tap()
    }

    // MARK: - Boot

    /// Unconfigured/local environment: app resolves straight into the shell.
    /// `apiMock` keeps the Portfolio tab's FX fetch offline and deterministic.
    func testBootResolvesToLocalModeAndShowsPortfolio() throws {
        let app = launchApp(reset: true, apiMock: true)

        XCTAssertTrue(
            app.staticTexts["Portfolio"].waitForExistence(timeout: 10),
            "App stayed on the startup loading placeholder instead of reaching the shell"
        )
    }

    // MARK: - Auth gate

    /// Configured signed-out environment: sign-in screen is shown.
    func testConfiguredSignedOutShowsSignInScreen() throws {
        let app = launchApp(reset: true, supabaseConfigured: true)

        XCTAssertTrue(
            app.staticTexts["Sign in"].waitForExistence(timeout: 10),
            "Configured-but-signed-out launch should show the sign-in screen"
        )
    }

    /// From Sign In, "Use local mode" enters the shell (Portfolio tab).
    func testUseLocalModeEntersShell() throws {
        let app = launchApp(reset: true, supabaseConfigured: true, apiMock: true)
        XCTAssertTrue(app.staticTexts["Sign in"].waitForExistence(timeout: 10))

        app.buttons["Use local mode"].tap()

        XCTAssertTrue(app.staticTexts["Portfolio"].waitForExistence(timeout: 10))
    }

    // MARK: - Tabs

    func testTabSwitchingShowsEachDestination() throws {
        let app = launchApp(reset: true, apiMock: true)
        XCTAssertTrue(app.staticTexts["Portfolio"].waitForExistence(timeout: 10))

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertTrue(tabBar.buttons["Portfolio"].exists, "Portfolio tab must exist")
        XCTAssertTrue(tabBar.buttons["Watchlist"].exists, "Watchlist tab must exist")
        XCTAssertTrue(tabBar.buttons["Account"].exists, "Account tab must exist")

        tabBar.buttons["Watchlist"].tap()
        XCTAssertTrue(app.staticTexts["BBCA.JK"].waitForExistence(timeout: 10))

        tabBar.buttons["Account"].tap()
        XCTAssertTrue(app.staticTexts["Synced"].waitForExistence(timeout: 10)
            || app.staticTexts["Guest"].waitForExistence(timeout: 10)
            || app.staticTexts["Local"].waitForExistence(timeout: 10))

        tabBar.buttons["Portfolio"].tap()
        XCTAssertTrue(app.staticTexts["No holdings"].waitForExistence(timeout: 10))
    }

    // MARK: - Persistence

    func testAppearanceSelectionPersistsAcrossRelaunch() throws {
        var app = launchApp(reset: true, apiMock: true)
        app.tabBars.buttons["Account"].tap()
        XCTAssertTrue(app.buttons["Appearance, Dark"].waitForExistence(timeout: 10))

        app.buttons["Appearance, Dark"].tap()
        XCTAssertTrue(app.staticTexts["Light"].waitForExistence(timeout: 10))
        app.staticTexts["Light"].tap()
        app.terminate()

        app = launchApp()
        app.tabBars.buttons["Account"].tap()
        XCTAssertTrue(
            app.buttons["Appearance, Light"].waitForExistence(timeout: 10),
            "Appearance selection should survive relaunch"
        )
    }

    func testPrivacyTogglePersistsAcrossRelaunch() throws {
        var app = launchApp(reset: true, apiMock: true)
        app.tabBars.buttons["Account"].tap()
        XCTAssertTrue(app.buttons["Privacy mode, Off"].waitForExistence(timeout: 10))

        app.buttons["Privacy mode, Off"].tap()
        XCTAssertTrue(app.buttons["Privacy mode, On"].waitForExistence(timeout: 10))
        app.terminate()

        app = launchApp()
        app.tabBars.buttons["Account"].tap()
        XCTAssertTrue(
            app.buttons["Privacy mode, On"].waitForExistence(timeout: 10),
            "Privacy toggle should survive relaunch"
        )
    }

    // MARK: - Watchlist

    /// Boot → Watchlist → default 8 symbols seeded and visible.
    func testWatchlistBootSeedsDefaults() throws {
        let app = launchApp(reset: true, apiMock: true)
        openWatchlist(app)

        XCTAssertTrue(app.staticTexts["BBCA.JK"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["BBRI.JK"].exists)
        XCTAssertTrue(app.staticTexts["BMRI.JK"].exists)
        XCTAssertTrue(app.staticTexts["MSFT"].exists)
    }

    /// Add an exact ticker via the add-symbol sheet.
    func testAddExactSymbol() throws {
        let app = launchApp(reset: true, apiMock: true)
        openAddSymbolSheet(app)

        let field = app.textFields["BBCA.JK, NVDA, BTC-USD"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("TSLA")
        app.buttons["Add exact symbol"].tap()

        XCTAssertTrue(app.staticTexts["TSLA"].waitForExistence(timeout: 10))
    }

    /// Search returns results; selecting one adds the symbol to the list.
    func testSearchSelectsResultAndAddsSymbol() throws {
        let app = launchApp(reset: true, apiMock: true)
        openAddSymbolSheet(app)

        let field = app.textFields["BBCA.JK, NVDA, BTC-USD"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("nvd\n")

        XCTAssertTrue(app.buttons["Add NVD"].waitForExistence(timeout: 5))
        app.buttons["Add NVD"].tap()

        XCTAssertTrue(app.staticTexts["NVD"].waitForExistence(timeout: 10))
    }

    /// Search with zero results shows the empty state.
    func testSearchShowsEmptyState() throws {
        let app = launchApp(reset: true, apiMock: true)
        openAddSymbolSheet(app)

        let field = app.textFields["BBCA.JK, NVDA, BTC-USD"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("zzz\n")

        XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 5))
    }

    /// Search failure shows the error state with Retry.
    func testSearchShowsErrorState() throws {
        let app = launchApp(reset: true, apiMock: true, apiMode: "search-fail")
        openAddSymbolSheet(app)

        let field = app.textFields["BBCA.JK, NVDA, BTC-USD"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("aapl\n")

        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 5))
    }

    /// Swipe-to-delete removes the row.
    func testSwipeDeleteRemovesRow() throws {
        let app = launchApp(reset: true, apiMock: true)
        openWatchlist(app)
        XCTAssertTrue(app.staticTexts["BBCA.JK"].waitForExistence(timeout: 10))

        let row = app.buttons["watchlist-row-BBCA.JK"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5))
        app.buttons["Delete"].tap()

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: row)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.staticTexts["BBCA.JK"].exists)
    }

    /// Pull-to-refresh re-fetches quotes; a quote failure surfaces the warning
    /// while the saved symbols stay.
    func testPullToRefreshQuoteFailureKeepsSymbols() throws {
        let app = launchApp(reset: true, apiMock: true, apiMode: "quotes-fail-on-refresh")
        openWatchlist(app)
        XCTAssertTrue(app.staticTexts["BBCA.JK"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Quotes could not refresh. Showing saved symbols."].exists)

        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertTrue(
            app.staticTexts["Quotes could not refresh. Showing saved symbols."].waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.staticTexts["BBCA.JK"].exists, "Saved symbols must survive a failed refresh")
    }

    /// Full quote failure on load: symbols shown plus warning card.
    func testQuoteFailureShowsWarningAndSymbols() throws {
        let app = launchApp(reset: true, apiMock: true, apiMode: "quotes-fail")
        openWatchlist(app)

        XCTAssertTrue(app.staticTexts["Quotes could not refresh. Showing saved symbols."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["BBCA.JK"].exists)
        XCTAssertTrue(app.buttons["Add symbol"].exists, "List must stay usable with quotes unavailable")
    }

    /// Reorder mode drag changes the displayed order.
    func testReorderChangesOrder() throws {
        let app = launchApp(reset: true, apiMock: true)
        openWatchlist(app)
        XCTAssertTrue(app.staticTexts["BBCA.JK"].waitForExistence(timeout: 10))

        app.buttons["Reorder symbols"].tap()

        let grip = app.images["watchlist-grip-BBCA.JK"]
        let msft = app.buttons["watchlist-row-MSFT"]
        XCTAssertTrue(grip.waitForExistence(timeout: 5))
        XCTAssertTrue(msft.waitForExistence(timeout: 5))
        let start = grip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let target = msft.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 2.5, thenDragTo: target, withVelocity: XCUIGestureVelocity.default, thenHoldForDuration: 0.5)

        let deadline = Date().addingTimeInterval(10)
        var reordered = false
        while Date() < deadline {
            if app.buttons["watchlist-row-BBCA.JK"].frame.minY
                > app.buttons["watchlist-row-MSFT"].frame.minY {
                reordered = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(reordered, "BBCA.JK should sit below MSFT after the drag")
    }

    /// Existing local watchlist survives relaunch (no reseed, no reset).
    func testWatchlistPersistsAcrossRelaunch() throws {
        var app = launchApp(reset: true, apiMock: true)
        openAddSymbolSheet(app)

        let field = app.textFields["BBCA.JK, NVDA, BTC-USD"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("TSLA")
        app.buttons["Add exact symbol"].tap()
        XCTAssertTrue(app.staticTexts["TSLA"].waitForExistence(timeout: 10))
        app.terminate()

        app = launchApp(reset: false, apiMock: true)
        openWatchlist(app)

        XCTAssertTrue(app.staticTexts["TSLA"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["BBCA.JK"].exists)
    }

    /// Forced empty repository renders the empty state.
    func testWatchlistEmptyState() throws {
        let app = launchApp(reset: true, apiMock: true, watchlistMode: "-uitest-watchlist-empty")
        openWatchlist(app)

        XCTAssertTrue(app.staticTexts["No symbols"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Add tickers to build a focused watchlist."].exists)
    }

    /// Forced repository failure renders the error state with Retry.
    func testWatchlistErrorState() throws {
        let app = launchApp(reset: true, apiMock: true, watchlistMode: "-uitest-watchlist-fail")
        openWatchlist(app)

        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 10))
    }

    // MARK: - Portfolio

    private func addDigitalHolding(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["No holdings"].waitForExistence(timeout: 10))
        app.buttons["Add holding"].tap()

        let symbol = app.textFields["Symbol"]
        XCTAssertTrue(symbol.waitForExistence(timeout: 5))
        symbol.tap()
        symbol.typeText("NVDA")

        let amount = app.textFields["Amount"]
        amount.tap()
        amount.typeText("10")

        let price = app.textFields["Average price"]
        price.tap()
        price.typeText("100")

        app.buttons["Save holding"].tap()
        XCTAssertTrue(app.staticTexts["NVDA"].waitForExistence(timeout: 10))
    }

    /// Empty portfolio renders the empty state with the add action available.
    func testPortfolioEmptyState() throws {
        let app = launchApp(reset: true, apiMock: true)

        XCTAssertTrue(app.staticTexts["No holdings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Add a position to track total value and profit/loss."].exists)
        XCTAssertTrue(app.buttons["Add holding"].exists)
    }

    /// Add a digital holding via the sheet; it appears in the list.
    func testPortfolioAddDigitalHolding() throws {
        let app = launchApp(reset: true, apiMock: true)
        addDigitalHolding(app)
    }

    /// Add a cash bucket (IDR FX served by the mock); it appears with its label.
    func testPortfolioAddCashHolding() throws {
        let app = launchApp(reset: true, apiMock: true)
        XCTAssertTrue(app.staticTexts["No holdings"].waitForExistence(timeout: 10))
        app.buttons["Add holding"].tap()

        XCTAssertTrue(app.buttons["Cash"].waitForExistence(timeout: 5))
        app.buttons["Cash"].tap()

        let label = app.textFields["Cash label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        label.tap()
        label.typeText("Emergency fund")

        let amount = app.textFields["Amount"]
        amount.tap()
        amount.typeText("1000000")

        app.buttons["Save holding"].tap()
        XCTAssertTrue(app.staticTexts["Emergency fund"].waitForExistence(timeout: 10))
    }

    /// Swipe Delete opens the confirmation dialog; confirming removes the row.
    func testPortfolioDeleteConfirmationAppears() throws {
        let app = launchApp(reset: true, apiMock: true)
        addDigitalHolding(app)

        let row = app.buttons["portfolio-row-NVDA"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()

        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5))
        app.buttons["Delete"].tap()

        let alert = app.alerts["Delete item?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["This cannot be undone."].exists)
        alert.buttons["Delete"].tap()

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: row)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.staticTexts["NVDA"].exists)
    }

    /// Allocation sheet opens and shows chart sections.
    func testPortfolioAllocationSheetOpens() throws {
        let app = launchApp(reset: true, apiMock: true)
        addDigitalHolding(app)

        XCTAssertTrue(app.buttons["Allocation"].waitForExistence(timeout: 10))
        app.buttons["Allocation"].tap()

        XCTAssertTrue(app.staticTexts["Allocation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Asset mix"].exists)
        XCTAssertTrue(app.staticTexts["Digital allocation"].exists)
    }

    /// Privacy censor masks sensitive values on the Portfolio screen. Censored
    /// values carry Flutter-parity hidden semantics ("Hidden value",
    /// "Hidden profit and loss value", "Hidden quantity") instead of the raw
    /// masked string, so the UI test asserts those semantics.
    func testPortfolioPrivacyCensorRendersCensoredValues() throws {
        let app = launchApp(reset: true, apiMock: true)
        addDigitalHolding(app)

        let hideButton = app.buttons["Hide sensitive values"]
        XCTAssertTrue(hideButton.waitForExistence(timeout: 10))
        hideButton.tap()

        XCTAssertTrue(app.staticTexts["Hidden value"].waitForExistence(timeout: 5), "net worth must be masked")
        XCTAssertTrue(app.staticTexts["Hidden profit and loss value"].exists, "P/L amount must be masked")
        XCTAssertTrue(app.staticTexts["Hidden quantity"].exists, "quantity must be masked")
        XCTAssertTrue(app.staticTexts["Hidden market value"].exists, "holding value must be masked")

        app.buttons["Show sensitive values"].tap()
        XCTAssertFalse(app.staticTexts["Hidden value"].exists, "values must be restored when censor is off")
    }

    // MARK: - Performance

    @MainActor
    func testLaunchPerformance() throws {
        // Configure the launched app to stay offline (local mode + API mock);
        // the Portfolio tab fetches FX on load.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["-uitest-reset", "-uitest-api-mock"]
            app.launchEnvironment["SUPABASE_URL"] = "https://<your-project>.supabase.co"
            app.launchEnvironment["SUPABASE_ANON_KEY"] = "<your-anon-key>"
            app.launch()
        }
    }
}
