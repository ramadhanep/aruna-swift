import SwiftUI

/// Percent-change label. Positive → successText, negative → errorText,
/// zero/missing → secondaryText. Port of `PriceChangeText`.
struct PriceChangeText: View {
    let value: Double?
    var compact: Bool = false

    @Environment(\.arunaPalette) private var palette

    var body: some View {
        let change = value ?? 0
        let color = change > 0
            ? palette.successText
            : change < 0
            ? palette.errorText
            : palette.secondaryText

        Text(ArunaFormatters.percent(value))
            .arunaText(compact ? .priceChangeCompact : .priceChange)
            .arunaNumeric()
            .foregroundStyle(color)
            .lineLimit(1)
    }
}
