import Foundation

public enum Suit: Int, CaseIterable, Codable, Hashable, Sendable, Comparable {
    case clubs, diamonds, hearts, spades

    public var symbol: String {
        switch self {
        case .clubs: "♣"
        case .diamonds: "♦"
        case .hearts: "♥"
        case .spades: "♠"
        }
    }

    public var name: String {
        switch self {
        case .clubs: "Clubs"
        case .diamonds: "Diamonds"
        case .hearts: "Hearts"
        case .spades: "Spades"
        }
    }

    public var isRed: Bool { self == .diamonds || self == .hearts }

    public static func < (lhs: Suit, rhs: Suit) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum Rank: Int, CaseIterable, Codable, Hashable, Sendable, Comparable {
    case two = 2, three, four, five, six, seven, eight, nine, ten
    case jack, queen, king, ace
    case littleJoker, bigJoker

    public static let standard: [Rank] = Rank.allCases.filter { !$0.isJoker }

    public var isJoker: Bool { self == .littleJoker || self == .bigJoker }

    public var label: String {
        switch self {
        case .jack: "J"
        case .queen: "Q"
        case .king: "K"
        case .ace: "A"
        case .littleJoker, .bigJoker: "★"
        default: String(rawValue)
        }
    }

    public static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A playing card. Jokers are modelled as spades so they are trump everywhere.
public struct Card: Hashable, Codable, Sendable, Identifiable, CustomStringConvertible {
    public let rank: Rank
    public let suit: Suit

    public init(_ rank: Rank, _ suit: Suit) {
        self.rank = rank
        self.suit = rank.isJoker ? .spades : suit
    }

    public static let bigJoker = Card(.bigJoker, .spades)
    public static let littleJoker = Card(.littleJoker, .spades)

    public var id: String { description }
    public var isTrump: Bool { suit == .spades }

    public var description: String {
        switch rank {
        case .bigJoker: "BJ"
        case .littleJoker: "LJ"
        default: rank.label + suit.symbol
        }
    }

    /// Strength of the card within its suit under the given rules.
    public func power(_ rules: HouseRules) -> Int {
        switch rank {
        case .bigJoker: 100
        case .littleJoker: 99
        case .two where suit == .spades && rules.bigDeuce: 98
        default: rank.rawValue
        }
    }
}

public extension Array where Element == Card {
    /// Sorted for display: alternating colors, high to low within suit.
    func sortedForHand(_ rules: HouseRules) -> [Card] {
        let order: [Suit] = [.spades, .hearts, .clubs, .diamonds]
        return sorted { a, b in
            let ai = order.firstIndex(of: a.suit)!, bi = order.firstIndex(of: b.suit)!
            if ai != bi { return ai < bi }
            return a.power(rules) > b.power(rules)
        }
    }
}
