import Foundation

/// Seats in clockwise play order. South is the human; North is their partner.
public enum Seat: Int, CaseIterable, Codable, Hashable, Sendable {
    case south, west, north, east

    public var next: Seat { Seat(rawValue: (rawValue + 1) % 4)! }
    public var partner: Seat { Seat(rawValue: (rawValue + 2) % 4)! }
    public var team: Team { rawValue % 2 == 0 ? .us : .them }

    public var name: String {
        switch self {
        case .south: "South"
        case .west: "West"
        case .north: "North"
        case .east: "East"
        }
    }
}

public enum Team: Int, CaseIterable, Codable, Hashable, Sendable {
    case us, them

    public var seats: [Seat] { self == .us ? [.south, .north] : [.west, .east] }
    public var opponent: Team { self == .us ? .them : .us }
}

public enum Bid: Hashable, Codable, Sendable, CustomStringConvertible {
    case tricks(Int)
    case nilBid
    case blindNil

    public var isNil: Bool { self == .nilBid || self == .blindNil }

    /// Tricks this bid contributes to the team contract.
    public var contractTricks: Int {
        if case .tricks(let n) = self { return n }
        return 0
    }

    public var description: String {
        switch self {
        case .tricks(let n): "\(n)"
        case .nilBid: "Nil"
        case .blindNil: "Blind Nil"
        }
    }
}

public struct Play: Hashable, Codable, Sendable {
    public let seat: Seat
    public let card: Card
}

public struct Trick: Hashable, Codable, Sendable {
    public let leader: Seat
    public private(set) var plays: [Play] = []

    public init(leader: Seat) { self.leader = leader }

    public var ledSuit: Suit? { plays.first?.card.suit }
    public var isComplete: Bool { plays.count == 4 }
    public var nextSeat: Seat {
        var s = leader
        for _ in plays { s = s.next }
        return s
    }

    mutating func add(_ card: Card, by seat: Seat) {
        plays.append(Play(seat: seat, card: card))
    }

    public func card(of seat: Seat) -> Card? { plays.first { $0.seat == seat }?.card }

    /// The play currently winning the trick.
    public func winningPlay(_ rules: HouseRules) -> Play? {
        guard var best = plays.first else { return nil }
        for p in plays.dropFirst() where Trick.beats(p.card, best.card, rules: rules) {
            best = p
        }
        return best
    }

    /// Whether `challenger` (played later) beats `current` (the winner so far).
    public static func beats(_ challenger: Card, _ current: Card, rules: HouseRules) -> Bool {
        if challenger.suit == current.suit { return challenger.power(rules) > current.power(rules) }
        return challenger.isTrump
    }
}
