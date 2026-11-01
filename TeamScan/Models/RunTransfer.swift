import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// ".arcdex" file with a shared Nuzlocke / Soul Link run.
    static let arcdexRun = UTType(exportedAs: "app.lukas.teamscan.run")
}

/// Everything of a run in one file – sent to the partner via AirDrop, WhatsApp, Messages …
nonisolated struct RunExport: Codable {
    struct Member: Codable {
        var uuid: UUID
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

    struct Link: Codable {
        var uuid: UUID
        var route: String
        var locationId: Int?
        var nickname: String
        var status: String
        var createdAt: Date
        var diedAt: Date?
        var deathNote: String
        var members: [Member]
    }

    var format = 1
    var runID: UUID
    var name: String
    var game: String
    var platform: String
    var mode: String
    var player1: String
    var player2: String
    var rules: NuzlockeRules
    var exportedAt: Date
    var links: [Link]
}

enum RunTransfer {
    // MARK: Export

    static func export(_ save: Savegame) -> RunExport {
        RunExport(
            runID: save.uuid, name: save.name, game: save.gameRaw, platform: save.platformRaw, mode: save.modeRaw,
            player1: save.player1, player2: save.player2, rules: save.rules, exportedAt: Date(),
            links: save.links.sorted { $0.createdAt < $1.createdAt }.map { l in
                RunExport.Link(uuid: l.uuid, route: l.route, locationId: l.locationId, nickname: l.nickname, status: l.statusRaw,
                               createdAt: l.createdAt, diedAt: l.diedAt, deathNote: l.deathNote,
                               members: l.members.sorted { $0.player < $1.player }.map { m in
                                   RunExport.Member(uuid: m.uuid, player: m.player, order: m.order, pokemonId: m.pokemonId,
                                                    nickname: m.nickname, level: m.level, shiny: m.shiny, gender: m.gender,
                                                    itemId: m.itemId, abilityId: m.abilityId, natureId: m.natureId,
                                                    teraTypeId: m.teraTypeId, megaFormId: m.megaFormId, gigantamax: m.gigantamax,
                                                    moveIds: m.moveIds, evs: m.evs, ivs: m.ivs)
                               })
            })
    }

    static func data(_ save: Savegame) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(export(save))) ?? Data()
    }

    static func decode(_ data: Data) -> RunExport? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RunExport.self, from: data)
    }

    static func read(_ url: URL) -> RunExport? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    static func fileName(_ save: Savegame) -> String {
        let base = save.displayName.components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:")).joined()
        return base.isEmpty ? "Run" : base
    }

    // MARK: Import

    static func existing(_ run: RunExport, context: ModelContext) -> Savegame? {
        let id = run.runID
        return try? context.fetch(FetchDescriptor<Savegame>(predicate: #Predicate { $0.uuid == id })).first
    }

    /// Creates the run, or replaces its catches with the received state. Returns the save file.
    @discardableResult
    static func apply(_ run: RunExport, context: ModelContext) -> Savegame {
        let save: Savegame
        if let found = existing(run, context: context) {
            save = found
            for link in save.links { context.delete(link) }
            save.links.removeAll()
            for team in save.teams where team.player > 0 {
                for m in team.members { context.delete(m) }
            }
        } else {
            let game = Game(rawValue: run.game) ?? .swsh
            save = Savegame(game: game, platform: Platform(rawValue: run.platform), name: run.name)
            save.uuid = run.runID
            context.insert(save)
        }
        save.gameRaw = run.game
        save.platformRaw = run.platform
        save.name = run.name
        save.modeRaw = run.mode
        save.player1 = run.player1
        save.player2 = run.player2
        save.rules = run.rules

        for p in save.players {
            let team = save.runTeam(p, context: context)
            team.name = save.playerName(p)
            team.game = save.game
        }

        for l in run.links {
            let link = NuzlockeLink(route: l.route, locationId: l.locationId)
            link.uuid = l.uuid
            link.nickname = l.nickname
            link.statusRaw = l.status
            link.createdAt = l.createdAt
            link.diedAt = l.diedAt
            link.deathNote = l.deathNote
            context.insert(link)
            link.savegame = save
            for e in l.members {
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
                m.link = link
                if link.status == .team { m.team = save.runTeam(e.player, context: context) }
            }
        }
        save.touch()
        try? context.save()
        return save
    }
}

/// The run as a shareable file.
struct RunFile: Transferable {
    let data: Data
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .arcdexRun) { file in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("share", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("\(file.name).arcdex")
            try file.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

/// Asks before a received run is added or replaces the own state.
struct RunImportSheet: View {
    let run: RunExport
    var onDone: (Savegame?) -> Void
    @Environment(\.modelContext) private var context

    var body: some View {
        let existing = RunTransfer.existing(run, context: context)
        let game = Game(rawValue: run.game) ?? .swsh
        let mode = RunMode(rawValue: run.mode) ?? .nuzlocke
        let alive = run.links.filter { $0.status == LinkStatus.team.rawValue || $0.status == LinkStatus.box.rawValue }.count
        let dead = run.links.filter { $0.status == LinkStatus.dead.rawValue }.count
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: mode.icon)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 80)
                    .background(game.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.top, 20)
                VStack(spacing: 4) {
                    Text(run.name.isEmpty ? game.title : run.name).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                    Text("\(mode.title) · \(game.title)").font(.subheadline).foregroundStyle(.secondary)
                    if mode == .soulLink {
                        Text("\(run.player1.isEmpty ? L("Spieler 1", "Player 1") : run.player1) & \(run.player2.isEmpty ? L("Spieler 2", "Player 2") : run.player2)")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                HStack(spacing: 8) {
                    StatPill(icon: "heart.fill", text: L("\(alive) leben", "\(alive) alive"), highlight: true)
                    StatPill(icon: "xmark.seal.fill", text: L("\(dead) tot", "\(dead) fainted"))
                    StatPill(icon: "map", text: L("\(run.links.count) Begegnungen", "\(run.links.count) encounters"))
                }
                Text(L("Stand vom \(run.exportedAt.formatted(date: .abbreviated, time: .shortened))",
                       "State from \(run.exportedAt.formatted(date: .abbreviated, time: .shortened))"))
                    .font(.footnote).foregroundStyle(.secondary)

                if existing != nil {
                    Label(L("Diesen Run hast du schon. Dein Stand wird durch den empfangenen ersetzt (Fänge, Box, Friedhof, Regeln).",
                            "You already have this run. Your state will be replaced by the received one (catches, box, graveyard, rules)."),
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline)
                        .padding(14)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Spacer()
                Button {
                    let save = RunTransfer.apply(run, context: context)
                    onDone(save)
                } label: {
                    Text(existing == nil ? L("Run hinzufügen", "Add run") : L("Stand übernehmen", "Use this state"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.appPrimary)
                .controlSize(.large)
            }
            .padding(20)
            .navigationTitle(L("Run empfangen", "Received run"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { onDone(nil) } }
            }
        }
        .presentationDetents([.large])
    }
}
