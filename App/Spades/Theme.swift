import SwiftUI
import SpadesEngine

/// "Midnight card room": ink-navy felt, brass accents, ivory cards with serif type.
enum Theme {
    static let feltCenter = Color(red: 0.10, green: 0.17, blue: 0.27)
    static let feltEdge = Color(red: 0.03, green: 0.05, blue: 0.10)
    static let brass = Color(red: 0.86, green: 0.70, blue: 0.42)
    static let brassDeep = Color(red: 0.62, green: 0.47, blue: 0.24)
    static let ivory = Color(red: 0.98, green: 0.96, blue: 0.91)
    static let ivoryShade = Color(red: 0.91, green: 0.88, blue: 0.80)
    static let ink = Color(red: 0.09, green: 0.10, blue: 0.14)
    static let crimson = Color(red: 0.74, green: 0.12, blue: 0.20)
    static let panel = Color(red: 0.06, green: 0.09, blue: 0.15).opacity(0.92)
    static let hairline = Color.white.opacity(0.10)
    static let mist = Color.white.opacity(0.62)
    static let usTint = Color(red: 0.42, green: 0.78, blue: 0.70)
    static let themTint = Color(red: 0.93, green: 0.48, blue: 0.40)

    static func tint(_ team: Team) -> Color { team == .us ? usTint : themTint }

    static func suitColor(_ card: Card) -> Color {
        if card.rank == .bigJoker { return crimson }
        if card.rank == .littleJoker { return ink }
        return card.suit.isRed ? crimson : ink
    }

    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

struct FeltBackground: View {
    var body: some View {
        ZStack {
            RadialGradient(colors: [Theme.feltCenter, Theme.feltEdge], center: .center, startRadius: 40, endRadius: 620)
            // Subtle woven texture.
            Canvas { ctx, size in
                let step: CGFloat = 6
                var path = Path()
                var x: CGFloat = -size.height
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    x += step
                }
                ctx.stroke(path, with: .color(.white.opacity(0.018)), lineWidth: 1)
            }
            // Brass rail glow at the edges.
            RoundedRectangle(cornerRadius: 48)
                .strokeBorder(
                    LinearGradient(colors: [Theme.brass.opacity(0.35), .clear, Theme.brass.opacity(0.2)],
                                   startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
                .padding(6)
                .blendMode(.screen)
        }
        .ignoresSafeArea()
    }
}

struct BrassButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label(17, weight: .bold))
            .foregroundStyle(prominent ? Theme.ink : Theme.brass)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background {
                if prominent {
                    Capsule().fill(LinearGradient(colors: [Theme.brass, Theme.brassDeep], startPoint: .top, endPoint: .bottom))
                } else {
                    Capsule().strokeBorder(Theme.brass.opacity(0.7), lineWidth: 1.5)
                }
            }
            .shadow(color: prominent ? Theme.brass.opacity(0.35) : .clear, radius: 12, y: 4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Frosted dark panel used for overlays.
struct PanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial.opacity(0.5), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.brass.opacity(0.25), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
    }
}

extension View {
    func panel() -> some View { modifier(PanelBackground()) }
}
