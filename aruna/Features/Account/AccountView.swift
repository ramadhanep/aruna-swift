import SwiftUI

/// Port of `account_screen.dart`. Identity, preferences (appearance + privacy
/// mode), connection info, and sign out / sign in.
struct AccountView: View {
    @Environment(\.arunaPalette) private var palette
    @Environment(AppEnvironment.self) private var environment

    @State private var isSigningOut = false
    @State private var authError: String?
    @State private var showsAppearance = false

    private var user: AuthUser? { environment.currentUser }

    var body: some View {
        ArunaScaffold(title: "Account") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    identityCard
                        .padding(.horizontal, ArunaSpacing.s20)
                        .padding(.top, ArunaSpacing.s12)

                    SettingsLabel(title: "Preferences")
                        .padding(.top, ArunaSpacing.s20)

                    ArunaListGroup(
                        inset: true,
                        margin: EdgeInsets(top: 0, leading: ArunaSpacing.s20, bottom: 0, trailing: ArunaSpacing.s20)
                    ) {
                        VStack(spacing: 0) {
                            SettingRow(
                                label: "Appearance",
                                value: environment.themeMode.label,
                                icon: "paintbrush",
                                onTap: { showsAppearance = true }
                            )
                            ArunaListDivider(indent: 56)
                            SettingRow(
                                label: "Privacy mode",
                                value: environment.privacyCensorEnabled ? "On" : "Off",
                                icon: environment.privacyCensorEnabled ? "eye.slash" : "eye",
                                onTap: { environment.togglePrivacyCensor() }
                            )
                        }
                    }

                    SettingsLabel(title: "Connection")
                        .padding(.top, ArunaSpacing.s20)

                    ArunaListGroup(
                        inset: true,
                        margin: EdgeInsets(top: 0, leading: ArunaSpacing.s20, bottom: 0, trailing: ArunaSpacing.s20)
                    ) {
                        VStack(spacing: 0) {
                            SettingRow(label: "API base", value: AppConfig.apiBaseURL, icon: "cloud")
                            ArunaListDivider(indent: 56)
                            SettingRow(label: "Sync", value: syncStatus, icon: "arrow.triangle.2.circlepath")
                            ArunaListDivider(indent: 56)
                            SettingRow(label: "Auth redirect", value: AppConfig.oauthRedirectURL, icon: "link")
                        }
                    }

                    if let authError {
                        Text(authError)
                            .font(.system(size: 13))
                            .foregroundStyle(palette.errorText)
                            .padding(.horizontal, ArunaSpacing.s20)
                            .padding(.top, ArunaSpacing.s16)
                    }

                    bottomAction
                        .padding(.horizontal, ArunaSpacing.s20)
                        .padding(.top, ArunaSpacing.s16)
                }
                .padding(.bottom, 120)
            }
        }
        .sheet(isPresented: $showsAppearance) {
            AppearanceSheetView()
                .presentationDetents([.medium])
                .presentationBackground(palette.elevated)
        }
    }

    // MARK: - Identity

    private var identityCard: some View {
        ArunaCard(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16), radius: ArunaRadius.identity) {
            HStack(spacing: ArunaSpacing.s12) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(palette.control)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "person")
                            .font(.system(size: 20))
                            .foregroundStyle(palette.primaryText)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(identityName)
                        .arunaText(.titleMedium)
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                    Text(identitySubtitle)
                        .arunaText(.bodyMedium)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                StatusBadge(label: statusBadge)
            }
        }
    }

    private var identityName: String {
        user?.name ?? user?.email ?? "Local mode"
    }

    private var identitySubtitle: String {
        user?.email ?? (environment.isSupabaseConfigured ? "Guest session" : "Local mode")
    }

    private var statusBadge: String {
        environment.isSignedIn ? "Synced" : environment.isSupabaseConfigured ? "Guest" : "Local"
    }

    private var syncStatus: String {
        environment.isSignedIn
            ? "Supabase enabled"
            : environment.isSupabaseConfigured
            ? "Local until sign-in"
            : "Local only"
    }

    // MARK: - Actions

    @ViewBuilder
    private var bottomAction: some View {
        if environment.isSignedIn {
            Button {
                Task { await signOut() }
            } label: {
                if isSigningOut {
                    InlineButtonSpinner(label: "Signing out...")
                } else {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            .buttonStyle(ArunaOutlinedButtonStyle())
            .disabled(isSigningOut)
        } else {
            Button {
                Task { try? await environment.signInWithGoogle() }
            } label: {
                Label("Sign in with Google", systemImage: "arrow.right.circle")
            }
            .buttonStyle(ArunaPrimaryButtonStyle())
            .disabled(!environment.isSupabaseConfigured)
        }
    }

    private func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        authError = nil
        defer { isSigningOut = false }
        do {
            try await environment.signOut()
        } catch {
            authError = String(describing: error)
        }
    }
}

/// Port of `_StatusBadge`.
struct StatusBadge: View {
    let label: String

    @Environment(\.arunaPalette) private var palette

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(palette.control)
            .clipShape(RoundedRectangle(cornerRadius: ArunaRadius.badge))
            .overlay(
                RoundedRectangle(cornerRadius: ArunaRadius.badge)
                    .strokeBorder(palette.border, lineWidth: 1)
            )
    }
}

/// Port of `_SettingsLabel`.
struct SettingsLabel: View {
    let title: String

    @Environment(\.arunaPalette) private var palette

    var body: some View {
        Text(title)
            .arunaText(.bodyMedium)
            .fontWeight(.semibold)
            .foregroundStyle(palette.secondaryText)
            .padding(.horizontal, ArunaSpacing.s20)
            .padding(.bottom, ArunaSpacing.s8)
    }
}

/// Port of `_SettingRow`.
struct SettingRow: View {
    let label: String
    let value: String
    let icon: String
    var onTap: (() -> Void)? = nil

    @Environment(\.arunaPalette) private var palette

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) {
                    rowContent
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label), \(value)")
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: ArunaSpacing.s12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(palette.icon)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .arunaText(.bodyMedium)
                    .foregroundStyle(palette.primaryText)
                Text(value)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(2)
            }
            Spacer()
            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16))
                    .foregroundStyle(palette.mutedText)
            }
        }
        .padding(EdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 14))
        .contentShape(Rectangle())
    }
}

/// Appearance picker (System / Light / Dark). Port of `_showAppearanceSheet`.
struct AppearanceSheetView: View {
    @Environment(\.arunaPalette) private var palette
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    private let options: [(mode: ArunaThemeMode, icon: String)] = [
        (.system, "monitor"),
        (.light, "sun.max"),
        (.dark, "moon"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Appearance")
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
                }
                .buttonStyle(.plain)
            }
            .padding(EdgeInsets(top: 16, leading: 20, bottom: 8, trailing: 20))

            ArunaListGroup(inset: true, margin: EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)) {
                VStack(spacing: 0) {
                    ForEach(options.indices, id: \.self) { index in
                        let option = options[index]
                        let selected = option.mode == environment.themeMode
                        Button {
                            environment.themeMode = option.mode
                            dismiss()
                        } label: {
                            HStack(spacing: ArunaSpacing.s12) {
                                Image(systemName: option.icon)
                                    .font(.system(size: 20))
                                    .foregroundStyle(palette.icon)
                                    .frame(width: 24)
                                Text(option.mode.label)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(palette.primaryText)
                                Spacer()
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 18))
                                        .foregroundStyle(palette.primaryText)
                                }
                            }
                            .padding(EdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 14))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.mode.label)
                        if index < options.count - 1 {
                            ArunaListDivider(indent: 56)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 20)
    }
}
