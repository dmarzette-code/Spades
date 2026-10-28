import Foundation

public protocol SpadesAI: Sendable {
    /// Called before the player looks at their cards, only when blind nil is legal.
    func wantsBlindNil(_ view: PlayerView) -> Bool
    func chooseBid(_ view: PlayerView) -> Bid
    func choosePlay(_ view: PlayerView) -> Card
}

public enum Difficulty: String, CaseIterable, Codable, Sendable, Identifiable {
    case easy, medium, hard

    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }

    public var blurb: String {
        switch self {
        case .easy: "Forgets what's been played and bids loosely."
        case .medium: "Solid club player. Counts cards, bids honestly."
        case .hard: "Simulates the rest of the hand before every bid and card."
        }
    }

    /// The heuristic part of each level. Hard adds simulation on top (see `makeAI`).
    public var tuning: AITuning {
        switch self {
        case .easy: AITuning(bidBias: -0.3, bidNoise: 1.4, mistakeRate: 0.22, remembersCards: false, setsNils: false)
        case .medium: AITuning(bidBias: 0, bidNoise: 0.35, mistakeRate: 0.03, remembersCards: true, setsNils: true, tableAwareness: 0.15)
        case .hard: Self.rolloutTuning
        }
    }

    /// The sharpest pure heuristic, found by self-play sweeps. Hard uses it to play out simulations.
    public static let rolloutTuning = AITuning(bidBias: 0, bidNoise: 0, mistakeRate: 0, remembersCards: true, setsNils: true, tableAwareness: 0.15)

    public func makeAI() -> SpadesAI {
        self == .hard ? MonteCarloAI() : HeuristicAI(self)
    }
}

/// Knobs that separate a casual bot from a sharp one.
public struct AITuning: Hashable, Sendable {
    /// Added to the hand's trick estimate before rounding. Positive bids more aggressively.
    public var bidBias: Double
    /// Random spread (in tricks) applied to bids.
    public var bidNoise: Double
    /// Chance of making a loose, unconsidered play.
    public var mistakeRate: Double
    /// Whether the bot tracks played cards and voids.
    public var remembersCards: Bool
    /// Whether the bot deliberately tries to break opponents' nils.
    public var setsNils: Bool
    /// Extra tricks added when partner already bid a number: partner's bid was already cautious,
    /// so shading ours too would make the team bid too low.
    public var partnerBias: Double
    /// Per unclaimed trick, how much a late bidder leans up when the table's bids leave tricks floating.
    public var tableAwareness: Double

    public init(bidBias: Double, bidNoise: Double, mistakeRate: Double, remembersCards: Bool, setsNils: Bool,
                partnerBias: Double = 0, tableAwareness: Double = 0) {
        self.bidBias = bidBias
        self.bidNoise = bidNoise
        self.mistakeRate = mistakeRate
        self.remembersCards = remembersCards
        self.setsNils = setsNils
        self.partnerBias = partnerBias
        self.tableAwareness = tableAwareness
    }
}

/// A card-counting heuristic player. It only knows what a real player at the table would know.
public struct HeuristicAI: SpadesAI {
    public let tuning: AITuning

    public init(_ difficulty: Difficulty = .hard) { tuning = difficulty.tuning }
    public init(tuning: AITuning) { self.tuning = tuning }

    /// Repeatable pseudo-randomness derived from what this player can see, so games replay identically.
    func jitter(_ view: PlayerView, salt: UInt64) -> Double {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325 ^ salt
        func mix(_ v: UInt64) { h = (h ^ v) &* 0x0000_0100_0000_01B3 }
        mix(UInt64(view.seat.rawValue))
        mix(UInt64(view.completedTricks.count))
        mix(UInt64(view.currentTrick.plays.count))
        for c in view.hand { mix(UInt64(c.rank.rawValue * 4 + c.suit.rawValue)) }
        for t in view.scores.values.sorted(by: { $0.points < $1.points }) { mix(UInt64(bitPattern: Int64(t.points))) }
        h ^= h >> 33
        h &*= 0xFF51_AFD7_ED55_8CCD
        h ^= h >> 33
        return Double(h >> 11) / Double(1 << 53)
    }

    // MARK: Bidding

    public func wantsBlindNil(_ view: PlayerView) -> Bool {
        let deficit = view.scores[view.seat.team.opponent]!.points - view.scores[view.seat.team]!.points
        return view.canBidBlindNil && deficit >= max(200, view.rules.blindNilMinDeficit)
            && view.bids[view.seat.partner] == nil
    }

    /// Estimated number of tricks this hand takes on its own.
    public static func estimateTricks(_ hand: [Card], rules: HouseRules) -> Double {
        let knowledge = CardKnowledge(hand: hand, played: [], rules: rules)
        let spades = hand.filter(\.isTrump).sorted { $0.power(rules) > $1.power(rules) }
        var tricks = 0.0
        var spadeHonorTricks = 0
        for (i, card) in spades.enumerated() {
            let higher = knowledge.higherUnseen(than: card).count
            let guards = spades.count - i - 1
            if higher == 0 { tricks += 1; spadeHonorTricks += 1 }
            else if guards >= higher { tricks += higher == 1 ? 0.85 : 0.65; spadeHonorTricks += 1 }
        }
        tricks += Double(max(0, spades.count - max(4, spadeHonorTricks + 3))) * 0.9
        var spareTrumps = max(0, spades.count - spadeHonorTricks)

        for suit in [Suit.clubs, .diamonds, .hearts] {
            let cards = hand.filter { $0.suit == suit }
            let n = cards.count
            let ranks = Set(cards.map(\.rank))
            if ranks.contains(.ace) { tricks += n <= 5 ? 1 : 0.7 }
            if ranks.contains(.king) {
                if n == 1 { tricks += 0.2 }
                else if n <= 4 { tricks += ranks.contains(.ace) ? 0.9 : 0.7 }
                else { tricks += 0.4 }
            }
            if ranks.contains(.queen), n >= 3, n <= 4 { tricks += ranks.contains(.king) || ranks.contains(.ace) ? 0.5 : 0.25 }
            // Ruffing potential with spare spades.
            if n <= 1 && spareTrumps > 0 {
                let ruffs = min(spareTrumps, n == 0 ? 2 : 1)
                tricks += Double(ruffs) * 0.7
                spareTrumps -= ruffs
            }
        }
        return tricks
    }

    func shouldBidNil(_ hand: [Card], rules: HouseRules, estimate: Double) -> Bool {
        guard estimate < 1.6 else { return false }
        let spades = hand.filter(\.isTrump)
        if spades.count > 3 { return false }
        if spades.contains(where: { $0.power(rules) >= Rank.jack.rawValue }) { return false }
        for suit in [Suit.clubs, .diamonds, .hearts] {
            let cards = hand.filter { $0.suit == suit }.map { $0.rank.rawValue }.sorted()
            guard let lowest = cards.first else { continue }
            if cards.contains(Rank.ace.rawValue) { return false }
            if cards.contains(Rank.king.rawValue) && cards.count < 4 { return false }
            if cards.count <= 2 && cards.last! >= Rank.queen.rawValue { return false }
            if lowest > 7 { return false }
        }
        return true
    }

    public func chooseBid(_ view: PlayerView) -> Bid {
        let legal = view.legalBids
        let estimate = Self.estimateTricks(view.hand, rules: view.rules)
        let partnerBid = view.bids[view.seat.partner]

        if legal.contains(.nilBid), partnerBid?.isNil != true,
           shouldBidNil(view.hand, rules: view.rules, estimate: estimate) {
            if let pb = partnerBid, pb.contractTricks >= 3 { return .nilBid }
            if partnerBid == nil { return .nilBid }
            if estimate < 1.0 { return .nilBid }
        }

        var target = estimate + tuning.bidBias
        if tuning.bidNoise > 0 { target += (jitter(view, salt: 1) - 0.5) * 2 * tuning.bidNoise }
        if let pb = partnerBid, !pb.isNil { target += tuning.partnerBias }
        if view.bids.count >= 2 {
            // Tricks nobody has claimed yet; late bidders can afford to reach for some of them.
            let claimed = view.bids.values.reduce(0) { $0 + $1.contractTricks }
            let floating = Double(13 - claimed) - estimate
            if floating > 0 { target += floating * tuning.tableAwareness * Double(view.bids.count - 1) / 2 }
        }
        // Partner of a nil bidder must cover them, so bid a little more conservatively.
        if partnerBid?.isNil == true { target -= 0.3 }
        // Close to the bag limit: lean toward bidding up rather than eating bags.
        let bags = view.scores[view.seat.team]!.bags
        if view.rules.bagsEnabled && bags >= view.rules.bagLimit - 3 { target += 0.4 }
        var bid = max(1, Int(target.rounded()))
        // Don't push the table total far past 13.
        let othersTotal = view.bids.values.reduce(0) { $0 + $1.contractTricks }
        if othersTotal + bid > 14 { bid = max(1, 14 - othersTotal) }

        let numeric = legal.compactMap { b -> Int? in if case .tricks(let n) = b { return n } else { return nil } }
        guard let lo = numeric.min(), let hi = numeric.max() else { return legal.first ?? .tricks(1) }
        return .tricks(min(max(bid, lo), hi))
    }

    // MARK: Play

    public func choosePlay(_ view: PlayerView) -> Card {
        let legal = view.legalPlays
        guard legal.count > 1 else { return legal[0] }
        if tuning.mistakeRate > 0 && jitter(view, salt: 2) < tuning.mistakeRate {
            return legal[Int(jitter(view, salt: 3) * Double(legal.count)) % legal.count]
        }
        let ctx = PlayContext(view, remembersCards: tuning.remembersCards)

        if ctx.iAmLiveNil { return ctx.playAsNil() }
        if ctx.partnerIsLiveNil { return ctx.coverPartner() }
        if tuning.setsNils, let nilSeat = ctx.liveOpponentNil, !ctx.mustFocusOnContract { return ctx.setNil(nilSeat) }
        return ctx.wantTricks ? ctx.playToWin() : ctx.playToDuck()
    }
}

// MARK: - Card knowledge

/// Tracks which cards are still unseen from one player's point of view.
struct CardKnowledge {
    let rules: HouseRules
    let unseen: Set<Card>

    init(hand: [Card], played: [Card], rules: HouseRules) {
        self.rules = rules
        self.unseen = Set(rules.deck).subtracting(hand).subtracting(played)
    }

    func higherUnseen(than card: Card) -> [Card] {
        unseen.filter { $0.suit == card.suit && $0.power(rules) > card.power(rules) }
    }

    /// No unseen card of the same suit outranks it.
    func isBoss(_ card: Card) -> Bool { higherUnseen(than: card).isEmpty }

    func unseenCount(_ suit: Suit) -> Int { unseen.filter { $0.suit == suit }.count }
}

struct PlayContext {
    let view: PlayerView
    let rules: HouseRules
    let me: Seat
    let legal: [Card]
    let trick: Trick
    let knowledge: CardKnowledge
    let voids: [Seat: Set<Suit>]
    let tricksLeft: Int

    init(_ view: PlayerView, remembersCards: Bool = true) {
        self.view = view
        rules = view.rules
        me = view.seat
        legal = view.legalPlays
        trick = view.currentTrick
        // A forgetful player only knows the cards on the table right now.
        let remembered = remembersCards ? view.completedTricks : []
        let played = remembered.flatMap { $0.plays.map(\.card) } + view.currentTrick.plays.map(\.card)
        knowledge = CardKnowledge(hand: view.hand, played: played, rules: view.rules)
        var v: [Seat: Set<Suit>] = [:]
        for t in remembered + [view.currentTrick] {
            guard let led = t.ledSuit else { continue }
            for p in t.plays where p.card.suit != led {
                v[p.seat, default: []].insert(led)
                if !p.card.isTrump { v[p.seat, default: []].insert(.spades) }
            }
        }
        voids = v
        tricksLeft = view.hand.count
    }

    // MARK: Situation

    func p(_ c: Card) -> Int { c.power(rules) }
    var partner: Seat { me.partner }
    var isLeading: Bool { trick.plays.isEmpty }
    var seatsAfterMe: [Seat] {
        var s: [Seat] = []
        var next = me.next
        for _ in 0..<(3 - trick.plays.count) { s.append(next); next = next.next }
        return s
    }
    var isLast: Bool { trick.plays.count == 3 }
    var winning: Play? { trick.winningPlay(rules) }
    var partnerWinning: Bool { winning?.seat == partner }

    func isLiveNil(_ seat: Seat) -> Bool { view.bids[seat]?.isNil == true && view.tricksWon[seat] == 0 }
    var iAmLiveNil: Bool { isLiveNil(me) }
    var partnerIsLiveNil: Bool { isLiveNil(partner) }
    var liveOpponentNil: Seat? { [me.next, me.next.next.next].first(where: isLiveNil) }

    func teamNeed(_ team: Team) -> Int {
        let contract = team.seats.reduce(0) { $0 + (view.bids[$1]?.contractTricks ?? 0) }
        let taken = team.seats.reduce(0) { acc, s in
            let counts = view.bids[s]?.isNil != true || rules.nilTricksCountForPartner
            return acc + (counts ? view.tricksWon[s] ?? 0 : 0)
        }
        return contract - taken
    }
    var myNeed: Int { teamNeed(me.team) }
    var theirNeed: Int { teamNeed(me.team.opponent) }

    var mustFocusOnContract: Bool { myNeed > 0 && myNeed >= tricksLeft - 1 }

    var wantTricks: Bool {
        if myNeed > 0 { return true }
        // Contract made: try to set the opponents if it's realistic, otherwise duck bags.
        let bagRoom = !rules.bagsEnabled || view.scores[me.team]!.bags + (-myNeed) < rules.bagLimit - 2
        return theirNeed > 0 && theirNeed <= tricksLeft && bagRoom
    }

    func mightBeTrumped(_ suit: Suit, by seats: [Seat]) -> Bool {
        guard suit != .spades else { return false }
        return seats.contains { s in s.team != me.team && voids[s]?.contains(suit) == true && voids[s]?.contains(.spades) != true }
    }

    /// Cards in hand that would currently win the trick.
    func winners(from cards: [Card]) -> [Card] {
        guard let w = winning else { return cards }
        return cards.filter { Trick.beats($0, w.card, rules: rules) }
    }

    func lowest(_ cards: [Card]) -> Card {
        cards.min { (p($0), $0.isTrump ? 1 : 0) < (p($1), $1.isTrump ? 1 : 0) }!
    }

    func highest(_ cards: [Card]) -> Card {
        cards.max { (p($0), $0.isTrump ? 1 : 0) < (p($1), $1.isTrump ? 1 : 0) }!
    }

    /// Lowest non-trump card if possible: discards never waste spades.
    func cheapestDiscard(_ cards: [Card]) -> Card {
        let side = cards.filter { !$0.isTrump }
        guard !side.isEmpty else { return lowest(cards) }
        // Prefer shortening a short suit so we can ruff later.
        let bySuit = Dictionary(grouping: side, by: \.suit)
        let candidates = bySuit.values.map { lowest($0) }
        return candidates.min { a, b in
            let la = bySuit[a.suit]!.count, lb = bySuit[b.suit]!.count
            return (p(a) + la * 2) < (p(b) + lb * 2)
        }!
    }

    /// Would this card be a sure winner if played now?
    func isSafeWinner(_ card: Card) -> Bool {
        guard winners(from: [card]).count == 1 else { return false }
        let later = seatsAfterMe
        if later.isEmpty { return true }
        if !knowledge.isBoss(card) { return later.allSatisfy { $0.team == me.team } }
        return !mightBeTrumped(card.suit, by: later)
    }

    // MARK: Strategies

    func playToWin() -> Card {
        if isLeading {
            let bosses = legal.filter { !$0.isTrump && knowledge.isBoss($0) && !mightBeTrumped($0.suit, by: [me.next, me.next.next.next]) }
            if let b = bosses.max(by: { p($0) < p($1) }) { return b }
            let trumps = legal.filter(\.isTrump)
            if let topTrump = trumps.max(by: { p($0) < p($1) }), knowledge.isBoss(topTrump),
               trumps.count * 2 >= knowledge.unseenCount(.spades) { return topTrump }
            // Lead low from the shortest side suit to set up ruffs.
            let side = legal.filter { !$0.isTrump }
            if !side.isEmpty {
                let bySuit = Dictionary(grouping: side, by: \.suit)
                let shortest = bySuit.min { a, b in (a.value.count, a.key.rawValue) < (b.value.count, b.key.rawValue) }!
                return lowest(shortest.value)
            }
            return lowest(legal)
        }

        let canWin = winners(from: legal)
        if partnerWinning, let w = winning {
            let partnerSafe = isLast || knowledge.isBoss(w.card) && !mightBeTrumped(w.card.suit, by: seatsAfterMe)
            if partnerSafe { return cheapestDiscard(legal) }
            if let sure = canWin.filter(isSafeWinner).min(by: { p($0) < p($1) }) { return sure }
            return cheapestDiscard(legal)
        }
        guard !canWin.isEmpty else { return cheapestDiscard(legal) }
        if isLast { return lowest(canWin) }
        if let sure = canWin.filter(isSafeWinner).min(by: { p($0) < p($1) }) { return sure }
        // Second hand low; third hand high.
        let following = legal.first?.suit == trick.ledSuit
        if trick.plays.count == 1 && following && myNeed < tricksLeft / 2 { return lowest(legal) }
        return following ? highest(canWin) : lowest(canWin)
    }

    func playToDuck() -> Card {
        if isLeading {
            // Lead the card most likely to be beaten.
            return legal.max { knowledge.higherUnseen(than: $0).count < knowledge.higherUnseen(than: $1).count
                || (knowledge.higherUnseen(than: $0).count == knowledge.higherUnseen(than: $1).count && p($0) > p($1)) }!
        }
        let losers = legal.filter { winners(from: [$0]).isEmpty }
        if !losers.isEmpty {
            // Dump the most dangerous card that still loses.
            let side = losers.filter { !$0.isTrump }
            return highest(side.isEmpty ? losers : side)
        }
        // Forced to take the lead: if last, unload the highest; otherwise hope to be overtaken.
        return isLast ? highest(legal) : lowest(legal)
    }

    func playAsNil() -> Card {
        if isLeading {
            let side = legal.filter { !$0.isTrump }
            return lowest(side.isEmpty ? legal : side)
        }
        let losers = legal.filter { winners(from: [$0]).isEmpty }
        if !losers.isEmpty {
            let side = losers.filter { !$0.isTrump }
            // Following suit: the highest card that still ducks. Void: throw away the scariest side card.
            return highest(side.isEmpty ? losers : side)
        }
        return isLast ? highest(legal) : lowest(legal)
    }

    func coverPartner() -> Card {
        let partnerPlayed = trick.card(of: partner) != nil
        if isLeading {
            let side = legal.filter { !$0.isTrump }
            if let boss = side.filter({ knowledge.isBoss($0) }).max(by: { p($0) < p($1) }) { return boss }
            return highest(side.isEmpty ? legal : side)
        }
        let canWin = winners(from: legal)
        if partnerPlayed {
            if partnerWinning {
                // Must overtake partner.
                if !canWin.isEmpty { return isLast ? lowest(canWin) : highest(canWin) }
                return cheapestDiscard(legal)
            }
            // Partner is safely under someone; play normally.
            return wantTricks ? playToWin() : playToDuck()
        }
        // Partner plays after me: win big so they can duck under.
        if !canWin.isEmpty { return highest(canWin) }
        return cheapestDiscard(legal)
    }

    func setNil(_ nilSeat: Seat) -> Card {
        let nilPlayed = trick.card(of: nilSeat) != nil
        if isLeading {
            let side = legal.filter { !$0.isTrump && !(voids[nilSeat]?.contains($0.suit) ?? false) }
            return lowest(side.isEmpty ? legal : side)
        }
        if nilPlayed {
            if winning?.seat == nilSeat {
                // Leave the nil bidder on top.
                let losers = legal.filter { winners(from: [$0]).isEmpty }
                if !losers.isEmpty { return highest(losers) }
                return lowest(legal)
            }
            return wantTricks ? playToWin() : playToDuck()
        }
        // Nil bidder still to play: stay low so they're forced over us.
        let following = legal.first?.suit == trick.ledSuit
        if following { return lowest(legal) }
        return cheapestDiscard(legal)
    }
}
