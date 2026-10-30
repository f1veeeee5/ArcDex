import Foundation

/// Any item of the games (not only held items) – for the Pokédex item pages.
struct ExtraItem: Codable, Identifiable, Hashable, Bilingual {
    let id: Int
    let key: String
    let de: String
    let en: String
    /// item category id
    let cat: Int
    /// bag pocket: 1 items, 2 medicine, 3 balls, 5 berries, 7 battle items, 8 key items
    let p: Int
    /// generations the item exists in
    let g: [Int]
    /// description [de, en]
    let t: [String]

    var text: String? {
        guard t.count == 2 else { return nil }
        let s = Lang.current == .de ? t[0] : t[1]
        return s.isEmpty ? (t[1].isEmpty ? nil : t[1]) : s
    }
}

enum ItemPocket: Int, CaseIterable, Identifiable {
    case items = 1, medicine = 2, balls = 3, berries = 5, battle = 7, key = 8

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .items: return L("Items", "Items")
        case .medicine: return L("Medizin", "Medicine")
        case .balls: return L("Bälle", "Poké Balls")
        case .berries: return L("Beeren", "Berries")
        case .battle: return L("Kampf-Items", "Battle items")
        case .key: return L("Basis-Items", "Key items")
        }
    }

    var icon: String {
        switch self {
        case .items: return "bag.fill"
        case .medicine: return "cross.case.fill"
        case .balls: return "circle.circle.fill"
        case .berries: return "leaf.fill"
        case .battle: return "bolt.fill"
        case .key: return "key.fill"
        }
    }
}

private struct ExtraData: Codable {
    let moveText: [String: [String]]
    let items: [ExtraItem]
    let categories: [String: [String]]
    let abilityGen: [String: Int]
}

/// Texts and lists for the move / ability / item pages, loaded on first use.
final class DexExtra {
    static let shared = DexExtra()

    let items: [ExtraItem]
    private let moveText: [String: [String]]
    private let categories: [String: [String]]
    private let abilityGen: [String: Int]
    private let itemById: [Int: ExtraItem]

    private init() {
        guard let url = Bundle.main.url(forResource: "dexextra", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode(ExtraData.self, from: data) else {
            items = []; moveText = [:]; categories = [:]; abilityGen = [:]; itemById = [:]
            return
        }
        items = raw.items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        moveText = raw.moveText
        categories = raw.categories
        abilityGen = raw.abilityGen
        itemById = Dictionary(raw.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func pick(_ pair: [String]?) -> String? {
        guard let pair, pair.count == 2 else { return nil }
        let s = Lang.current == .de ? pair[0] : pair[1]
        return s.isEmpty ? (pair[1].isEmpty ? nil : pair[1]) : s
    }

    func moveDescription(_ id: Int) -> String? { pick(moveText[String(id)]) }
    func categoryName(_ id: Int) -> String? { pick(categories[String(id)]) }
    func abilityGeneration(_ id: Int) -> Int? { abilityGen[String(id)] }
    func item(_ id: Int) -> ExtraItem? { itemById[id] }
}

extension Dex {
    /// Pokémon that can learn a move in a game (base forms + regional forms, no Megas).
    func learners(of moveId: Int, game: Game) -> [DexPokemon] {
        // only Pokémon with their own learnset – otherwise the "all moves" fallback would list everyone
        available(in: game).filter { p in
            isAvailable(p.id, in: game) && learnset(for: p.id, game: game).contains { $0.id == moveId }
        }
    }

    private func available(in game: Game) -> [DexPokemon] {
        availablePokemon(in: game).filter { $0.kind == nil && $0.id < 20000 }
    }

    /// Pokémon with an ability (normal or hidden).
    func pokemon(withAbility id: Int, game: Game?) -> (normal: [DexPokemon], hidden: [DexPokemon]) {
        let list = (game.map { availablePokemon(in: $0) } ?? pokemon).filter { $0.id < 20000 }
        let gen = game?.gen ?? 9
        var normal: [DexPokemon] = [], hidden: [DexPokemon] = []
        for p in list {
            let slots = p.abilitySlots(gen: gen)
            if slots.regular.contains(id) { normal.append(p) } else if slots.hidden == id { hidden.append(p) }
        }
        let order: (DexPokemon, DexPokemon) -> Bool = { ($0.sp, $0.id) < ($1.sp, $1.id) }
        return (normal.sorted(by: order), hidden.sorted(by: order))
    }

    /// Default game for "who learns it" when no game is filtered: the newest game in which the move exists.
    func newestGame(withMove moveId: Int) -> Game? {
        for game in [Game.sv, .swsh, .sm, .oras, .xy, .b2w2, .bw, .hgss, .pt, .dp, .e, .frlg, .rs, .c, .gs, .y, .rb]
        where game.hasLearnsets {
            if !learners(of: moveId, game: game).isEmpty { return game }
        }
        return nil
    }
}
