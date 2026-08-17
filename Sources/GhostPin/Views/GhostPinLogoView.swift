import SwiftUI

struct GhostPinLogoMark: View {
    var size: CGFloat = 34
    var isMuted = false

    var body: some View {
        Group {
            if let logo = GhostPinAssets.logo {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .opacity(isMuted ? 0.58 : 1)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .accessibilityHidden(true)
    }
}
