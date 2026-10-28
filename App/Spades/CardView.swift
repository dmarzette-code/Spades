import SwiftUI
import SpadesEngine

struct CardView: View {
    let card: Card
    var width: CGFloat = 64

    private var height: CGFloat { width * 1.42 }
    private var color: Color { Theme.suitColor(card) }
    private var corner: CGFloat { width * 0.11 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [Theme.ivory, Theme.ivoryShade], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.75)

            if card.rank.isJoker {
                jokerFace
            } else {
                cornerIndex
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(width * 0.07)
                cornerIndex
                    .rotationEffect(.degrees(180))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(width * 0.07)
                center
            }
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.35), radius: width * 0.06, y: width * 0.03)
        .accessibilityElement()
        .accessibilityLabel(accessibilityName)
    }

    private var cornerIndex: some View {
        VStack(spacing: -width * 0.03) {
            Text(card.rank.label)
                .font(Theme.display(width * 0.28, weight: .bold))
            Text(card.suit.symbol)
                .font(.system(size: width * 0.22))
        }
        .foregroundStyle(color)
        .fixedSize()
    }

    @ViewBuilder
    private var center: some View {
        switch card.rank {
        case .jack, .queen, .king:
            ZStack {
                RoundedRectangle(cornerRadius: width * 0.06)
                    .strokeBorder(color.opacity(0.35), lineWidth: 1)
                    .background(RoundedRectangle(cornerRadius: width * 0.06).fill(color.opacity(0.06)))
                VStack(spacing: 0) {
                    Text(card.rank.label)
                        .font(Theme.display(width * 0.42, weight: .heavy))
                    Text(card.suit.symbol)
                        .font(.system(size: width * 0.2))
                }
                .foregroundStyle(color)
            }
            .frame(width: width * 0.5, height: height * 0.52)
        case .ace:
            Text(card.suit.symbol)
                .font(.system(size: width * (card.suit == .spades ? 0.62 : 0.5)))
                .foregroundStyle(color)
        default:
            Text(card.suit.symbol)
                .font(.system(size: width * 0.38))
                .foregroundStyle(color.opacity(0.9))
        }
    }

    private var jokerFace: some View {
        VStack(spacing: width * 0.03) {
            Text("★")
                .font(.system(size: width * 0.42))
            Text(card.rank == .bigJoker ? "BIG" : "LITTLE")
                .font(Theme.label(width * 0.13, weight: .heavy))
                .tracking(1)
            Text("JOKER")
                .font(Theme.display(width * 0.17, weight: .heavy))
                .tracking(1.5)
        }
        .foregroundStyle(color)
        .padding(width * 0.08)
        .overlay(
            RoundedRectangle(cornerRadius: width * 0.06)
                .strokeBorder(color.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        )
    }

    private var accessibilityName: String {
        switch card.rank {
        case .bigJoker: "Big Joker"
        case .littleJoker: "Little Joker"
        default: "\(card.rank.label) of \(card.suit.name)"
        }
    }
}

struct CardBackView: View {
    var width: CGFloat = 64

    var body: some View {
        let height = width * 1.42
        let corner = width * 0.11
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.14, green: 0.20, blue: 0.36), Color(red: 0.06, green: 0.08, blue: 0.17)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Canvas { ctx, size in
                let step = max(5, size.width / 8)
                var path = Path()
                var x = -size.height
                while x < size.width + size.height {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    path.move(to: CGPoint(x: x + size.height, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
                ctx.stroke(path, with: .color(Theme.brass.opacity(0.18)), lineWidth: 0.6)
            }
            .clipShape(RoundedRectangle(cornerRadius: corner * 0.7, style: .continuous))
            .padding(width * 0.07)
            RoundedRectangle(cornerRadius: corner * 0.7, style: .continuous)
                .strokeBorder(Theme.brass.opacity(0.65), lineWidth: max(0.75, width * 0.02))
                .padding(width * 0.07)
            Text("♠")
                .font(.system(size: width * 0.36))
                .foregroundStyle(Theme.brass)
                .shadow(color: Theme.brass.opacity(0.5), radius: 4)
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.35), radius: width * 0.05, y: width * 0.03)
    }
}

#Preview {
    HStack {
        CardView(card: Card(.ace, .spades))
        CardView(card: Card(.queen, .hearts))
        CardView(card: Card(.seven, .diamonds))
        CardView(card: .bigJoker)
        CardBackView()
    }
    .padding()
    .background(FeltBackground())
}
