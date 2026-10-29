import Foundation
import SwiftData

// MARK: - Raw data (wiki.json)

struct WikiSpecies: Codable {
    /// gender rate in eighths female, -1 = genderless
    let gr: Int
    /// capture rate
    let cr: Int
    let bh: Int
    let hc: Int
    /// evolution chain id
    let ch: Int
    /// evolves from species
    let from: Int
    /// 0 normal, 1 legendary, 2 mythical
    let leg: Int
    let baby: Bool
    /// genus [de, en]
    let g: [String]?
    /// flavor text per game [de, en]
    let ft: [String: [String]]?
    let evo: [WikiEvo]?
}

struct WikiEvo: Codable, Hashable {
    let vg: Int
    /// trigger: 1 level-up, 2 trade, 3 use item, 4 shed, other = special
    let t: Int
    let lv: Int?
    let it: Int?
    let hi: Int?
    let hp: Int?
    let af: Int?
    let mv: Int?
    let mt: Int?
    let ge: Int?
    let loc: Int?
    let ps: Int?
    let pt: Int?
    let ts: Int?
    let rs: Int?
    let tod: String?
    let rain: Int?
    let ud: Int?
}

struct WikiEncounter: Codable, Hashable {
    /// location id
    let l: Int
    /// encounter methods
    let m: [Int]
    /// level range
    let lv: [Int]
    /// versions ("Sword", "Shield", …)
    let v: [String]
    /// highest encounter rate in %
    let r: Int
    /// Max Raid dens
    let d: [String]?
}

private struct WikiData: Codable {
    let species: [String: WikiSpecies]
    let chains: [String: [[Int]]]
    let hw: [String: [Int]]
    let abilities: [String: [String]]
    let enc: [String: [String: [WikiEncounter]]]
    let locations: [String: [String]]
    let methods: [String: String]
    let evoItems: [String: [String]]
}

// MARK: - Access

final class Wiki {
    static let shared = Wiki()
    private let data: WikiData

    private init() {
        guard let url = Bundle.main.url(forResource: "wiki", withExtension: "json"),
              let raw = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(WikiData.self, from: raw) else {
            fatalError("wiki.json fehlt oder ist kaputt")
        }
        data = decoded
    }

    private func pick(_ pair: [String]?) -> String? {
        guard let pair, pair.count == 2 else { return nil }
        let s = Lang.current == .de ? pair[0] : pair[1]
        return s.isEmpty ? (pair[1].isEmpty ? nil : pair[1]) : s
    }

    func species(_ id: Int) -> WikiSpecies? { data.species[String(id)] }

    func genus(_ species: Int) -> String? { pick(self.species(species)?.g) }

    /// Flavor text for a game. Falls back to the newest other game and tells which one.
    func flavor(species id: Int, game: Game) -> (text: String, from: Game?)? {
        guard let ft = species(id)?.ft else { return nil }
        if let t = pick(ft[game.rawValue]) { return (t, nil) }
        for g in Game.allCases.reversed() where g != game {
            if let t = pick(ft[g.rawValue]) { return (t, g) }
        }
        return nil
    }

    /// Height in m and weight in kg.
    func heightWeight(_ p: DexPokemon) -> (Double, Double)? {
        let v = data.hw[String(p.id)] ?? p.base.flatMap { data.hw[String($0)] }
        guard let v, v.count == 2 else { return nil }
        return (Double(v[0]) / 10, Double(v[1]) / 10)
    }

    func abilityText(_ id: Int) -> String? { pick(data.abilities[String(id)]) }

    func locationName(_ id: Int) -> String { pick(data.locations[String(id)]) ?? "#\(id)" }

    func evoItemName(_ id: Int) -> String {
        pick(data.evoItems[String(id)]) ?? Dex.shared.item(id)?.name ?? "Item #\(id)"
    }

    /// Wild encounters. For cosmetic forms the data of the base form is used (`fromBase` = true).
    func encounters(_ p: DexPokemon, game: Game) -> (list: [WikiEncounter], fromBase: Bool) {
        if let list = data.enc[String(p.id)]?[game.rawValue] { return (list, false) }
        if let base = p.base, p.kind == nil, let list = data.enc[String(base)]?[game.rawValue] { return (list, true) }
        return ([], false)
    }

    func hasEncounterData(for game: Game) -> Bool { game != .sv }

    // MARK: Evolution

    /// Species ids grouped by evolution stage.
    func stages(chain: Int) -> [[Int]] {
        guard let members = data.chains[String(chain)] else { return [] }
        var depth: [Int: Int] = [:]
        let parent = Dictionary(uniqueKeysWithValues: members.map { ($0[0], $0[1]) })
        func d(_ s: Int) -> Int {
            if let v = depth[s] { return v }
            let p = parent[s] ?? 0
            let v = (p == 0 || parent[p] == nil) ? 0 : d(p) + 1
            depth[s] = v
            return v
        }
        members.forEach { _ = d($0[0]) }
        let maxD = depth.values.max() ?? 0
        return (0...maxD).map { level in members.map { $0[0] }.filter { depth[$0] == level }.sorted() }
    }

    /// How a species evolves (from its pre-evolution), for the given game.
    func evolutionText(species id: Int, game: Game) -> String? {
        guard let all = species(id)?.evo, !all.isEmpty else { return nil }
        let valid = all.filter { $0.vg <= game.maxVersionGroup }
        let pool = valid.isEmpty ? all : valid
        let newest = pool.map(\.vg).max() ?? 0
        // the rules of the newest version group that is not newer than the game
        let texts = pool.filter { $0.vg == newest }.map(describe).uniqued()
        return texts.prefix(2).joined(separator: L(" oder ", " or "))
    }

    private func describe(_ e: WikiEvo) -> String {
        let dex = Dex.shared
        var parts: [String] = []
        switch e.t {
        case 1:
            if let lv = e.lv { parts.append("Lv. \(lv)") } else { parts.append(L("Level-Up", "Level up")) }
        case 2:
            parts.append(L("Tausch", "Trade"))
        case 3:
            if let it = e.it { parts.append(evoItemName(it)) } else { parts.append(L("Item", "Item")) }
        case 4:
            parts.append(L("Lv. 20 mit freiem Platz und Pokéball", "Lv. 20 with a free slot and a Poké Ball"))
        default:
            if let lv = e.lv { parts.append("Lv. \(lv)") }
            parts.append(L("Besondere Bedingung", "Special condition"))
        }
        if e.hp != nil { parts.append(L("hohe Freundschaft", "high friendship")) }
        if e.af != nil { parts.append(L("hohe Zuneigung", "high affection")) }
        if let tod = e.tod {
            switch tod {
            case "day": parts.append(L("am Tag", "during the day"))
            case "night": parts.append(L("in der Nacht", "at night"))
            case "dusk": parts.append(L("in der Abenddämmerung", "at dusk"))
            default: break
            }
        }
        if let hi = e.hi { parts.append(L("hält \(evoItemName(hi))", "holding \(evoItemName(hi))")) }
        if let mv = e.mv, let m = dex.move(mv) { parts.append(L("kennt \(m.name)", "knows \(m.name)")) }
        if let mt = e.mt, let t = dex.type(mt) { parts.append(L("kennt eine \(t.name)-Attacke", "knows a \(t.name) move")) }
        if let ge = e.ge { parts.append(ge == 1 ? "♀" : "♂") }
        if let loc = e.loc { parts.append(L("in/bei \(locationName(loc))", "at \(locationName(loc))")) }
        if let ps = e.ps, let p = dex.defaultPokemon(species: ps) { parts.append(L("mit \(p.name) im Team", "with \(p.name) in the party")) }
        if let pt = e.pt, let t = dex.type(pt) { parts.append(L("mit \(t.name)-Pokémon im Team", "with a \(t.name) Pokémon in the party")) }
        if let ts = e.ts, let p = dex.defaultPokemon(species: ts) { parts.append(L("gegen \(p.name)", "for \(p.name)")) }
        if let rs = e.rs {
            parts.append(rs > 0 ? L("Angriff > Verteidigung", "Attack > Defense") : (rs < 0 ? L("Angriff < Verteidigung", "Attack < Defense") : L("Angriff = Verteidigung", "Attack = Defense")))
        }
        if e.rain != nil { parts.append(L("bei Regen", "in the rain")) }
        if e.ud != nil { parts.append(L("Konsole umgedreht", "console upside down")) }
        return parts.joined(separator: ", ")
    }

    // MARK: Encounter methods

    func methodName(_ id: Int) -> String {
        switch id {
        case 1: return L("Im Gras / in Höhlen", "Tall grass / caves")
        case 2: return L("Angel", "Old Rod")
        case 3: return L("Profiangel", "Good Rod")
        case 4: return L("Superangel", "Super Rod")
        case 5: return L("Surfen", "Surfing")
        case 6: return L("Zertrümmerer", "Rock Smash")
        case 7: return L("Kopfnuss an Bäumen", "Headbutt trees")
        case 8: return L("Dunkles Gras", "Dark grass")
        case 9: return L("Raschelndes Gras", "Rustling grass")
        case 10: return L("Staubwolken", "Dust clouds")
        case 11: return L("Brückenschatten", "Bridge shadows")
        case 12: return L("Angeln an dunklen Stellen", "Fishing in dark spots")
        case 13: return L("Surfen an dunklen Stellen", "Surfing in dark spots")
        case 14, 15, 16: return L("Blumenfelder", "Flower fields")
        case 17: return L("Unwegsames Gelände", "Rough terrain")
        case 18: return L("Geschenk", "Gift")
        case 19: return L("Ei als Geschenk", "Gift egg")
        case 20: return L("Feste Begegnung", "Static encounter")
        case 32: return L("Inselscanner", "Island Scan")
        case 33: return L("SOS-Kampf", "SOS battle")
        case 34: return L("Angeln an sprudelnden Stellen", "Fishing at bubbling spots")
        case 35: return L("Beerenbaum", "Berry tree")
        case 36: return L("Tausch mit Person", "In-game trade")
        case 37: return L("SOS-Kampf (sprudelnde Stelle)", "SOS battle (bubbling spot)")
        case 38: return L("Sichtbar in der Spielwelt", "Visible in the overworld")
        case 39: return L("Sichtbar auf dem Wasser", "Visible on water")
        case 40: return L("Am Himmel", "In the sky")
        case 44: return L("Horde (5 Pokémon)", "Horde (5 Pokémon)")
        case 54: return L("Versteckte Grotte", "Hidden Grotto")
        case 56: return L("Aus dem Boden / Sumpf", "From the ground / swamp")
        case 57: return L("Feste Begegnung in der Spielwelt", "Fixed overworld encounter")
        case 58: return L("Feste Begegnung auf dem Wasser", "Fixed encounter on water")
        case 59: return L("Greift beim Wasser an", "Chases you in the water")
        case 60: return L("Dyna-Abenteuer", "Dynamax Adventure")
        case 61: return L("Dyna-Raid", "Max Raid Battle")
        case 62: return L("Aus einer Mülltonne", "From a trash can")
        case 63: return L("Aus einem raschelnden Busch", "From a rustling bush")
        default: return data.methods[String(id)] ?? L("Sonstiges", "Other")
        }
    }

    /// Approximate catch chance at full HP without status (Gen 3–7 formula).
    static func catchChance(rate: Int, ball: Double) -> Double {
        let a = Double(rate) * ball / 3
        if a >= 255 { return 1 }
        let b = 65536 / pow(255 / a, 0.1875)
        return pow(b / 65536, 4)
    }
}

extension Game {
    var versionNames: [String] {
        switch self {
        case .xy: return ["X", "Y"]
        case .sm: return ["Sun", "Moon", "Ultra Sun", "Ultra Moon"]
        case .swsh: return ["Sword", "Shield"]
        case .sv: return ["Scarlet", "Violet"]
        }
    }

    static func localizedVersion(_ v: String) -> String {
        guard Lang.current == .de else { return v }
        switch v {
        case "Sun": return "Sonne"
        case "Moon": return "Mond"
        case "Ultra Sun": return "Ultrasonne"
        case "Ultra Moon": return "Ultramond"
        case "Sword": return "Schwert"
        case "Shield": return "Schild"
        case "Scarlet": return "Karmesin"
        case "Violet": return "Purpur"
        default: return v
        }
    }
}

// MARK: - Favorites

@Model
final class FavoritePokemon {
    var pokemonId: Int = 0
    var shiny: Bool = false
    var addedAt: Date = Date()

    init(pokemonId: Int, shiny: Bool) {
        self.pokemonId = pokemonId
        self.shiny = shiny
    }
}
