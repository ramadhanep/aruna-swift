import SwiftUI

/// Lightweight line chart, 180pt tall. Port of `SparklineChart`.
///
/// - 3 horizontal grid lines at 5% primary-text alpha
/// - 2pt round line, green when final ≥ first, red otherwise
/// - gradient fill 18% → 0%
/// - fewer than 2 points → "No chart data"
struct SparklineChart: View {
    let points: [PricePoint]
    var fallback: [Double] = []

    @Environment(\.arunaPalette) private var palette

    var body: some View {
        let values = points.isEmpty ? fallback : points.map(\.price)

        Canvas { context, size in
            drawGrid(in: &context, size: size)

            guard values.count >= 2 else {
                context.draw(
                    Text("No chart data")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.mutedText),
                    at: CGPoint(x: size.width / 2, y: size.height / 2)
                )
                return
            }

            drawLine(values: values, in: &context, size: size)
        }
        .frame(height: 180)
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        for i in 1..<4 {
            let y = size.height * CGFloat(i) / 4
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(palette.primaryText.opacity(0.05)), lineWidth: 1)
        }
    }

    private func drawLine(values: [Double], in context: inout GraphicsContext, size: CGSize) {
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let range = maxValue - minValue == 0 ? 1 : maxValue - minValue

        var points: [CGPoint] = []
        for (index, value) in values.enumerated() {
            let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
            let y = size.height - CGFloat((value - minValue) / range) * size.height
            points.append(CGPoint(x: x, y: y))
        }

        var line = Path()
        line.addLines(points)

        var fill = line
        fill.addLine(to: CGPoint(x: size.width, y: size.height))
        fill.addLine(to: CGPoint(x: 0, y: size.height))
        fill.closeSubpath()

        let isUp = (values.last ?? 0) >= (values.first ?? 0)
        let color = isUp ? palette.successText : palette.errorText

        context.fill(
            fill,
            with: .linearGradient(
                Gradient(colors: [color.opacity(0.18), color.opacity(0)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )
        context.stroke(
            line,
            with: .color(color),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )
    }
}
