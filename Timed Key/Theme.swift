import SwiftUI

enum Theme {
    static let window = Color(red: 8 / 255, green: 10 / 255, blue: 11 / 255)
    static let surface = Color.white.opacity(0.055)
    static let surfaceRaised = Color.white.opacity(0.085)
    static let surfaceHover = Color.white.opacity(0.11)
    static let border = Color.white.opacity(0.11)
    static let borderStrong = Color.white.opacity(0.18)

    static let textPrimary = Color(red: 245 / 255, green: 247 / 255, blue: 244 / 255)
    static let textSecondary = Color(red: 245 / 255, green: 247 / 255, blue: 244 / 255).opacity(0.64)
    static let textMuted = Color(red: 245 / 255, green: 247 / 255, blue: 244 / 255).opacity(0.40)

    static let accent = Color(red: 204 / 255, green: 1, blue: 0)
    static let accentPressed = Color(red: 183 / 255, green: 230 / 255, blue: 0)
    static let accentInk = Color(red: 17 / 255, green: 20 / 255, blue: 0)
    static let success = Color(red: 120 / 255, green: 224 / 255, blue: 143 / 255)
    static let warning = Color(red: 1, green: 209 / 255, blue: 102 / 255)
    static let danger = Color(red: 1, green: 107 / 255, blue: 107 / 255)
    static let info = Color(red: 120 / 255, green: 169 / 255, blue: 1)
}

struct GlassCardModifier: ViewModifier {
    var radius: CGFloat = 20
    var raised = false

    func body(content: Content) -> some View {
        content
            .background(raised ? Theme.surfaceRaised : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(raised ? Theme.borderStrong : Theme.border, lineWidth: 1)
            }
            .shadow(
                color: .black.opacity(raised ? 0.30 : 0.18),
                radius: raised ? 18 : 10,
                x: 0,
                y: raised ? 9 : 5
            )
    }
}

extension View {
    func glassCard(radius: CGFloat = 20, raised: Bool = false) -> some View {
        modifier(GlassCardModifier(radius: radius, raised: raised))
    }
}
