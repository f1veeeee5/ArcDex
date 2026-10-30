import Foundation
import SwiftData

@Model
final class Team {
    var uuid: UUID = UUID()
    var name: String = ""
    var gameRaw: String = Game.swsh.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// "doubles" or "singles" – only used for Pokémon Champions teams
    var formatRaw: String = BattleFormat.doubles.rawValue
    @Relationship(deleteRule: .cascade, inverse: \TeamMember.team)
    var members: [TeamMember] = []

    init(name: String, game: Game) {
        self.name = name
        self.gameRaw = game.rawValue
    }

    var game: Game {
        get { Game(rawValue: gameRaw) ?? .swsh }
        set { gameRaw = newValue.rawValue }
    }

    var format: BattleFormat {
        get { BattleFormat(rawValue: formatRaw) ?? .doubles }
        set { formatRaw = newValue.rawValue }
    }

    var sortedMembers: [TeamMember] {
        members.sorted { $0.order < $1.order }
    }

    var isFull: Bool { members.count >= 6 }

    func touch() { updatedAt = Date() }
}

@Model
final class TeamMember {
    var uuid: UUID = UUID()
    var order: Int = 0
    var pokemonId: Int = 25
    var nickname: String = ""
    var level: Int = 50
    var shiny: Bool = false
    /// "M", "F" or "" (unknown / genderless)
    var gender: String = ""
    var itemId: Int?
    var abilityId: Int?
    var natureId: Int?
    var teraTypeId: Int?
    /// selected mega / primal form
    var megaFormId: Int?
    var gigantamax: Bool = false
    var moveIds: [Int] = []
    var evs: [Int] = [0, 0, 0, 0, 0, 0]
    var ivs: [Int] = [31, 31, 31, 31, 31, 31]
    var team: Team?

    init(pokemonId: Int, order: Int, level: Int = 50) {
        self.pokemonId = pokemonId
        self.order = order
        self.level = level
        if let p = Dex.shared.pokemon(pokemonId) {
            self.abilityId = p.ab.first
        }
    }
}

extension TeamMember {
    var species: DexPokemon? { Dex.shared.pokemon(pokemonId) }

    /// The form that is actually shown and used in battle (mega / gigantamax).
    func battleForm(in game: Game) -> DexPokemon? {
        if let mega = megaFormId, game.hasMega, let p = Dex.shared.pokemon(mega) { return p }
        if gigantamax, let g = Dex.shared.gmaxForm(for: pokemonId, game: game) { return g }
        return species
    }

    /// Types used for the analysis (mega forms can change types).
    func types(in game: Game) -> [Int] {
        (battleForm(in: game) ?? species)?.types(gen: game.gen) ?? []
    }

    var displayName: String {
        nickname.isEmpty ? (species?.name ?? "?") : nickname
    }

    var moves: [DexMove] { moveIds.compactMap { Dex.shared.move($0) } }
    var item: DexItem? { itemId.flatMap { Dex.shared.item($0) } }
    var ability: DexAbility? { abilityId.flatMap { Dex.shared.ability($0) } }
    var nature: DexNature? { natureId.flatMap { Dex.shared.nature($0) } }

    func setPokemon(_ id: Int) {
        guard id != pokemonId else { return }
        pokemonId = id
        megaFormId = nil
        gigantamax = false
        if let p = Dex.shared.pokemon(id) {
            let legal = Dex.shared.abilities(for: p).map(\.id)
            if let a = abilityId, legal.contains(a) { } else { abilityId = p.ab.first }
        }
    }

    /// Puts a move into a slot. An existing move in that slot is replaced (not pushed down).
    /// If the move is already in another slot, the two moves swap places.
    func setMove(_ moveId: Int?, at index: Int) {
        var list = moveIds
        if let moveId {
            if index < list.count {
                if let other = list.firstIndex(of: moveId), other != index {
                    list.swapAt(other, index)
                } else {
                    list[index] = moveId
                }
            } else if !list.contains(moveId) {
                list.append(moveId)
            }
        } else if index < list.count {
            list.remove(at: index)
        }
        moveIds = Array(list.prefix(4))
    }

    /// Adds scanned moves: scanned ones first, then the previous moves until 4 slots are filled.
    func applyScannedMoves(_ ids: [Int]) {
        var result: [Int] = []
        for id in ids where !result.contains(id) { result.append(id) }
        for id in moveIds where !result.contains(id) { result.append(id) }
        moveIds = Array(result.prefix(4))
    }

    func apply(_ scan: ScannedMember, replaceSpecies: Bool) {
        if replaceSpecies, let id = scan.pokemonId { setPokemon(id) }
        if let l = scan.level { level = l }
        if let i = scan.itemId { itemId = i }
        if let a = scan.abilityId { abilityId = a }
        if let n = scan.natureId { natureId = n }
        if !scan.moveIds.isEmpty { applyScannedMoves(scan.moveIds) }
        if let i = scan.itemId, let form = megaForm(forStone: i) {
            megaFormId = form
        }
    }

    /// Returns the mega form that belongs to a mega stone, if it fits this Pokémon.
    func megaForm(forStone itemId: Int) -> Int? {
        for game in [Game.za, .sm, .oras, .xy, .lgpe] {
            if let form = Dex.shared.megaForms(for: pokemonId, game: game).first(where: { $0.stone == itemId }) {
                return form.id
            }
        }
        return nil
    }
}

/// Result of a scan before it is applied.
struct ScannedMember: Identifiable, Hashable {
    let id = UUID()
    var pokemonId: Int?
    var level: Int?
    var itemId: Int?
    var abilityId: Int?
    var natureId: Int?
    var moveIds: [Int] = []
    var include = true
}

enum StatNames {
    static var short: [String] {
        Lang.current == .de
            ? ["KP", "Angr.", "Vert.", "Sp.-Ang.", "Sp.-Vert.", "Init."]
            : ["HP", "Atk", "Def", "SpA", "SpD", "Spe"]
    }
    static let showdown = ["HP", "Atk", "Def", "SpA", "SpD", "Spe"]
}


// MARK: - Z-Moves (Sun / Moon)

enum ZCrystal {
    /// type Z-Crystals: item key prefix -> type id
    private static let typeCrystals: [String: Int] = [
        "normalium": T.normal, "fightinium": T.fighting, "flyinium": T.flying, "poisonium": T.poison,
        "groundium": T.ground, "rockium": T.rock, "buginium": T.bug, "ghostium": T.ghost, "steelium": T.steel,
        "firium": T.fire, "waterium": T.water, "grassium": T.grass, "electrium": T.electric, "psychium": T.psychic,
        "icium": T.ice, "dragonium": T.dragon, "darkinium": T.dark, "fairium": T.fairy,
    ]

    /// species Z-Crystals: item key prefix -> (move key, allowed species, required form key)
    private static let speciesCrystals: [String: (move: String, species: Set<Int>, form: String?)] = [
        "pikanium": ("volt-tackle", [25], nil),
        "pikashunium": ("thunderbolt", [25], nil),
        "aloraichium": ("thunderbolt", [26], "raichu-alola"),
        "decidium": ("spirit-shackle", [724], nil),
        "incinium": ("darkest-lariat", [727], nil),
        "primarium": ("sparkling-aria", [730], nil),
        "eevium": ("last-resort", [133], nil),
        "snorlium": ("giga-impact", [143], nil),
        "mewnium": ("psychic", [151], nil),
        "marshadium": ("spectral-thief", [802], nil),
        "tapunium": ("natures-madness", [785, 786, 787, 788], nil),
        "kommonium": ("clanging-scales", [784], nil),
        "lycanium": ("stone-edge", [745], nil),
        "mimikium": ("play-rough", [778], nil),
        "solganium": ("sunsteel-strike", [791, 800], nil),
        "lunalium": ("moongeist-beam", [792, 800], nil),
        "ultranecrozium": ("photon-geyser", [800], nil),
    ]

    private static func prefix(_ item: DexItem) -> String {
        String(item.key.split(separator: "-").first ?? "")
    }

    /// Moves of this Pokémon that become a Z-Move with the held item.
    static func zMoves(for member: TeamMember, game: Game) -> Set<Int> {
        guard game.hasZMoves, let item = member.item, item.isZCrystal, let p = member.species else { return [] }
        let key = prefix(item)
        if let type = typeCrystals[key] {
            return Set(member.moves.filter { $0.t == type }.map(\.id))
        }
        if let rule = speciesCrystals[key], rule.species.contains(p.sp), rule.form == nil || rule.form == p.key {
            return Set(member.moves.filter { $0.key == rule.move }.map(\.id))
        }
        return []
    }

    /// Short explanation for the editor, e.g. "Pikanium Z: Volt Tackle becomes a Z-Move".
    static func hint(for member: TeamMember, game: Game) -> String? {
        guard game.hasZMoves, let item = member.item, item.isZCrystal, let p = member.species else { return nil }
        let key = prefix(item)
        let ids = zMoves(for: member, game: game)
        let names = member.moves.filter { ids.contains($0.id) }.map(\.name)
        if let type = typeCrystals[key], let t = Dex.shared.type(type) {
            return names.isEmpty
                ? L("\(item.name): Gib \(member.displayName) eine \(t.name)-Attacke, damit daraus eine Z-Attacke wird.",
                    "\(item.name): Give \(member.displayName) a \(t.name) move to turn it into a Z-Move.")
                : L("\(item.name): \(names.joined(separator: ", ")) \(names.count == 1 ? "wird" : "werden") zur Z-Attacke.",
                    "\(item.name): \(names.joined(separator: ", ")) \(names.count == 1 ? "becomes a" : "become") Z-Move\(names.count == 1 ? "" : "s").")
        }
        if let rule = speciesCrystals[key] {
            let moveName = Dex.shared.moves.first { $0.key == rule.move }?.name ?? rule.move
            if !rule.species.contains(p.sp) || (rule.form != nil && rule.form != p.key) {
                return L("\(item.name) funktioniert nur bei einem bestimmten Pokémon – nicht bei \(member.displayName).",
                         "\(item.name) only works for a specific Pokémon – not for \(member.displayName).")
            }
            return names.isEmpty
                ? L("\(item.name): \(member.displayName) braucht \(moveName) für seine eigene Z-Attacke.",
                    "\(item.name): \(member.displayName) needs \(moveName) for its exclusive Z-Move.")
                : L("\(item.name): \(moveName) wird zur exklusiven Z-Attacke.", "\(item.name): \(moveName) becomes its exclusive Z-Move.")
        }
        return nil
    }
}


enum BattleFormat: String, CaseIterable, Identifiable {
    case singles, doubles
    var id: String { rawValue }
    var title: String { self == .singles ? L("Einzel", "Singles") : L("Doppel", "Doubles") }
}

extension TeamMember {
    /// Real stat value at the given level (IV, EV and nature included).
    func stat(_ index: Int, base: Int, level: Int, game: Game) -> Int {
        let iv = game.hasIVs ? ivs[index] : 31
        let ev = game.hasEVs ? evs[index] : 0
        let core = (2 * base + iv + ev / 4) * level / 100
        if index == 0 { return base == 1 ? 1 : core + level + 10 }   // Shedinja always has 1 HP
        var value = Double(core + 5)
        if let n = nature, !n.isNeutral {
            if n.up == index + 1 { value *= 1.1 }
            if n.down == index + 1 { value *= 0.9 }
        }
        return Int(value)
    }
}
