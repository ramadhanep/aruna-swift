import SwiftUI

/// Allocation distribution sheet. Port of `_PortfolioDistributionSheet`: four
/// donut sections (Asset mix, Digital allocation, Cash by currency, Holdings),
/// each filtered to a positive total. Uses the shared `DonutChart`.
struct AllocationSheet: View {
    let state: PortfolioState
    let currencyCode: String

    @Environment(\.arunaPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    private var sections: [(title: String, items: [PortfolioDistributionItem])] {
        [
            ("Asset mix", state.assetTypeDistribution),
            ("Digital allocation", state.digitalDistribution),
            ("Cash by currency", state.cashDistribution),
            ("Holdings", state.holdingsDistribution),
        ].filter { sectionTotal($0.items) > 0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Allocation")
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
            .padding(.horizontal, 16)
            .padding(.top, 12)

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        ArunaCard {
                            ChartSection(title: section.title, items: section.items, currencyCode: currencyCode)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
        }
    }

    private func sectionTotal(_ items: [PortfolioDistributionItem]) -> Double {
        items.reduce(0) { $0 + $1.valueUSD }
    }
}

private struct ChartSection: View {
    let title: String
    let items: [PortfolioDistributionItem]
    let currencyCode: String

    @Environment(\.arunaPalette) private var palette

    var body: some View {
        let slices = chartSlices(items)
        let total = slices.reduce(0.0) { $0 + $1.valueUSD }

        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .arunaText(.titleMedium)
                .foregroundStyle(palette.primaryText)

            DonutChart(slices: slices)
                .frame(maxWidth: 220, maxHeight: 220)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)

            VStack(spacing: 10) {
                ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
                    legendRow(slice, total: total, isLast: index == slices.count - 1)
                }
            }
            .padding(.top, 18)
        }
    }

    private func legendRow(_ slice: DonutSlice, total: Double, isLast: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(slice.color)
                .frame(width: 9, height: 9)
            Text(slice.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(String(format: "%.1f%%", total == 0 ? 0 : (slice.valueUSD / total) * 100))
                    .arunaText(.labelSmall)
                    .arunaNumeric()
                    .foregroundStyle(palette.secondaryText)
                Text(ArunaFormatters.money(slice.value, currency: currencyCode))
                    .arunaText(.labelSmall)
                    .arunaNumeric()
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: 112, alignment: .trailing)
        }
    }

    private func chartSlices(_ items: [PortfolioDistributionItem]) -> [DonutSlice] {
        let paletteColors = DonutChart.palette(for: palette)
        var result: [DonutSlice] = []
        for (index, item) in items.enumerated() where item.valueUSD > 0 {
            result.append(
                DonutSlice(
                    label: item.label,
                    value: item.value,
                    valueUSD: item.valueUSD,
                    color: paletteColors[index % paletteColors.count]
                )
            )
        }
        return result
    }
}
