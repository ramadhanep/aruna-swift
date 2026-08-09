import SwiftUI

/// Inline spinner + label for button loading states. Port of
/// `InlineButtonSpinner`.
struct InlineButtonSpinner: View {
    let label: String

    var body: some View {
        HStack(spacing: ArunaSpacing.s8) {
            ProgressView()
                .frame(width: 16, height: 16)
            Text(label)
        }
    }
}

// MARK: - Button styles

/// Primary: white background (accent), 48pt tall, 10pt radius. Port of the
/// Flutter `ElevatedButton` theme.
struct ArunaPrimaryButtonStyle: ButtonStyle {
    @Environment(\.arunaPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .arunaText(.button)
            .foregroundStyle(palette.page)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(isEnabled ? palette.accent : palette.control)
            .clipShape(RoundedRectangle(cornerRadius: ArunaRadius.button))
            .opacity(isEnabled ? 1 : 0.6)
    }
}

/// Outlined: transparent background, strong border, 48pt tall, 10pt radius.
/// Port of the Flutter `OutlinedButton` theme.
struct ArunaOutlinedButtonStyle: ButtonStyle {
    @Environment(\.arunaPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .arunaText(.button)
            .foregroundStyle(palette.primaryText)
            .frame(maxWidth: .infinity, minHeight: 48)
            .overlay(
                RoundedRectangle(cornerRadius: ArunaRadius.button)
                    .strokeBorder(palette.strongBorder, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.4)
    }
}
