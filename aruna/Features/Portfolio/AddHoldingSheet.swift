import SwiftUI

/// Add/edit holding bottom sheet. Port of `add_holding_sheet.dart`: Digital and
/// Cash modes, Flutter-identical fields, validation messages, saving state.
struct AddHoldingSheet: View {
    let viewModel: PortfolioViewModel
    let holding: PortfolioHolding?

    @Environment(\.arunaPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var majorType: String
    @State private var symbolText: String
    @State private var quantityText: String
    @State private var averagePriceText: String
    @State private var currencyText: String
    @State private var marketText: String
    @State private var categoryText: String
    @State private var cashAmountText: String
    @State private var assetType: String
    @State private var unit: String
    @State private var cashCurrency: String
    @State private var emoji: String
    @State private var formError: String?
    @State private var isSubmitting = false

    private static let assetTypes = ["stock", "etf", "crypto", "fund", "other"]
    private static let units = ["share", "lot"]
    private static let cashCurrencies = ["IDR", "USD", "SGD"]
    private static let cashEmojis = ["💵", "💰", "🏦", "🪙", "💳", "💸", "🇺🇸", "🇮🇩", "🇸🇬"]

    init(
        viewModel: PortfolioViewModel,
        holding: PortfolioHolding? = nil,
        initialSymbol: String? = nil,
        initialCurrency: String? = nil,
        initialMarket: String? = nil,
        initialAssetType: String? = nil
    ) {
        self.viewModel = viewModel
        self.holding = holding

        var majorType = "digital"
        var symbolText = ""
        var quantityText = ""
        var averagePriceText = ""
        var currencyText = "USD"
        var marketText = ""
        var categoryText = ""
        var cashAmountText = ""
        var assetType = "stock"
        var unit = "share"
        var cashCurrency = "IDR"
        var emoji = PortfolioHolding.defaultCashEmoji

        if let holding {
            if holding.isCash {
                majorType = "cash"
                categoryText = holding.category ?? holding.name ?? "Cash"
                cashCurrency = holding.cashCurrency ?? "IDR"
                cashAmountText = Self.formatInputNumber(holding.nativeAmount ?? holding.quantity)
                emoji = holding.cashEmoji
            } else {
                symbolText = holding.symbol
                quantityText = Self.formatInputNumber(holding.quantity)
                averagePriceText = Self.formatInputNumber(holding.averagePrice)
                currencyText = holding.currency ?? Self.defaultCurrency(holding.symbol)
                marketText = holding.market ?? Self.defaultMarket(holding.symbol)
                assetType = Self.normalizeAssetType(holding.assetType, symbol: holding.symbol)
                unit = holding.unit ?? Self.defaultUnit(holding.symbol)
            }
        } else if let initialSymbol = initialSymbol?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
            !initialSymbol.isEmpty {
            symbolText = initialSymbol
            currencyText = initialCurrency?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ?? Self.defaultCurrency(initialSymbol)
            marketText = initialMarket?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ?? Self.defaultMarket(initialSymbol)
            assetType = Self.normalizeAssetType(initialAssetType, symbol: initialSymbol)
            unit = Self.defaultUnit(initialSymbol)
        }

        _majorType = State(initialValue: majorType)
        _symbolText = State(initialValue: symbolText)
        _quantityText = State(initialValue: quantityText)
        _averagePriceText = State(initialValue: averagePriceText)
        _currencyText = State(initialValue: currencyText)
        _marketText = State(initialValue: marketText)
        _categoryText = State(initialValue: categoryText)
        _cashAmountText = State(initialValue: cashAmountText)
        _assetType = State(initialValue: assetType)
        _unit = State(initialValue: unit)
        _cashCurrency = State(initialValue: cashCurrency)
        _emoji = State(initialValue: emoji)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                modeButtons
                fields
                if let formError {
                    Text(formError)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.errorText)
                }
                saveButton
            }
            .padding(.horizontal, ArunaSpacing.s20)
            .padding(.top, ArunaSpacing.s16)
            .padding(.bottom, ArunaSpacing.s20)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(holding == nil ? "Add holding" : "Edit holding")
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

    private var modeButtons: some View {
        HStack(spacing: 12) {
            modeButton(selected: majorType != "cash", icon: "arrow.up.right", label: "Digital") {
                majorType = "digital"
            }
            modeButton(selected: majorType == "cash", icon: "creditcard", label: "Cash") {
                majorType = "cash"
            }
        }
    }

    private func modeButton(selected: Bool, icon: String, label: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .arunaText(.button)
            }
            .foregroundStyle(selected ? palette.page : palette.primaryText)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(selected ? palette.accent : palette.page)
            .clipShape(RoundedRectangle(cornerRadius: ArunaRadius.button))
            .overlay(
                RoundedRectangle(cornerRadius: ArunaRadius.button)
                    .strokeBorder(selected ? palette.accent : palette.strongBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
    }

    // MARK: - Fields

    @ViewBuilder
    private var fields: some View {
        if majorType == "cash" {
            arunaField("Cash label", text: $categoryText)
                .textInputAutocapitalization(.words)

            HStack(spacing: 12) {
                arunaField("Amount", text: $cashAmountText)
                    .keyboardType(.decimalPad)
                SelectField(
                    options: Self.cashCurrencies.map { ($0, cashCurrencyLabel($0)) },
                    selected: cashCurrency
                ) { cashCurrency = $0 }
                .disabled(isSubmitting)
            }

            emojiPicker
        } else {
            arunaField("Symbol", text: Binding(
                get: { symbolText },
                set: { newValue in
                    symbolText = newValue
                    let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    if normalized.hasSuffix(".JK"), unit != "lot" {
                        unit = "lot"
                    }
                }
            ))
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()

            SelectField(
                options: Self.assetTypes.map { ($0, assetTypeLabel($0)) },
                selected: assetType
            ) { assetType = $0 }
            .disabled(isSubmitting)

            HStack(spacing: 12) {
                arunaField("Amount", text: $quantityText)
                    .keyboardType(.decimalPad)
                SelectField(
                    options: Self.units.map { ($0, unitLabel($0)) },
                    selected: unit
                ) { unit = $0 }
                .disabled(isSubmitting)
            }

            arunaField("Average price", text: $averagePriceText)
                .keyboardType(.decimalPad)

            HStack(spacing: 12) {
                arunaField("Currency", text: $currencyText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                arunaField("Market", text: $marketText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
        }
    }

    private var emojiPicker: some View {
        HStack(spacing: 8) {
            ForEach(Self.cashEmojis, id: \.self) { option in
                Button {
                    emoji = option
                } label: {
                    Text(option)
                        .font(.system(size: 20))
                        .frame(width: 44, height: 44)
                        .background(emoji == option ? palette.accent : palette.control)
                        .clipShape(RoundedRectangle(cornerRadius: ArunaRadius.emojiTile))
                        .overlay(
                            RoundedRectangle(cornerRadius: ArunaRadius.emojiTile)
                                .strokeBorder(emoji == option ? palette.accent : palette.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
            }
        }
    }

    private var saveButton: some View {
        Button {
            submit()
        } label: {
            if isSubmitting {
                InlineButtonSpinner(label: "Saving...")
            } else {
                HStack(spacing: 8) {
                    Image(systemName: holding == nil ? "plus" : "checkmark")
                        .font(.system(size: 16))
                    Text(holding == nil ? "Save holding" : "Update holding")
                }
            }
        }
        .buttonStyle(ArunaPrimaryButtonStyle())
        .disabled(isSubmitting)
    }

    // MARK: - Submit (port of Flutter `_submit`)

    private func submit() {
        guard !isSubmitting else { return }
        formError = nil

        if majorType == "cash" {
            let amount = parseNumber(cashAmountText)
            if amount <= 0 || categoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                formError = "Enter a cash label and amount."
                return
            }
            let fxRates = viewModel.state?.fxRates ?? PortfolioFxRates()
            if cashCurrency == "IDR", !fxRates.hasIdr {
                formError = "IDR FX is unavailable. Pull to refresh."
                return
            }
            if cashCurrency == "SGD", !fxRates.hasSgd {
                formError = "SGD FX is unavailable. Pull to refresh."
                return
            }

            isSubmitting = true
            Task {
                do {
                    if let holding {
                        try await viewModel.updateHolding(
                            id: holding.id, symbol: holding.symbol, quantity: amount, averagePrice: 0,
                            type: "cash", category: categoryText, cashCurrency: cashCurrency,
                            nativeAmount: amount, emoji: emoji
                        )
                    } else {
                        try await viewModel.addHolding(
                            symbol: "", quantity: amount, averagePrice: 0,
                            type: "cash", category: categoryText, cashCurrency: cashCurrency,
                            nativeAmount: amount, emoji: emoji
                        )
                    }
                    dismiss()
                } catch {
                    isSubmitting = false
                    formError = String(describing: error)
                }
            }
        } else {
            let symbol = symbolText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let quantity = parseNumber(quantityText)
            let averagePrice = parseAveragePrice(averagePriceText)

            if symbol.isEmpty || quantity <= 0 || averagePrice < 0 {
                formError = "Enter a symbol, amount, and price."
                return
            }

            isSubmitting = true
            Task {
                do {
                    if let holding {
                        try await viewModel.updateHolding(
                            id: holding.id, symbol: symbol, quantity: quantity, averagePrice: averagePrice,
                            currency: currencyText, market: marketText, assetType: assetType,
                            type: "digital", unit: unit
                        )
                    } else {
                        try await viewModel.addHolding(
                            symbol: symbol, quantity: quantity, averagePrice: averagePrice,
                            currency: currencyText, market: marketText, assetType: assetType,
                            type: "digital", unit: unit
                        )
                    }
                    dismiss()
                } catch {
                    isSubmitting = false
                    formError = String(describing: error)
                }
            }
        }
    }

    // MARK: - Shared field

    private func arunaField(
        _ placeholder: String,
        text: Binding<String>
    ) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 15))
            .foregroundStyle(palette.primaryText)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(palette.control)
            .clipShape(RoundedRectangle(cornerRadius: ArunaRadius.input))
            .overlay(
                RoundedRectangle(cornerRadius: ArunaRadius.input)
                    .strokeBorder(palette.border, lineWidth: 1)
            )
            .disabled(isSubmitting)
    }

    // MARK: - Helpers (port of free functions in add_holding_sheet.dart)

    private func parseNumber(_ text: String) -> Double {
        let cleaned = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned) ?? 0
    }

    private func parseAveragePrice(_ text: String) -> Double {
        let cleaned = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned) ?? -1
    }

    private func cashCurrencyLabel(_ code: String) -> String {
        switch code {
        case "IDR": return "🇮🇩 IDR"
        case "USD": return "🇺🇸 USD"
        default: return "🇸🇬 SGD"
        }
    }

    private func assetTypeLabel(_ value: String) -> String {
        switch value {
        case "stock": return "Stock"
        case "etf": return "ETF"
        case "crypto": return "Crypto"
        case "fund": return "Fund"
        default: return "Other"
        }
    }

    private func unitLabel(_ value: String) -> String {
        value == "lot" ? "Lot" : "Share"
    }

    private static func formatInputNumber(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(value)
    }

    private static func defaultCurrency(_ symbol: String) -> String {
        symbol.hasSuffix(".JK") ? "IDR" : "USD"
    }

    private static func defaultMarket(_ symbol: String) -> String {
        if symbol.hasSuffix(".JK") { return "IDX" }
        if symbol.hasSuffix("-USD") { return "CRYPTO" }
        return "US"
    }

    private static func defaultUnit(_ symbol: String) -> String {
        symbol.hasSuffix(".JK") ? "lot" : "share"
    }

    private static func normalizeAssetType(_ value: String?, symbol: String) -> String {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let normalized, assetTypes.contains(normalized) {
            return normalized
        }
        return symbol.hasSuffix("-USD") ? "crypto" : "stock"
    }
}

// MARK: - SelectField

private struct SelectField: View {
    let options: [(value: String, label: String)]
    let selected: String
    let onSelect: (String) -> Void

    @Environment(\.arunaPalette) private var palette

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button {
                    onSelect(option.value)
                } label: {
                    Text(option.label)
                }
            }
        } label: {
            HStack {
                Text(options.first { $0.value == selected }?.label ?? selected)
                    .font(.system(size: 15))
                    .foregroundStyle(palette.primaryText)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondaryText)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(palette.control)
            .clipShape(RoundedRectangle(cornerRadius: ArunaRadius.input))
            .overlay(
                RoundedRectangle(cornerRadius: ArunaRadius.input)
                    .strokeBorder(palette.border, lineWidth: 1)
            )
        }
    }
}
