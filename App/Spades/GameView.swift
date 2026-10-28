import SwiftUI
import SpadesEngine

@MainActor
struct GameView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var controller = GameController()
    @State private var selected: Card?
    @State private var hintCard: Card?
    @State private var showingMenu = false
    @State private var started = false
    @State private var rejectedTap = 0

    private var game: SpadesGame { controller.game }

    var body: some View {
        ZStack {
            FeltBackground()

            VStack(spacing: 0) {
                ScoreBar(controller: controller) { showingMenu = true }
                    .padding(.top, 4)
                table
                statusLine
                    .padding(.bottom, 4)
                HandView(
                    cards: controller.humanHand,
                    revealed: controller.humanHandRevealed,
                    playable: controller.legalPlays,
                    isMyTurn: controller.isHumanTurnToPlay,
                    selected: selected,
                    highlighted: hintCard,
                    onTap: tap)
                    .frame(height: 150)
                    .modifier(Shake(animatableData: CGFloat(rejectedTap)))
            }

            overlays
        }
        .sensoryFeedback(.impact(weight: .light), trigger: controller.tableCards.count)
        .sensoryFeedback(.error, trigger: rejectedTap)
        .sheet(isPresented: $showingMenu) {
            GameMenuView(
                lastTrick: game.completedTricks.last,
                names: controller.names,
                onNewGame: startGame,
                onLeave: { dismiss() })
                .environment(settings)
        }
        .onAppear {
            guard !started else { return }
            started = true
            startGame()
        }
        .onChange(of: settings.pace) { _, pace in controller.pace = pace }
        .onChange(of: settings.difficulty) { _, level in controller.difficulty = level }
        .onChange(of: controller.isGameOver) { _, over in
            guard over else { return }
            settings.gamesPlayed += 1
            if controller.winner == .us { settings.gamesWon += 1 }
        }
        .onChange(of: controller.isHumanTurnToPlay) { _, _ in
            selected = nil
            hintCard = nil
        }
    }

    // MARK: Table

    private var table: some View {
        GeometryReader { geo in
            let cardW = min(66, geo.size.width / 6)
            ZStack {
                VStack(spacing: 4) {
                    PlayerPlate(seat: .north, controller: controller)
                    MiniFan(count: game.hands[.north]?.count ?? 0)
                }
                .position(x: geo.size.width / 2, y: 62)

                HStack(spacing: 6) {
                    PlayerPlate(seat: .west, controller: controller)
                    MiniFan(count: game.hands[.west]?.count ?? 0, vertical: true)
                }
                .position(x: 58, y: geo.size.height * 0.48)

                HStack(spacing: 6) {
                    MiniFan(count: game.hands[.east]?.count ?? 0, vertical: true)
                    PlayerPlate(seat: .east, controller: controller)
                }
                .position(x: geo.size.width - 58, y: geo.size.height * 0.48)

                TrickArea(controller: controller, cardWidth: cardW)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.52)

                PlayerPlate(seat: .south, controller: controller)
                    .scaleEffect(0.85)
                    .position(x: geo.size.width / 2, y: geo.size.height - 44)
                    .opacity(controller.tableCards.contains { $0.seat == .south } ? 0 : 1)
            }
        }
    }

    private var statusLine: some View {
        HStack(spacing: 10) {
            Text(statusText)
                .font(Theme.display(15, weight: .medium).italic())
                .foregroundStyle(controller.isHumanTurnToPlay ? Theme.brass : Theme.mist)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: statusText)
            if controller.isHumanTurnToPlay {
                Button {
                    withAnimation(.spring) { hintCard = controller.hint }
                } label: {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.brass)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.panel))
                        .overlay(Circle().strokeBorder(Theme.hairline))
                }
                .accessibilityLabel("Hint")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(height: 32)
        .animation(.spring(response: 0.3), value: controller.isHumanTurnToPlay)
    }

    private var statusText: String {
        let name = { (s: Seat) in controller.names[s] ?? s.name }
        switch game.phase {
        case .bidding:
            if controller.awaitingBlindNilDecision { return "Blind nil is on the table" }
            return game.turn == controller.human ? "Your bid" : "\(name(game.turn)) is bidding…"
        case .playing:
            if controller.sweepingTo != nil || controller.tableCards.count == 4 {
                let winner = game.currentTrick.leader
                return winner == controller.human ? "Your trick" : "\(name(winner)) takes it"
            }
            guard game.turn == controller.human else { return "\(name(game.turn)) is thinking…" }
            if let led = game.currentTrick.ledSuit {
                return controller.legalPlays.contains { $0.suit == led } ? "Follow \(led.symbol)" : "Out of \(led.symbol) — your call"
            }
            if !game.spadesBroken && game.rules.spadesMustBeBroken { return "Your lead · spades not broken" }
            return "Your lead"
        case .roundComplete, .gameOver:
            return ""
        case .notStarted:
            return "Shuffling…"
        }
    }

    // MARK: Overlays

    @ViewBuilder
    private var overlays: some View {
        if controller.awaitingBlindNilDecision {
            dimmed {
                BlindNilPanel(
                    deficit: game.scores[.them]!.points - game.scores[.us]!.points,
                    value: game.rules.blindNilValue,
                    onDecide: { blind in withAnimation(.spring) { controller.decideBlindNil(blind) } })
            }
        } else if controller.isHumanTurnToBid {
            VStack {
                Spacer()
                BidPanel(
                    legal: controller.legalBids,
                    suggestion: settings.showBidSuggestion ? controller.suggestedBid : nil,
                    partnerName: controller.names[.north] ?? "Partner",
                    partnerBid: game.bids[.north],
                    onBid: { bid in withAnimation(.spring) { controller.bid(bid) } })
                    .padding(.horizontal, 12)
                    .padding(.bottom, 150)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if controller.showingRoundSummary, let result = controller.lastRoundResult {
            dimmed {
                RoundSummaryView(
                    result: result, rules: game.rules, names: controller.names,
                    isFinal: controller.isGameOver,
                    onContinue: {
                        withAnimation(.spring) {
                            if controller.isGameOver { controller.showingRoundSummary = false } else { controller.nextRound() }
                        }
                    })
            }
        } else if let winner = controller.winner {
            dimmed {
                GameOverView(winner: winner, scores: game.scores, onPlayAgain: startGame, onLeave: { dismiss() })
            }
        }
    }

    private func dimmed<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            content().padding(.horizontal, 16)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: Actions

    private func startGame() {
        selected = nil
        hintCard = nil
        controller.pace = settings.pace
        controller.difficulty = settings.difficulty
        controller.newGame(rules: settings.rules)
    }

    private func tap(_ card: Card) {
        guard controller.isHumanTurnToPlay else { return }
        guard controller.legalPlays.contains(card) else {
            withAnimation(.default) { rejectedTap += 1 }
            return
        }
        if settings.oneTapPlay || selected == card {
            selected = nil
            hintCard = nil
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) { controller.play(card) }
        } else {
            selected = card
        }
    }
}

/// Horizontal shake for an illegal card tap.
struct Shake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 3), y: 0))
    }
}
