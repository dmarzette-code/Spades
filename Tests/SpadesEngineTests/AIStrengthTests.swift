import Foundation
import XCTest
@testable import SpadesEngine

struct MatchStats {
    var gamesA = 0, gamesB = 0
    var handsPlayed = 0
    var pointsA = 0, pointsB = 0
    var contractsA = 0, madeA = 0
    var nilsA = 0, nilsMadeA = 0

    var winRateA: Double { Double(gamesA) / Double(max(1, gamesA + gamesB)) }
    var makeRateA: Double { Double(madeA) / Double(max(1, contractsA)) }
    var pointsPerHandEdge: Double { Double(pointsA - pointsB) / Double(max(1, handsPlayed)) }
}

enum Arena {
    /// Team A (South/North) vs team B (West/East). Each deal is played twice with the teams swapping
    /// seats, so neither side benefits from better cards.
    static func match(_ a: SpadesAI, _ b: SpadesAI, games: Int, rules: HouseRules = .standard, seed: UInt64 = 1) -> MatchStats {
        var stats = MatchStats()
        for g in 0..<games {
            for swap in [false, true] {
                var rng = SeededRNG(seed &* 1_000_003 &+ UInt64(g))
                let us: SpadesAI = swap ? b : a, them: SpadesAI = swap ? a : b
                let aTeam: Team = swap ? .them : .us
                var game = SpadesGame(rules: rules, dealer: .east)
                for _ in 0..<60 {
                    game.startRound(using: &rng)
                    let ai = { (s: Seat) in s.team == .us ? us : them }
                    while game.phase == .bidding {
                        let v = game.view(for: game.turn)
                        let p = ai(game.turn)
                        try! game.placeBid(v.canBidBlindNil && p.wantsBlindNil(v) ? .blindNil : p.chooseBid(v), for: game.turn)
                    }
                    while game.phase == .playing {
                        try! game.play(ai(game.turn).choosePlay(game.view(for: game.turn)), by: game.turn)
                    }
                    let r = game.history.last!
                    stats.handsPlayed += 1
                    stats.pointsA += r.teams[aTeam]!.delta
                    stats.pointsB += r.teams[aTeam.opponent]!.delta
                    let mine = r.teams[aTeam]!
                    if mine.contract > 0 {
                        stats.contractsA += 1
                        if mine.madeContract { stats.madeA += 1 }
                    }
                    stats.nilsA += mine.nilOutcomes.count
                    stats.nilsMadeA += mine.nilOutcomes.filter(\.made).count
                    if case .gameOver(let winner) = game.phase {
                        if winner == aTeam { stats.gamesA += 1 } else { stats.gamesB += 1 }
                        break
                    }
                }
            }
        }
        return stats
    }
}

final class AIStrengthTests: XCTestCase {
    func testDifficultyLadder() {
        let hardVsMedium = Arena.match(HeuristicAI(.hard), HeuristicAI(.medium), games: 60)
        let mediumVsEasy = Arena.match(HeuristicAI(.medium), HeuristicAI(.easy), games: 60)
        print("hard vs medium: win \(hardVsMedium.winRateA), edge/hand \(hardVsMedium.pointsPerHandEdge)")
        print("medium vs easy: win \(mediumVsEasy.winRateA), edge/hand \(mediumVsEasy.pointsPerHandEdge)")
        XCTAssertGreaterThan(hardVsMedium.pointsPerHandEdge, 0)
        XCTAssertGreaterThan(mediumVsEasy.winRateA, 0.65)
    }

    /// Monte Carlo hard vs the best pure heuristic. Run with SPADES_TUNE=1 (release build recommended).
    func testMonteCarloStrength() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SPADES_TUNE"] != nil)
        let games = Int(ProcessInfo.processInfo.environment["SPADES_GAMES"] ?? "") ?? 20
        let start = Date()
        var mc = MonteCarloAI()
        let mode = ProcessInfo.processInfo.environment["SPADES_MC"] ?? "both"
        mc.simulateBids = mode != "play"
        mc.simulatePlays = mode != "bid"
        let s = Arena.match(mc, HeuristicAI(.hard), games: games)
        let elapsed = Date().timeIntervalSince(start)
        print(String(format: "MC(\(mode)) vs heuristic: games %d-%d win %.3f edge/hand %+.2f make %.3f nils %d/%d  (%.1fs, %.1f ms/hand)",
                     s.gamesA, s.gamesB, s.winRateA, s.pointsPerHandEdge, s.makeRateA, s.nilsMadeA, s.nilsA,
                     elapsed, elapsed * 1000 / Double(s.handsPlayed)))
    }

    /// Parameter sweep used to tune bidding. Run with `SPADES_TUNE=1 swift test --filter Tuning`.
    func testTuningSweep() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SPADES_TUNE"] != nil)
        let baseline = HeuristicAI(tuning: AITuning(bidBias: 0, bidNoise: 0, mistakeRate: 0, remembersCards: true, setsNils: true))
        let games = Int(ProcessInfo.processInfo.environment["SPADES_GAMES"] ?? "") ?? 150
        for bias in [0.0, 0.2, 0.4] {
            for partner in [0.0, 0.3, 0.6, 0.9] {
                for table in [0.0, 0.15, 0.3] {
                    let t = AITuning(bidBias: bias, bidNoise: 0, mistakeRate: 0, remembersCards: true, setsNils: true,
                                     partnerBias: partner, tableAwareness: table)
                    let s = Arena.match(HeuristicAI(tuning: t), baseline, games: games)
                    print(String(format: "bias %.1f partner %.1f table %.2f  win %.3f  edge/hand %+.2f  make %.3f",
                                 bias, partner, table, s.winRateA, s.pointsPerHandEdge, s.makeRateA))
                }
            }
        }
    }
}

final class CalibrationTests: XCTestCase {
    /// How well does the trick estimate predict actual tricks taken? Run with SPADES_TUNE=1.
    func testCalibration() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SPADES_TUNE"] != nil)
        let ai = HeuristicAI(.hard)
        var buckets: [Int: (n: Int, est: Double, actual: Int)] = [:]
        var teamErr: [Int: (n: Int, sum: Int)] = [:]
        for seed in 0..<3000 {
            var rng = SeededRNG(UInt64(seed) &* 31 &+ 5)
            var g = SpadesGame(rules: .standard, dealer: .east)
            g.startRound(using: &rng)
            var est: [Seat: Double] = [:]
            for s in Seat.allCases { est[s] = HeuristicAI.estimateTricks(g.hands[s]!, rules: g.rules) }
            while g.phase == .bidding { try! g.placeBid(ai.chooseBid(g.view(for: g.turn)), for: g.turn) }
            while g.phase == .playing { try! g.play(ai.choosePlay(g.view(for: g.turn)), by: g.turn) }
            for s in Seat.allCases where g.history[0].bids[s]?.isNil == false {
                let b = Int((est[s]! * 2).rounded())
                let cur = buckets[b] ?? (0, 0, 0)
                buckets[b] = (cur.n + 1, cur.est + est[s]!, cur.actual + g.history[0].tricks[s]!)
            }
            for t in Team.allCases {
                let r = g.history[0].teams[t]!
                guard r.nilOutcomes.isEmpty else { continue }
                let cur = teamErr[r.contract] ?? (0, 0)
                teamErr[r.contract] = (cur.n + 1, cur.sum + r.totalTricks)
            }
        }
        for k in buckets.keys.sorted() {
            let v = buckets[k]!
            print(String(format: "est %.1f  n %4d  actual %.2f", v.est / Double(v.n), v.n, Double(v.actual) / Double(v.n)))
        }
        for k in teamErr.keys.sorted() {
            let v = teamErr[k]!
            print(String(format: "team bid %2d  n %4d  took %.2f", k, v.n, Double(v.sum) / Double(v.n)))
        }
    }
}
