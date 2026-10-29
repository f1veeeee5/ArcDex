import Foundation
import SwiftData

@Model
final class Team {
    var uuid: UUID = UUID()
    var name: String = ""
    var gameRaw: String = Game.swsh.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
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

    func setMove(_ moveId: Int?, at index: Int) {
        var list = moveIds
        if let moveId {
            list.removeAll { $0 == moveId }
            if index < list.count { list.insert(moveId, at: index) } else { list.append(moveId) }
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
