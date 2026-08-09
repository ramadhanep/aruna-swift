import SwiftUI
import Observation

/// Shared scroll signal the tab shell owns. Tab content reports scroll
/// direction through `.arunaScrollSensitive()`; the shell drives the liquid
/// tab bar compression. Kept reusable so Phase 3/4 feature screens (Watchlist,
/// Portfolio) plug in without any shell changes.
@MainActor
@Observable
final class TabScrollState {
    var isCompressed = false
}

/// Flutter `MainShell`: `TabView` (state structure) + custom floating liquid
/// tab bar (visible navigation). One `NavigationStack` per tab preserves each
/// tab's independent navigation state.
struct MainShell: View {
    @Environment(\.arunaPalette) private var palette
    @State private var selectedIndex = 0
    @State private var scrollState = TabScrollState()

    var body: some View {
        TabView(selection: $selectedIndex) {
            PortfolioTab()
                .tabItem { EmptyView() }
                .tag(0)
            WatchlistTab()
                .tabItem { EmptyView() }
                .tag(1)
            AccountTab()
                .tabItem { EmptyView() }
                .tag(2)
        }
        .toolbar(.hidden, for: .tabBar)
        .environment(scrollState)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            LiquidTabBar(
                selectedIndex: selectedIndex,
                isCompressed: scrollState.isCompressed,
                onSelect: { index in
                    withAnimation(.easeOutCubic) { scrollState.isCompressed = false }
                    selectedIndex = index
                }
            )
            .padding(.horizontal, ArunaSpacing.tabBarHorizontal)
            .padding(.bottom, ArunaSpacing.tabBarBottom)
        }
        .background(palette.page)
    }
}

private struct PortfolioTab: View {
    var body: some View {
        NavigationStack {
            PhasePendingView(title: "Portfolio", icon: "wallet.bifold", message: "Portfolio tracking arrives in Phase 4.")
        }
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

/// Minimal Phase 2 placeholder destination. Scrollable so the liquid tab bar
/// compression is exercised; replaced by the real feature screen in its phase.
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
            .arunaScrollSensitive()
        }
    }
}

// MARK: - Liquid tab bar

struct LiquidTabBar: View {
    let selectedIndex: Int
    let isCompressed: Bool
    let onSelect: (Int) -> Void

    @Environment(\.arunaPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    private static let tabs: [(label: String, icon: String)] = [
        ("Portfolio", "wallet.bifold"),
        ("Watchlist", "checklist"),
        ("Account", "person.crop.circle"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.tabs.indices, id: \.self) { index in
                let tab = Self.tabs[index]
                let selected = index == selectedIndex
                Button {
                    onSelect(index)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 22))
                        Text(tab.label)
                            .font(.system(size: 11, weight: selected ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selected ? palette.primaryText : palette.mutedText)
                    .frame(maxWidth: .infinity)
                    .frame(height: ArunaSpacing.tabBarHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(barBackground)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ArunaRadius.tabBar))
        .overlay(
            RoundedRectangle(cornerRadius: ArunaRadius.tabBar)
                .strokeBorder(palette.strongBorder, lineWidth: 1)
        )
        .scaleEffect(isCompressed ? 0.9 : 1, anchor: .bottom)
        .opacity(isCompressed ? 0.88 : 1)
        .animation(.easeOutCubic, value: isCompressed)
    }

    private var barBackground: Color {
        colorScheme == .dark
            ? Color(hex: 0x111113, alpha: 0xB8 / 255.0)
            : Color(hex: 0xFFFFFF, alpha: 0xDF / 255.0)
    }
}

// MARK: - Scroll sensitivity

private struct ScrollSensitiveModifier: ViewModifier {
    @Environment(TabScrollState.self) private var scrollState

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                abs(geometry.contentOffset.y)
            } action: { old, new in
                if new <= 8 {
                    scrollState.isCompressed = false
                } else if new > old {
                    scrollState.isCompressed = true
                } else {
                    scrollState.isCompressed = false
                }
            }
    }
}

extension View {
    /// Reports vertical scroll depth so the shell can compress the tab bar.
    func arunaScrollSensitive() -> some View {
        modifier(ScrollSensitiveModifier())
    }
}

// MARK: - Motion tokens

extension Animation {
    /// Flutter `Curves.easeOutCubic`, 220ms — tab bar compression.
    static let easeOutCubic = Animation.timingCurve(0.215, 0.61, 0.355, 1, duration: 0.22)
}
