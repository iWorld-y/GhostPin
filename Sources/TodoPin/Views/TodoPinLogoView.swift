import SwiftUI

struct TodoPinLogoMark: View {
    var size: CGFloat = 34
    var isMuted = false

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.80, green: 0.96, blue: 0.42).opacity(isMuted ? 0.72 : 1),
                                Color(red: 0.15, green: 0.72, blue: 0.33).opacity(isMuted ? 0.76 : 1),
                                Color(red: 0.02, green: 0.45, blue: 0.38).opacity(isMuted ? 0.72 : 1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
                    .stroke(.white.opacity(isMuted ? 0.28 : 0.46), lineWidth: max(1, side * 0.035))

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(isMuted ? 0.12 : 0.20),
                                Color.white.opacity(0)
                            ],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: side * 0.7
                        )
                    )
                    .offset(x: -side * 0.18, y: -side * 0.20)

                Image(systemName: "mappin.circle.fill")
                    .symbolRenderingMode(.palette)
                    .font(.system(size: side * 0.58, weight: .semibold))
                    .foregroundStyle(
                        .white.opacity(isMuted ? 0.72 : 0.96),
                        Color(red: 0.03, green: 0.52, blue: 0.22).opacity(isMuted ? 0.52 : 0.82)
                    )
                    .shadow(color: .black.opacity(isMuted ? 0.08 : 0.15), radius: side * 0.08, y: side * 0.05)
                    .offset(y: side * 0.02)

                Image(systemName: "checkmark")
                    .font(.system(size: side * 0.25, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.04, green: 0.46, blue: 0.18).opacity(isMuted ? 0.74 : 0.95))
                    .offset(x: side * 0.01, y: -side * 0.07)

                TodoPinWaveArc(startAngle: .degrees(128), endAngle: .degrees(232))
                    .stroke(Color(red: 0.87, green: 1.0, blue: 0.55).opacity(isMuted ? 0.42 : 0.78), lineWidth: max(1, side * 0.045))
                    .frame(width: side * 0.20, height: side * 0.34)
                    .offset(x: -side * 0.29, y: side * 0.14)

                TodoPinWaveArc(startAngle: .degrees(-52), endAngle: .degrees(52))
                    .stroke(Color(red: 0.87, green: 1.0, blue: 0.55).opacity(isMuted ? 0.42 : 0.78), lineWidth: max(1, side * 0.045))
                    .frame(width: side * 0.20, height: side * 0.34)
                    .offset(x: side * 0.29, y: side * 0.14)
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct TodoPinWaveArc: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}
