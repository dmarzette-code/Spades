import Foundation

/// Hard difficulty. For each decision it deals out many guesses of the hidden hands that fit everything
/// it has seen (including which players have shown out of which suits), plays each option to the end of
/// the hand with a fast heuristic player, and picks the option that scores best on average.
/// It never looks at real hidden cards: guesses are built from its own `PlayerView` only.
public struct MonteCarloAI: SpadesAI {
    public let rollout: HeuristicAI
    /// Rough cap on rollout card plays per decision; keeps thinking time bounded on device.
    public let playBudget: Int
    public let bidSamples: Int
    public var simulateBids = true
    public var simulatePlays = true

    public init(rollout: HeuristicAI = HeuristicAI(tuning: Difficulty.rolloutTuning), playBudget: Int = 9_000, bidSamples: Int = 32) {
        self.rollout = rollout
        self.playBudget = playBudget
        self.bidSamples = bidSamples
    }

    public func wantsBlindNil(_ view: PlayerView) -> Bool { rollout.wantsBlindNil(view) }

    // MARK: Bidding

    public func chooseBid(_ view: PlayerView) -> Bid {
        let baseline = rollout.chooseBid(view)
        guard simulateBids else { return baseline }
        let estimate = HeuristicAI.estimateTricks(view.hand, rules: view.rules)
        var candidates = Set<Bid>()
        let center = max(1, baseline.contractTricks)
        for n in (center - 2)...(center + 2) where view.legalBids.contains(.tricks(n)) { candidates.insert(.tricks(n)) }
        if view.legalBids.contains(.nilBid) && estimate < 2.6 && view.bids[view.seat.partner]?.isNil != true {
            candidates.insert(.nilBid)
        }
        candidates.insert(baseline)
        guard candidates.count > 1 else { return baseline }

        var rng = SplitMix64(seed: Self.seed(view, salt: 11))
        var totals: [Bid: Double] = [:]
        for _ in 0..<bidSamples {
            guard let hands = Self.sampleHands(view, rng: &rng) else { break }
            for bid in candidates {
                var game = SpadesGame(view: view, hands: hands)
                try? game.placeBid(bid, for: view.seat)
                totals[bid, default: 0] += playOut(&game, for: view.seat.team)
            }
        }
        // Small preference for the heuristic's bid so sampling noise doesn't cause erratic bids.
        totals[baseline, default: 0] += Double(bidSamples) * 1.5
        return totals.max { $0.value < $1.value || ($0.value == $1.value && $0.key.contractTricks > $1.key.contractTricks) }?.key ?? baseline
    }

    // MARK: Play

    public func choosePlay(_ view: PlayerView) -> Card {
        let legal = view.legalPlays
        guard legal.count > 1 else { return legal[0] }
        let baseline = rollout.choosePlay(view)
        guard simulatePlays else { return baseline }
        let candidates = Self.distinctOptions(legal, view: view)
        guard candidates.count > 1 else { return baseline }

        let remainingPlays = max(1, view.hand.count * 4 - view.currentTrick.plays.count)
        let samples = min(40, max(8, playBudget / (candidates.count * remainingPlays)))
        var rng = SplitMix64(seed: Self.seed(view, salt: 29))
        var totals: [Card: Double] = [:]
        for _ in 0..<samples {
            guard let hands = Self.sampleHands(view, rng: &rng) else { break }
            for card in candidates {
                var game = SpadesGame(view: view, hands: hands)
                _ = try? game.play(card, by: view.seat)
                totals[card, default: 0] += playOut(&game, for: view.seat.team)
            }
        }
        totals[baseline, default: 0] += Double(samples) * 0.75
        return totals.max { $0.value < $1.value }?.key ?? baseline
    }

    /// Cards that are touching in rank (e.g. 9-8 when the 10 is gone) are equivalent; try only one.
    static func distinctOptions(_ legal: [Card], view: PlayerView) -> [Card] {
        let rules = view.rules
        let played = Set(view.completedTricks.flatMap { $0.plays.map(\.card) } + view.currentTrick.plays.map(\.card))
        let allBySuit = Dictionary(grouping: rules.deck, by: \.suit).mapValues { $0.sorted { $0.power(rules) < $1.power(rules) } }
        var result: [Card] = []
        for suit in Suit.allCases {
            let mine = Set(legal.filter { $0.suit == suit })
            guard !mine.isEmpty else { continue }
            var runOpen = false
            for card in allBySuit[suit] ?? [] {
                if mine.contains(card) {
                    if !runOpen { result.append(card); runOpen = true }
                } else if !played.contains(card) {
                    runOpen = false
                }
            }
        }
        return result
    }

    /// Play the hand to the end with the rollout player; returns our team's value minus theirs.
    private func playOut(_ game: inout SpadesGame, for team: Team) -> Double {
        while game.phase == .bidding {
            let v = game.view(for: game.turn)
            try? game.placeBid(rollout.chooseBid(v), for: game.turn)
        }
        while game.phase == .playing {
            let v = game.view(for: game.turn)
            guard (try? game.play(rollout.choosePlay(v), by: game.turn)) != nil else { break }
        }
        guard let r = game.history.last else { return 0 }
        return value(r.teams[team]!, game.rules) - value(r.teams[team.opponent]!, game.rules)
    }

    /// Hand score with bags charged at their long-run cost instead of +1 each.
    private func value(_ r: TeamRoundResult, _ rules: HouseRules) -> Double {
        guard rules.bagsEnabled, rules.bagLimit > 0 else { return Double(r.delta) }
        let bagCost = Double(rules.bagPenalty) / Double(rules.bagLimit)
        return Double(r.delta + r.bagPenaltyPoints) - Double(r.bagsTaken) * bagCost
    }

    // MARK: Sampling hidden hands

    /// Deal the unseen cards to the other three players, respecting hand sizes and known voids.
    static func sampleHands(_ view: PlayerView, rng: inout SplitMix64) -> [Seat: [Card]]? {
        var unseen = Set(view.rules.deck)
        unseen.subtract(view.hand)
        for t in view.completedTricks { for p in t.plays { unseen.remove(p.card) } }
        for p in view.currentTrick.plays { unseen.remove(p.card) }

        var voids: [Seat: Set<Suit>] = [:]
        for t in view.completedTricks + [view.currentTrick] {
            guard let led = t.ledSuit else { continue }
            for p in t.plays where p.card.suit != led {
                voids[p.seat, default: []].insert(led)
                if !p.card.isTrump { voids[p.seat, default: []].insert(.spades) }
            }
        }

        let others = Seat.allCases.filter { $0 != view.seat }
        let cards = Array(unseen)
        for attempt in 0..<12 {
            let respectVoids = attempt < 10
            var capacity = Dictionary(uniqueKeysWithValues: others.map { ($0, view.handSizes[$0] ?? 0) })
            var hands: [Seat: [Card]] = [:]
            func eligible(_ c: Card) -> [Seat] {
                others.filter { capacity[$0]! > 0 && !(respectVoids && voids[$0]?.contains(c.suit) == true) }
            }
            // Most constrained cards first.
            let order = cards.shuffled(using: &rng).sorted { eligible($0).count < eligible($1).count }
            var ok = true
            for c in order {
                let seats = eligible(c)
                guard !seats.isEmpty else { ok = false; break }
                // Weight by remaining capacity so hand sizes fill evenly.
                let total = seats.reduce(0) { $0 + capacity[$1]! }
                var pick = Int.random(in: 0..<total, using: &rng)
                var chosen = seats[0]
                for s in seats {
                    pick -= capacity[s]!
                    if pick < 0 { chosen = s; break }
                }
                hands[chosen, default: []].append(c)
                capacity[chosen]! -= 1
            }
            if ok {
                hands[view.seat] = view.hand
                for s in others where hands[s] == nil { hands[s] = [] }
                return hands
            }
        }
        return nil
    }

    static func seed(_ view: PlayerView, salt: UInt64) -> UInt64 {
        var h: UInt64 = 0x9E37_79B9_7F4A_7C15 ^ salt
        func mix(_ v: UInt64) { h = (h ^ v) &* 0x0000_0100_0000_01B3 }
        mix(UInt64(view.seat.rawValue))
        for c in view.hand { mix(UInt64(c.rank.rawValue * 4 + c.suit.rawValue)) }
        for t in view.completedTricks { for p in t.plays { mix(UInt64(p.card.rank.rawValue * 4 + p.card.suit.rawValue)) } }
        for p in view.currentTrick.plays { mix(UInt64(p.card.rank.rawValue * 4 + p.card.suit.rawValue)) }
        return h
    }
}

/// Small, fast, seedable generator so AI decisions are reproducible.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
