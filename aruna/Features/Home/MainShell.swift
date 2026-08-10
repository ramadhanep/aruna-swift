import SwiftUI

/// Flutter `MainShell`: native SwiftUI `TabView` with one `NavigationStack`
/// per tab so each tab's navigation state is preserved independently.
///
/// The tab bar is the system iOS tab bar. Appearance (color, material, Liquid
/// Glass, animation, safe area) is intentionally system-controlled.
struct MainShell: View {
    @Environment(\.arunaPalette) private var palette
    @State private var selectedIndex = 0

    var body: some View {
        TabView(selection: $selectedIndex) {
            PortfolioTab()
                .tabItem { Label("Portfolio", systemImage: "wallet.bifold") }
                .tag(0)
            WatchlistTab()
                .tabItem { Label("Watchlist", systemImage: "checklist") }
                .tag(1)
            AccountTab()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(2)
        }
        .background(palette.page)
    }
}

private struct PortfolioTab: View {
    var body: some View {
        PortfolioView()
    }
}

private struct WatchlistTab: View {
    @State private var path: [StockRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            WatchlistView()
                .navigationDestination(for: StockRoute.self) { route in
                    PhasePendingView(
                        title: route.symbol,
                        icon: "chart.line.uptrend.xyaxis",
                        message: "Stock detail arrives in Phase 5."
                    )
                }
        }
    }
}

private struct AccountTab: View {
    var body: some View {
        NavigationStack {
            AccountView()
        }
    }
}

/// Minimal Phase 2 placeholder destination; replaced by the real feature
/// screen in its phase.
struct PhasePendingView: View {
    let title: String
    let icon: String
    let message: String

    @Environment(\.arunaPalette) private var palette

    var body: some View {
        ArunaScaffold(title: title) {
            ScrollView {
                EmptyState(title: title, message: message, icon: icon)
                    .frame(maxWidth: .infinity)
                    .frame(height: 420)
                Color.clear.frame(height: 400)
            }
        }
    }
}

// MARK: - Motion tokens

extension Animation {
    /// Flutter `Curves.easeOutCubic`, 220ms.
    static let easeOutCubic = Animation.timingCurve(0.215, 0.61, 0.355, 1, duration: 0.22)
}
