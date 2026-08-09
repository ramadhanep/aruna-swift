import SwiftUI

/// Grouped list container. `inset: true` gives a rounded bordered box (radius
/// 12); `inset: false` gives edge-to-edge top/bottom hairlines. Port of
/// `ArunaListGroup`.
struct ArunaListGroup<Content: View>: View {
    let content: Content
    let inset: Bool
    let margin: EdgeInsets

    @Environment(\.arunaPalette) private var palette

    init(
        inset: Bool = false,
        margin: EdgeInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.inset = inset
        self.margin = margin
    }

    var body: some View {
        content
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: inset ? ArunaRadius.listGroup : 0))
            .overlay {
                if inset {
                    RoundedRectangle(cornerRadius: ArunaRadius.listGroup)
                        .strokeBorder(palette.border, lineWidth: 1)
                }
            }
            .overlay(alignment: .top) {
                if !inset { hairline }
            }
            .overlay(alignment: .bottom) {
                if !inset { hairline }
            }
            .padding(margin)
    }

    private var hairline: some View {
        Rectangle().fill(palette.border).frame(height: 1)
    }
}

/// List divider with leading indent. Port of `ArunaListDivider`.
struct ArunaListDivider: View {
    var indent: CGFloat = 20

    @Environment(\.arunaPalette) private var palette

    var body: some View {
        Rectangle()
            .fill(palette.border)
            .frame(height: 1)
            .padding(.leading, indent)
    }
}
