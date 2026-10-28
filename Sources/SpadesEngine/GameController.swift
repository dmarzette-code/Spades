import Foundation
import Observation

public enum Pace: String, CaseIterable, Codable, Sendable, Identifiable {
    case relaxed, normal, fast, instant

    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }

    var aiThink: Duration {
        switch self {
        case .relaxed: .milliseconds(900)
        case .normal: .milliseconds(550)
        case .fast: .milliseconds(250)
        case .instant: .zero
        }
    }

    var trickHold: Duration {
        switch self {
        case .relaxed: .milliseconds(1300)
        case .normal: .milliseconds(900)
        case .fast: .milliseconds(500)
        case .instant: .zero
        }
    }

    var sweep: Duration { self == .instant ? .zero : .milliseconds(450) }
}

/// Drives a game between the human at South and three AI players, with pacing for the UI.
@MainActor
@Observable
public final class GameController {
    public private(set) var game: SpadesGame
    public let human: Seat = .south
    public var pace: Pace
    public var names: [Seat: String] = [.south: "You", .west: "Rosa", .north: "Marcus", .east: "Dev"]

    /// Cards sitting in the middle of the table right now.
    public private(set) var tableCards: [Play] = []
    /// Set briefly when a trick is being collected, so the UI can sweep it toward the winner.
    public private(set) var sweepingTo: Seat?
    /// The human may bid blind nil and hasn't decided yet; their cards stay face down.
    public private(set) var awaitingBlindNilDecision = false
    public private(set) var humanHandRevealed = true
    public private(set) var lastRoundResult: RoundResult?
    public var showingRoundSummary = false
    public private(set) var isBusy = false

    /// How strong the opponents are. Your partner always plays at full strength.
    public var difficulty: Difficulty {
        didSet { if !opponentsOverridden { opponentAI = difficulty.makeAI() } }
    }

    private var opponentAI: SpadesAI
    private let partnerAI: SpadesAI
    private let advisor: SpadesAI = HeuristicAI(.hard)
    private let opponentsOverridden: Bool
    private var loop: Task<Void, Never>?

    /// - Parameters:
    ///   - opponentAI: Overrides the difficulty's opponents (useful for tests).
    ///   - partnerAI: Defaults to the hard AI.
    public init(rules: HouseRules = .standard, pace: Pace = .normal, difficulty: Difficulty = .medium,
                opponentAI: SpadesAI? = nil, partnerAI: SpadesAI? = nil) {
        self.game = SpadesGame(rules: rules)
        self.pace = pace
        self.difficulty = difficulty
        self.opponentsOverridden = opponentAI != nil
        self.opponentAI = opponentAI ?? difficulty.makeAI()
        self.partnerAI = partnerAI ?? Difficulty.hard.makeAI()
    }

    private func ai(for seat: Seat) -> SpadesAI {
        seat.team == human.team ? partnerAI : opponentAI
    }

    // MARK: Derived state for the UI

    public var rules: HouseRules { game.rules }
    public var humanHand: [Card] { game.hands[human] ?? [] }
    public var isHumanTurnToBid: Bool { game.phase == .bidding && game.turn == human && !isBusy && !awaitingBlindNilDecision }
    public var isHumanTurnToPlay: Bool { game.phase == .playing && game.turn == human && !isBusy && sweepingTo == nil }
    public var legalPlays: Set<Card> { isHumanTurnToPlay ? Set(game.legalPlays(for: human)) : [] }
    public var legalBids: [Bid] { isHumanTurnToBid ? game.legalBids(for: human) : [] }
    public var isGameOver: Bool { if case .gameOver = game.phase { true } else { false } }
    public var winner: Team? { if case .gameOver(let t) = game.phase { t } else { nil } }

    /// What the AI would bid with your hand.
    public var suggestedBid: Bid? {
        guard isHumanTurnToBid else { return nil }
        return advisor.chooseBid(game.view(for: human))
    }

    /// What your partner would play from your hand.
    public var hint: Card? {
        guard isHumanTurnToPlay else { return nil }
        return partnerAI.choosePlay(game.view(for: human))
    }

    // MARK: Commands

    public func newGame(rules: HouseRules) {
        loop?.cancel()
        game = SpadesGame(rules: rules, dealer: Seat.allCases.randomElement()!)
        lastRoundResult = nil
        showingRoundSummary = false
        dealRound()
    }

    public func newGame<R: RandomNumberGenerator>(rules: HouseRules, dealer: Seat, rng: inout R) {
        loop?.cancel()
        game = SpadesGame(rules: rules, dealer: dealer)
        game.startRound(using: &rng)
        afterDeal()
    }

    public func nextRound() {
        guard game.phase == .roundComplete else { return }
        showingRoundSummary = false
        dealRound()
    }

    public func nextRound<R: RandomNumberGenerator>(rng: inout R) {
        guard game.phase == .roundComplete else { return }
        showingRoundSummary = false
        game.startRound(using: &rng)
        afterDeal()
    }

    public func decideBlindNil(_ goBlind: Bool) {
        guard awaitingBlindNilDecision else { return }
        awaitingBlindNilDecision = false
        humanHandRevealed = true
        if goBlind {
            try? game.placeBid(.blindNil, for: human)
            resume()
        }
    }

    public func bid(_ bid: Bid) {
        guard isHumanTurnToBid else { return }
        do {
            try game.placeBid(bid, for: human)
            resume()
        } catch {}
    }

    public func play(_ card: Card) {
        guard isHumanTurnToPlay, legalPlays.contains(card),
              let outcome = try? game.play(card, by: human) else { return }
        // The card hits the table synchronously so the UI can animate it inside the tap's transaction.
        tableCards.append(Play(seat: human, card: card))
        isBusy = true
        loop = Task {
            await handle(outcome)
            isBusy = false
            await run()
        }
    }

    /// Run AI turns until the human needs to act. Exposed for tests.
    public func waitUntilIdle() async {
        await loop?.value
    }

    // MARK: Internals

    private func dealRound() {
        game.startRound()
        afterDeal()
    }

    private func afterDeal() {
        tableCards = []
        sweepingTo = nil
        let blindPossible = game.canBidBlindNil(human)
        awaitingBlindNilDecision = false
        humanHandRevealed = !blindPossible
        resume()
    }

    private func resume() {
        loop?.cancel()
        loop = Task { await run() }
    }

    private func pause(_ d: Duration) async {
        guard d > .zero else { await Task.yield(); return }
        try? await Task.sleep(for: d)
    }

    /// AI decisions run off the main actor so animations stay smooth while the hard AI simulates.
    private nonisolated func think<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await Task.detached(priority: .userInitiated) { work() }.value
    }

    private func run() async {
        isBusy = true
        defer { isBusy = false }
        while !Task.isCancelled {
            switch game.phase {
            case .bidding:
                let seat = game.turn
                if seat == human {
                    if !humanHandRevealed && game.canBidBlindNil(human) {
                        awaitingBlindNilDecision = true
                    } else {
                        humanHandRevealed = true
                    }
                    return
                }
                let view = game.view(for: seat)
                let player = ai(for: seat)
                async let decision = think { view.canBidBlindNil && player.wantsBlindNil(view) ? Bid.blindNil : player.chooseBid(view) }
                await pause(pace.aiThink)
                let bid = await decision
                guard !Task.isCancelled else { return }
                try? game.placeBid(bid, for: seat)
                if game.phase == .playing { humanHandRevealed = true }
            case .playing:
                let seat = game.turn
                if seat == human { return }
                let view = game.view(for: seat)
                let player = ai(for: seat)
                async let decision = think { player.choosePlay(view) }
                await pause(pace.aiThink)
                let card = await decision
                guard !Task.isCancelled else { return }
                await perform(card, by: seat)
            default:
                return
            }
        }
    }

    private func perform(_ card: Card, by seat: Seat) async {
        guard let outcome = try? game.play(card, by: seat) else { return }
        tableCards.append(Play(seat: seat, card: card))
        await handle(outcome)
    }

    private func handle(_ outcome: PlayOutcome) async {
        switch outcome {
        case .trickContinues:
            break
        case .trickComplete(_, let winner):
            await collect(to: winner)
        case .roundComplete(_, let winner, let result):
            await collect(to: winner)
            lastRoundResult = result
            showingRoundSummary = true
        }
    }

    private func collect(to winner: Seat) async {
        await pause(pace.trickHold)
        sweepingTo = winner
        await pause(pace.sweep)
        tableCards = []
        sweepingTo = nil
    }
}
