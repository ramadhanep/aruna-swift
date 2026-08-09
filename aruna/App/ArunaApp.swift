import SwiftUI

@main
struct ArunaApp: App {
    @State private var environment = AppEnvironment.live()

    init() {
        // UI-test isolation: wipe persisted settings so tests start from a
        // known state instead of inheriting developer defaults.
        if ProcessInfo.processInfo.arguments.contains("-uitest-reset") {
            ArunaStorage().clearSettingsForUITests()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .preferredColorScheme(environment.themeMode.preferredColorScheme)
                .onOpenURL { url in
                    environment.handleOpenURL(url)
                }
        }
    }
}

/// Auth gate. Startup loading only exists while the startup state is
/// unresolved; every terminal state renders a real destination.
struct RootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Group {
            switch environment.authState {
            case .loading:
                ArunaScaffold(title: "Aruna") {
                    LoadingState(label: environment.startupState == .resolvingSession
                        ? "Restoring session…"
                        : "Starting…")
                }
            case .signedIn, .guest:
                MainShell()
            case .signedOut:
                SignInView()
            }
        }
        .environment(\.arunaPalette, environment.palette(for: colorScheme))
        .task { await environment.start() }
    }
}
