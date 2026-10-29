import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Team.updatedAt, order: .reverse) private var allTeams: [Team]
    /// "all" or a Game raw value
    @AppStorage("gameFilter") private var filterRaw = "all"
    @AppStorage("defaultLevel") private var defaultLevel = 50

    private enum AddAction: String, Identifiable {
        case create, scan, importShowdown
        var id: String { rawValue }
    }

    @State private var path = NavigationPath()
    @State private var askGame: AddAction?
    @State private var pendingAction: AddAction?
    @State private var pendingGame: Game?
    @State private var importGame: Game?
    @State private var scanGame: Game?
    @State private var renaming: Team?
    @State private var renameText = ""

    private var filter: Game? { Game(rawValue: filterRaw) }
    private var teams: [Team] {
        guard let filter else { return allTeams }
        return allTeams.filter { $0.gameRaw == filter.rawValue }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GameFilterBar(filterRaw: $filterRaw, counts: countsPerGame, total: allTeams.count)

                    if teams.isEmpty {
                        EmptyTeamsView(game: filter,
                                       onCreate: { askGame = .create },
                                       onScan: { askGame = .scan },
                                       onImport: { askGame = .importShowdown })
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(teams) { team in
                                NavigationLink(value: team) {
                                    TeamCard(team: team)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { renameText = team.name; renaming = team } label: { Label(L("Umbenennen", "Rename"), systemImage: "pencil") }
                                    Button { duplicate(team) } label: { Label(L("Duplizieren", "Duplicate"), systemImage: "plus.square.on.square") }
                                    Button(role: .destructive) { context.delete(team) } label: { Label(L("Löschen", "Delete"), systemImage: "trash") }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L("Meine Teams", "My Teams"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { askGame = .create } label: { Label(L("Neues Team", "New team"), systemImage: "plus") }
                        Button { askGame = .scan } label: { Label(L("Team scannen", "Scan team"), systemImage: "camera.viewfinder") }
                        Button { askGame = .importShowdown } label: { Label(L("Aus Showdown importieren", "Import from Showdown"), systemImage: "square.and.arrow.down") }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: Team.self) { team in
                TeamDetailView(team: team, path: $path)
            }
            .navigationDestination(for: TeamMember.self) { member in
                MemberEditView(member: member, game: member.team?.game ?? .swsh)
                    .onDisappear { member.team?.touch() }
            }
            .navigationDestination(for: DexRoute.self) { route in
                PokemonDetailView(pokemonId: route.pokemonId, preferredGame: route.game)
            }
            .sheet(item: $askGame, onDismiss: runPendingAction) { action in
                GameChooserSheet(suggested: filter, title: title(for: action)) { game in
                    pendingGame = game
                    pendingAction = action
                }
            }
            .sheet(item: $importGame) { game in
                ShowdownImportView(game: game) { imported in
                    let team = Team(name: imported.name ?? L("Importiertes Team", "Imported team"), game: game)
                    context.insert(team)
                    for (i, m) in imported.members.prefix(6).enumerated() {
                        let member = Showdown.makeMember(m, order: i)
                        context.insert(member)
                        member.team = team
                    }
                    path.append(team)
                }
            }
            .sheet(item: $scanGame) { game in
                MemberScanSheet(game: game, mode: .team) { scanned in
                    let team = Team(name: nextTeamName(for: game), game: game)
                    context.insert(team)
                    for (i, s) in scanned.prefix(6).enumerated() {
                        guard let pid = s.pokemonId else { continue }
                        let member = TeamMember(pokemonId: pid, order: i, level: s.level ?? defaultLevel)
                        context.insert(member)
                        member.team = team
                        member.apply(s, replaceSpecies: false)
                    }
                    path.append(team)
                }
            }
            .alert(L("Team umbenennen", "Rename team"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField(L("Name", "Name"), text: $renameText)
                Button(L("Sichern", "Save")) { renaming?.name = renameText; renaming = nil }
                Button(L("Abbrechen", "Cancel"), role: .cancel) { renaming = nil }
            }
        }
    }

    private func title(for action: AddAction) -> String {
        switch action {
        case .create: return L("Neues Team", "New team")
        case .scan: return L("Team scannen", "Scan team")
        case .importShowdown: return L("Showdown-Import", "Showdown import")
        }
    }

    private func runPendingAction() {
        guard let game = pendingGame, let action = pendingAction else { return }
        pendingGame = nil
        pendingAction = nil
        switch action {
        case .create: createTeam(in: game)
        case .scan: scanGame = game
        case .importShowdown: importGame = game
        }
    }

    private var countsPerGame: [Game: Int] {
        Dictionary(grouping: allTeams, by: \.game).mapValues(\.count)
    }

    private func nextTeamName(for game: Game) -> String {
        "Team \(allTeams.filter { $0.game == game }.count + 1)"
    }

    private func createTeam(in game: Game) {
        let team = Team(name: nextTeamName(for: game), game: game)
        context.insert(team)
        path.append(team)
    }

    private func duplicate(_ team: Team) {
        let copy = Team(name: team.name + L(" (Kopie)", " (Copy)"), game: team.game)
        context.insert(copy)
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
}

// MARK: - Game filter

struct GameFilterBar: View {
    @Binding var filterRaw: String
    var counts: [Game: Int]
    var total: Int

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
            Text(L("\(count) \(count == 1 ? "Team" : "Teams")", "\(count) \(count == 1 ? "team" : "teams")"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct GameChooserSheet: View {
    var suggested: Game?
    var title: String
    var onPick: (Game) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("Aus welchem Spiel ist das Team?", "Which game is this team from?"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(Game.generations, id: \.gen) { group in
                        Text("Generation \(group.gen)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(group.games) { game in
                                Button {
                                    onPick(game)
                                    dismiss()
                                } label: {
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
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
            }
        }
        .presentationDetents([.large])
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
