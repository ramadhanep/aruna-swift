import SwiftUI

/// Standard screen scaffold: 52pt header with title + optional action, 1pt
/// bottom divider, page background. Port of `ArunaScaffold`.
struct ArunaScaffold<Content: View, Action: View, Bottom: View>: View {
    let title: String
    let content: Content
    let action: Action
    let bottom: Bottom

    @Environment(\.arunaPalette) private var palette

    init(
        title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder action: () -> Action = { EmptyView() },
        @ViewBuilder bottom: () -> Bottom = { EmptyView() }
    ) {
        self.title = title
        self.content = content()
        self.action = action()
        self.bottom = bottom()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(palette.border)
                .frame(height: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottom
        }
        .background(palette.page)
    }

    private var header: some View {
        HStack {
            Text(title)
                .arunaText(.appBarTitle)
                .foregroundStyle(palette.primaryText)
            Spacer()
            action
        }
        .padding(.horizontal, ArunaSpacing.s20)
        .frame(height: ArunaSpacing.toolbarHeight)
    }
}
