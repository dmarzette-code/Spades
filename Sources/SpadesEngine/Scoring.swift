import Foundation

public struct TeamScore: Hashable, Codable, Sendable {
    public var points: Int = 0
    public var bags: Int = 0
    public init(points: Int = 0, bags: Int = 0) {
        self.points = points
        self.bags = bags
    }
}

public struct NilOutcome: Hashable, Codable, Sendable {
    public let seat: Seat
    public let blind: Bool
    public let tricks: Int
    public var made: Bool { tricks == 0 }
    public let points: Int
}

/// Breakdown of how one team scored in a hand, so the UI can explain every point.
public struct TeamRoundResult: Hashable, Codable, Sendable {
    public let team: Team
    public let contract: Int
    public let tricksTowardContract: Int
    public let totalTricks: Int
    public let contractPoints: Int
    public let nilOutcomes: [NilOutcome]
    public let bagsTaken: Int
    public let bagPenaltyCount: Int
    public let bagPenaltyPoints: Int
    public let before: TeamScore
    public let after: TeamScore

    public var madeContract: Bool { contract == 0 || tricksTowardContract >= contract }
    public var delta: Int { after.points - before.points }
}

public struct RoundResult: Hashable, Codable, Sendable {
    public let roundNumber: Int
    public let bids: [Seat: Bid]
    public let tricks: [Seat: Int]
    public let teams: [Team: TeamRoundResult]
}

public enum Scorer {
    public static func score(team: Team, bids: [Seat: Bid], tricks: [Seat: Int],
                             before: TeamScore, rules: HouseRules) -> TeamRoundResult {
        var contract = 0
        var counted = 0
        var bags = 0
        var points = 0
        var nils: [NilOutcome] = []
        var total = 0

        for seat in team.seats {
            let bid = bids[seat] ?? .tricks(0)
            let taken = tricks[seat] ?? 0
            total += taken
            if bid.isNil {
                let value = bid == .blindNil ? rules.blindNilValue : rules.nilValue
                let made = taken == 0
                let p = made ? value : -value
                points += p
                nils.append(NilOutcome(seat: seat, blind: bid == .blindNil, tricks: taken, points: p))
                if rules.nilTricksCountForPartner { counted += taken } else { bags += taken }
            } else {
                contract += bid.contractTricks
                counted += taken
            }
        }

        var contractPoints = 0
        if contract == 0 {
            bags += counted
        } else if counted >= contract {
            contractPoints = 10 * contract
            if rules.doubleForTenPlus && contract >= 10 { contractPoints *= 2 }
            bags += counted - contract
        } else {
            contractPoints = -10 * contract
        }
        points += contractPoints + bags

        var after = TeamScore(points: before.points + points, bags: before.bags)
        var penalties = 0
        if rules.bagsEnabled && rules.bagLimit > 0 {
            after.bags += bags
            while after.bags >= rules.bagLimit {
                after.bags -= rules.bagLimit
                after.points -= rules.bagPenalty
                penalties += 1
            }
        }

        return TeamRoundResult(
            team: team, contract: contract, tricksTowardContract: counted, totalTricks: total,
            contractPoints: contractPoints, nilOutcomes: nils, bagsTaken: bags,
            bagPenaltyCount: penalties, bagPenaltyPoints: penalties * rules.bagPenalty,
            before: before, after: after)
    }
}
