import Foundation

/// One suggested set. Short keys keep the bundled JSON small.
struct MovesetEntry: Codable, Hashable {
    /// source: "factory", "bss", "random", "doubles" (or "story", made in the app)
    let s: String
    /// tier, e.g. "OU"
    let t: String?
    /// role, e.g. "Setup Sweeper"
    let r: String?
    /// the four moves
    let m: [Int]
    /// alternative moves
    let x: [Int]?
    let i: Int?
    let a: Int?
    let n: Int?
    let e: [Int]?
    let v: [Int]?
    let tt: Int?
    let g: Int?

    init(s: String, m: [Int], r: String? = nil, item: Int? = nil, nature: Int? = nil) {
        self.s = s; self.m = m; self.r = r; self.i = item; self.n = nature
        t = nil; x = nil; a = nil; e = nil; v = nil; tt = nil; g = nil
    }

    var isStory: Bool { s == "story" }

    /// Has more than moves (item, nature, EVs …).
    var isFullSet: Bool { i != nil || n != nil || e != nil }

    var sourceTitle: String {
        switch s {
        case "factory": return "Battle Factory" + (t.map { " · \($0)" } ?? "")
        case "bss": return "Battle Stadium"
        case "doubles": return L("Doppelkampf", "Doubles")
        case "story": return L("Story", "Playthrough")
        default: return L("Zufallskampf", "Random Battle")
        }
    }

    var roleTitle: String? {
        guard let r, !r.isEmpty else { return nil }
        guard Lang.current == .de else { return r }
        var text = r
        for (en, de) in MovesetEntry.roleNames { text = text.replacingOccurrences(of: en, with: de) }
        return text
    }

    private static let roleNames: [(String, String)] = [
        ("Doubles ", "Doppel-"), ("Setup Sweeper", "Setup-Angreifer"), ("Fast Attacker", "Schneller Angreifer"),
        ("Bulky Attacker", "Robuster Angreifer"), ("Bulky Setup", "Robustes Setup"), ("Bulky Support", "Robuster Support"),
        ("Fast Support", "Schneller Support"), ("Fast Bulky Setup", "Schnelles robustes Setup"), ("Wallbreaker", "Mauerbrecher"),
        ("Staller", "Staller"), ("Bulky Protect", "Robust mit Schutzschild"), ("Offensive Protect", "Offensiv mit Schutzschild"),
        ("Tera Blast user", "Tera-Ausbruch"), ("Z-Move user", "Z-Attacke"), ("Choice Item user", "Wahl-Item"),
        ("Tera Blast user", "Tera-Ausbruch"), ("Generalist", "Allrounder"), ("Spinner", "Turbodreher"),
        ("Bulky Wall", "Mauer"), ("Pivot", "Wechsler"), ("Support", "Support"), ("Attacker", "Angreifer"),
    ]
}

private struct MovesetData: Codable {
    let sets: [String: [String: [MovesetEntry]]]
    let levelup: [String: [String: [[Int]]]]
}

/// Moveset suggestions: competitive sets from Pokémon Showdown (MIT license) and playthrough sets from level-up moves.
final class Movesets {
    static let shared = Movesets()

    private let sets: [String: [String: [MovesetEntry]]]
    private let levelup: [String: [String: [[Int]]]]

    private init() {
        guard let url = Bundle.main.url(forResource: "movesets", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode(MovesetData.self, from: data) else {
            sets = [:]; levelup = [:]
            return
        }
        sets = raw.sets
        levelup = raw.levelup
    }

    private static let sourceOrder = ["factory": 0, "bss": 1, "random": 2, "doubles": 3]

    /// Competitive sets for this Pokémon and its battle forms (Mega …) in that game.
    func competitive(for pokemonId: Int, game: Game, doublesFirst: Bool = false) -> [(pokemonId: Int, set: MovesetEntry)] {
        guard let table = sets[game.rawValue] else { return [] }
        let dex = Dex.shared
        var ids = [pokemonId]
        if let p = dex.pokemon(pokemonId), pokemonId >= 20000, let base = p.base { ids = [base] }
        for form in dex.megaForms(for: ids[0], game: game) where !ids.contains(form.id) { ids.append(form.id) }
        var result: [(Int, MovesetEntry)] = []
        var seen = Set<[Int]>()
        for id in ids {
            for entry in table[String(id)] ?? [] {
                // same moves + same item = same suggestion
                let sig = entry.m + [entry.i ?? 0, -1]
                if seen.insert(sig).inserted { result.append((id, entry)) }
            }
        }
        return result.sorted { a, b in
            let oa = order(a.1, doublesFirst), ob = order(b.1, doublesFirst)
            return oa != ob ? oa < ob : false
        }
        .map { (pokemonId: $0.0, set: $0.1) }
    }

    private func order(_ e: MovesetEntry, _ doublesFirst: Bool) -> Int {
        if doublesFirst && e.s == "doubles" { return -1 }
        return Movesets.sourceOrder[e.s] ?? 9
    }

    // MARK: Playthrough

    private func levelupMoves(_ pokemonId: Int, game: Game) -> [(move: Int, level: Int)]? {
        guard let table = levelup[game.rawValue] else { return nil }
        let dex = Dex.shared
        var candidates = [pokemonId]
        if let p = dex.pokemon(pokemonId) {
            if let base = p.base { candidates.append(base) }
            if let def = dex.defaultPokemon(species: p.sp)?.id { candidates.append(def) }
        }
        for id in candidates {
            if let list = table[String(id)], !list.isEmpty {
                return list.compactMap { $0.count == 2 ? ($0[0], $0[1]) : nil }
            }
        }
        return nil
    }

    private static let avoid: Set<String> = [
        "self-destruct", "explosion", "hyper-beam", "giga-impact", "blast-burn", "hydro-cannon", "frenzy-plant",
        "rock-wrecker", "roar-of-time", "focus-punch", "dream-eater", "last-resort", "belch", "rollout", "ice-ball",
        "fling", "natural-gift", "snore", "future-sight", "doom-desire", "outrage", "thrash", "petal-dance",
        "solar-beam", "solar-blade", "sky-attack", "skull-bash", "razor-wind", "dig", "fly", "bounce", "dive",
        "phantom-force", "shadow-force", "meteor-beam", "synchronoise", "steel-beam", "mind-blown", "head-smash",
        "final-gambit", "memento", "perish-song", "struggle", "eruption", "water-spout", "dragon-energy", "fake-out",
    ]

    private static let goodStatus: [String] = [
        "swords-dance", "dragon-dance", "nasty-plot", "quiver-dance", "shell-smash", "calm-mind", "bulk-up",
        "victory-dance", "coil", "shift-gear", "recover", "roost", "slack-off", "soft-boiled", "milk-drink",
        "synthesis", "moonlight", "morning-sun", "shore-up", "spore", "sleep-powder", "thunder-wave",
        "will-o-wisp", "hypnosis", "growth", "work-up",
    ]

    /// Four sensible moves from the level-up moves up to the given level: strong STAB moves, type coverage
    /// and one good status move. A rule-based suggestion, not a hand-made set.
    func story(for pokemonId: Int, game: Game, level: Int) -> MovesetEntry? {
        let dex = Dex.shared
        guard let list = levelupMoves(pokemonId, game: game), let p = dex.pokemon(pokemonId) else { return nil }
        var seen = Set<Int>()
        let available = list.filter { $0.level <= level }.compactMap { item -> DexMove? in
            guard seen.insert(item.move).inserted else { return nil }
            return dex.move(item.move)
        }
        guard !available.isEmpty else { return nil }
        let stab = Set(p.types(gen: game.gen))
        let physical = p.s[1] >= p.s[3]
        func score(_ m: DexMove) -> Double {
            guard m.isDamaging, m.p > 1, !Movesets.avoid.contains(m.key) else { return 0 }
            var s = Double(m.p) * Double(m.a == 0 ? 100 : m.a) / 100
            if stab.contains(m.t) { s *= 1.5 }
            // before Gen 4 the category came from the type
            let isPhysical = game.gen >= 4 ? m.isPhysical : [1, 2, 3, 4, 5, 6, 7, 8, 9].contains(m.t)
            if isPhysical != physical { s *= 0.7 }
            if m.pr > 0 { s *= 0.85 }
            return s
        }
        let attacks = available.filter { score($0) > 0 }.sorted { score($0) > score($1) }
        var chosen: [DexMove] = []
        var usedTypes = Set<Int>()
        for m in attacks where stab.contains(m.t) && !usedTypes.contains(m.t) && chosen.count < 2 {
            chosen.append(m); usedTypes.insert(m.t)
        }
        for m in attacks where !usedTypes.contains(m.t) && chosen.count < 3 && score(m) >= 40 {
            chosen.append(m); usedTypes.insert(m.t)
        }
        if let status = Movesets.goodStatus.lazy.compactMap({ key in available.first { $0.key == key } }).first {
            chosen.append(status)
        }
        for m in attacks where chosen.count < 4 && !chosen.contains(m) { chosen.append(m) }
        guard !chosen.isEmpty else { return nil }
        let moves = Array(chosen.prefix(4))
        // nature: boosts the stronger attack stat and lowers the unused one
        var nature: Int?
        if game.hasNatures {
            nature = dex.natures.first { $0.key == (physical ? "adamant" : "modest") }?.id
        }
        // item: the type-boosting item of the strongest own-type attack – or none
        var item: Int?
        if game.hasHeldItems, let main = moves.first(where: { $0.isDamaging && stab.contains($0.t) }),
           let keys = Movesets.typeItems[main.t] {
            let available = dex.items(for: game)
            item = keys.lazy.compactMap { key in available.first { $0.key == key }?.id }.first
        }
        return MovesetEntry(s: "story", m: moves.map(\.id), item: item, nature: nature)
    }

    /// Type-boosting held items (Charcoal, Mystic Water …) per type id.
    private static let typeItems: [Int: [String]] = [
        1: ["silk-scarf"], 2: ["black-belt"], 3: ["sharp-beak"], 4: ["poison-barb"], 5: ["soft-sand"], 6: ["hard-stone"],
        7: ["silver-powder"], 8: ["spell-tag"], 9: ["metal-coat"], 10: ["charcoal"], 11: ["mystic-water"], 12: ["miracle-seed"],
        13: ["magnet"], 14: ["twisted-spoon"], 15: ["never-melt-ice"], 16: ["dragon-fang"], 17: ["black-glasses"], 18: ["fairy-feather", "pixie-plate"],
    ]
}
