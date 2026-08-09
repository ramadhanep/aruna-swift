import SwiftUI

/// Logo/initials avatar for a ticker. 40pt default, 48pt override. Port of
/// `TickerAvatar`.
///
/// ponytail: iOS SwiftUI cannot rasterize SVG (Flutter used `flutter_svg`).
/// `.svg` logo URLs fall through to the initials fallback. Add an SVG renderer
/// (e.g. SVGKit / SDWebImageSVGCoder) in a later phase if the API serves `.svg`
/// logos.
struct TickerAvatar: View {
    let symbol: String
    let logoURL: String?
    var size: CGFloat = 40

    @Environment(\.arunaPalette) private var palette

    var body: some View {
        ZStack {
            Circle()
                .fill(palette.control)
            content
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    @ViewBuilder
    private var content: some View {
        if let logoURL, !logoURL.isEmpty, let url = URL(string: logoURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure, .empty:
                    initialsView
                @unknown default:
                    initialsView
                }
            }
        } else {
            initialsView
        }
    }

    private var initialsView: some View {
        Text(initials)
            .arunaText(.tickerFallback)
            .arunaNumeric()
            .foregroundStyle(palette.primaryText)
    }

    private var initials: String {
        let normalized = symbol
            .replacingOccurrences(of: ".JK", with: "")
            .replacingOccurrences(of: "-USD", with: "")
            .uppercased()
        return normalized.count <= 4 ? normalized : String(normalized.prefix(4))
    }
}
