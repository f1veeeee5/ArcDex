import Foundation
import SwiftData
import SwiftUI

// MARK: - Mode & rules

/// What kind of save file this is. Raw values are stored – never rename.
enum RunMode: String, CaseIterable, Identifiable, Codable {
    case normal, nuzlocke, soulLink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: return L("Normal", "Normal")
        case .nuzlocke: return "Nuzlocke"
        case .soulLink: return "Soul Link"
        }
    }

    var icon: String {
        switch self {
        case .normal: return "gamecontroller.fill"
        case .nuzlocke: return "flame.fill"
        case .soulLink: return "link"
        }
    }

    var isRun: Bool { self != .normal }
}

/// Nuzlocke rules of one run. Only used for Nuzlocke / Soul Link save files.
nonisolated struct NuzlockeRules: Codable, Equatable {
    var firstEncounterOnly = true
    var faintIsDeath = true
    var nicknames = true
    var dupesClause = true
    var shinyClause = true
    var levelCapOn = false
    var levelCap = 15
    var noItemsInBattle = false
    var setMode = false
    var noLegendaries = false
    /// Soul Link: a primary type only once per team
    var typeClause = true
    /// Soul Link: a primary type only once across both teams
    var typeClauseShared = false
}

// MARK: - Linked encounter

enum LinkStatus: String, CaseIterable, Identifiable, Codable {
    case team, box, dead, missed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .team: return "Team"
        case .box: return "Box"
        case .dead: return L("Gestorben", "Fainted")
        case .missed: return L("Verpasst", "Missed")
        }
    }

    var icon: String {
        switch self {
        case .team: return "square.grid.2x2.fill"
        case .box: return "archivebox.fill"
        case .dead: return "xmark.seal.fill"
        case .missed: return "slash.circle"
        }
    }
}

/// One encounter of a run: the Pokémon caught on a route – in a Soul Link one per player, sharing one nickname.
@Model
final class NuzlockeLink {
    var uuid: UUID = UUID()
    var route: String = ""
    /// location id from the database (nil for routes typed in by hand)
    var locationId: Int?
    var nickname: String = ""
    var statusRaw: String = LinkStatus.box.rawValue
    var createdAt: Date = Date()
    var diedAt: Date?
    var deathNote: String = ""
    var savegame: Savegame?
    /// the Pokémon of player 1 / player 2 (`TeamMember.player`)
    @Relationship(deleteRule: .cascade, inverse: \TeamMember.link)
    var members: [TeamMember] = []

    init(route: String, locationId: Int?) {
        self.route = route
        self.locationId = locationId
    }

    var status: LinkStatus {
        get { LinkStatus(rawValue: statusRaw) ?? .box }
        set { statusRaw = newValue.rawValue }
    }

    func member(_ player: Int) -> TeamMember? { members.first { $0.player == player } }

    /// Team order (same slot in both teams).
    var order: Int { members.map(\.order).min() ?? 0 }

    var displayName: String {
        if !nickname.isEmpty { return nickname }
        return members.sorted { $0.player < $1.player }.compactMap { $0.species?.name }.joined(separator: " & ")
    }
}

extension TeamMember {
    var isLinked: Bool { link != nil }
}

// MARK: - Save file helpers

extension Savegame {
    var mode: RunMode {
        get { RunMode(rawValue: modeRaw) ?? .normal }
        set { modeRaw = newValue.rawValue }
    }

    var rules: NuzlockeRules {
        get { (try? JSONDecoder().decode(NuzlockeRules.self, from: rulesData)) ?? NuzlockeRules() }
        set { rulesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var players: [Int] { mode == .soulLink ? [1, 2] : [1] }

    func playerName(_ p: Int) -> String {
        let name = p == 1 ? player1 : player2
        if !name.isEmpty { return name }
        return mode == .soulLink ? L("Spieler \(p)", "Player \(p)") : L("Mein Team", "My team")
    }

    /// The team of a player (created when missing).
    func runTeam(_ player: Int, context: ModelContext) -> Team {
        if let t = teams.first(where: { $0.player == player }) { return t }
        let t = Team(name: playerName(player), game: game)
        t.player = player
        context.insert(t)
        t.savegame = self
        return t
    }

    func runTeamIfExists(_ player: Int) -> Team? { teams.first { $0.player == player } }

    func links(_ status: LinkStatus) -> [NuzlockeLink] {
        let list = links.filter { $0.status == status }
        switch status {
        case .team: return list.sorted { $0.order < $1.order }
        case .dead: return list.sorted { ($0.diedAt ?? .distantPast) > ($1.diedAt ?? .distantPast) }
        default: return list.sorted { $0.createdAt > $1.createdAt }
        }
    }

    var teamIsFull: Bool { links(.team).count >= 6 }
}

// MARK: - Actions (keep both players in sync)

enum NuzlockeActions {
    /// Creates a new encounter. `species` = Pokémon per player (nil = nothing caught).
    @discardableResult
    static func addEncounter(to save: Savegame, route: String, locationId: Int?, species: [Int: Int], nickname: String,
                             level: Int, shiny: [Int: Bool], status: LinkStatus, context: ModelContext) -> NuzlockeLink {
        let link = NuzlockeLink(route: route.trimmingCharacters(in: .whitespacesAndNewlines), locationId: locationId)
        link.nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        context.insert(link)
        link.savegame = save
        if status == .missed || species.isEmpty {
            link.status = .missed
        } else {
            for p in save.players {
                guard let id = species[p] else { continue }
                let m = TeamMember(pokemonId: id, order: 0, level: level)
                context.insert(m)
                m.player = p
                m.nickname = link.nickname
                m.shiny = shiny[p] ?? false
                m.link = link
            }
            let target: LinkStatus = (status == .team && save.teamIsFull) ? .box : status
            set(link, to: target, in: save, context: context)
        }
        save.touch()
        return link
    }

    /// Moves a pair to team / box / graveyard – always both Pokémon together.
    static func set(_ link: NuzlockeLink, to status: LinkStatus, in save: Savegame, note: String = "", context: ModelContext) {
        let wasTeam = link.status == .team
        let nextSlot = (save.links(.team).filter { $0 !== link }.map(\.order).max() ?? -1) + 1
        link.status = status
        for m in link.members {
            if status == .team {
                m.team = save.runTeam(m.player, context: context)
                if !wasTeam { m.order = nextSlot }
            } else {
                m.team = nil
            }
        }
        if status == .dead {
            link.diedAt = Date()
            link.deathNote = note
        } else {
            link.diedAt = nil
        }
        compactOrder(save)
        for t in save.teams { t.touch() }
        save.touch()
    }

    /// Slots without gaps, same slot for both partners.
    static func compactOrder(_ save: Savegame) {
        for (i, link) in save.links(.team).enumerated() {
            for m in link.members { m.order = i }
        }
    }

    /// After dragging a Pokémon in one team: put the partners into the same slots.
    static func mirrorOrder(from team: Team) {
        guard let save = team.savegame, save.mode == .soulLink else { return }
        for m in team.members {
            guard let link = m.link else { continue }
            for partner in link.members where partner !== m { partner.order = m.order }
        }
        save.teams.forEach { $0.touch() }
    }

    /// One nickname for both partners.
    static func nicknameChanged(_ member: TeamMember) {
        guard let link = member.link else { return }
        link.nickname = member.nickname
        for partner in link.members where partner !== member && partner.nickname != member.nickname {
            partner.nickname = member.nickname
        }
    }

    static func delete(_ link: NuzlockeLink, from save: Savegame, context: ModelContext) {
        context.delete(link)
        save.links.removeAll { $0 === link }
        compactOrder(save)
        save.touch()
    }
}

// MARK: - Rule checks (warnings only)

struct RuleWarning: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let icon: String
}

enum NuzlockeCheck {
    static func evolutionFamily(_ pokemonId: Int) -> Int? {
        guard let p = Dex.shared.pokemon(pokemonId) else { return nil }
        return Wiki.shared.species(p.sp)?.ch
    }

    /// Warnings for a planned encounter.
    static func encounter(save: Savegame, route: String, species: [Int: Int], shiny: [Int: Bool], nickname: String,
                          status: LinkStatus, ignoring: NuzlockeLink? = nil) -> [RuleWarning] {
        let rules = save.rules
        var list: [RuleWarning] = []
        let others = save.links.filter { $0 !== ignoring }
        let anyShiny = shiny.values.contains(true)
        let key = route.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if rules.firstEncounterOnly, !key.isEmpty, !(rules.shinyClause && anyShiny),
           others.contains(where: { $0.route.lowercased() == key }) {
            list.append(RuleWarning(text: L("Auf „\(route)“ gab es schon eine Begegnung.", "There was already an encounter on “\(route)”."), icon: "map"))
        }
        if rules.dupesClause, status != .missed {
            let caught = Set(others.flatMap(\.members).compactMap { evolutionFamily($0.pokemonId) })
            for (p, id) in species.sorted(by: { $0.key < $1.key }) {
                if let fam = evolutionFamily(id), caught.contains(fam), let name = Dex.shared.pokemon(id)?.name {
                    list.append(RuleWarning(text: L("Dupe: \(name) bzw. seine Entwicklungsreihe wurde schon gefangen.", "Dupe: \(name) or its evolution line was already caught.")
                                            + (save.mode == .soulLink ? " (\(save.playerName(p)))" : ""), icon: "doc.on.doc"))
                }
            }
        }
        if rules.noLegendaries {
            for id in species.values {
                if let p = Dex.shared.pokemon(id), (Wiki.shared.species(p.sp)?.leg ?? 0) > 0 {
                    list.append(RuleWarning(text: L("\(p.name) ist legendär oder mysteriös.", "\(p.name) is legendary or mythical."), icon: "crown"))
                }
            }
        }
        if rules.nicknames, status != .missed, nickname.trimmingCharacters(in: .whitespaces).isEmpty {
            list.append(RuleWarning(text: L("Noch kein Spitzname.", "No nickname yet."), icon: "character.cursor.ibeam"))
        }
        if save.mode == .soulLink, status == .team, rules.typeClause || rules.typeClauseShared {
            list += typeClash(save: save, adding: species, ignoring: ignoring)
        }
        return list
    }

    /// Soul Link type clause: the primary type may only appear once per team (or across both teams).
    static func typeClash(save: Savegame, adding: [Int: Int] = [:], ignoring: NuzlockeLink? = nil) -> [RuleWarning] {
        let rules = save.rules
        let game = save.game
        var perPlayer: [Int: [Int]] = [:]
        for link in save.links(.team) where link !== ignoring {
            for m in link.members {
                if let t = m.types(in: game).first { perPlayer[m.player, default: []].append(t) }
            }
        }
        for (p, id) in adding {
            if let t = Dex.shared.pokemon(id)?.types(gen: game.gen).first { perPlayer[p, default: []].append(t) }
        }
        var list: [RuleWarning] = []
        func dupes(_ types: [Int]) -> [Int] {
            Dictionary(grouping: types, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
        }
        if rules.typeClause {
            for p in save.players {
                let d = dupes(perPlayer[p] ?? [])
                if !d.isEmpty {
                    let names = d.compactMap { Dex.shared.type($0)?.name }.joined(separator: ", ")
                    list.append(RuleWarning(text: L("Primärtyp doppelt im Team von \(save.playerName(p)): \(names)", "Primary type twice in \(save.playerName(p))’s team: \(names)"), icon: "exclamationmark.triangle"))
                }
            }
        }
        if rules.typeClauseShared {
            let d = dupes(perPlayer.values.flatMap { $0 })
            if !d.isEmpty && !(rules.typeClause && list.count > 0) {
                let names = d.compactMap { Dex.shared.type($0)?.name }.joined(separator: ", ")
                list.append(RuleWarning(text: L("Primärtyp doppelt über beide Teams: \(names)", "Primary type twice across both teams: \(names)"), icon: "exclamationmark.triangle"))
            }
        }
        return list
    }

    /// Warnings for the current state of the run.
    static func run(_ save: Savegame) -> [RuleWarning] {
        let rules = save.rules
        var list: [RuleWarning] = []
        if save.mode == .soulLink, rules.typeClause || rules.typeClauseShared {
            list += typeClash(save: save)
        }
        if rules.levelCapOn {
            let over = save.links(.team).flatMap(\.members).filter { $0.level > rules.levelCap }
            if !over.isEmpty {
                let names = over.map { $0.displayName }.joined(separator: ", ")
                list.append(RuleWarning(text: L("Über dem Level-Cap \(rules.levelCap): \(names)", "Above the level cap \(rules.levelCap): \(names)"), icon: "chart.line.uptrend.xyaxis"))
            }
        }
        if rules.nicknames {
            let unnamed = save.links.filter { $0.status != .missed && $0.nickname.isEmpty }
            if !unnamed.isEmpty {
                list.append(RuleWarning(text: L("\(unnamed.count) Pokémon ohne Spitznamen.", "\(unnamed.count) Pokémon without a nickname."), icon: "character.cursor.ibeam"))
            }
        }
        return list
    }
}

// MARK: - Routes

extension Wiki {
    /// Locations with wild Pokémon in a game, sorted naturally (Route 2 before Route 10).
    func routes(in game: Game) -> [(id: Int, name: String)] {
        let ids = Wiki.routeIndex(game).keys
        return ids.map { (id: $0, name: locationName($0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Pokémon that can be found at a location.
    func pokemon(at location: Int, game: Game) -> [Int] {
        Wiki.routeIndex(game)[location] ?? []
    }

    private static var indexCache: [Game: [Int: [Int]]] = [:]

    private static func routeIndex(_ game: Game) -> [Int: [Int]] {
        if let cached = indexCache[game] { return cached }
        var index: [Int: Set<Int>] = [:]
        for p in Dex.shared.availablePokemon(in: game) where p.id < 20000 && p.kind == nil {
            for e in Wiki.shared.encounters(p, game: game).list {
                index[e.l, default: []].insert(p.id)
            }
        }
        let result = index.mapValues { Array($0).sorted() }
        indexCache[game] = result
        return result
    }
}
