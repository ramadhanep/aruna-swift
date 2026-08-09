import SwiftUI

// MARK: - Colors

struct ArunaPalette: Sendable {
    let page: Color
    let surface: Color
    let elevated: Color
    let control: Color
    let primaryText: Color
    let secondaryText: Color
    let mutedText: Color
    let icon: Color
    let border: Color
    let strongBorder: Color
    let accent: Color
    let success: Color
    let successText: Color
    let error: Color
    let errorText: Color
    let warning: Color
    let warningText: Color

    static let dark = ArunaPalette(
        page: Color(hex: 0x09090B),
        surface: Color(hex: 0x111113),
        elevated: Color(hex: 0x1C1C1F),
        control: Color(hex: 0x27272A),
        primaryText: Color(hex: 0xFAFAFA),
        secondaryText: Color(hex: 0xA1A1AA),
        mutedText: Color(hex: 0x52525B),
        icon: Color(hex: 0x71717A),
        border: Color(hex: 0xFFFFFF, alpha: 0.06),
        strongBorder: Color(hex: 0xFFFFFF, alpha: 0.10),
        accent: Color(hex: 0xFFFFFF),
        success: Color(hex: 0x16A34A),
        successText: Color(hex: 0x4ADE80),
        error: Color(hex: 0xDC2626),
        errorText: Color(hex: 0xF87171),
        warning: Color(hex: 0xD97706),
        warningText: Color(hex: 0xFCD34D)
    )

    static let light = ArunaPalette(
        page: Color(hex: 0xFAFAFA),
        surface: Color(hex: 0xFFFFFF),
        elevated: Color(hex: 0xFFFFFF),
        control: Color(hex: 0xF4F4F5),
        primaryText: Color(hex: 0x111113),
        secondaryText: Color(hex: 0x52525B),
        mutedText: Color(hex: 0xA1A1AA),
        icon: Color(hex: 0x71717A),
        border: Color(hex: 0x000000, alpha: 0.08),
        strongBorder: Color(hex: 0x000000, alpha: 0.14),
        accent: Color(hex: 0x111113),
        success: Color(hex: 0x16A34A),
        successText: Color(hex: 0x15803D),
        error: Color(hex: 0xDC2626),
        errorText: Color(hex: 0xDC2626),
        warning: Color(hex: 0xD97706),
        warningText: Color(hex: 0xB45309)
    )
}

private struct ArunaPaletteKey: EnvironmentKey {
    static let defaultValue: ArunaPalette = .dark
}

extension EnvironmentValues {
    var arunaPalette: ArunaPalette {
        get { self[ArunaPaletteKey.self] }
        set { self[ArunaPaletteKey.self] = newValue }
    }
}

// MARK: - Theme mode

enum ArunaThemeMode: String, Sendable {
    case dark
    case light
    case system

    /// Display label (Flutter `themeModeLabel`).
    var label: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .system: return "System"
        }
    }

    func palette(for systemScheme: ColorScheme) -> ArunaPalette {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return systemScheme == .light ? .light : .dark
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}

// MARK: - Typography

struct ArunaTextStyle: Sendable {
    let size: CGFloat
    let weight: Font.Weight
    let tracking: CGFloat
    /// Flutter `TextStyle.height` line-height multiplier. SwiftUI has no direct
    /// equivalent; kept as a token for future line-spacing tuning.
    let height: CGFloat

    var font: Font { .system(size: size, weight: weight) }
}

extension ArunaTextStyle {
    static let displayLarge = ArunaTextStyle(size: 32, weight: .bold, tracking: -0.64, height: 1.1)
    static let headlineLarge = ArunaTextStyle(size: 24, weight: .bold, tracking: -0.24, height: 1.2)
    static let titleLarge = ArunaTextStyle(size: 20, weight: .semibold, tracking: 0, height: 1.3)
    static let titleMedium = ArunaTextStyle(size: 17, weight: .medium, tracking: 0, height: 1.4)
    static let bodyLarge = ArunaTextStyle(size: 15, weight: .regular, tracking: 0, height: 1.6)
    static let bodyMedium = ArunaTextStyle(size: 13, weight: .regular, tracking: 0, height: 1.5)
    static let labelSmall = ArunaTextStyle(size: 11, weight: .medium, tracking: 0, height: 1.4)

    // Concrete styles from MIGRATION.md.
    static let appBarTitle = ArunaTextStyle(size: 17, weight: .semibold, tracking: 0, height: 1.4)
    static let bigPrice = ArunaTextStyle(size: 32, weight: .bold, tracking: 0, height: 1.1)
    static let netWorth = ArunaTextStyle(size: 31, weight: .bold, tracking: -0.6, height: 1.1)
    static let listPrice = ArunaTextStyle(size: 13.5, weight: .semibold, tracking: 0, height: 1.3)
    static let plAmount = ArunaTextStyle(size: 12, weight: .semibold, tracking: 0, height: 1.3)
    static let plPercent = ArunaTextStyle(size: 11.5, weight: .semibold, tracking: 0, height: 1.3)
    static let latestPrice = ArunaTextStyle(size: 11.5, weight: .medium, tracking: 0, height: 1.3)
    static let priceChange = ArunaTextStyle(size: 13, weight: .semibold, tracking: 0, height: 1.3)
    static let priceChangeCompact = ArunaTextStyle(size: 12, weight: .semibold, tracking: 0, height: 1.3)
    static let tabLabel = ArunaTextStyle(size: 11, weight: .medium, tracking: 0, height: 1.2)
    static let button = ArunaTextStyle(size: 15, weight: .semibold, tracking: 0, height: 1.3)
    static let brand = ArunaTextStyle(size: 32, weight: .bold, tracking: 0, height: 1.1)
    static let tickerFallback = ArunaTextStyle(size: 11, weight: .bold, tracking: 0, height: 1.2)
}

extension View {
    func arunaText(_ style: ArunaTextStyle) -> some View {
        font(style.font).tracking(style.tracking)
    }

    func arunaNumeric() -> some View {
        monospacedDigit()
    }
}

// MARK: - Spacing

enum ArunaSpacing {
    static let s4: CGFloat = 4
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s20: CGFloat = 20
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32
    static let s40: CGFloat = 40

    static let screenHorizontal: CGFloat = 20
    static let card: CGFloat = 16
    static let summaryHorizontal: CGFloat = 18
    static let summaryVertical: CGFloat = 16
    static let warning: CGFloat = 14
    static let sheetHorizontal: CGFloat = 20
    static let listBottom: CGFloat = 120
    static let rowEdgeInsets = EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 16)
    static let toolbarHeight: CGFloat = 52
    static let tabBarHeight: CGFloat = 62
    static let tabBarHorizontal: CGFloat = 16
    static let tabBarBottom: CGFloat = 10
}

// MARK: - Radius

enum ArunaRadius {
    static let card: CGFloat = 12
    static let identity: CGFloat = 14
    static let warning: CGFloat = 10
    static let button: CGFloat = 10
    static let input: CGFloat = 10
    static let sheetTop: CGFloat = 16
    static let tabBar: CGFloat = 22
    static let listGroup: CGFloat = 12
    static let badge: CGFloat = 9
    static let emojiTile: CGFloat = 10
}

// MARK: - Color(hex)

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
