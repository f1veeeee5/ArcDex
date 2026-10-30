import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Start page: all save files (each with its teams and shiny hunts).
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Savegame.updatedAt, order: .reverse) private var allSaves: [Savegame]
    @Query(filter: #Predicate<ShinyHunt> { $0.foundAt == nil }, sort: \ShinyHunt.updatedAt, order: .reverse)
    private var activeHunts: [ShinyHunt]
    /// "all" or a Game raw value
    @AppStorage("gameFilter") private var filterRaw = "all"

    @State private var path = NavigationPath()
    @State private var showNewSave = false
    @State private var editingSave: Savegame?
    @State private var deletingSave: Savegame?
    @State private var showFileImport = false
    @State private var importedRun: ReceivedRun?

    private var filter: Game? { Game(rawValue: filterRaw) }
    private var saves: [Savegame] {
        guard let filter else { return allSaves }
        return allSaves.filter { $0.gameRaw == filter.rawValue }
    }
    private var hunts: [ShinyHunt] {
        activeHunts.filter { h in h.savegame != nil && (filter == nil || h.savegame?.gameRaw == filter?.rawValue) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GameFilterBar(filterRaw: $filterRaw, counts: countsPerGame, total: allSaves.count,
                                  countLabel: { n in L("\(n) \(n == 1 ? "Spielstand" : "Spielstände")", "\(n) \(n == 1 ? "save" : "saves")") })

                    if !hunts.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(L("Aktive Shiny-Hunts", "Active shiny hunts"), systemImage: "sparkles")
                                .font(.headline)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(hunts) { hunt in
                                        HuntMiniCard(hunt: hunt) { path.append(hunt) }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .scrollClipDisabled()
                        }
                    }

                    if saves.isEmpty {
                        EmptySavesView(game: filter) { showNewSave = true }
                    } else {
                        if !hunts.isEmpty {
                            Label(L("Spielstände", "Save files"), systemImage: "square.grid.2x2.fill")
                                .font(.headline)
                                .padding(.top, 4)
                        }
                        LazyVStack(spacing: 14) {
                            ForEach(saves) { save in
                                NavigationLink(value: save) {
                                    SavegameCard(save: save)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { editingSave = save } label: { Label(L("Bearbeiten", "Edit"), systemImage: "pencil") }
                                    Button(role: .destructive) { deletingSave = save } label: { Label(L("Löschen", "Delete"), systemImage: "trash") }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L("Spielstände", "Save Files"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showNewSave = true } label: { Label(L("Neuer Spielstand", "New save file"), systemImage: "plus") }
                        Button { showFileImport = true } label: { Label(L("Run aus Datei laden", "Load run from file"), systemImage: "square.and.arrow.down") }
                    } label: { Image(systemName: "plus") }
                    .accessibilityLabel(L("Neuer Spielstand", "New save file"))
                }
            }
            .navigationDestination(for: Savegame.self) { save in
                if save.mode.isRun {
                    NuzlockeRunView(save: save, path: $path)
                } else {
                    SavegameDetailView(save: save, path: $path)
                }
            }
            .navigationDestination(for: Team.self) { team in
                TeamDetailView(team: team, path: $path)
            }
            .navigationDestination(for: TeamMember.self) { member in
                if let team = member.team {
                    MemberPagerView(team: team, start: member)
                } else {
                    MemberEditView(member: member, game: member.link?.savegame?.game ?? .swsh)
                }
            }
            .navigationDestination(for: ShinyHunt.self) { hunt in
                HuntView(hunt: hunt, path: $path)
            }
            .navigationDestination(for: DexRoute.self) { route in
                PokemonDetailView(pokemonId: route.pokemonId, preferredGame: route.game)
            }
            .navigationDestination(for: DexAbilityRoute.self) { route in
                AbilityDetailView(abilityId: route.id, game: route.game)
            }
            .navigationDestination(for: DexMoveRoute.self) { route in
                MoveDetailView(moveId: route.id, preferredGame: route.game)
            }
            .navigationDestination(for: DexItemRoute.self) { route in
                ItemDetailView(itemId: route.id, game: route.game)
            }
            .sheet(isPresented: $showNewSave) {
                SavegameEditSheet(save: nil, suggested: filter) { new in
                    path.append(new)
                }
            }
            .sheet(item: $editingSave) { save in
                SavegameEditSheet(save: save, suggested: nil) { _ in }
            }
            .confirmationDialog(L("Spielstand löschen?", "Delete save file?"),
                                isPresented: Binding(get: { deletingSave != nil }, set: { if !$0 { deletingSave = nil } }),
                                titleVisibility: .visible, presenting: deletingSave) { save in
                Button(L("Löschen", "Delete"), role: .destructive) {
                    HuntActivityManager.end(huntsOf: save)
                    context.delete(save)
                }
            } message: { save in
                Text(L("Alle \(save.teams.count) Teams und \(save.hunts.count) Shiny-Hunts darin werden ebenfalls gelöscht.",
                       "All \(save.teams.count) teams and \(save.hunts.count) shiny hunts in it will be deleted too."))
            }
            .fileImporter(isPresented: $showFileImport, allowedContentTypes: [.arcdexRun, .json, .data]) { result in
                if case .success(let url) = result, let run = RunTransfer.read(url) {
                    importedRun = ReceivedRun(run: run)
                }
            }
            .sheet(item: $importedRun) { item in
                RunImportSheet(run: item.run) { save in
                    importedRun = nil
                    if let save {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            path = NavigationPath()
                            path.append(save)
                        }
                    }
                }
            }
            .task { SavegameMigration.run(context) }
            .onOpenURL { url in
                // arcdex://hunt/<uuid> – tapping the Live Activity opens the hunt
                guard url.host() == "hunt", let id = UUID(uuidString: url.lastPathComponent),
                      let hunt = activeHunts.first(where: { $0.uuid == id }) else { return }
                path = NavigationPath()
                if let save = hunt.savegame { path.append(save) }
                path.append(hunt)
            }
        }
    }

    private var countsPerGame: [Game: Int] {
        Dictionary(grouping: allSaves, by: \.game).mapValues(\.count)
    }
}

// MARK: - Save file card

struct SavegameCard: View {
    let save: Savegame

    var body: some View {
        let game = save.game
        let hunts = save.activeHunts
        let found = save.foundHunts.count
        let latestTeam = save.sortedTeams.first
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(save.displayName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        if !save.name.isEmpty {
                            Text(game.compactTitle)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(game.gradient, in: Capsule())
                        }
                        Label(save.platform.shortTitle, systemImage: save.platform.icon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                GameMechanicIcon(game: game, size: 18)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(game.gradient, in: Circle())
            }

            if let team = latestTeam, !team.members.isEmpty {
                HStack(spacing: 4) {
                    ForEach(team.sortedMembers) { m in
                        PokemonSprite(pokemonId: m.battleForm(in: game)?.id ?? m.pokemonId, shiny: m.shiny)
                            .frame(width: 40, height: 40)
                    }
                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 8) {
                if save.mode.isRun {
                    StatPill(icon: save.mode.icon, text: save.mode.title, highlight: true)
                    StatPill(icon: "heart.fill", text: L("\(save.links(.team).count + save.links(.box).count) leben", "\(save.links(.team).count + save.links(.box).count) alive"))
                    let dead = save.links(.dead).count
                    if dead > 0 { StatPill(icon: "xmark.seal.fill", text: L("\(dead) tot", "\(dead) fainted")) }
                } else {
                StatPill(icon: "square.grid.2x2.fill", text: "\(save.teams.count) \(save.teams.count == 1 ? "Team" : "Teams")")
                if game.hasShinyHunting {
                    StatPill(icon: "scope", text: "\(hunts.count) \(hunts.count == 1 ? "Hunt" : "Hunts")", highlight: !hunts.isEmpty)
                    if found > 0 {
                        StatPill(icon: "sparkles", text: "\(found) Shiny\(found == 1 ? "" : "s")", highlight: true)
                    }
                }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .card()
        .overlay(alignment: .leading) {
            Capsule().fill(game.gradient).frame(width: 4).padding(.vertical, 18)
        }
    }
}

struct StatPill: View {
    let icon: String
    let text: String
    var highlight = false

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(highlight ? Color.orange : Color.secondary)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background((highlight ? Color.orange : Color.secondary).opacity(0.12), in: Capsule())
    }
}

struct EmptySavesView: View {
    let game: Game?
    var onCreate: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(game?.gradient ?? LinearGradient(colors: [Color(hex: 0x7300D6), Color(hex: 0xE5007E)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 84, height: 84)
                Image(systemName: "gamecontroller.fill").font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
            }
            .padding(.top, 30)
            Text(game.map { L("Noch kein Spielstand für \($0.title)", "No save file for \($0.title) yet") } ?? L("Noch keine Spielstände", "No save files yet"))
                .font(.title3.weight(.bold)).multilineTextAlignment(.center)
            Text(L("Lege einen Spielstand an – darin sammelst du deine Teams und Shiny-Hunts.",
                   "Create a save file – it holds your teams and shiny hunts."))
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(action: onCreate) {
                Label(L("Spielstand anlegen", "Create save file"), systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .card()
    }
}

// MARK: - Game filter

struct GameFilterBar: View {
    @Binding var filterRaw: String
    var counts: [Game: Int]
    var total: Int
    var countLabel: (Int) -> String = { n in L("\(n) \(n == 1 ? "Team" : "Teams")", "\(n) \(n == 1 ? "team" : "teams")") }

    private var selected: Game? { Game(rawValue: filterRaw) }

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Picker(selection: $filterRaw.animation(.snappy)) {
                    Text(L("Alle Spiele", "All games") + "  (\(total))").tag("all")
                    GameMenuItems(counts: counts)
                } label: { EmptyView() }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.subheadline.weight(.bold))
                    Text(selected?.compactTitle ?? L("Alle Spiele", "All games"))
                        .lineLimit(1)
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(selected == nil ? Color.primary : Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background {
                    Capsule().fill(selected.map { AnyShapeStyle($0.gradient) } ?? AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
                }
                .contentShape(Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            if selected != nil {
                Button {
                    withAnimation(.snappy) { filterRaw = "all" }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(9)
                        .background(Color(.secondarySystemGroupedBackground), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Filter entfernen", "Clear filter"))
                .transition(.scale.combined(with: .opacity))
            }
            Spacer()
            let count = selected.map { counts[$0] ?? 0 } ?? total
            Text(countLabel(count))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Team card

struct TeamCard: View {
    let team: Team

    var body: some View {
        let members = team.sortedMembers
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(team.name).font(.title3.weight(.bold)).foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text(team.game.title)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(team.game.gradient, in: Capsule())
                        Text(team.updatedAt, format: .relative(presentation: .named))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            HStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { i in
                    VStack(spacing: 6) {
                        ZStack(alignment: .topTrailing) {
                            Circle().fill(Color(.tertiarySystemFill))
                            if i < members.count {
                                let m = members[i]
                                PokemonSprite(pokemonId: m.battleForm(in: team.game)?.id ?? m.pokemonId, shiny: m.shiny)
                                    .padding(4)
                                if m.shiny { ShinyBadge().offset(x: 2, y: -2) }
                            }
                        }
                        .aspectRatio(1, contentMode: .fit)

                        HStack(spacing: 3) {
                            if i < members.count {
                                ForEach(members[i].types(in: team.game), id: \.self) { t in
                                    Circle().fill(TypeColor.color(t)).frame(width: 7, height: 7)
                                }
                            }
                        }
                        .frame(height: 7)
                    }
                }
            }
        }
        .padding(16)
        .card()
        .overlay(alignment: .leading) {
            Capsule().fill(team.game.gradient).frame(width: 4).padding(.vertical, 18)
        }
    }
}

struct EmptyTeamsView: View {
    let game: Game?
    var onCreate: () -> Void
    var onScan: () -> Void
    var onImport: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(game?.gradient ?? LinearGradient(colors: [Color(hex: 0x7300D6), Color(hex: 0xE5007E)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 84, height: 84)
                Image(systemName: "camera.viewfinder").font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
            }
            .padding(.top, 30)
            Text(game.map { L("Noch keine Teams für \($0.title)", "No teams for \($0.title) yet") } ?? L("Noch keine Teams", "No teams yet"))
                .font(.title3.weight(.bold)).multilineTextAlignment(.center)
            Text(L("Fotografiere dein Team in der Switch oder lege es selbst an.", "Take a photo of your team on the Switch or build it yourself."))
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(spacing: 10) {
                Button(action: onScan) {
                    Label(L("Team scannen", "Scan team"), systemImage: "camera.viewfinder").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                HStack(spacing: 10) {
                    Button(action: onCreate) { Label(L("Neues Team", "New team"), systemImage: "plus").frame(maxWidth: .infinity) }
                    Button(action: onImport) { Label("Showdown", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .card()
    }
}
