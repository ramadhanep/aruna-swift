import SwiftUI

/// Standard surface card. Radius 12, 1pt border, 16pt padding, no shadow.
/// Port of `ArunaCard`.
struct ArunaCard<Content: View>: View {
    let content: Content
    let padding: EdgeInsets
    let radius: CGFloat
    let background: Color?

    @Environment(\.arunaPalette) private var palette

    init(
        padding: EdgeInsets = EdgeInsets(top: ArunaSpacing.card, leading: ArunaSpacing.card, bottom: ArunaSpacing.card, trailing: ArunaSpacing.card),
        radius: CGFloat = ArunaRadius.card,
        background: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.padding = padding
        self.radius = radius
        self.background = background
    }

    var body: some View {
        content
            .padding(padding)
            .background(background ?? palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(palette.border, lineWidth: 1)
            )
    }
}
