import Foundation
import SwiftData
import SwiftUI

// MARK: - Platform

/// The system a save file is played on. Raw values are stored – never rename existing ones.
enum Platform: String, CaseIterable, Identifiable, Codable {
    case gameBoy, gameBoyColor, gba, ds, threeDS, wiiU, switch1, switch2, emulator, mobile, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gameBoy: return "Game Boy"
        case .gameBoyColor: return "Game Boy Color"
        case .gba: return "Game Boy Advance"
        case .ds: return "Nintendo DS"
        case .threeDS: return "Nintendo 3DS"
        case .wiiU: return "Wii U"
        case .switch1: return "Nintendo Switch"
        case .switch2: return "Nintendo Switch 2"
        case .emulator: return L("Emulator", "Emulator")
        case .mobile: return L("Smartphone", "Phone")
        case .other: return L("Anderes", "Other")
        }
    }

    var shortTitle: String {
        switch self {
        case .gameBoy: return "GB"
        case .gameBoyColor: return "GBC"
        case .gba: return "GBA"
        case .ds: return "DS"
        case .threeDS: return "3DS"
        case .wiiU: return "Wii U"
        case .switch1: return "Switch"
        case .switch2: return "Switch 2"
        case .emulator: return L("Emulator", "Emulator")
        case .mobile: return L("Handy", "Phone")
        case .other: return L("Anderes", "Other")
        }
    }

    var icon: String {
        switch self {
        case .gameBoy, .gameBoyColor, .gba, .ds, .threeDS: return "gamecontroller"
        case .wiiU, .switch1, .switch2: return "gamecontroller.fill"
        case .emulator: return "desktopcomputer"
        case .mobile: return "iphone"
        case .other: return "questionmark.circle"
        }
    }

    /// Platforms that make sense for a game – the original system first, then the usual alternatives.
    static func options(for game: Game) -> [Platform] {
        var list: [Platform]
        switch game.gen {
        case 1: list = [.gameBoy, .gameBoyColor, .threeDS]
        case 2: list = [.gameBoyColor, .threeDS]
        case 3: list = [.gba]
        case 4, 5: list = [.ds]
        case 6, 7: list = game == .lgpe ? [.switch1, .switch2] : [.threeDS]
        default: list = [.switch1, .switch2]
        }
        if game == .champ { list = [.switch1, .switch2, .mobile] }
        return list + [.emulator, .other]
    }

    static func defaultPlatform(for game: Game) -> Platform {
        options(for: game).first ?? .other
    }
}

// MARK: - Save file

@Model
final class Savegame {
    var uuid: UUID = UUID()
    /// Optional name like "Nuzlocke" – the game title is shown when it is empty.
    var name: String = ""
    var gameRaw: String = Game.swsh.rawValue
    var platformRaw: String = Platform.switch1.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \Team.savegame)
    var teams: [Team] = []
    @Relationship(deleteRule: .cascade, inverse: \ShinyHunt.savegame)
    var hunts: [ShinyHunt] = []
    /// "normal", "nuzlocke" or "soulLink"
    var modeRaw: String = RunMode.normal.rawValue
    var rulesData: Data = Data()
    var player1: String = ""
    var player2: String = ""
    @Relationship(deleteRule: .cascade, inverse: \NuzlockeLink.savegame)
    var links: [NuzlockeLink] = []
    /// The local profile this save file belongs to (nil only for data of older app versions, fixed on launch).
    var profileID: UUID?

    init(game: Game, platform: Platform? = nil, name: String = "") {
        self.gameRaw = game.rawValue
        self.platformRaw = (platform ?? Platform.defaultPlatform(for: game)).rawValue
        self.name = name
        // new save files belong to the profile that is active right now
        self.profileID = ProfileStore.activeID
    }

    var game: Game {
        get { Game(rawValue: gameRaw) ?? .swsh }
        set { gameRaw = newValue.rawValue }
    }

    var platform: Platform {
        get { Platform(rawValue: platformRaw) ?? .other }
        set { platformRaw = newValue.rawValue }
    }

    var displayName: String { name.isEmpty ? game.title : name }

    var sortedTeams: [Team] { teams.sorted { $0.updatedAt > $1.updatedAt } }
    var activeHunts: [ShinyHunt] { hunts.filter { !$0.isFound }.sorted { $0.updatedAt > $1.updatedAt } }
    var foundHunts: [ShinyHunt] { hunts.filter(\.isFound).sorted { ($0.foundAt ?? .distantPast) > ($1.foundAt ?? .distantPast) } }

    func touch() { updatedAt = Date() }
}

enum SavegameMigration {
    /// Teams from older app versions get a save file per game, so nothing is lost.
    @MainActor
    static func run(_ context: ModelContext) {
        guard let teams = try? context.fetch(FetchDescriptor<Team>()) else { return }
        let orphans = teams.filter { $0.savegame == nil }
        guard !orphans.isEmpty else { return }
        let saves = (try? context.fetch(FetchDescriptor<Savegame>())) ?? []
        var byGame: [Game: Savegame] = [:]
        for s in saves where byGame[s.game] == nil { byGame[s.game] = s }
        for team in orphans {
            let save: Savegame
            if let existing = byGame[team.game] {
                save = existing
            } else {
                save = Savegame(game: team.game)
                save.createdAt = team.createdAt
                save.updatedAt = team.updatedAt
                context.insert(save)
                byGame[team.game] = save
            }
            team.savegame = save
            if team.updatedAt > save.updatedAt { save.updatedAt = team.updatedAt }
        }
        try? context.save()
    }
}

// MARK: - Shiny hunt

/// A shiny that appeared during a hunt but was not the target ("phase").
struct HuntPhase: Codable, Hashable, Identifiable {
    var id = UUID()
    /// Total encounter count when the phase happened.
    var count: Int
    var pokemonId: Int?
    var date: Date = Date()
}

@Model
final class ShinyHunt {
    var uuid: UUID = UUID()
    var pokemonId: Int = 25
    var methodRaw: String = HuntMethod.encounter.rawValue
    var count: Int = 0
    /// How much the big button adds (e.g. 5 for horde encounters).
    var step: Int = 1
    var shinyCharm: Bool = false
    /// Sparkling Power level (Scarlet/Violet, Legends: Z-A): 0–3
    var sparklingPower: Int = 0
    /// Pokédex research in Legends: Arceus: 0 = none, 1 = level 10, 2 = perfect
    var research: Int = 0
    /// Scarlet/Violet outbreak: 0 = under 30 defeated, 1 = 30–59, 2 = 60+
    var outbreakTier: Int = 0
    /// Let's Go: lure active
    var lure: Bool = false
    /// Own odds "1 in N" for the custom method.
    var customOdds: Int = 4096
    var startedAt: Date = Date()
    var updatedAt: Date = Date()
    var foundAt: Date?
    /// Seconds counted while the timer was stopped before.
    var elapsed: Double = 0
    /// Set while the timer is running.
    var timerStartedAt: Date?
    var phasesData: Data = Data()
    var notes: String = ""
    var savegame: Savegame?
    /// Catch proof: photo or video taken with the app camera within 24 h after the find (file name in Documents/ShinyProof)
    var proofFile: String?
    var proofIsVideo: Bool = false
    var proofTakenAt: Date?

    init(pokemonId: Int, method: HuntMethod) {
        self.pokemonId = pokemonId
        self.methodRaw = method.rawValue
    }

    var method: HuntMethod {
        get { HuntMethod(rawValue: methodRaw) ?? .encounter }
        set { methodRaw = newValue.rawValue }
    }

    var game: Game { savegame?.game ?? .swsh }
    var isFound: Bool { foundAt != nil }
    var species: DexPokemon? { Dex.shared.pokemon(pokemonId) }
    var name: String { species?.name ?? "?" }

    var phases: [HuntPhase] {
        get { (try? JSONDecoder().decode([HuntPhase].self, from: phasesData)) ?? [] }
        set { phasesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// Encounters since the last phase.
    var countInPhase: Int { count - (phases.last?.count ?? 0) }

    var timerRunning: Bool { timerStartedAt != nil }

    func totalTime(at date: Date = Date()) -> TimeInterval {
        elapsed + (timerStartedAt.map { date.timeIntervalSince($0) } ?? 0)
    }

    func startTimer() { if timerStartedAt == nil { timerStartedAt = Date() } }
    func stopTimer() {
        if let start = timerStartedAt { elapsed += Date().timeIntervalSince(start) }
        timerStartedAt = nil
    }

    func add(_ amount: Int) {
        count = max(0, count + amount)
        updatedAt = Date()
        savegame?.touch()
    }

    func markFound() {
        stopTimer()
        foundAt = Date()
        updatedAt = Date()
    }

    var odds: ShinyOdds { ShinyOdds(hunt: self) }
}

// MARK: - Methods

enum HuntMethod: String, CaseIterable, Identifiable, Codable {
    case encounter, softReset, egg, masuda, sos, catchCombo, outbreak, dynamaxAdventure, plaOutbreak, plaMassiveOutbreak, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .encounter: return L("Zufallsbegegnung", "Random encounters")
        case .softReset: return L("Soft Reset", "Soft resets")
        case .egg: return L("Eier ausbrüten", "Hatching eggs")
        case .masuda: return L("Masuda-Methode", "Masuda method")
        case .sos: return L("SOS-Kette", "SOS chain")
        case .catchCombo: return L("Fang-Kombo", "Catch combo")
        case .outbreak: return L("Massenausbruch", "Mass outbreak")
        case .dynamaxAdventure: return L("Dyna-Raid-Abenteuer", "Dynamax Adventure")
        case .plaOutbreak: return L("Massenvorkommen", "Mass outbreak")
        case .plaMassiveOutbreak: return L("Massives Massenvorkommen", "Massive mass outbreak")
        case .custom: return L("Eigene Chance", "Custom odds")
        }
    }

    var icon: String {
        switch self {
        case .encounter: return "leaf.fill"
        case .softReset: return "arrow.counterclockwise"
        case .egg, .masuda: return "oval.portrait.fill"
        case .sos: return "phone.fill"
        case .catchCombo: return "link"
        case .outbreak, .plaOutbreak, .plaMassiveOutbreak: return "circle.hexagongrid.fill"
        case .dynamaxAdventure: return "flag.checkered"
        case .custom: return "slider.horizontal.3"
        }
    }

    /// What one count means – shown under the counter.
    var unit: String {
        switch self {
        case .encounter, .outbreak, .plaOutbreak, .plaMassiveOutbreak: return L("Begegnungen", "Encounters")
        case .softReset: return L("Resets", "Resets")
        case .egg, .masuda: return L("Eier", "Eggs")
        case .sos: return L("Kettenlänge", "Chain length")
        case .catchCombo: return L("Kombo", "Combo")
        case .dynamaxAdventure: return L("Abenteuer", "Adventures")
        case .custom: return L("Versuche", "Attempts")
        }
    }

    /// The odds grow with the counter (chain methods).
    var isChain: Bool { self == .sos || self == .catchCombo }

    static func available(in game: Game) -> [HuntMethod] {
        var list: [HuntMethod] = [.encounter, .softReset]
        if game.hasBreeding { list.append(.egg) }
        if game.hasMasuda { list.append(.masuda) }
        switch game {
        case .sm: list.append(.sos)
        case .lgpe: list.append(.catchCombo)
        case .sv: list.append(.outbreak)
        case .swsh: list.append(.dynamaxAdventure)
        case .pla: list += [.plaOutbreak, .plaMassiveOutbreak]
        default: break
        }
        list.append(.custom)
        return list
    }
}

extension Game {
    /// Shiny hunting makes sense here (Gen 1 has no shinies, Champions has no wild Pokémon).
    var hasShinyHunting: Bool { hasShiny && self != .champ }
    var hasBreeding: Bool { gen >= 2 && ![.lgpe, .pla, .za, .champ].contains(self) }
    var hasMasuda: Bool { gen >= 4 && hasBreeding }
    var hasShinyCharm: Bool { [.b2w2, .xy, .oras, .sm, .lgpe, .swsh, .bdsp, .pla, .sv, .za].contains(self) }
    var hasSparklingPower: Bool { self == .sv || self == .za }
    /// Base odds 1 in …
    var baseShinyOdds: Double { gen >= 6 ? 4096 : 8192 }
}

// MARK: - Odds

/// Shiny odds as "rolls": every roll is one try with the base odds.
/// Sources for the bonus rolls: Bulbapedia / Serebii / RotomLabs shiny rate tables.
struct ShinyOdds {
    let game: Game
    let method: HuntMethod
    let charm: Bool
    let sparklingPower: Int
    let research: Int
    let outbreakTier: Int
    let lure: Bool
    let customOdds: Int

    init(game: Game, method: HuntMethod, charm: Bool, sparklingPower: Int = 0, research: Int = 0,
         outbreakTier: Int = 0, lure: Bool = false, customOdds: Int = 4096) {
        self.game = game
        self.method = method
        self.charm = charm && game.hasShinyCharm
        self.sparklingPower = game.hasSparklingPower ? sparklingPower : 0
        self.research = game == .pla ? research : 0
        self.outbreakTier = outbreakTier
        self.lure = lure
        self.customOdds = max(1, customOdds)
    }

    init(hunt: ShinyHunt) {
        self.init(game: hunt.game, method: hunt.method, charm: hunt.shinyCharm, sparklingPower: hunt.sparklingPower,
                  research: hunt.research, outbreakTier: hunt.outbreakTier, lure: hunt.lure, customOdds: hunt.customOdds)
    }

    private var charmRolls: Int {
        guard charm else { return 0 }
        return (game == .pla || game == .za) ? 3 : 2
    }

    /// Number of rolls for the given counter value (chains get better the longer they are).
    func rolls(at count: Int) -> Int {
        var r = 1 + charmRolls
        switch method {
        case .masuda:
            r += game.gen == 4 ? 4 : 5
        case .sos:
            if count >= 31 { r += 12 } else if count >= 21 { r += 8 } else if count >= 11 { r += 4 }
        case .catchCombo:
            if count >= 31 { r += 11 } else if count >= 21 { r += 7 } else if count >= 11 { r += 3 }
            if lure { r += 1 }
        case .outbreak:
            r += min(max(outbreakTier, 0), 2)
        case .plaOutbreak: r += 25
        case .plaMassiveOutbreak: r += 12
        default: break
        }
        r += sparklingPower
        if game == .pla { r += research >= 2 ? 3 : (research >= 1 ? 1 : 0) }
        return r
    }

    /// Chance per encounter (0–1).
    func probability(at count: Int) -> Double {
        switch method {
        case .custom: return 1 / Double(customOdds)
        case .dynamaxAdventure: return charm ? 1.0 / 100 : 1.0 / 300
        default:
            return 1 - pow(1 - 1 / game.baseShinyOdds, Double(rolls(at: count)))
        }
    }

    /// "1 in N" for the current counter value.
    func oneIn(at count: Int) -> Double { 1 / probability(at: count) }

    /// Chance that at least one shiny should have appeared after `count` tries.
    func cumulative(after count: Int) -> Double {
        guard count > 0 else { return 0 }
        if !method.isChain {
            return 1 - pow(1 - probability(at: count), Double(count))
        }
        var logMiss = 0.0
        for i in 1...count { logMiss += log(1 - probability(at: i)) }
        return 1 - exp(logMiss)
    }

    /// Text like "1/4096" or "1/1365,3".
    func label(at count: Int) -> String { ShinyOdds.format(oneIn(at: count)) }

    static func format(_ n: Double) -> String {
        let rounded = (n * 10).rounded() / 10
        let value = rounded == rounded.rounded() ? String(Int(rounded)) : rounded.formatted(.number.precision(.fractionLength(1)).locale(Lang.current.locale))
        return "1/" + value
    }
}
