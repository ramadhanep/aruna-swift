import SwiftUI
import UniformTypeIdentifiers

/// Typed route toward Stock Detail (Phase 5). Rows push this value now so the
/// detail screen can plug in without touching the watchlist.
struct StockRoute: Hashable {
    let symbol: String
}

/// Watchlist tab (Phase 3). Creates the view model from the environment once;
/// the tab shell preserves its state across tab switches.
struct WatchlistView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.arunaPalette) private var palette

    @State private var viewModel: WatchlistViewModel?
    @State private var isReorderMode = false
    @State private var deletingSymbol: String?
    @State private var deleteError: String?
    @State private var draggedSymbol: String?
    @State private var showsAddSheet = false

    var body: some View {
        Group {
            if let viewModel {
                content(for: viewModel)
            } else {
                ArunaScaffold(title: "Watchlist") {
                    LoadingState(label: "Loading watchlist")
                }
            }
        }
        .task {
            if viewModel == nil {
                let viewModel = WatchlistViewModel(
                    repository: environment.watchlistRepository,
                    market: environment.marketRepository
                )
                self.viewModel = viewModel
                await viewModel.load()
            }
        }
    }

    // MARK: - Content

    private func content(for viewModel: WatchlistViewModel) -> some View {
        ArunaScaffold(
            title: "Watchlist",
            content: {
                switch viewModel.phase {
                case .loading:
                    LoadingState(label: "Loading watchlist")
                case .failed(let message):
                    ErrorState(message: message) {
                        Task { await viewModel.load() }
                    }
                case .loaded:
                    if viewModel.items.isEmpty {
                        EmptyState(
                            title: "No symbols",
                            message: "Add tickers to build a focused watchlist.",
                            icon: "checklist"
                        )
                    } else {
                        watchlistList(for: viewModel)
                    }
                }
            },
            action: { actions(for: viewModel) }
        )
        .sheet(isPresented: $showsAddSheet) {
            AddSymbolSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
                .presentationBackground(palette.elevated)
        }
    }

    private func actions(for viewModel: WatchlistViewModel) -> some View {
        HStack(spacing: 4) {
            if !viewModel.items.isEmpty {
                Button {
                    withAnimation(.easeOutCubic) { isReorderMode.toggle() }
                } label: {
                    Image(systemName: isReorderMode ? "checkmark" : "line.3.horizontal")
                        .font(.system(size: 20))
                        .foregroundStyle(palette.primaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isReorderMode ? "Done reordering" : "Reorder symbols")
            }
            Button {
                showsAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20))
                    .foregroundStyle(palette.primaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add symbol")
        }
    }

    // MARK: - List

    private func watchlistList(for viewModel: WatchlistViewModel) -> some View {
        List {
            if viewModel.quoteError != nil {
                // Flutter parity: the quote-failure warning always shows this
                // fixed text (see watchlist_screen.dart), never the raw error.
                warningCard(
                    message: "Quotes could not refresh. Showing saved symbols.",
                    icon: "exclamationmark.circle",
                    color: palette.warningText
                )
            }
            if let deleteError {
                warningCard(
                    message: deleteError,
                    icon: "exclamationmark.circle",
                    color: palette.errorText
                )
            }
            ForEach(Array(viewModel.items.enumerated()), id: \.element.symbol) { index, item in
                WatchlistRow(
                    item: item,
                    quote: viewModel.quotes[item.symbol],
                    index: index,
                    isLast: index == viewModel.items.count - 1,
                    isReorderMode: isReorderMode,
                    isDeleting: deletingSymbol == item.symbol,
                    draggedSymbol: $draggedSymbol,
                    onDelete: { delete(item.symbol, from: viewModel) },
                    onDrop: { dragged, target in
                        Task { await viewModel.reorderSymbol(from: dragged, to: target) }
                    }
                )
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .padding(.top, ArunaSpacing.s12)
        .refreshable {
            await viewModel.refreshQuotes()
        }
    }

    private func warningCard(message: String, icon: String, color: Color) -> some View {
        ArunaCard(
            padding: EdgeInsets(top: ArunaSpacing.warning, leading: ArunaSpacing.warning, bottom: ArunaSpacing.warning, trailing: ArunaSpacing.warning),
            radius: ArunaRadius.warning
        ) {
            HStack(spacing: ArunaSpacing.s12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(color)
                Text(message)
                    .arunaText(.bodyMedium)
                    .foregroundStyle(palette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, ArunaSpacing.s20)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: ArunaSpacing.s12, trailing: 0))
    }

    // MARK: - Mutations

    private func delete(_ symbol: String, from viewModel: WatchlistViewModel) {
        guard deletingSymbol == nil else { return }
        deletingSymbol = symbol
        deleteError = nil
        Task {
            do {
                try await viewModel.removeSymbol(symbol)
            } catch {
                deleteError = String(describing: error)
            }
            deletingSymbol = nil
        }
    }
}

// MARK: - Row

private struct WatchlistRow: View {
    let item: WatchlistItem
    let quote: StockQuote?
    let index: Int
    let isLast: Bool
    let isReorderMode: Bool
    let isDeleting: Bool
    @Binding var draggedSymbol: String?
    let onDelete: () -> Void
    let onDrop: (String, String) -> Void

    @Environment(\.arunaPalette) private var palette
    @State private var isDropTarget = false

    var body: some View {
        if isReorderMode {
            baseRow
                .onDrop(of: [UTType.text], isTargeted: $isDropTarget) { _, _ in
                    guard let dragged = draggedSymbol, dragged != item.symbol else { return false }
                    onDrop(dragged, item.symbol)
                    return true
                }
        } else {
            baseRow
        }
    }

    private var baseRow: some View {
        NavigationLink(value: StockRoute(symbol: item.symbol)) {
            HStack(spacing: ArunaSpacing.s12) {
                TickerAvatar(symbol: item.symbol, logoURL: quote?.logoURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.symbol)
                        .arunaText(.titleMedium)
                        .arunaNumeric()
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                    Text(item.name ?? quote?.name ?? "Quote pending")
                        .arunaText(.bodyMedium)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ArunaFormatters.money(quote?.price, currency: quote?.currency))
                        .arunaText(.listPrice)
                        .arunaNumeric()
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                    PriceChangeText(value: quote?.changePercent, compact: true)
                }
                Color.clear.frame(width: 4)
                trailing
            }
            .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("watchlist-row-\(item.symbol)")
        .listRowInsets(EdgeInsets())
        .listRowBackground(palette.surface)
        .listRowSeparator(.hidden)
        .overlay(alignment: .bottom) {
            if !isLast {
                ArunaListDivider(indent: 72)
            }
        }
        .overlay {
            if isDropTarget {
                Rectangle()
                    .fill(palette.border)
                    .frame(height: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.leading, 20)
                    .padding(.trailing, 16)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                onDelete()
            } label: {
                if isDeleting {
                    ProgressView().tint(palette.errorText)
                } else {
                    Label("Delete", systemImage: "trash")
                }
            }
            .tint(Color(hex: 0xDC2626, alpha: 0x15))
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if isDeleting {
            ProgressView()
                .tint(palette.secondaryText)
                .frame(width: 44, height: 44)
        } else if isReorderMode {
            // Flutter `ReorderableDragStartListener(gripVertical)`: drag starts
            // on the grip handle, never the row (keeps tap-to-navigate intact).
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 20))
                .foregroundStyle(palette.icon)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .onDrag {
                    draggedSymbol = item.symbol
                    return NSItemProvider(object: item.symbol as NSString)
                }
                .accessibilityIdentifier("watchlist-grip-\(item.symbol)")
        } else {
            Color.clear.frame(width: 0, height: 44)
        }
    }
}
