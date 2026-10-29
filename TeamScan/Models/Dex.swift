import Foundation

struct DexType: Codable, Identifiable, Hashable, Bilingual {
    let id: Int
    let key: String
    let de: String
    let en: String
}

struct DexAbility: Codable, Identifiable, Hashable, Bilingual {
    let id: Int
    let key: String
    let de: String
    let en: String
}

struct DexMove: Codable, Identifiable, Hashable, Bilingual {
    let id: Int
    let key: String
    let de: String
    let en: String
    /// type id
    let t: Int
    /// damage class: 1 status, 2 physical, 3 special
    let c: Int
    /// power
    let p: Int
    /// accuracy
    let a: Int
    let pp: Int
    /// priority
    let pr: Int
    /// generation introduced
    let g: Int

    var isDamaging: Bool { c != 1 }
    var isPhysical: Bool { c == 2 }
    var isSpecial: Bool { c == 3 }
}

struct DexNature: Codable, Identifiable, Hashable, Bilingual {
    let id: Int
    let key: String
    let de: String
    let en: String
    /// increased stat id (2 atk … 6 spe)
    let up: Int
    /// decreased stat id
    let down: Int
    var isNeutral: Bool { up == down }
}

struct DexItem: Codable, Identifiable, Hashable, Bilingual {
    let id: Int
    let key: String
    let de: String
    let en: String
    let cat: Int
    let gens: [Int]

    var isMegaStone: Bool { cat == 44 }
    var isZCrystal: Bool { cat == 46 }
}

struct DexPokemon: Codable, Identifiable, Hashable, Bilingual {
    let id: Int
    /// species id (national dex number)
    let sp: Int
    /// species identifier
    let sk: String
    /// default form of the species
    let def: Bool
    let key: String
    let de: String
    let en: String
    /// type ids
    let t: [Int]
    /// base stats hp, atk, def, spa, spd, spe
    let s: [Int]
    /// regular abilities
    let ab: [Int]
    /// hidden ability (0 = none)
    let ha: Int
    /// for battle-only forms (mega / gmax / primal): the pokemon they come from
    let base: Int?
    let vg: Int?
    /// "mega", "gmax", "primal" or nil
    let kind: String?
    /// mega stone item id
    let stone: Int?
    /// sprite file name for alternate forms that share one PokéAPI entry (e.g. "423-east")
    let img: String?
    /// types in earlier generations: "5" = types up to Gen 5
    let tp: [String: [Int]]?
    /// abilities in earlier generations: [last gen, slot, ability id (0 = none)]
    let abp: [[Int]]?

    /// Types as they were in a given generation (e.g. Clefairy was Normal before Gen 6).
    func types(gen: Int) -> [Int] {
        guard let tp else { return t }
        let candidates = tp.compactMap { k, v -> (Int, [Int])? in
            guard let g = Int(k), g >= gen else { return nil }
            return (g, v)
        }
        return candidates.min { $0.0 < $1.0 }?.1 ?? t
    }

    /// Regular abilities (slot 1, 2) and hidden ability (slot 3) in a generation.
    func abilitySlots(gen: Int) -> (regular: [Int], hidden: Int) {
        var slots: [Int: Int] = [:]
        for (i, a) in ab.enumerated() { slots[i + 1] = a }
        if ha != 0 { slots[3] = ha }
        if let abp {
            var bySlot: [Int: (Int, Int)] = [:]
            for e in abp where e.count == 3 && e[0] >= gen {
                if let cur = bySlot[e[1]], cur.0 <= e[0] { continue }
                bySlot[e[1]] = (e[0], e[2])
            }
            for (slot, v) in bySlot { slots[slot] = v.1 == 0 ? nil : v.1 }
        }
        if gen < 5 { slots[3] = nil }
        let regular = [slots[1], slots[2]].compactMap { $0 }
        return (regular, slots[3] ?? 0)
    }

    /// Sprite file names to try, most specific first.
    var spriteKeys: [String] {
        var keys: [String] = []
        if let img { keys.append(img) }
        if id < 20000 { keys.append(String(id)) }
        if let base { keys.append(String(base)) }
        return keys
    }

    var isBattleForm: Bool { kind != nil }
    var dexNumber: String { String(format: "#%04d", sp) }
}

private struct DexData: Codable {
    let typePast: [[Int]]
    let types: [DexType]
    let abilities: [DexAbility]
    let moves: [DexMove]
    let natures: [DexNature]
    let items: [DexItem]
    let pokemon: [DexPokemon]
    let learnsets: [String: [String: [Int]]]
    let dex: [String: [Int]]
}

/// All Pokémon data (German + English), loaded once from the bundled JSON.
final class Dex {
    static let shared = Dex()

    let types: [DexType]
    let moves: [DexMove]
    let items: [DexItem]
    let abilities: [DexAbility]
    let natures: [DexNature]
    let pokemon: [DexPokemon]

    private let typeById: [Int: DexType]
    private let moveById: [Int: DexMove]
    private let itemById: [Int: DexItem]
    private let abilityById: [Int: DexAbility]
    private let natureById: [Int: DexNature]
    private let pokemonById: [Int: DexPokemon]
    private let abilityByKey: [String: DexAbility]
    private let learnsets: [Game: [Int: [Int]]]
    private let dexLists: [Game: [Int]]
    private let battleForms: [Int: [DexPokemon]]
    private let speciesDefault: [Int: Int]
    private var availableCache: [Game: [DexPokemon]] = [:]
    private var itemCache: [Game: [DexItem]] = [:]

    private init() {
        guard let url = Bundle.main.url(forResource: "pokedata", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("pokedata.json fehlt im Bundle")
        }
        let raw: DexData
        do {
            raw = try JSONDecoder().decode(DexData.self, from: data)
        } catch {
            fatalError("pokedata.json konnte nicht gelesen werden: \(error)")
        }
        types = raw.types
        TypeChart.pastOverrides = raw.typePast
        moves = raw.moves
        items = raw.items
        abilities = raw.abilities
        natures = raw.natures
        pokemon = raw.pokemon

        typeById = Dictionary(uniqueKeysWithValues: raw.types.map { ($0.id, $0) })
        moveById = Dictionary(uniqueKeysWithValues: raw.moves.map { ($0.id, $0) })
        itemById = Dictionary(uniqueKeysWithValues: raw.items.map { ($0.id, $0) })
        abilityById = Dictionary(uniqueKeysWithValues: raw.abilities.map { ($0.id, $0) })
        natureById = Dictionary(uniqueKeysWithValues: raw.natures.map { ($0.id, $0) })
        pokemonById = Dictionary(uniqueKeysWithValues: raw.pokemon.map { ($0.id, $0) })
        abilityByKey = Dictionary(uniqueKeysWithValues: raw.abilities.map { ($0.key, $0) })

        var ls: [Game: [Int: [Int]]] = [:]
        var dl: [Game: [Int]] = [:]
        for game in Game.allCases {
            var map: [Int: [Int]] = [:]
            for (k, v) in raw.learnsets[game.rawValue] ?? [:] {
                if let id = Int(k) { map[id] = v }
            }
            ls[game] = map
            dl[game] = raw.dex[game.rawValue] ?? []
        }
        learnsets = ls
        dexLists = dl

        var forms: [Int: [DexPokemon]] = [:]
        var defaults: [Int: Int] = [:]
        for p in raw.pokemon {
            if let base = p.base, p.isBattleForm { forms[base, default: []].append(p) }
            if p.def { defaults[p.sp] = p.id }
        }
        battleForms = forms
        speciesDefault = defaults
    }

    // MARK: Lookups

    func type(_ id: Int) -> DexType? { typeById[id] }
    func move(_ id: Int) -> DexMove? { moveById[id] }
    func item(_ id: Int) -> DexItem? { itemById[id] }
    func ability(_ id: Int) -> DexAbility? { abilityById[id] }
    func ability(key: String) -> DexAbility? { abilityByKey[key] }
    func nature(_ id: Int) -> DexNature? { natureById[id] }
    func pokemon(_ id: Int) -> DexPokemon? { pokemonById[id] }

    /// The 18 battle types (without Stellar).
    var battleTypes: [DexType] { types.filter { $0.id <= 18 } }

    /// Types that existed in a generation (no Dark/Steel in Gen 1, no Fairy before Gen 6).
    func battleTypes(gen: Int) -> [DexType] {
        battleTypes.filter { t in
            if gen < 2 && (t.id == T.dark || t.id == T.steel) { return false }
            if gen < 6 && t.id == T.fairy { return false }
            return true
        }
    }

    /// Tera types incl. Stellar.
    var teraTypes: [DexType] { types.filter { $0.id <= 19 } }

    // MARK: Game specific

    /// All Pokémon (incl. regional / alternate forms, without battle-only forms) that exist in a game.
    func availablePokemon(in game: Game) -> [DexPokemon] {
        if let cached = availableCache[game] { return cached }
        let ids = Set(dexLists[game] ?? [])
        let list = pokemon.filter { ids.contains($0.id) }.sorted { ($0.sp, $0.id) < ($1.sp, $1.id) }
        availableCache[game] = list
        return list
    }

    func isAvailable(_ pokemonId: Int, in game: Game) -> Bool {
        learnsets[game]?[pokemonId] != nil
    }

    /// Moves the Pokémon can learn in this game. Falls back to the base form and then to all moves of the generation.
    func learnset(for pokemonId: Int, game: Game) -> [DexMove] {
        let table = learnsets[game] ?? [:]
        var ids = table[pokemonId]
        if ids == nil, let p = pokemon(pokemonId) {
            if let base = p.base { ids = table[base] }
            if ids == nil, let def = speciesDefault[p.sp] { ids = table[def] }
        }
        if let ids, !ids.isEmpty {
            return ids.compactMap { moveById[$0] }.sorted { $0.name < $1.name }
        }
        return moves.filter { $0.g <= game.gen }.sorted { $0.name < $1.name }
    }

    func allMoves(for game: Game) -> [DexMove] {
        moves.filter { $0.g <= game.gen }.sorted { $0.name < $1.name }
    }

    /// Mega (and primal) forms usable in this game.
    func megaForms(for pokemonId: Int, game: Game) -> [DexPokemon] {
        guard game.hasMega else { return [] }
        return (battleForms[pokemonId] ?? []).filter {
            ($0.kind == "mega" || $0.kind == "primal") && ($0.vg ?? 99) <= game.maxVersionGroup
        }
    }

    func gmaxForm(for pokemonId: Int, game: Game) -> DexPokemon? {
        guard game.hasDynamax else { return nil }
        return (battleForms[pokemonId] ?? []).first { $0.kind == "gmax" }
    }

    func items(for game: Game) -> [DexItem] {
        guard game.hasHeldItems else { return [] }
        if let cached = itemCache[game] { return cached }
        let list = items.filter { item in
            if item.isMegaStone && !game.hasMega { return false }
            if item.isZCrystal && !game.hasZMoves { return false }
            return item.gens.isEmpty || item.gens.contains(where: { $0 <= game.gen })
        }.sorted { $0.name < $1.name }
        itemCache[game] = list
        return list
    }

    private var dexSets: [Game: Set<Int>] = [:]

    /// Whether a Pokémon (incl. battle forms) appears in a game.
    func appears(_ pokemonId: Int, in game: Game) -> Bool {
        guard let p = pokemon(pokemonId) else { return false }
        switch p.kind {
        case "mega", "primal":
            guard game.hasMega, (p.vg ?? 99) <= game.maxVersionGroup else { return false }
            // the base form must be a normal form – never recurse into another battle form
            var baseId = p.base ?? 0
            if baseId == p.id || pokemon(baseId)?.isBattleForm != false {
                baseId = speciesDefault[p.sp] ?? 0
            }
            guard baseId != p.id, pokemon(baseId)?.isBattleForm == false else { return false }
            return appears(baseId, in: game)
        case "gmax":
            return game.hasDynamax
        default:
            if dexSets[game] == nil { dexSets[game] = Set(dexLists[game] ?? []) }
            return dexSets[game]?.contains(pokemonId) ?? false
        }
    }

    func games(for pokemonId: Int) -> [Game] {
        Game.allCases.filter { appears(pokemonId, in: $0) }
    }

    func defaultPokemon(species: Int) -> DexPokemon? {
        speciesDefault[species].flatMap { pokemon($0) }
    }

    /// All forms of a species (regional, cosmetic, mega, gigantamax …), default first.
    func forms(ofSpecies species: Int) -> [DexPokemon] {
        if formsCache.isEmpty {
            formsCache = Dictionary(grouping: pokemon, by: \.sp)
        }
        return (formsCache[species] ?? []).sorted { ($0.def ? 0 : 1, $0.id) < ($1.def ? 0 : 1, $1.id) }
    }
    private var formsCache: [Int: [DexPokemon]] = [:]

    func abilities(for p: DexPokemon, gen: Int) -> [DexAbility] {
        let slots = p.abilitySlots(gen: gen)
        var ids = slots.regular
        if slots.hidden != 0 { ids.append(slots.hidden) }
        var seen = Set<Int>()
        return ids.filter { seen.insert($0).inserted }.compactMap { abilityById[$0] }
    }

    func abilities(for p: DexPokemon) -> [DexAbility] {
        var ids = p.ab
        if p.ha != 0 { ids.append(p.ha) }
        var seen = Set<Int>()
        return ids.filter { seen.insert($0).inserted }.compactMap { abilityById[$0] }
    }
}
