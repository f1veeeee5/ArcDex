import Foundation

/// Game guide data (starters, legendaries, way through the region, important trainers) from guide.json.
/// The trainer teams come from Bulbapedia / Serebii (see `sources` of each trainer).
nonisolated struct GuideText: Codable, Hashable {
    let de: String
    let en: String
    @MainActor var text: String { Lang.current == .de ? de : en }
}

nonisolated struct GuidePokemon: Codable, Hashable {
    /// Pokémon id
    let p: Int
    /// level
    let l: Int
    /// move ids (may be empty when the source has none)
    let m: [Int]
    /// ability id
    var a: Int?
    var gmax: Bool?
}

nonisolated struct GuideTeam: Codable, Hashable {
    /// e.g. "You chose Grookey" – nil if there is only one team
    let label: GuideText?
    let team: [GuidePokemon]
}

nonisolated struct GuideTrainer: Codable, Hashable, Identifiable {
    enum Role: String, Codable, CaseIterable {
        case gym, elite, champion, rival, boss
    }

    let id: String
    let name: GuideText
    let role: Role
    let order: Int
    let location: String
    /// type speciality (type id)
    let type: Int?
    /// "sword" / "shield" … when only in one version
    let version: String?
    let double: Bool
    let mission: GuideText?
    let hint: GuideText?
    let teams: [GuideTeam]
    let sources: [String]
    /// Pokémon Showdown trainer sprite name
    var avatar: String?

    /// strongest Pokémon level
    var aceLevel: Int { teams.flatMap(\.team).map(\.l).max() ?? 0 }
}

nonisolated struct GuideLegend: Codable, Hashable {
    let p: Int
    let version: String?
    let note: GuideText?
}

nonisolated struct GuideStop: Codable, Hashable {
    let name: String
    /// trainer id(s) fought here, "a|b" for version-exclusive gym leaders, "cup" for the Champion Cup
    let trainer: String?
    let note: GuideText?
}

nonisolated struct GameGuide: Codable {
    let starters: [Int]
    var legendaries: [GuideLegend]?
    var route: [GuideStop]?
    var trainers: [GuideTrainer]?

    var hasTrainers: Bool { !(trainers ?? []).isEmpty }

    func trainers(_ role: GuideTrainer.Role) -> [GuideTrainer] {
        (trainers ?? []).filter { $0.role == role }.sorted { $0.order < $1.order }
    }

    func trainer(_ id: String) -> GuideTrainer? { trainers?.first { $0.id == id } }
}

private nonisolated struct GuideFile: Codable {
    let games: [String: GameGuide]
}

final class GuideData {
    static let shared = GuideData()
    private let games: [String: GameGuide]

    private init() {
        guard let url = Bundle.main.url(forResource: "guide", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(GuideFile.self, from: data) else {
            games = [:]
            return
        }
        games = file.games
    }

    func guide(for game: Game) -> GameGuide? { games[game.rawValue] }
}

extension GuideTrainer.Role {
    var title: String {
        switch self {
        case .gym: return L("Arenaleiter", "Gym Leaders")
        case .elite: return L("Top 4 / Champion Cup", "Elite Four / Champion Cup")
        case .champion: return L("Champ", "Champion")
        case .rival: return L("Rivalen", "Rivals")
        case .boss: return L("Bosse", "Bosses")
        }
    }

    var icon: String {
        switch self {
        case .gym: return "shield.lefthalf.filled"
        case .elite: return "star.circle.fill"
        case .champion: return "crown.fill"
        case .rival: return "figure.2"
        case .boss: return "bolt.shield.fill"
        }
    }
}

extension Game {
    /// Name of a version for "sword" / "shield" style keys.
    static func versionTitle(_ key: String) -> String {
        switch key {
        case "sword": return L("Schwert", "Sword")
        case "shield": return L("Schild", "Shield")
        default: return key.capitalized
        }
    }
}
