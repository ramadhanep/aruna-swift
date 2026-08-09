import SwiftUI

/// Port of `sign_in_screen.dart`. Google sign-in via the auth service seam, or
/// enter local/guest mode. Never touches Supabase directly.
struct SignInView: View {
    @Environment(\.arunaPalette) private var palette
    @Environment(AppEnvironment.self) private var environment

    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading) {
            Text("Aruna")
                .arunaText(.brand)
                .foregroundStyle(palette.primaryText)
            Text("A lightweight market cockpit for watchlists, detail checks, and portfolio tracking.")
                .arunaText(.bodyMedium)
                .foregroundStyle(palette.secondaryText)
                .padding(.top, ArunaSpacing.s8)

            Spacer()

            ArunaCard {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Sign in")
                        .arunaText(.titleLarge)
                        .foregroundStyle(palette.primaryText)
                    Text(description)
                        .arunaText(.bodyMedium)
                        .foregroundStyle(palette.secondaryText)
                        .padding(.top, 6)

                    Button {
                        Task { await signIn() }
                    } label: {
                        googleButtonLabel
                    }
                    .buttonStyle(ArunaPrimaryButtonStyle())
                    .disabled(!environment.isSupabaseConfigured || isSubmitting)
                    .padding(.top, ArunaSpacing.s20)

                    Button {
                        environment.continueAsGuest()
                    } label: {
                        Label("Use local mode", systemImage: "smartphone")
                            .arunaText(.button)
                    }
                    .buttonStyle(ArunaOutlinedButtonStyle())
                    .padding(.top, ArunaSpacing.s12)
                }
            }
        }
        .padding(.horizontal, ArunaSpacing.s20)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.page)
    }

    @ViewBuilder
    private var googleButtonLabel: some View {
        if isSubmitting {
            InlineButtonSpinner(label: "Continue with Google")
        } else {
            Label("Continue with Google", systemImage: "arrow.right.circle")
        }
    }

    private var description: String {
        environment.isSupabaseConfigured
            ? "Use Google to sync your watchlist and portfolio through Supabase."
            : "Supabase public keys are not configured. You can still use local mode on this device."
    }

    private func signIn() async {
        isSubmitting = true
        defer { isSubmitting = false }
        try? await environment.signInWithGoogle()
    }
}
