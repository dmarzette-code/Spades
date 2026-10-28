import SwiftUI
import SpadesEngine

extension Seat {
    var direction: CGSize {
        switch self {
        case .south: CGSize(width: 0, height: 1)
        case .north: CGSize(width: 0, height: -1)
        case .west: CGSize(width: -1, height: 0)
        case .east: CGSize(width: 1, height: 0)
        }
    }

    /// A small fixed tilt so the trick pile looks hand-placed.
    var tilt: Double {
        switch self {
        case .south: -3
        case .west: 8
        case .north: 4
        case .east: -7
        }
    }
}

// MARK: - Score bar

struct ScoreBar: View {
    let controller: GameController
    let onMenu: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onMenu) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.brass)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.panel))
                    .overlay(Circle().strokeBorder(Theme.hairline))
            }
            .accessibilityLabel("Menu")
            TeamScoreView(team: .us, controller: controller)
            TeamScoreView(team: .them, controller: controller)
        }
        .padding(.horizontal, 12)
    }
}

struct TeamScoreView: View {
    let team: Team
    let controller: GameController

    private var game: SpadesGame { controller.game }
    private var score: TeamScore { game.scores[team]! }
    private var biddingDone: Bool { game.biddingComplete }
    private var won: Int { team.seats.reduce(0) { $0 + (game.tricksWon[$1] ?? 0) } }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(team == .us ? "US" : "THEM")
                    .font(Theme.label(11, weight: .heavy))
                    .tracking(1.5)
                    .foregroundStyle(Theme.tint(team))
                Text("\(score.points)")
                    .font(Theme.display(24, weight: .bold))
                    .foregroundStyle(Theme.ivory)
                    .contentTransition(.numericText())
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                if biddingDone {
                    Text("\(won) / \(game.contract(for: team))")
                        .font(Theme.label(15, weight: .bold))
                        .foregroundStyle(won >= game.contract(for: team) ? Theme.tint(team) : Theme.ivory)
                        .monospacedDigit()
                } else {
                    Text("bidding")
                        .font(Theme.label(11))
                        .foregroundStyle(Theme.mist)
                }
                if controller.rules.bagsEnabled {
                    BagMeter(bags: score.bags, limit: controller.rules.bagLimit)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.tint(team).opacity(0.3)))
        .animation(.spring, value: score)
    }
}

struct BagMeter: View {
    let bags: Int
    let limit: Int

    var body: some View {
        let shown = min(limit, 10)
        let filled = limit > 10 ? Int((Double(bags) / Double(limit) * 10).rounded(.down)) : bags
        HStack(spacing: 2) {
            ForEach(0..<shown, id: \.self) { i in
                Capsule()
                    .fill(i < filled ? (bags >= limit - 2 ? Theme.crimson : Theme.brass) : Color.white.opacity(0.12))
                    .frame(width: 4, height: 7)
            }
        }
        .accessibilityLabel("\(bags) of \(limit) bags")
    }
}

// MARK: - Player plates

struct PlayerPlate: View {
    let seat: Seat
    let controller: GameController

    private var game: SpadesGame { controller.game }
    private var isTurn: Bool {
        (game.phase == .bidding || game.phase == .playing) && game.turn == seat && controller.sweepingTo == nil
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(LinearGradient(colors: [Theme.tint(seat.team).opacity(0.85), Theme.tint(seat.team).opacity(0.35)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 46, height: 46)
                    .overlay(
                        Text(String((controller.names[seat] ?? "?").prefix(1)))
                            .font(Theme.display(22, weight: .bold))
                            .foregroundStyle(Theme.ink)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Theme.brass, lineWidth: isTurn ? 3 : 0)
                            .padding(-4)
                            .shadow(color: Theme.brass, radius: isTurn ? 8 : 0)
                    )
                if game.dealer == seat {
                    Text("D")
                        .font(Theme.label(10, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Theme.ivory))
                        .offset(x: 6, y: -4)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isTurn)

            Text(controller.names[seat] ?? seat.name)
                .font(Theme.label(13, weight: .semibold))
                .foregroundStyle(Theme.ivory)
            statusChip
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusChip: some View {
        let won = game.tricksWon[seat] ?? 0
        Group {
            if let bid = game.bids[seat] {
                if bid.isNil {
                    Text(bid == .blindNil ? "BLIND NIL" : "NIL")
                        .foregroundStyle(won == 0 ? Theme.brass : Theme.crimson)
                } else if game.biddingComplete {
                    Text("\(won) of \(bid.contractTricks)")
                        .foregroundStyle(Theme.ivory)
                } else {
                    Text("Bid \(bid.contractTricks)")
                        .foregroundStyle(Theme.ivory)
                }
            } else if game.phase == .bidding && isTurn {
                ThinkingDots()
            } else {
                Text("—").foregroundStyle(Theme.mist)
            }
        }
        .font(Theme.label(12, weight: .bold))
        .monospacedDigit()
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .contentTransition(.numericText())
        .animation(.spring, value: won)
    }
}

struct ThinkingDots: View {
    @State private var on = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Theme.brass)
                    .frame(width: 4, height: 4)
                    .opacity(on ? 1 : 0.25)
                    .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.18), value: on)
            }
        }
        .frame(height: 14)
        .onAppear { on = true }
    }
}

/// A compact fan of face-down cards showing how many an opponent holds.
struct MiniFan: View {
    let count: Int
    var vertical = false

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                CardBackView(width: 20)
                    .offset(x: vertical ? 0 : CGFloat(i) * 4 - CGFloat(count) * 2,
                            y: vertical ? CGFloat(i) * 4 - CGFloat(count) * 2 : 0)
            }
        }
        .frame(width: vertical ? 24 : 20 + CGFloat(count) * 4, height: vertical ? 28 + CGFloat(count) * 4 : 30)
        .animation(.easeOut(duration: 0.2), value: count)
    }
}

// MARK: - Trick area

struct TrickArea: View {
    let controller: GameController
    var cardWidth: CGFloat = 60

    var body: some View {
        let reach = cardWidth * 0.72
        ZStack {
            ForEach(controller.tableCards, id: \.card) { play in
                let d = play.seat.direction
                let sweep = controller.sweepingTo?.direction
                CardView(card: play.card, width: cardWidth)
                    .rotationEffect(.degrees(play.seat.tilt))
                    .offset(x: d.width * reach, y: d.height * reach)
                    .offset(x: (sweep?.width ?? 0) * 260, y: (sweep?.height ?? 0) * 320)
                    .scaleEffect(sweep == nil ? 1 : 0.45)
                    .opacity(sweep == nil ? 1 : 0)
                    .transition(.asymmetric(
                        insertion: .offset(x: d.width * 240, y: d.height * 300).combined(with: .scale(scale: 0.8)),
                        removal: .identity))
            }
        }
        .frame(width: cardWidth * 3.2, height: cardWidth * 3.4)
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: controller.tableCards)
        .animation(.easeIn(duration: 0.42), value: controller.sweepingTo)
    }
}

// MARK: - The human's hand

struct HandView: View {
    let cards: [Card]
    let revealed: Bool
    let playable: Set<Card>
    let isMyTurn: Bool
    let selected: Card?
    let highlighted: Card?
    let onTap: (Card) -> Void

    var body: some View {
        GeometryReader { geo in
            let n = cards.count
            let cardW = min(84, max(54, geo.size.width / 5.6))
            let spacing = n > 1 ? min(cardW * 0.64, (geo.size.width - 20 - cardW) / CGFloat(n - 1)) : 0
            let total = cardW + spacing * CGFloat(max(0, n - 1))
            let mid = Double(n - 1) / 2
            ForEach(Array(cards.enumerated()), id: \.element) { i, card in
                let offsetFromMid = Double(i) - mid
                let canPlay = playable.contains(card)
                let lift: CGFloat = selected == card ? 26 : (isMyTurn && canPlay ? 8 : 0)
                Group {
                    if revealed {
                        CardView(card: card, width: cardW)
                    } else {
                        CardBackView(width: cardW)
                    }
                }
                .overlay {
                    if isMyTurn && !canPlay {
                        RoundedRectangle(cornerRadius: cardW * 0.11, style: .continuous)
                            .fill(Color.black.opacity(0.45))
                    }
                }
                .overlay {
                    if highlighted == card {
                        RoundedRectangle(cornerRadius: cardW * 0.11, style: .continuous)
                            .strokeBorder(Theme.brass, lineWidth: 3)
                            .shadow(color: Theme.brass, radius: 10)
                    }
                }
                .rotationEffect(.degrees(offsetFromMid * 2.4), anchor: .bottom)
                .position(x: (geo.size.width - total) / 2 + cardW / 2 + spacing * CGFloat(i),
                          y: geo.size.height - cardW * 0.71 - 6 + CGFloat(offsetFromMid * offsetFromMid) * 0.9 - lift)
                .zIndex(Double(i))
                .onTapGesture { onTap(card) }
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: cards)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: selected)
        .animation(.easeOut(duration: 0.2), value: isMyTurn)
    }
}
