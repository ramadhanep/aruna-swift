import SwiftUI

/// Full-screen loading spinner + label. Port of `LoadingState`.
struct LoadingState: View {
    var label: String = "Loading"

    @Environment(\.arunaPalette) private var palette

    var body: some View {
        VStack(spacing: ArunaSpacing.s12) {
            ProgressView()
                .frame(width: 22, height: 22)
                .tint(palette.secondaryText)
            Text(label)
                .arunaText(.bodyMedium)
                .foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Centered empty-state message + icon. Port of `EmptyState`.
struct EmptyState: View {
    let title: String
    let message: String
    var icon: String = "magnifyingglass"

    @Environment(\.arunaPalette) private var palette

    var body: some View {
        VStack(spacing: ArunaSpacing.s12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(palette.icon)
            Text(title)
                .arunaText(.titleMedium)
                .foregroundStyle(palette.primaryText)
            Text(message)
                .arunaText(.bodyMedium)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.secondaryText)
        }
        .padding(ArunaSpacing.s24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Blocking error message with optional retry. Port of `ErrorState`.
struct ErrorState: View {
    let message: String
    var onRetry: (() -> Void)? = nil

    @Environment(\.arunaPalette) private var palette

    var body: some View {
        VStack(spacing: ArunaSpacing.s12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 24))
                .foregroundStyle(palette.errorText)
            Text(message)
                .arunaText(.bodyMedium)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.secondaryText)
            if let onRetry {
                Button("Retry", action: onRetry)
                    .buttonStyle(ArunaOutlinedButtonStyle())
                    .padding(.top, ArunaSpacing.s4)
            }
        }
        .padding(ArunaSpacing.s24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
