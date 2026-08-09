import SwiftUI

/// One donut segment.
struct DonutSlice: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let valueUSD: Double
    let color: Color
}

/// Donut chart. Base ring = control, rounded caps, stroke
/// `max(16, radius * 0.28)`. Port of `_DonutChart`.
struct DonutChart: View {
    let slices: [DonutSlice]

    @Environment(\.arunaPalette) private var palette

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            let strokeWidth = max(CGFloat(16), radius * 0.28)
            let ringRadius = radius - strokeWidth / 2

            var base = Path()
            base.addArc(
                center: center,
                radius: ringRadius,
                startAngle: .degrees(0),
                endAngle: .degrees(360),
                clockwise: false
            )
            context.stroke(
                base,
                with: .color(palette.control),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
            )

            let total = slices.reduce(0.0) { $0 + $1.valueUSD }
            guard total > 0 else { return }

            var startAngle = -Double.pi / 2
            for slice in slices {
                let sweep = slice.valueUSD / total * Double.pi * 2
                var arc = Path()
                arc.addArc(
                    center: center,
                    radius: ringRadius,
                    startAngle: Angle(radians: startAngle),
                    endAngle: Angle(radians: startAngle + sweep),
                    clockwise: false
                )
                context.stroke(
                    arc,
                    with: .color(slice.color),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .butt)
                )
                startAngle += sweep
            }
        }
    }

    /// Slice color palette, cycled by index.
    static func palette(for palette: ArunaPalette) -> [Color] {
        [
            palette.accent,
            palette.successText,
            palette.warningText,
            Color(hex: 0x60A5FA),
            Color(hex: 0xF472B6),
            Color(hex: 0xA78BFA),
            Color(hex: 0x2DD4BF),
            Color(hex: 0xF97316),
        ]
    }
}
