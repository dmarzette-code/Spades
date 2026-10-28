import Foundation
import Observation
import SpadesEngine

/// User preferences, persisted to UserDefaults.
@MainActor
@Observable
final class AppSettings {
    var rules: HouseRules { didSet { save(rules, "rules") } }
    var pace: Pace { didSet { save(pace, "pace") } }
    /// Play a card with one tap instead of tap-to-lift, tap-to-play.
    var oneTapPlay: Bool { didSet { UserDefaults.standard.set(oneTapPlay, forKey: "oneTapPlay") } }
    var showBidSuggestion: Bool { didSet { UserDefaults.standard.set(showBidSuggestion, forKey: "showBidSuggestion") } }
    var gamesWon: Int { didSet { UserDefaults.standard.set(gamesWon, forKey: "gamesWon") } }
    var gamesPlayed: Int { didSet { UserDefaults.standard.set(gamesPlayed, forKey: "gamesPlayed") } }

    init() {
        let d = UserDefaults.standard
        rules = d.data(forKey: "rules").flatMap(HouseRules.decodeLeniently) ?? .standard
        pace = Self.load("pace") ?? .normal
        oneTapPlay = d.bool(forKey: "oneTapPlay")
        showBidSuggestion = d.object(forKey: "showBidSuggestion") as? Bool ?? true
        gamesWon = d.integer(forKey: "gamesWon")
        gamesPlayed = d.integer(forKey: "gamesPlayed")
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
