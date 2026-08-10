import SwiftUI

/// Portfolio tab (Phase 4). Port of `portfolio_screen.dart`: summary card,
/// controls (currency/sort/Allocation), warning panel, digital + cash sections
/// with swipe Edit/Delete, delete confirmation, privacy censor integration, and
/// navigation to stock detail (Phase 5 placeholder destination).
struct PortfolioView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.arunaPalette) private var palette

    @State private var viewModel: PortfolioViewModel?
    @State private var path: [StockRoute] = []
    @State private var showsAddSheet = false
    @State private var showsAllocation = false
    @State private var editingHolding: PortfolioHolding?
    @State private var pendingDelete: PortfolioHoldingMetrics?
    @State private var deleteError: String?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let viewModel {
                    content(for: viewModel)
                } else {
                    ArunaScaffold(title: "Portfolio") {
                        LoadingState(label: "Loading portfolio")
                    }
                }
            }
            .navigationDestination(for: StockRoute.self) { route in
                PhasePendingView(
                    title: route.symbol,
                    icon: "chart.line.uptrend.xyaxis",
                    message: "Stock detail arrives in Phase 5."
                )
            }
        }
        .task {
            if viewModel == nil {
                let viewModel = PortfolioViewModel(
                    repository: environment.portfolioRepository,
                    market: environment.marketRepository
                )
                self.viewModel = viewModel
                await viewModel.load()
            }
        }
    }

    // MARK: - Content

    private func content(for viewModel: PortfolioViewModel) -> some View {
        let isCensored = environment.privacyCensorEnabled
        return Group {
            switch viewModel.phase {
            case .loading:
                ArunaScaffold(title: "Portfolio") {
                    LoadingState(label: "Loading portfolio")
                }
            case .failed(let message):
                ArunaScaffold(title: "Portfolio") {
                    ErrorState(message: message) {
                        Task { await viewModel.load() }
                    }
                }
            case .loaded:
                if let state = viewModel.state, state.holdings.isEmpty {
                    ArunaScaffold(
                        title: "Portfolio",
                        content: {
                            EmptyState(
                                title: "No holdings",
                                message: "Add a position to track total value and profit/loss.",
                                icon: "wallet.bifold"
                            )
                        },
                        action: { addButton }
                    )
                } else if let state = viewModel.state {
                    ArunaScaffold(
                        title: "Portfolio",
                        content: {
                            portfolioList(state: state, viewModel: viewModel, isCensored: isCensored)
                        },
                        action: { addButton }
                    )
                }
            }
        }
        .sheet(isPresented: $showsAddSheet) {
            AddHoldingSheet(
                viewModel: viewModel,
                holding: editingHolding
            )
            .presentationDetents([.large])
            .presentationBackground(palette.elevated)
            .presentationCornerRadius(ArunaRadius.sheetTop)
        }
        .sheet(isPresented: $showsAllocation) {
            if let state = viewModel.state {
                AllocationSheet(
                    state: state,
                    currencyCode: portfolioDisplayCurrencyCode(state.effectiveCurrency)
                )
                .presentationDetents([.medium, .large])
                .presentationBackground(palette.elevated)
                .presentationCornerRadius(ArunaRadius.sheetTop)
            }
        }
        .alert("Delete item?", isPresented: deleteConfirmBinding) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteHolding(viewModel)
            }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private var addButton: some View {
        Button {
            editingHolding = nil
            showsAddSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20))
                .foregroundStyle(palette.primaryText)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add holding")
    }

    private var deleteConfirmBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private func deleteHolding(_ viewModel: PortfolioViewModel) {
        guard let position = pendingDelete else { return }
        pendingDelete = nil
        Task {
            do {
                try await viewModel.removeHolding(id: position.holding.id)
                deleteError = nil
            } catch {
                deleteError = String(describing: error)
            }
        }
    }

    // MARK: - List

    private func portfolioList(state: PortfolioState, viewModel: PortfolioViewModel, isCensored: Bool) -> some View {
        let currencyCode = portfolioDisplayCurrencyCode(state.effectiveCurrency)
        let digitalLast = state.digitalPositions.count - 1
        let cashLast = state.cashPositions.count - 1

        return List {
            SummaryCard(
                summary: state.summary,
                currencyCode: currencyCode,
                isCensored: isCensored,
                onToggleCensor: { environment.togglePrivacyCensor() }
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 0, trailing: 20))

            controls(state: state, viewModel: viewModel)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 0, trailing: 20))

            if state.fxError != nil || state.quoteError != nil {
                warningPanel(
                    message: state.fxError ?? "Latest quotes failed. Cost basis is still available."
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 0, trailing: 20))
            }

            if let deleteError {
                warningPanel(message: deleteError)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 0, trailing: 20))
            }

            if !state.digitalPositions.isEmpty {
                sectionLabel("Digital assets")
                ForEach(Array(state.digitalPositions.enumerated()), id: \.element.holding.id) { index, position in
                    digitalRow(
                        position,
                        currencyCode: currencyCode,
                        isCensored: isCensored,
                        isFirst: index == 0,
                        isLast: index == digitalLast,
                        onEdit: { editingHolding = position.holding; showsAddSheet = true },
                        onDelete: { pendingDelete = position }
                    )
                }
            }

            if !state.cashPositions.isEmpty {
                sectionLabel("Cash")
                ForEach(Array(state.cashPositions.enumerated()), id: \.element.holding.id) { index, position in
                    cashRow(
                        position,
                        currencyCode: currencyCode,
                        isCensored: isCensored,
                        isFirst: index == 0,
                        isLast: index == cashLast,
                        onEdit: { editingHolding = position.holding; showsAddSheet = true },
                        onDelete: { pendingDelete = position }
                    )
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .padding(.top, 12)
        .refreshable {
            await viewModel.refreshQuotes()
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .arunaText(.bodyMedium)
            .fontWeight(.semibold)
            .foregroundStyle(palette.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
    }

    private func warningPanel(message: String) -> some View {
        ArunaCard(
            padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14),
            radius: ArunaRadius.warning
        ) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(palette.warningText)
                Text(message)
                    .arunaText(.bodyMedium)
                    .foregroundStyle(palette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Controls

    private func controls(state: PortfolioState, viewModel: PortfolioViewModel) -> some View {
        HStack(spacing: 8) {
            currencyMenu(state: state, viewModel: viewModel)
            sortMenu(state: state, viewModel: viewModel)
            Spacer()
            Button {
                showsAllocation = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chart.pie")
                        .font(.system(size: 16))
                        .foregroundStyle(palette.secondaryText)
                    Text("Allocation")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .accessibilityLabel("Allocation")
        }
    }

    private func currencyMenu(state: PortfolioState, viewModel: PortfolioViewModel) -> some View {
        Menu {
            ForEach(PortfolioDisplayCurrency.allCases, id: \.self) { currency in
                Button {
                    Task { await viewModel.setDisplayCurrency(currency) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: currency == state.displayCurrency ? "checkmark" : "")
                            .font(.system(size: 16))
                            .foregroundStyle(palette.primaryText)
                        Text(portfolioDisplayCurrencyCode(currency))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(palette.primaryText)
                        if currency == state.displayCurrency, state.effectiveCurrency != state.displayCurrency {
                            Text("showing \(portfolioDisplayCurrencyCode(state.effectiveCurrency))")
                                .arunaText(.labelSmall)
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                }
            }
        } label: {
            toolbarButton(icon: "dollarsign.circle", label: portfolioDisplayCurrencyCode(state.effectiveCurrency))
        }
        .accessibilityLabel("Display currency")
    }

    private func sortMenu(state: PortfolioState, viewModel: PortfolioViewModel) -> some View {
        Menu {
            ForEach(PortfolioSortOption.allCases, id: \.self) { option in
                Button {
                    Task { await viewModel.setSortOption(option) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: option == state.sortOption ? "checkmark" : "")
                            .font(.system(size: 16))
                            .foregroundStyle(palette.primaryText)
                        Text(option.label)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(palette.primaryText)
                    }
                }
            }
        } label: {
            toolbarButton(icon: "arrow.up.arrow.down", label: state.sortOption.shortLabel)
        }
        .accessibilityLabel("Sort holdings")
    }

    private func toolbarButton(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(palette.secondaryText)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .arunaNumeric()
                .foregroundStyle(palette.primaryText)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.border, lineWidth: 1))
    }

    // MARK: - Rows

    private func digitalRow(
        _ position: PortfolioHoldingMetrics,
        currencyCode: String,
        isCensored: Bool,
        isFirst: Bool,
        isLast: Bool,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        NavigationLink(value: StockRoute(symbol: position.holding.symbol)) {
            HStack(spacing: 12) {
                TickerAvatar(symbol: position.holding.symbol, logoURL: position.quote?.logoURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text(position.holding.symbol)
                        .arunaText(.titleMedium)
                        .arunaNumeric()
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                    Text(PrivacyFormatters.sensitiveQuantity(quantityLine(position), isCensored: isCensored))
                        .arunaText(.bodyMedium)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                        .accessibilityLabel(isCensored ? "Hidden quantity" : "")
                }
                Spacer()
                HoldingProfitStack(position: position, currencyCode: currencyCode, isCensored: isCensored)
                HoldingValueStack(position: position, currencyCode: currencyCode, isCensored: isCensored)
            }
            .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("portfolio-row-\(position.holding.symbol)")
        .listRowInsets(EdgeInsets())
        .listRowBackground(palette.surface)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(palette.control)
            Button {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(Color(hex: 0xDC2626, alpha: 0x14))
        }
        .overlay(alignment: .top) {
            if isFirst { hairline }
        }
        .overlay(alignment: .bottom) {
            if isLast {
                hairline
            } else {
                ArunaListDivider(indent: 72)
            }
        }
    }

    private func cashRow(
        _ position: PortfolioHoldingMetrics,
        currencyCode: String,
        isCensored: Bool,
        isFirst: Bool,
        isLast: Bool,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            CashAvatar(emoji: position.holding.cashEmoji)
            VStack(alignment: .leading, spacing: 2) {
                Text(position.holding.displayName)
                    .arunaText(.titleMedium)
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Text(PrivacyFormatters.sensitiveMoney(
                    ArunaFormatters.money(position.nativeCashValue, currency: position.holding.cashCurrency),
                    isCensored: isCensored
                ))
                .arunaText(.bodyMedium)
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .accessibilityLabel(isCensored ? "Hidden cash balance" : "")
            }
            Spacer()
            CashValueStack(
                value: PrivacyFormatters.sensitiveMoney(
                    ArunaFormatters.money(position.currentValue, currency: currencyCode),
                    isCensored: isCensored
                ),
                currency: currencyCode,
                isCensored: isCensored
            )
        }
        .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 16))
        .contentShape(Rectangle())
        .accessibilityIdentifier("portfolio-row-\(position.holding.symbol)")
        .listRowInsets(EdgeInsets())
        .listRowBackground(palette.surface)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(palette.control)
            Button {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(Color(hex: 0xDC2626, alpha: 0x14))
        }
        .overlay(alignment: .top) {
            if isFirst { hairline }
        }
        .overlay(alignment: .bottom) {
            if isLast {
                hairline
            } else {
                ArunaListDivider(indent: 72)
            }
        }
    }

    private var hairline: some View {
        Rectangle().fill(palette.border).frame(height: 1)
    }

    private func quantityLine(_ position: PortfolioHoldingMetrics) -> String {
        let holding = position.holding
        return "\(ArunaFormatters.number(holding.quantity)) \(holding.unit ?? "share")"
    }
}

// MARK: - Summary card

private struct SummaryCard: View {
    let summary: PortfolioSummary
    let currencyCode: String
    let isCensored: Bool
    let onToggleCensor: () -> Void

    @Environment(\.arunaPalette) private var palette

    var body: some View {
        ArunaCard(
            padding: EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18),
            radius: ArunaRadius.identity
        ) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Net worth")
                        .arunaText(.bodyMedium)
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    Button(action: onToggleCensor) {
                        Image(systemName: isCensored ? "eye.slash" : "eye")
                            .font(.system(size: 18))
                            .foregroundStyle(palette.primaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isCensored ? "Show sensitive values" : "Hide sensitive values")
                }
                Text(PrivacyFormatters.sensitiveMoney(
                    ArunaFormatters.money(summary.totalValue, currency: currencyCode),
                    isCensored: isCensored,
                    large: true
                ))
                .font(.system(size: 31, weight: .bold))
                .tracking(-0.6)
                .arunaNumeric()
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.top, 8)
                .accessibilityLabel(isCensored ? "Hidden value" : "")

                HStack {
                    Text("Total P/L")
                        .arunaText(.bodyMedium)
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    Text(PrivacyFormatters.sensitiveMoney(
                        ArunaFormatters.signedMoney(summary.profitLoss, currency: currencyCode),
                        isCensored: isCensored
                    ))
                    .font(.system(size: 13, weight: .semibold))
                    .arunaNumeric()
                    .foregroundStyle(gainColor)
                    .lineLimit(1)
                    .accessibilityLabel(isCensored ? "Hidden profit and loss value" : "")
                    Text(ArunaFormatters.percent(summary.profitLossPercent))
                        .font(.system(size: 13, weight: .semibold))
                        .arunaNumeric()
                        .foregroundStyle(gainColor)
                }
                .padding(.top, 14)
            }
        }
    }

    private var gainColor: Color {
        summary.profitLoss > 0 ? palette.successText : summary.profitLoss < 0 ? palette.errorText : palette.secondaryText
    }
}

// MARK: - Holding value stacks

private struct HoldingProfitStack: View {
    let position: PortfolioHoldingMetrics
    let currencyCode: String
    let isCensored: Bool

    @Environment(\.arunaPalette) private var palette

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(PrivacyFormatters.sensitiveMoney(
                ArunaFormatters.signedMoney(position.profitLoss, currency: currencyCode),
                isCensored: isCensored
            ))
            .font(.system(size: 12, weight: .semibold))
            .arunaNumeric()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityLabel(isCensored ? "Hidden profit and loss value" : "")
            Text(ArunaFormatters.percent(position.profitLossPercent))
                .font(.system(size: 11.5, weight: .semibold))
                .arunaNumeric()
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(minWidth: 84, alignment: .trailing)
    }

    private var color: Color {
        position.profitLoss > 0 ? palette.successText : position.profitLoss < 0 ? palette.errorText : palette.secondaryText
    }
}

private struct HoldingValueStack: View {
    let position: PortfolioHoldingMetrics
    let currencyCode: String
    let isCensored: Bool

    @Environment(\.arunaPalette) private var palette

    var body: some View {
        let holding = position.holding
        VStack(alignment: .trailing, spacing: 2) {
            Text(PrivacyFormatters.sensitiveMoney(
                ArunaFormatters.money(position.currentValue, currency: currencyCode),
                isCensored: isCensored
            ))
            .font(.system(size: 13.5, weight: .semibold))
            .arunaNumeric()
            .foregroundStyle(palette.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityLabel(isCensored ? "Hidden market value" : "")
            Text(ArunaFormatters.money(position.quote?.price, currency: position.quote?.currency ?? holding.currency))
                .font(.system(size: 11.5, weight: .medium))
                .arunaNumeric()
                .foregroundStyle(latestColor)
                .lineLimit(1)
        }
        .frame(minWidth: 112, alignment: .trailing)
    }

    private var latestColor: Color {
        guard position.quote?.price != nil else { return palette.secondaryText }
        return position.profitLoss > 0 ? palette.successText : position.profitLoss < 0 ? palette.errorText : palette.secondaryText
    }
}

private struct CashValueStack: View {
    let value: String
    let currency: String
    let isCensored: Bool

    @Environment(\.arunaPalette) private var palette

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.system(size: 13.5, weight: .semibold))
                .arunaNumeric()
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityLabel(isCensored ? "Hidden converted value" : "")
            Text(currency)
                .arunaText(.bodyMedium)
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
        }
        .frame(minWidth: 128, alignment: .trailing)
    }
}

// MARK: - CashAvatar

/// Port of `CashAvatar`: 40pt circle, `control` bg, emoji glyph.
struct CashAvatar: View {
    let emoji: String
    var size: CGFloat = 40

    @Environment(\.arunaPalette) private var palette

    var body: some View {
        ZStack {
            Circle().fill(palette.control)
            Text(emoji)
                .font(.system(size: 20))
        }
        .frame(width: size, height: size)
    }
}
