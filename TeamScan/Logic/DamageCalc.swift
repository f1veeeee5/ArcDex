import Foundation

/// One side of a damage calculation: a Pokémon with real stats, ability, item and moves.
struct Combatant: Equatable {
    var pokemonId: Int
    var level: Int
    /// HP, Atk, Def, SpA, SpD, Spe (real values)
    var stats: [Int]
    var types: [Int]
    var abilityKey: String?
    var itemKey: String?
    var moves: [DexMove]
    var shiny = false

    var name: String { Dex.shared.pokemon(pokemonId)?.name ?? "?" }

    /// A team member with its EVs, IVs, nature, ability, item and moves.
    static func member(_ m: TeamMember, game: Game) -> Combatant? {
        guard let p = m.battleForm(in: game) ?? m.species else { return nil }
        return Combatant(pokemonId: p.id, level: m.level,
                         stats: (0..<6).map { m.stat($0, base: p.s[$0], level: m.level, game: game) },
                         types: m.types(in: game), abilityKey: m.ability?.key,
                         itemKey: game.hasHeldItems ? m.item?.key : nil, moves: m.moves, shiny: m.shiny)
    }

    /// In-game trainer Pokémon: no EVs, average IVs, neutral nature (the real values differ per game).
    static func trainer(_ g: GuidePokemon, game: Game) -> Combatant? {
        let dex = Dex.shared
        guard let p = dex.pokemon(g.p) else { return nil }
        return Combatant(pokemonId: p.id, level: g.l,
                         stats: (0..<6).map { trainerStat($0, base: p.s[$0], level: g.l) },
                         types: p.types(gen: game.gen),
                         abilityKey: g.a.flatMap { dex.ability($0)?.key } ?? p.ab.first.flatMap { dex.ability($0)?.key },
                         itemKey: nil, moves: g.m.compactMap { dex.move($0) })
    }

    /// Any Pokémon with a moveset suggestion (story or competitive set).
    static func free(pokemonId: Int, level: Int, set: MovesetEntry?, game: Game) -> Combatant? {
        let dex = Dex.shared
        guard let p = dex.pokemon(pokemonId) else { return nil }
        let competitive = set.map { !$0.isStory } ?? false
        let nature = set?.n.flatMap { id in dex.natures.first { $0.id == id } }
        let evs = set?.e ?? [0, 0, 0, 0, 0, 0]
        let stats: [Int] = (0..<6).map { i in
            guard competitive else { return trainerStat(i, base: p.s[i], level: level) }
            let core = (2 * p.s[i] + 31 + (i < evs.count ? evs[i] : 0) / 4) * level / 100
            if i == 0 { return p.s[0] == 1 ? 1 : core + level + 10 }
            var v = Double(core + 5)
            if let n = nature, !n.isNeutral {
                if n.up == i + 1 { v *= 1.1 }
                if n.down == i + 1 { v *= 0.9 }
            }
            return Int(v)
        }
        return Combatant(pokemonId: p.id, level: level, stats: stats, types: p.types(gen: game.gen),
                         abilityKey: (set?.a).flatMap { dex.ability($0)?.key } ?? p.ab.first.flatMap { dex.ability($0)?.key },
                         itemKey: competitive ? (set?.i).flatMap { dex.item($0)?.key } : nil,
                         moves: (set?.m ?? []).compactMap { dex.move($0) })
    }

    static func trainerStat(_ i: Int, base: Int, level: Int) -> Int {
        let core = (2 * base + 20) * level / 100
        return i == 0 ? core + level + 10 : core + 5
    }
}

enum Weather: String, CaseIterable, Identifiable {
    case none, sun, rain, sand, snow
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return L("Kein Wetter", "No weather")
        case .sun: return L("Sonne", "Sun")
        case .rain: return L("Regen", "Rain")
        case .sand: return L("Sandsturm", "Sandstorm")
        case .snow: return L("Schnee / Hagel", "Snow / Hail")
        }
    }
    var icon: String {
        switch self {
        case .none: return "circle.slash"
        case .sun: return "sun.max.fill"
        case .rain: return "cloud.rain.fill"
        case .sand: return "wind"
        case .snow: return "snowflake"
        }
    }
}

struct DamageOptions: Equatable {
    var weather: Weather = .none
    var critical = false
    /// stat stages of the attacker's attacking stat and the defender's defending stat (−6…+6)
    var attackBoost = 0
    var defenseBoost = 0
}

/// Result for one move.
struct DamageResult: Identifiable {
    let move: DexMove
    /// damage in HP points
    let min: Int
    let max: Int
    let defenderHP: Int
    let effectiveness: Double
    /// moves whose damage can't be calculated here (status, variable power …)
    let note: String?

    var id: Int { move.id }
    var minPercent: Double { Double(min) / Double(Swift.max(defenderHP, 1)) }
    var maxPercent: Double { Double(max) / Double(Swift.max(defenderHP, 1)) }

    /// "2 hits" / "2–3 hits" / nil
    var hitsText: String? {
        guard max > 0 else { return nil }
        let best = Int((Double(defenderHP) / Double(max)).rounded(.up))
        let worst = min > 0 ? Int((Double(defenderHP) / Double(min)).rounded(.up)) : 99
        if best <= 1 && worst <= 1 { return L("K.O. mit 1 Treffer", "OHKO") }
        if worst >= 99 { return L("\(best)+ Treffer", "\(best)+ hits") }
        return best == worst ? L("\(best) Treffer", "\(best) hits") : L("\(best)–\(worst) Treffer", "\(best)–\(worst) hits")
    }
}

enum DamageCalc {
    /// Damage of every move of `attacker` against `defender` (main-series formula, Gen 3+ style).
    static func results(attacker: Combatant, defender: Combatant, game: Game, options: DamageOptions) -> [DamageResult] {
        attacker.moves.map { result(move: $0, attacker: attacker, defender: defender, game: game, options: options) }
    }

    static func result(move: DexMove, attacker: Combatant, defender: Combatant, game: Game, options: DamageOptions) -> DamageResult {
        let gen = game.gen
        let hp = defender.stats[0]
        let eff = TypeChart.multiplier(attack: move.t, defense: defender.types, abilityKey: defender.abilityKey, gen: gen)
        func none(_ note: String?) -> DamageResult {
            DamageResult(move: move, min: 0, max: 0, defenderHP: hp, effectiveness: eff, note: note)
        }
        if move.c == 1 { return none(L("Statusattacke", "Status move")) }
        if eff == 0 { return none(L("Keine Wirkung", "No effect")) }

        // fixed damage
        switch move.key {
        case "seismic-toss", "night-shade":
            return DamageResult(move: move, min: attacker.level, max: attacker.level, defenderHP: hp, effectiveness: eff, note: nil)
        case "dragon-rage":
            return DamageResult(move: move, min: 40, max: 40, defenderHP: hp, effectiveness: eff, note: nil)
        case "sonic-boom":
            return DamageResult(move: move, min: 20, max: 20, defenderHP: hp, effectiveness: eff, note: nil)
        case "super-fang", "nature-s-madness", "natures-madness", "ruination":
            let half = Swift.max(hp / 2, 1)
            return DamageResult(move: move, min: half, max: half, defenderHP: hp, effectiveness: eff, note: nil)
        default: break
        }
        var power = move.p
        if power <= 1 { return none(L("Stärke hängt von der Situation ab", "Power depends on the situation")) }

        let physical: Bool = gen <= 3
            ? [T.normal, T.fighting, T.flying, T.poison, T.ground, T.rock, T.bug, T.ghost, T.steel].contains(move.t)
            : move.c == 2

        // ability / item power changes
        if attacker.abilityKey == "technician" && power <= 60 { power = power * 3 / 2 }

        var atk = Double(physical ? attacker.stats[1] : attacker.stats[3])
        var def = Double(physical ? defender.stats[2] : defender.stats[4])
        // stat stages (a critical hit ignores the attacker's drops and the defender's boosts)
        var aStage = options.attackBoost, dStage = options.defenseBoost
        if options.critical { aStage = Swift.max(aStage, 0); dStage = Swift.min(dStage, 0) }
        atk *= stage(aStage)
        def *= stage(dStage)
        if physical, ["huge-power", "pure-power"].contains(attacker.abilityKey) { atk *= 2 }
        if attacker.itemKey == "choice-band" && physical { atk *= 1.5 }
        if attacker.itemKey == "choice-specs" && !physical { atk *= 1.5 }
        if defender.itemKey == "assault-vest" && !physical { def *= 1.5 }
        if physical && defender.abilityKey == "fur-coat" { def *= 2 }
        // sandstorm boosts Rock types' Sp. Def, snow (Gen 9) boosts Ice types' Defense
        if options.weather == .sand && defender.types.contains(T.rock) && !physical && gen >= 4 { def *= 1.5 }
        if options.weather == .snow && defender.types.contains(T.ice) && physical && gen >= 9 { def *= 1.5 }

        let level = Double(attacker.level)
        var base = floor(floor(floor(2 * level / 5 + 2) * Double(power) * atk / Swift.max(def, 1)) / 50) + 2

        // weather
        if options.weather == .sun { if move.t == T.fire { base *= 1.5 } else if move.t == T.water { base *= 0.5 } }
        if options.weather == .rain { if move.t == T.water { base *= 1.5 } else if move.t == T.fire { base *= 0.5 } }
        if options.critical { base = floor(base * (gen >= 6 ? 1.5 : 2)) }

        var mods = 1.0
        if attacker.types.contains(move.t) { mods *= attacker.abilityKey == "adaptability" ? 2 : 1.5 }
        mods *= eff
        if attacker.itemKey == "life-orb" { mods *= 1.3 }
        if attacker.itemKey == "expert-belt" && eff > 1 { mods *= 1.2 }
        if let key = attacker.itemKey, typeItems[key] == move.t { mods *= 1.2 }

        let minDamage = Swift.max(Int(floor(floor(base * 0.85) * mods)), 1)
        let maxDamage = Swift.max(Int(floor(base * mods)), 1)
        return DamageResult(move: move, min: minDamage, max: maxDamage, defenderHP: hp, effectiveness: eff, note: nil)
    }

    private static func stage(_ s: Int) -> Double {
        s >= 0 ? Double(2 + s) / 2 : 2 / Double(2 - s)
    }

    /// Type-boosting held items (×1.2).
    private static let typeItems: [String: Int] = [
        "silk-scarf": T.normal, "black-belt": T.fighting, "sharp-beak": T.flying, "poison-barb": T.poison,
        "soft-sand": T.ground, "hard-stone": T.rock, "silver-powder": T.bug, "spell-tag": T.ghost,
        "metal-coat": T.steel, "charcoal": T.fire, "mystic-water": T.water, "miracle-seed": T.grass,
        "magnet": T.electric, "twisted-spoon": T.psychic, "never-melt-ice": T.ice, "dragon-fang": T.dragon,
        "black-glasses": T.dark, "fairy-feather": T.fairy, "pixie-plate": T.fairy,
    ]
}
