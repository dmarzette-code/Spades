import Foundation

/// Every table plays Spades a little differently. All of it is configurable here.
public struct HouseRules: Codable, Equatable, Hashable, Sendable {
    // Game length
    public var winningScore: Int = 500
    public var mercyRuleEnabled: Bool = true
    public var losingScore: Int = -200

    // Nil
    public var nilAllowed: Bool = true
    public var nilValue: Int = 100
    public var blindNilAllowed: Bool = false
    public var blindNilValue: Int = 200
    /// A team must be behind by at least this much to bid blind nil.
    public var blindNilMinDeficit: Int = 100
    /// When true, tricks taken by a failed nil count toward the partner's bid.
    public var nilTricksCountForPartner: Bool = false

    // Bags
    public var bagsEnabled: Bool = true
    public var bagLimit: Int = 10
    public var bagPenalty: Int = 100

    // Bidding
    /// "The board": a team's combined bid must be at least this many tricks (0 = off).
    public var minimumTeamBid: Int = 0
    /// Making a team bid of 10 or more scores double.
    public var doubleForTenPlus: Bool = false

    // Play
    public var spadesMustBeBroken: Bool = true
    /// The holder of the lowest club leads the first trick instead of the player left of the dealer.
    public var lowClubLeads: Bool = false
    /// Adds Big & Little Jokers as the top two trumps (2♣ and 2♥ are removed).
    public var jokersEnabled: Bool = false
    /// The 2♠ ranks above the A♠ (below any jokers).
    public var bigDeuce: Bool = false

    public init() {}

    public static let standard = HouseRules()

    public static let tournament: HouseRules = {
        var r = HouseRules()
        r.blindNilAllowed = false
        r.mercyRuleEnabled = false
        return r
    }()

    public static let jokersAndDeuces: HouseRules = {
        var r = HouseRules()
        r.jokersEnabled = true
        r.bigDeuce = true
        r.blindNilAllowed = true
        r.minimumTeamBid = 4
        return r
    }()

    public static let quickGame: HouseRules = {
        var r = HouseRules()
        r.winningScore = 250
        r.losingScore = -100
        return r
    }()

    public static let presets: [(name: String, rules: HouseRules)] = [
        ("Standard", .standard),
        ("Quick (250)", .quickGame),
        ("Jokers & Big Deuce", .jokersAndDeuces),
        ("No Mercy", .tournament),
    ]

    /// Decodes saved rules, filling in defaults for any setting added since they were saved.
    public static func decodeLeniently(_ data: Data) -> HouseRules? {
        guard let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let defaults = try? JSONEncoder().encode(HouseRules()),
              let base = (try? JSONSerialization.jsonObject(with: defaults)) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: base.merging(saved) { _, new in new })
        else { return nil }
        return try? JSONDecoder().decode(HouseRules.self, from: merged)
    }

    /// The cards used under these rules.
    public var deck: [Card] {
        var cards: [Card] = []
        for suit in Suit.allCases {
            for rank in Rank.standard {
                if jokersEnabled, rank == .two, suit == .clubs || suit == .hearts { continue }
                cards.append(Card(rank, suit))
            }
        }
        if jokersEnabled { cards += [.bigJoker, .littleJoker] }
        return cards
    }

    /// Short human-readable list of what's unusual about this table.
    public var highlights: [String] {
        var items: [String] = ["To \(winningScore)"]
        if !nilAllowed { items.append("No nil") }
        if blindNilAllowed { items.append("Blind nil") }
        if bagsEnabled { items.append("\(bagLimit) bags = −\(bagPenalty)") } else { items.append("No bag penalty") }
        if jokersEnabled { items.append("Jokers") }
        if bigDeuce { items.append("Big deuce") }
        if minimumTeamBid > 0 { items.append("Board \(minimumTeamBid)") }
        if doubleForTenPlus { items.append("10-for-200") }
        if !spadesMustBeBroken { items.append("Lead ♠ anytime") }
        if mercyRuleEnabled { items.append("Mercy \(losingScore)") }
        return items
    }
}
