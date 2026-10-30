import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// ".arcdexbackup" file with all data of the app.
    static let arcdexBackup = UTType(exportedAs: "app.lukas.teamscan.backup")
}

/// Everything the user created: save files with teams, shiny hunts and runs, plus Pokédex favorites.
nonisolated struct BackupFile: Codable {
    struct Member: Codable {
        var uuid: UUID
        var teamID: UUID?
        var linkID: UUID?
        var player: Int
        var order: Int
        var pokemonId: Int
        var nickname: String
        var level: Int
        var shiny: Bool
        var gender: String
        var itemId: Int?
        var abilityId: Int?
        var natureId: Int?
        var teraTypeId: Int?
        var megaFormId: Int?
        var gigantamax: Bool
        var moveIds: [Int]
        var evs: [Int]
        var ivs: [Int]
    }

    struct TeamEntry: Codable {
        var uuid: UUID
        var name: String
        var game: String
        var createdAt: Date
        var updatedAt: Date
        var format: String
        var player: Int
    }

    struct Hunt: Codable {
        var uuid: UUID
        var pokemonId: Int
        var method: String
        var count: Int
        var step: Int
        var shinyCharm: Bool
        var sparklingPower: Int
        var research: Int
        var outbreakTier: Int
        var lure: Bool
        var customOdds: Int
        var startedAt: Date
        var updatedAt: Date
        var foundAt: Date?
        var elapsed: Double
        var phases: Data
        var notes: String
    }

    struct Link: Codable {
        var uuid: UUID
        var route: String
        var locationId: Int?
        var nickname: String
        var status: String
        var createdAt: Date
        var diedAt: Date?
        var deathNote: String
    }

    struct Save: Codable {
        var uuid: UUID
        var name: String
        var game: String
        var platform: String
        var createdAt: Date
        var updatedAt: Date
        var mode: String
        var rules: Data
        var player1: String
        var player2: String
        var teams: [TeamEntry]
        var members: [Member]
        var hunts: [Hunt]
        var links: [Link]
    }

    struct Favorite: Codable {
        var pokemonId: Int
        var shiny: Bool
        var addedAt: Date
    }

    var format = 1
    var createdAt: Date
    var saves: [Save]
    var favorites: [Favorite]

    var teamCount: Int { saves.reduce(0) { $0 + $1.teams.filter { $0.player == 0 }.count } }
    var huntCount: Int { saves.reduce(0) { $0 + $1.hunts.count } }
    var runCount: Int { saves.filter { $0.mode != RunMode.normal.rawValue }.count }
}

enum Backup {
    // MARK: Create

    static func make(context: ModelContext) -> BackupFile {
        let saves = (try? context.fetch(FetchDescriptor<Savegame>())) ?? []
        let favorites = (try? context.fetch(FetchDescriptor<FavoritePokemon>())) ?? []
        return BackupFile(
            createdAt: Date(),
            saves: saves.map { s in
                var members: [UUID: TeamMember] = [:]
                for t in s.teams { for m in t.members { members[m.uuid] = m } }
                for l in s.links { for m in l.members { members[m.uuid] = m } }
                return BackupFile.Save(
                    uuid: s.uuid, name: s.name, game: s.gameRaw, platform: s.platformRaw, createdAt: s.createdAt,
                    updatedAt: s.updatedAt, mode: s.modeRaw, rules: s.rulesData, player1: s.player1, player2: s.player2,
                    teams: s.teams.map { t in
                        BackupFile.TeamEntry(uuid: t.uuid, name: t.name, game: t.gameRaw, createdAt: t.createdAt,
                                             updatedAt: t.updatedAt, format: t.formatRaw, player: t.player)
                    },
                    members: members.values.map { m in
                        BackupFile.Member(uuid: m.uuid, teamID: m.team?.uuid, linkID: m.link?.uuid, player: m.player, order: m.order,
                                          pokemonId: m.pokemonId, nickname: m.nickname, level: m.level, shiny: m.shiny,
                                          gender: m.gender, itemId: m.itemId, abilityId: m.abilityId, natureId: m.natureId,
                                          teraTypeId: m.teraTypeId, megaFormId: m.megaFormId, gigantamax: m.gigantamax,
                                          moveIds: m.moveIds, evs: m.evs, ivs: m.ivs)
                    },
                    hunts: s.hunts.map { h in
                        BackupFile.Hunt(uuid: h.uuid, pokemonId: h.pokemonId, method: h.methodRaw, count: h.count, step: h.step,
                                        shinyCharm: h.shinyCharm, sparklingPower: h.sparklingPower, research: h.research,
                                        outbreakTier: h.outbreakTier, lure: h.lure, customOdds: h.customOdds, startedAt: h.startedAt,
                                        updatedAt: h.updatedAt, foundAt: h.foundAt, elapsed: h.totalTime(), phases: h.phasesData,
                                        notes: h.notes)
                    },
                    links: s.links.map { l in
                        BackupFile.Link(uuid: l.uuid, route: l.route, locationId: l.locationId, nickname: l.nickname,
                                        status: l.statusRaw, createdAt: l.createdAt, diedAt: l.diedAt, deathNote: l.deathNote)
                    })
            },
            favorites: favorites.map { BackupFile.Favorite(pokemonId: $0.pokemonId, shiny: $0.shiny, addedAt: $0.addedAt) })
    }

    static func data(context: ModelContext) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(make(context: context))) ?? Data()
    }

    static func decode(_ data: Data) -> BackupFile? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BackupFile.self, from: data)
    }

    static func read(_ url: URL) -> BackupFile? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    static var fileName: String {
        "ArcDex-Backup-" + Date().formatted(.iso8601.year().month().day())
    }

    // MARK: Restore

    /// Save files from the backup replace the ones with the same id; everything else stays. Favorites are added.
    static func restore(_ backup: BackupFile, context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Savegame>())) ?? []
        for entry in backup.saves {
            if let old = existing.first(where: { $0.uuid == entry.uuid }) {
                HuntActivityManager.end(huntsOf: old)
                context.delete(old)
            }
        }
        try? context.save()

        for entry in backup.saves {
            let save = Savegame(game: Game(rawValue: entry.game) ?? .swsh, platform: Platform(rawValue: entry.platform), name: entry.name)
            context.insert(save)
            save.uuid = entry.uuid
            save.createdAt = entry.createdAt
            save.modeRaw = entry.mode
            save.rulesData = entry.rules
            save.player1 = entry.player1
            save.player2 = entry.player2

            var teams: [UUID: Team] = [:]
            for t in entry.teams {
                let team = Team(name: t.name, game: Game(rawValue: t.game) ?? save.game)
                context.insert(team)
                team.uuid = t.uuid
                team.createdAt = t.createdAt
                team.formatRaw = t.format
                team.player = t.player
                team.savegame = save
                team.updatedAt = t.updatedAt
                teams[t.uuid] = team
            }
            var links: [UUID: NuzlockeLink] = [:]
            for l in entry.links {
                let link = NuzlockeLink(route: l.route, locationId: l.locationId)
                context.insert(link)
                link.uuid = l.uuid
                link.nickname = l.nickname
                link.statusRaw = l.status
                link.createdAt = l.createdAt
                link.diedAt = l.diedAt
                link.deathNote = l.deathNote
                link.savegame = save
                links[l.uuid] = link
            }
            for e in entry.members {
                let m = TeamMember(pokemonId: e.pokemonId, order: e.order, level: e.level)
                context.insert(m)
                m.uuid = e.uuid
                m.player = e.player
                m.nickname = e.nickname
                m.shiny = e.shiny
                m.gender = e.gender
                m.itemId = e.itemId
                m.abilityId = e.abilityId
                m.natureId = e.natureId
                m.teraTypeId = e.teraTypeId
                m.megaFormId = e.megaFormId
                m.gigantamax = e.gigantamax
                m.moveIds = e.moveIds
                m.evs = e.evs
                m.ivs = e.ivs
                m.team = e.teamID.flatMap { teams[$0] }
                m.link = e.linkID.flatMap { links[$0] }
            }
            for h in entry.hunts {
                let hunt = ShinyHunt(pokemonId: h.pokemonId, method: HuntMethod(rawValue: h.method) ?? .encounter)
                context.insert(hunt)
                hunt.uuid = h.uuid
                hunt.count = h.count
                hunt.step = h.step
                hunt.shinyCharm = h.shinyCharm
                hunt.sparklingPower = h.sparklingPower
                hunt.research = h.research
                hunt.outbreakTier = h.outbreakTier
                hunt.lure = h.lure
                hunt.customOdds = h.customOdds
                hunt.startedAt = h.startedAt
                hunt.updatedAt = h.updatedAt
                hunt.foundAt = h.foundAt
                hunt.elapsed = h.elapsed
                hunt.phasesData = h.phases
                hunt.notes = h.notes
                hunt.savegame = save
            }
            save.updatedAt = entry.updatedAt
        }

        let favorites = (try? context.fetch(FetchDescriptor<FavoritePokemon>())) ?? []
        for f in backup.favorites where !favorites.contains(where: { $0.pokemonId == f.pokemonId && $0.shiny == f.shiny }) {
            let fav = FavoritePokemon(pokemonId: f.pokemonId, shiny: f.shiny)
            fav.addedAt = f.addedAt
            context.insert(fav)
        }
        try? context.save()
    }
}

struct BackupFileShare: Transferable {
    let data: Data
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .arcdexBackup) { file in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("backup", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("\(file.name).arcdexbackup")
            try file.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

/// Confirmation before restoring a backup.
struct BackupRestoreSheet: View {
    let backup: BackupFile
    var onDone: () -> Void
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "externaldrive.fill.badge.timemachine")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 80)
                    .background(Color.indigo.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.top, 20)
                Text(L("Backup vom \(backup.createdAt.formatted(date: .abbreviated, time: .shortened))",
                       "Backup from \(backup.createdAt.formatted(date: .abbreviated, time: .shortened))"))
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                FlowLayout(spacing: 8) {
                    StatPill(icon: "gamecontroller.fill", text: L("\(backup.saves.count) Spielstände", "\(backup.saves.count) save files"))
                    StatPill(icon: "square.grid.2x2.fill", text: "\(backup.teamCount) Teams")
                    StatPill(icon: "scope", text: "\(backup.huntCount) Hunts")
                    if backup.runCount > 0 { StatPill(icon: "flame.fill", text: L("\(backup.runCount) Runs", "\(backup.runCount) runs")) }
                    StatPill(icon: "heart.fill", text: L("\(backup.favorites.count) Favoriten", "\(backup.favorites.count) favorites"))
                }
                Label(L("Spielstände aus dem Backup ersetzen deine gleichen Spielstände. Alles, was nicht im Backup ist, bleibt erhalten.",
                        "Save files from the backup replace the same save files on this phone. Everything that isn't in the backup stays."),
                      systemImage: "info.circle")
                    .font(.subheadline)
                    .padding(14)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Spacer()
                Button {
                    Backup.restore(backup, context: context)
                    onDone()
                } label: {
                    Text(L("Wiederherstellen", "Restore")).font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(20)
            .navigationTitle(L("Backup laden", "Load backup"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { onDone() } }
            }
        }
    }
}
