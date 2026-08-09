import SwiftUI

/// Add-symbol bottom sheet: exact ticker entry + API-backed search. Port of
/// `lib/features/watchlist/presentation/add_symbol_sheet.dart`.
struct AddSymbolSheet: View {
    let viewModel: WatchlistViewModel

    @Environment(\.arunaPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var searchState: SearchState = .idle
    @State private var isAdding = false
    @State private var formError: String?
    @FocusState private var fieldFocused: Bool

    private enum SearchState {
        case idle
        case searching
        case results([SymbolSearchResult])
        case empty
        case error(String)
    }

    private static let suggestions = ["BBCA.JK", "AAPL", "QQQ", "BTC-USD"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ArunaSpacing.s12) {
                header
                searchField
                content
                if let formError {
                    Text(formError)
                        .arunaText(.bodyMedium)
                        .foregroundStyle(palette.errorText)
                }
                addExactButton
            }
            .padding(.horizontal, ArunaSpacing.s20)
            .padding(.top, ArunaSpacing.s16)
            .padding(.bottom, ArunaSpacing.s20)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Add symbol")
                .arunaText(.titleLarge)
                .foregroundStyle(palette.primaryText)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16))
                    .foregroundStyle(palette.icon)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(palette.icon)
            TextField("BBCA.JK, NVDA, BTC-USD", text: $query)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textCase(.uppercase)
                .foregroundStyle(palette.primaryText)
                .submitLabel(.search)
                .onSubmit { search() }
                .disabled(isAdding)
                .focused($fieldFocused)
            Button {
                search()
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 16))
                    .foregroundStyle(palette.primaryText)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isAdding)
            .accessibilityLabel("Search")
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(palette.control)
        .clipShape(RoundedRectangle(cornerRadius: ArunaRadius.input))
        .overlay(
            RoundedRectangle(cornerRadius: ArunaRadius.input)
                .strokeBorder(fieldFocused ? palette.accent : palette.border, lineWidth: 1)
        )
    }

    // MARK: - Results area

    @ViewBuilder
    private var content: some View {
        switch searchState {
        case .idle:
            suggestionChips
        case .searching:
            LoadingState(label: "Searching")
                .frame(height: 160)
        case .error(let message):
            ErrorState(message: message) { search() }
                .frame(height: 160)
        case .empty:
            EmptyState(
                title: "No matches",
                message: "Add the exact ticker if search returns nothing.",
                icon: "magnifyingglass"
            )
            .frame(height: 160)
        case .results(let results):
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results, id: \.symbol) { result in
                        resultRow(result)
                    }
                }
            }
            .frame(maxHeight: 320)
        }
    }

    private var suggestionChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                chip(Self.suggestions[0])
                chip(Self.suggestions[1])
            }
            HStack(spacing: 8) {
                chip(Self.suggestions[2])
                chip(Self.suggestions[3])
            }
        }
    }

    private func chip(_ symbol: String) -> some View {
        Button {
            add(symbol)
        } label: {
            Text(symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.primaryText)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(palette.control)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(palette.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isAdding)
        .accessibilityLabel("Add \(symbol)")
    }

    private func resultRow(_ result: SymbolSearchResult) -> some View {
        Button {
            add(result.symbol, name: result.name)
        } label: {
            HStack(spacing: ArunaSpacing.s12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.symbol)
                        .arunaText(.titleMedium)
                        .arunaNumeric()
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                    Text(result.name)
                        .arunaText(.bodyMedium)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 20))
                    .foregroundStyle(palette.icon)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAdding)
        .accessibilityLabel("Add \(result.symbol)")
    }

    // MARK: - Add

    private var addExactButton: some View {
        Button {
            add(query)
        } label: {
            if isAdding {
                InlineButtonSpinner(label: "Saving...")
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 16))
                    Text("Add exact symbol")
                }
            }
        }
        .buttonStyle(ArunaOutlinedButtonStyle())
        .disabled(isAdding)
    }

    private func search() {
        guard !isAdding else { return }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        searchState = .searching
        Task {
            do {
                let results = try await viewModel.searchSymbols(trimmed)
                searchState = results.isEmpty ? .empty : .results(results)
            } catch {
                searchState = .error(String(describing: error))
            }
        }
    }

    private func add(_ symbol: String, name: String? = nil) {
        guard !isAdding else { return }
        let trimmed = symbol.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            formError = "Enter a symbol."
            return
        }
        isAdding = true
        formError = nil
        Task {
            do {
                // Duplicate adds are a no-op that still dismisses (Flutter parity).
                _ = try await viewModel.addSymbol(trimmed, name: name)
                dismiss()
            } catch {
                isAdding = false
                formError = String(describing: error)
            }
        }
    }
}
