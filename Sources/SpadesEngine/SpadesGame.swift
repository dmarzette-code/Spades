import Foundation

public enum GameError: Error, Equatable {
    case wrongPhase
    case notYourTurn
    case illegalBid
    case illegalCard
}

public enum Phase: Hashable, Sendable {
    case notStarted
    case bidding
    case playing
    case roundComplete
    case gameOver(winner: Team)
}

public enum PlayOutcome: Hashable, Sendable {
    case trickContinues
    case trickComplete(Trick, winner: Seat)
    case roundComplete(Trick, winner: Seat, RoundResult)
}

/// The complete rules engine. A pure value type: no timing, no UI, no randomness except what you pass in.
public struct SpadesGame: Sendable {
    public var rules: HouseRules
    public private(set) var phase: Phase = .notStarted
    public private(set) var scores: [Team: TeamScore] = [.us: TeamScore(), .them: TeamScore()]
    public private(set) var dealer: Seat
    public private(set) var turn: Seat
    public private(set) var roundNumber = 0
    public private(set) var hands: [Seat: [Card]] = [:]
    public private(set) var bids: [Seat: Bid] = [:]
    public private(set) var tricksWon: [Seat: Int] = [:]
    public private(set) var currentTrick: Trick
    public private(set) var completedTricks: [Trick] = []
    public private(set) var spadesBroken = false
    public private(set) var history: [RoundResult] = []

    public init(rules: HouseRules = .standard, dealer: Seat = .east) {
        self.rules = rules
        self.dealer = dealer
        self.turn = dealer.next
        self.currentTrick = Trick(leader: dealer.next)
    }

    /// A game rebuilt from one player's knowledge plus guessed hands for everyone else. Used for simulation.
    init(view: PlayerView, hands: [Seat: [Card]]) {
        self.init(rules: view.rules, dealer: view.dealer)
        self.hands = hands
        scores = view.scores
        bids = view.bids
        tricksWon = view.tricksWon
        currentTrick = view.currentTrick
        completedTricks = view.completedTricks
        spadesBroken = view.spadesBroken
        roundNumber = 1
        phase = view.bids.count == 4 ? .playing : .bidding
        turn = view.seat
    }

    // MARK: Dealing

    public mutating func startRound<R: RandomNumberGenerator>(using rng: inout R) {
        if phase == .roundComplete { dealer = dealer.next }
        deal(rules.deck.shuffled(using: &rng))
    }

    public mutating func startRound() {
        var rng = SystemRandomNumberGenerator()
        startRound(using: &rng)
    }

    /// Deal a specific deck order (13 cards each, starting left of the dealer). Useful for tests and replays.
    public mutating func deal(_ deck: [Card]) {
        precondition(deck.count == 52, "Spades needs exactly 52 cards")
        roundNumber += 1
        hands = [:]
        var seat = dealer.next
        for card in deck {
            hands[seat, default: []].append(card)
            seat = seat.next
        }
        for s in Seat.allCases { hands[s] = hands[s, default: []].sortedForHand(rules) }
        bids = [:]
        tricksWon = Dictionary(uniqueKeysWithValues: Seat.allCases.map { ($0, 0) })
        completedTricks = []
        spadesBroken = false
        phase = .bidding
        turn = dealer.next
        currentTrick = Trick(leader: firstLeader)
    }

    private var firstLeader: Seat {
        guard rules.lowClubLeads, let low = lowestClubInPlay else { return dealer.next }
        return Seat.allCases.first { hands[$0]?.contains(low) == true } ?? dealer.next
    }

    // MARK: Bidding

    public func canBidBlindNil(_ seat: Seat) -> Bool {
        guard rules.blindNilAllowed, rules.nilAllowed, phase == .bidding else { return false }
        if case .nilBid = bids[seat.partner] { return false }
        if case .blindNil = bids[seat.partner] { return false }
        let mine = scores[seat.team]!.points, theirs = scores[seat.team.opponent]!.points
        return theirs - mine >= rules.blindNilMinDeficit
    }

    public func legalBids(for seat: Seat) -> [Bid] {
        guard phase == .bidding, turn == seat else { return [] }
        var floor = 1
        if rules.minimumTeamBid > 0, let partnerBid = bids[seat.partner] {
            floor = max(1, rules.minimumTeamBid - partnerBid.contractTricks)
        }
        var result: [Bid] = floor <= 13 ? (floor...13).map { .tricks($0) } : [.tricks(13)]
        // Under "the board", nil is only allowed if partner has already covered the minimum (or hasn't bid yet).
        let boardForbidsNil = rules.minimumTeamBid > 0
            && (bids[seat.partner].map { $0.contractTricks < rules.minimumTeamBid } ?? false)
        if rules.nilAllowed && !boardForbidsNil { result.insert(.nilBid, at: 0) }
        if canBidBlindNil(seat) && !boardForbidsNil { result.append(.blindNil) }
        return result
    }

    public mutating func placeBid(_ bid: Bid, for seat: Seat) throws {
        guard phase == .bidding else { throw GameError.wrongPhase }
        guard seat == turn else { throw GameError.notYourTurn }
        guard legalBids(for: seat).contains(bid) else { throw GameError.illegalBid }
        bids[seat] = bid
        if bids.count == 4 {
            phase = .playing
            turn = currentTrick.leader
        } else {
            turn = seat.next
        }
    }

    public var biddingComplete: Bool { bids.count == 4 }

    public func contract(for team: Team) -> Int {
        team.seats.reduce(0) { $0 + (bids[$1]?.contractTricks ?? 0) }
    }

    // MARK: Play

    public func legalPlays(for seat: Seat) -> [Card] {
        guard phase == .playing, turn == seat, let hand = hands[seat] else { return [] }
        if let led = currentTrick.ledSuit {
            let following = hand.filter { $0.suit == led }
            return following.isEmpty ? hand : following
        }
        if rules.lowClubLeads && completedTricks.isEmpty, let low = lowestClubInPlay, hand.contains(low) {
            return [low]
        }
        if rules.spadesMustBeBroken && !spadesBroken {
            let nonSpades = hand.filter { !$0.isTrump }
            if !nonSpades.isEmpty { return nonSpades }
        }
        return hand
    }

    private var lowestClubInPlay: Card? {
        Rank.standard.lazy.map { Card($0, .clubs) }.first { c in Seat.allCases.contains { hands[$0]?.contains(c) == true } }
    }

    @discardableResult
    public mutating func play(_ card: Card, by seat: Seat) throws -> PlayOutcome {
        guard phase == .playing else { throw GameError.wrongPhase }
        guard seat == turn else { throw GameError.notYourTurn }
        guard legalPlays(for: seat).contains(card) else { throw GameError.illegalCard }

        hands[seat]!.removeAll { $0 == card }
        currentTrick.add(card, by: seat)
        if card.isTrump { spadesBroken = true }

        guard currentTrick.isComplete else {
            turn = seat.next
            return .trickContinues
        }

        let trick = currentTrick
        let winner = trick.winningPlay(rules)!.seat
        tricksWon[winner, default: 0] += 1
        completedTricks.append(trick)
        currentTrick = Trick(leader: winner)
        turn = winner

        guard completedTricks.count == 13 else { return .trickComplete(trick, winner: winner) }
        let result = finishRound()
        return .roundComplete(trick, winner: winner, result)
    }

    private mutating func finishRound() -> RoundResult {
        var teams: [Team: TeamRoundResult] = [:]
        for team in Team.allCases {
            let r = Scorer.score(team: team, bids: bids, tricks: tricksWon, before: scores[team]!, rules: rules)
            teams[team] = r
            scores[team] = r.after
        }
        let result = RoundResult(roundNumber: roundNumber, bids: bids, tricks: tricksWon, teams: teams)
        history.append(result)
        if let winner = Self.winner(scores: scores, rules: rules) {
            phase = .gameOver(winner: winner)
        } else {
            phase = .roundComplete
        }
        return result
    }

    public static func winner(scores: [Team: TeamScore], rules: HouseRules) -> Team? {
        let us = scores[.us]!.points, them = scores[.them]!.points
        let someoneOut = us >= rules.winningScore || them >= rules.winningScore
            || (rules.mercyRuleEnabled && (us <= rules.losingScore || them <= rules.losingScore))
        guard someoneOut, us != them else { return nil }
        return us > them ? .us : .them
    }

    // MARK: Information available to one player

    /// Everything a player at `seat` is allowed to know. AI players only ever see this.
    public func view(for seat: Seat) -> PlayerView {
        PlayerView(
            seat: seat, rules: rules, hand: hands[seat] ?? [], handSizes: hands.mapValues(\.count),
            bids: bids, tricksWon: tricksWon, currentTrick: currentTrick, completedTricks: completedTricks,
            spadesBroken: spadesBroken, scores: scores, dealer: dealer,
            legalPlays: legalPlays(for: seat), legalBids: legalBids(for: seat),
            canBidBlindNil: canBidBlindNil(seat))
    }
}

public struct PlayerView: Sendable {
    public let seat: Seat
    public let rules: HouseRules
    public let hand: [Card]
    public let handSizes: [Seat: Int]
    public let bids: [Seat: Bid]
    public let tricksWon: [Seat: Int]
    public let currentTrick: Trick
    public let completedTricks: [Trick]
    public let spadesBroken: Bool
    public let scores: [Team: TeamScore]
    public let dealer: Seat
    public let legalPlays: [Card]
    public let legalBids: [Bid]
    public let canBidBlindNil: Bool
}
