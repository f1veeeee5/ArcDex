import SwiftUI
import SwiftData

// MARK: - Save file detail

struct SavegameDetailView: View {
    @Bindable var save: Savegame
    @Binding var path: NavigationPath
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultLevel") private var defaultLevel = 50

    @State private var showNewHunt = false
    @State private var showScan = false
    @State private var showImport = false
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var renaming: Team?
    @State private var renameText = ""

    private var game: Game { save.game }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if game.hasShinyHunting {
                    sectionTitle(L("Shiny-Hunts", "Shiny hunts"), icon: "scope") {
                        Button { showNewHunt = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                            .accessibilityLabel(L("Neuer Shiny-Hunt", "New shiny hunt"))
                    }
                    let hunts = save.activeHunts
                    if hunts.isEmpty {
                        StartHuntCard(game: game) { showNewHunt = true }
                    } else {
                        VStack(spacing: 12) {
                            ForEach(hunts) { hunt in
                                HuntRowCard(hunt: hunt) { path.append(hunt) }
                                    .contextMenu {
                                        Button(role: .destructive) { delete(hunt) } label: { Label(L("Hunt löschen", "Delete hunt"), systemImage: "trash") }
                                    }
                            }
                        }
                    }
                }

                sectionTitle("Teams", icon: "square.grid.2x2.fill") {
                    Menu {
                        teamMenu
                    } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                    .accessibilityLabel(L("Team hinzufügen", "Add team"))
                }
                let teams = save.sortedTeams
                if teams.isEmpty {
                    EmptyTeamsView(game: game,
                                   onCreate: createTeam,
                                   onScan: { showScan = true },
                                   onImport: { showImport = true })
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(teams) { team in
                            NavigationLink(value: team) { TeamCard(team: team) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { renameText = team.name; renaming = team } label: { Label(L("Umbenennen", "Rename"), systemImage: "pencil") }
                                    Button { duplicate(team) } label: { Label(L("Duplizieren", "Duplicate"), systemImage: "plus.square.on.square") }
                                    Button(role: .destructive) { context.delete(team) } label: { Label(L("Löschen", "Delete"), systemImage: "trash") }
                                }
                        }
                    }
                }

                let found = save.foundHunts
                if !found.isEmpty {
                    sectionTitle(L("Gefundene Shinys", "Shinies found"), icon: "sparkles") { EmptyView() }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                        ForEach(found) { hunt in
                            Button { path.append(hunt) } label: { FoundShinyTile(hunt: hunt) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) { delete(hunt) } label: { Label(L("Löschen", "Delete"), systemImage: "trash") }
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(save.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if game.hasShinyHunting {
                        Button { showNewHunt = true } label: { Label(L("Neuer Shiny-Hunt", "New shiny hunt"), systemImage: "scope") }
                    }
                    teamMenu
                } label: { Image(systemName: "plus") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEdit = true } label: { Label(L("Bearbeiten", "Edit"), systemImage: "pencil") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label(L("Spielstand löschen", "Delete save file"), systemImage: "trash") }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .sheet(isPresented: $showNewHunt) {
            HuntSettingsSheet(game: game, hunt: nil) { draft in
                let hunt = ShinyHunt(pokemonId: draft.pokemonId ?? 25, method: draft.method)
                context.insert(hunt)
                draft.apply(to: hunt)
                hunt.savegame = save
                save.touch()
                path.append(hunt)
            }
        }
        .sheet(isPresented: $showImport) {
            ShowdownImportView(game: game) { imported in
                let team = newTeam(name: imported.name ?? L("Importiertes Team", "Imported team"))
                for (i, m) in imported.members.prefix(6).enumerated() {
                    let member = Showdown.makeMember(m, order: i)
                    context.insert(member)
                    member.team = team
                }
                path.append(team)
            }
        }
        .sheet(isPresented: $showScan) {
            MemberScanSheet(game: game, mode: .team) { scanned in
                let team = newTeam(name: nextTeamName)
                for (i, s) in scanned.prefix(6).enumerated() {
                    guard let pid = s.pokemonId else { continue }
                    let member = TeamMember(pokemonId: pid, order: i, level: game.fixedLevel ?? s.level ?? defaultLevel)
                    context.insert(member)
                    member.team = team
                    member.apply(s, replaceSpecies: false)
                }
                path.append(team)
            }
        }
        .sheet(isPresented: $showEdit) {
            SavegameEditSheet(save: save, suggested: nil) { _ in }
        }
        .alert(L("Team umbenennen", "Rename team"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(L("Name", "Name"), text: $renameText)
            Button(L("Sichern", "Save")) { renaming?.name = renameText; renaming = nil }
            Button(L("Abbrechen", "Cancel"), role: .cancel) { renaming = nil }
        }
        .confirmationDialog(L("Spielstand löschen?", "Delete save file?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("Löschen", "Delete"), role: .destructive) {
                HuntActivityManager.end(huntsOf: save)
                context.delete(save)
                dismiss()
            }
        } message: {
            Text(L("Alle Teams und Shiny-Hunts darin werden ebenfalls gelöscht.", "All teams and shiny hunts in it will be deleted too."))
        }
    }

    @ViewBuilder private var teamMenu: some View {
        Button(action: createTeam) { Label(L("Neues Team", "New team"), systemImage: "plus") }
        Button { showScan = true } label: { Label(L("Team scannen", "Scan team"), systemImage: "camera.viewfinder") }
        Button { showImport = true } label: { Label(L("Aus Showdown importieren", "Import from Showdown"), systemImage: "square.and.arrow.down") }
    }

    private var header: some View {
        HStack(spacing: 14) {
            GameMechanicIcon(game: game, size: 24)
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(game.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(save.displayName).font(.title2.weight(.bold)).lineLimit(2)
                HStack(spacing: 8) {
                    if !save.name.isEmpty {
                        Text(game.compactTitle)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(game.gradient, in: Capsule())
                    }
                    Label(save.platform.title, systemImage: save.platform.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    private func sectionTitle<Accessory: View>(_ title: String, icon: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack {
            Label(title, systemImage: icon).font(.title3.weight(.bold))
            Spacer()
            accessory()
        }
        .padding(.top, 6)
    }

    private var nextTeamName: String { "Team \(save.teams.count + 1)" }

    private func newTeam(name: String) -> Team {
        let team = Team(name: name, game: game)
        if game.isChampions { team.format = .doubles }
        context.insert(team)
        team.savegame = save
        save.touch()
        return team
    }

    private func createTeam() {
        path.append(newTeam(name: nextTeamName))
    }

    private func duplicate(_ team: Team) {
        let copy = newTeam(name: team.name + L(" (Kopie)", " (Copy)"))
        copy.format = team.format
        for m in team.sortedMembers {
            let n = TeamMember(pokemonId: m.pokemonId, order: m.order, level: m.level)
            context.insert(n)
            n.nickname = m.nickname; n.shiny = m.shiny; n.gender = m.gender
            n.itemId = m.itemId; n.abilityId = m.abilityId; n.natureId = m.natureId
            n.teraTypeId = m.teraTypeId; n.megaFormId = m.megaFormId; n.gigantamax = m.gigantamax
            n.moveIds = m.moveIds; n.evs = m.evs; n.ivs = m.ivs
            n.team = copy
        }
    }

    private func delete(_ hunt: ShinyHunt) {
        HuntActivityManager.end(hunt: hunt)
        context.delete(hunt)
    }
}

// MARK: - Create / edit a save file

struct SavegameEditSheet: View {
    var save: Savegame?
    var suggested: Game?
    var onSave: (Savegame) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var game: Game?
    @State private var platform: Platform = .switch1
    @State private var name = ""
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Group {
                if let game {
                    form(game)
                } else {
                    GameGrid(suggested: suggested,
                             question: L("Welches Spiel spielst du?", "Which game are you playing?")) { picked in
                        withAnimation(.snappy) {
                            self.game = picked
                            platform = Platform.defaultPlatform(for: picked)
                        }
                    }
                }
            }
            .navigationTitle(save == nil ? L("Neuer Spielstand", "New save file") : L("Spielstand bearbeiten", "Edit save file"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                if game != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(save == nil ? L("Anlegen", "Create") : L("Sichern", "Save"), action: commit)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let save {
                game = save.game
                platform = save.platform
                name = save.name
            }
        }
    }

    private func form(_ game: Game) -> some View {
        Form {
            Section(L("Spiel", "Game")) {
                Button {
                    withAnimation(.snappy) { self.game = nil }
                } label: {
                    HStack(spacing: 12) {
                        GameMechanicIcon(game: game, size: 18)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(game.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text(game.title).foregroundStyle(.primary)
                        Spacer()
                        Text(L("Ändern", "Change")).font(.subheadline).foregroundStyle(.tint)
                    }
                }
            }
            Section {
                Picker(L("System", "System"), selection: $platform) {
                    ForEach(Platform.options(for: game)) { p in
                        Label(p.title, systemImage: p.icon).tag(p)
                    }
                }
                TextField(L("Name (optional, z. B. Nuzlocke)", "Name (optional, e.g. Nuzlocke)"), text: $name)
            } footer: {
                Text(L("Ohne Namen wird der Spieltitel angezeigt.", "Without a name the game title is shown."))
            }
        }
        .onChange(of: self.game) { _, new in
            if let new, !Platform.options(for: new).contains(platform) { platform = Platform.defaultPlatform(for: new) }
        }
    }

    private func commit() {
        guard let game else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let save {
            if save.game != game {
                save.game = game
                for t in save.teams { t.game = game }
                for h in save.hunts where !HuntMethod.available(in: game).contains(h.method) { h.method = .encounter }
            }
            save.platform = platform
            save.name = trimmed
            save.touch()
            onSave(save)
        } else {
            let new = Savegame(game: game, platform: platform, name: trimmed)
            context.insert(new)
            onSave(new)
        }
        dismiss()
    }
}

/// Grid of all games grouped by generation.
struct GameGrid: View {
    var suggested: Game?
    var question: String
    var onPick: (Game) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(question)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(Game.generations, id: \.gen) { group in
                    Text(group.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(group.games) { game in
                            Button { onPick(game) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        GameMechanicIcon(game: game, size: 18)
                                        Spacer()
                                        Text(game.shortTitle).font(.caption.weight(.heavy))
                                            .padding(.horizontal, 7).padding(.vertical, 3)
                                            .background(.white.opacity(0.22), in: Capsule())
                                    }
                                    Spacer(minLength: 0)
                                    Text(game.title).font(.headline).multilineTextAlignment(.leading)
                                        .lineLimit(2).minimumScaleFactor(0.8)
                                }
                                .foregroundStyle(.white)
                                .padding(12)
                                .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                                .background(game.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay {
                                    if game == suggested {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}
