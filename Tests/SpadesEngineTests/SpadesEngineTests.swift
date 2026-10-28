import XCTest
@testable import SpadesEngine

/// Deterministic RNG so simulations are reproducible.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(_ seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class CardTests: XCTestCase {
    func testStandardDeck() {
        let deck = HouseRules.standard.deck
        XCTAssertEqual(deck.count, 52)
        XCTAssertEqual(Set(deck).count, 52)
    }

    func testJokerDeckRemovesTwos() {
        var rules = HouseRules()
        rules.jokersEnabled = true
        let deck = rules.deck
        XCTAssertEqual(deck.count, 52)
        XCTAssertFalse(deck.contains(Card(.two, .clubs)))
        XCTAssertFalse(deck.contains(Card(.two, .hearts)))
        XCTAssertTrue(deck.contains(.bigJoker))
        XCTAssertTrue(Card.bigJoker.isTrump)
    }

    func testTrumpOrderWithJokersAndBigDeuce() {
        var rules = HouseRules()
        rules.jokersEnabled = true
        rules.bigDeuce = true
        let order = [Card.bigJoker, .littleJoker, Card(.two, .spades), Card(.ace, .spades), Card(.three, .spades)]
        for (a, b) in zip(order, order.dropFirst()) {
            XCTAssertGreaterThan(a.power(rules), b.power(rules), "\(a) should beat \(b)")
        }
    }

    func testRulesDecodeWithMissingKeys() throws {
        let old = #"{"winningScore": 300, "jokersEnabled": true}"#.data(using: .utf8)!
        let rules = try XCTUnwrap(HouseRules.decodeLeniently(old))
        XCTAssertEqual(rules.winningScore, 300)
        XCTAssertTrue(rules.jokersEnabled)
        XCTAssertEqual(rules.bagLimit, 10)
    }

    func testTrickWinner() {
        var trick = Trick(leader: .south)
        trick.add(Card(.king, .hearts), by: .south)
        trick.add(Card(.ace, .hearts), by: .west)
        trick.add(Card(.two, .spades), by: .north)
        trick.add(Card(.ace, .clubs), by: .east)
        XCTAssertEqual(trick.winningPlay(.standard)?.seat, .north)

        var offSuit = Trick(leader: .south)
        offSuit.add(Card(.three, .diamonds), by: .south)
        offSuit.add(Card(.ace, .clubs), by: .west)
        offSuit.add(Card(.four, .diamonds), by: .north)
        offSuit.add(Card(.king, .hearts), by: .east)
        XCTAssertEqual(offSuit.winningPlay(.standard)?.seat, .north)
    }
}

final class ScoringTests: XCTestCase {
    let rules = HouseRules.standard

    func score(_ bids: [Bid], _ tricks: [Int], before: TeamScore = TeamScore(), rules: HouseRules? = nil) -> TeamRoundResult {
        Scorer.score(team: .us, bids: [.south: bids[0], .north: bids[1]],
                     tricks: [.south: tricks[0], .north: tricks[1]], before: before, rules: rules ?? self.rules)
    }

    func testMadeContractWithBags() {
        let r = score([.tricks(3), .tricks(2)], [4, 3])
        XCTAssertEqual(r.after.points, 52)
        XCTAssertEqual(r.after.bags, 2)
    }

    func testSetContract() {
        let r = score([.tricks(5), .tricks(3)], [4, 3])
        XCTAssertEqual(r.after.points, -80)
        XCTAssertEqual(r.after.bags, 0)
    }

    func testBagPenalty() {
        let r = score([.tricks(3), .tricks(2)], [5, 3], before: TeamScore(points: 98, bags: 8))
        // +50 +3 bags = 151, bags 11 -> penalty -100, 1 bag left
        XCTAssertEqual(r.after.points, 51)
        XCTAssertEqual(r.after.bags, 1)
        XCTAssertEqual(r.bagPenaltyCount, 1)
    }

    func testNoBagPenaltyWhenDisabled() {
        var r2 = rules
        r2.bagsEnabled = false
        let r = score([.tricks(3), .tricks(2)], [5, 3], before: TeamScore(points: 98, bags: 8), rules: r2)
        XCTAssertEqual(r.after.points, 151)
    }

    func testSuccessfulNil() {
        let r = score([.nilBid, .tricks(4)], [0, 5])
        XCTAssertEqual(r.after.points, 100 + 40 + 1)
    }

    func testFailedNilTricksAreBags() {
        let r = score([.nilBid, .tricks(4)], [2, 4])
        XCTAssertEqual(r.after.points, -100 + 40 + 2)
        XCTAssertEqual(r.after.bags, 2)
    }

    func testFailedNilTricksHelpPartnerWhenEnabled() {
        var r2 = rules
        r2.nilTricksCountForPartner = true
        let r = score([.nilBid, .tricks(4)], [2, 2], rules: r2)
        XCTAssertEqual(r.after.points, -100 + 40)
    }

    func testBlindNil() {
        let r = score([.blindNil, .tricks(4)], [0, 4])
        XCTAssertEqual(r.after.points, 200 + 40)
    }

    func testTenForTwoHundred() {
        var r2 = rules
        r2.doubleForTenPlus = true
        XCTAssertEqual(score([.tricks(6), .tricks(4)], [6, 4], rules: r2).after.points, 200)
    }

    func testWinnerDetection() {
        XCTAssertNil(SpadesGame.winner(scores: [.us: TeamScore(points: 490), .them: TeamScore(points: 300)], rules: rules))
        XCTAssertEqual(SpadesGame.winner(scores: [.us: TeamScore(points: 510), .them: TeamScore(points: 300)], rules: rules), .us)
        XCTAssertNil(SpadesGame.winner(scores: [.us: TeamScore(points: 510), .them: TeamScore(points: 510)], rules: rules))
        XCTAssertEqual(SpadesGame.winner(scores: [.us: TeamScore(points: 520), .them: TeamScore(points: 530)], rules: rules), .them)
        XCTAssertEqual(SpadesGame.winner(scores: [.us: TeamScore(points: -210), .them: TeamScore(points: 30)], rules: rules), .them)
    }
}

final class GameRuleTests: XCTestCase {
    func newGame(_ rules: HouseRules = .standard, seed: UInt64 = 1) -> SpadesGame {
        var g = SpadesGame(rules: rules, dealer: .east)
        var rng = SeededRNG(seed)
        g.startRound(using: &rng)
        return g
    }

    func testDealGivesThirteenEach() {
        let g = newGame()
        for s in Seat.allCases { XCTAssertEqual(g.hands[s]?.count, 13) }
        XCTAssertEqual(g.turn, .south)
        XCTAssertEqual(g.phase, .bidding)
    }

    func testBiddingOutOfTurnRejected() {
        var g = newGame()
        XCTAssertThrowsError(try g.placeBid(.tricks(3), for: .west))
    }

    func testBoardMinimumBid() {
        var rules = HouseRules()
        rules.minimumTeamBid = 4
        var g = newGame(rules)
        try! g.placeBid(.tricks(1), for: .south)
        try! g.placeBid(.tricks(3), for: .west)
        let northBids = g.legalBids(for: .north)
        XCTAssertFalse(northBids.contains(.tricks(2)))
        XCTAssertTrue(northBids.contains(.tricks(3)))
        XCTAssertFalse(northBids.contains(.nilBid))
    }

    func testBlindNilRequiresDeficit() {
        var rules = HouseRules()
        rules.blindNilAllowed = true
        let g = newGame(rules)
        XCTAssertFalse(g.canBidBlindNil(.south))
    }

    func testCannotLeadSpadesUntilBroken() {
        var g = newGame()
        for s in [Seat.south, .west, .north, .east] { try! g.placeBid(.tricks(3), for: s) }
        let hand = g.hands[.south]!
        let legal = g.legalPlays(for: .south)
        if hand.contains(where: { !$0.isTrump }) {
            XCTAssertTrue(legal.allSatisfy { !$0.isTrump })
        }
    }

    func testMustFollowSuit() {
        var g = newGame()
        for s in [Seat.south, .west, .north, .east] { try! g.placeBid(.tricks(3), for: s) }
        let lead = g.legalPlays(for: .south)[0]
        try! g.play(lead, by: .south)
        let westHand = g.hands[.west]!
        let legal = g.legalPlays(for: .west)
        if westHand.contains(where: { $0.suit == lead.suit }) {
            XCTAssertTrue(legal.allSatisfy { $0.suit == lead.suit })
        } else {
            XCTAssertEqual(legal.count, westHand.count)
        }
    }

    func testLowClubLeads() {
        var rules = HouseRules()
        rules.lowClubLeads = true
        var g = newGame(rules)
        for _ in 0..<4 { try! g.placeBid(.tricks(3), for: g.turn) }
        XCTAssertTrue(g.hands[g.turn]!.contains(Card(.two, .clubs)))
        XCTAssertEqual(g.legalPlays(for: g.turn), [Card(.two, .clubs)])
    }

    func testPlayerViewHidesOtherHands() {
        let g = newGame()
        let v = g.view(for: .west)
        XCTAssertEqual(v.hand, g.hands[.west])
        XCTAssertEqual(v.handSizes[.south], 13)
    }
}

final class SimulationTests: XCTestCase {
    /// Play full games with four AIs under many rule sets; every move must be legal and the game must end.
    func testFullGamesUnderEveryPreset() {
        let ai = HeuristicAI()
        var everything = HouseRules.jokersAndDeuces
        everything.lowClubLeads = true
        everything.doubleForTenPlus = true
        everything.nilTricksCountForPartner = true
        everything.spadesMustBeBroken = false
        let ruleSets = HouseRules.presets.map(\.rules) + [everything]
        var rounds = 0
        for (i, rules) in ruleSets.enumerated() {
            for seed in 0..<25 {
                var rng = SeededRNG(UInt64(i * 1000 + seed))
                var g = SpadesGame(rules: rules, dealer: .east)
                var safety = 0
                while true {
                    g.startRound(using: &rng)
                    rounds += 1
                    while g.phase == .bidding {
                        let v = g.view(for: g.turn)
                        let bid = v.canBidBlindNil && ai.wantsBlindNil(v) ? .blindNil : ai.chooseBid(v)
                        XCTAssertNoThrow(try g.placeBid(bid, for: g.turn), "illegal bid \(bid)")
                    }
                    while g.phase == .playing {
                        let card = ai.choosePlay(g.view(for: g.turn))
                        XCTAssertNoThrow(try g.play(card, by: g.turn))
                    }
                    let last = g.history.last!
                    XCTAssertEqual(last.tricks.values.reduce(0, +), 13)
                    if case .gameOver = g.phase { break }
                    safety += 1
                    if safety > 200 { XCTFail("game never ended"); break }
                }
            }
        }
        XCTAssertGreaterThan(rounds, 100)
    }

    /// The AI's bids should be roughly honest: across many hands, teams make their bids most of the time.
    func testAIBidsAreReasonable() {
        let ai = HeuristicAI()
        var made = 0, total = 0, bagsTotal = 0, nilsBid = 0, nilsMade = 0
        for seed in 0..<400 {
            var rng = SeededRNG(UInt64(seed) &* 7919)
            var g = SpadesGame(rules: .standard, dealer: .east)
            g.startRound(using: &rng)
            while g.phase == .bidding { try! g.placeBid(ai.chooseBid(g.view(for: g.turn)), for: g.turn) }
            while g.phase == .playing { try! g.play(ai.choosePlay(g.view(for: g.turn)), by: g.turn) }
            for team in Team.allCases {
                let r = g.history[0].teams[team]!
                if r.contract > 0 {
                    total += 1
                    if r.madeContract { made += 1 }
                    bagsTotal += max(0, r.tricksTowardContract - r.contract)
                }
                nilsBid += r.nilOutcomes.count
                nilsMade += r.nilOutcomes.filter(\.made).count
            }
        }
        let rate = Double(made) / Double(total)
        let avgBags = Double(bagsTotal) / Double(total)
        print("AI contract make rate: \(rate), avg overtricks: \(avgBags), nils: \(nilsMade)/\(nilsBid)")
        XCTAssertGreaterThan(rate, 0.6)
        XCTAssertLessThan(avgBags, 2.5)
    }
}

@MainActor
final class ControllerTests: XCTestCase {
    func testControllerRunsUntilHumanActs() async {
        let c = GameController(rules: .standard, pace: .instant)
        var rng = SeededRNG(42)
        c.newGame(rules: .standard, dealer: .north, rng: &rng)
        await c.waitUntilIdle()
        // Dealer is North, so East bids first, then it's South's turn.
        XCTAssertTrue(c.isHumanTurnToBid)
        XCTAssertEqual(c.game.bids.count, 1)
        c.bid(c.suggestedBid!)
        await c.waitUntilIdle()
        // Everyone has bid; play continues until South must play.
        XCTAssertEqual(c.game.phase, .playing)
        XCTAssertTrue(c.isHumanTurnToPlay)
    }

    func testControllerPlaysWholeRoundWithHints() async {
        let c = GameController(rules: .standard, pace: .instant)
        var rng = SeededRNG(7)
        c.newGame(rules: .standard, dealer: .east, rng: &rng)
        await c.waitUntilIdle()
        c.bid(c.suggestedBid!)
        await c.waitUntilIdle()
        var guardCount = 0
        while c.game.phase == .playing && guardCount < 20 {
            c.play(c.hint!)
            await c.waitUntilIdle()
            guardCount += 1
        }
        XCTAssertNotNil(c.lastRoundResult)
        XCTAssertTrue(c.showingRoundSummary)
        XCTAssertTrue(c.humanHand.isEmpty)
    }

    func testBlindNilDecisionHidesHand() async {
        var rules = HouseRules()
        rules.blindNilAllowed = true
        rules.blindNilMinDeficit = 0
        let c = GameController(rules: rules, pace: .instant)
        var rng = SeededRNG(3)
        c.newGame(rules: rules, dealer: .east, rng: &rng)
        await c.waitUntilIdle()
        XCTAssertTrue(c.awaitingBlindNilDecision)
        XCTAssertFalse(c.humanHandRevealed)
        XCTAssertFalse(c.isHumanTurnToBid)
        c.decideBlindNil(false)
        XCTAssertTrue(c.humanHandRevealed)
        XCTAssertTrue(c.isHumanTurnToBid)
    }
}
