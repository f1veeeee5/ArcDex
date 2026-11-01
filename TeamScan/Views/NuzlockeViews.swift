import SwiftUI
import SwiftData

// MARK: - Run overview

struct NuzlockeRunView: View {
    @Bindable var save: Savegame
    @Binding var path: NavigationPath
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var newEncounter: EncounterPreset?
    @State private var editing: NuzlockeLink?
    @State private var showRules = false
    @State private var showRoutes = false
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var showBox = true

    private var game: Game { save.game }

    var body: some View {
        let team = save.links(.team)
        let box = save.links(.box)
        let dead = save.links(.dead)
        let warnings = NuzlockeCheck.run(save)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if !warnings.isEmpty {
                    WarningsCard(warnings: warnings)
                }

                sectionTitle("Team", icon: "square.grid.2x2.fill", count: "\(team.count)/6") {
                    Button { newEncounter = EncounterPreset() } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                        .accessibilityLabel(L("Neuer Fang", "New catch"))
                }
                if team.isEmpty {
                    EmptyRunCard(save: save) { newEncounter = EncounterPreset() }
                } else {
                    VStack(spacing: 10) {
                        ForEach(team) { link in
                            Button { editing = link } label: { LinkRow(link: link, save: save) }
                                .buttonStyle(.plain)
                        }
                    }
                    teamButtons
                }

                if !box.isEmpty {
                    Button {
                        withAnimation(.snappy) { showBox.toggle() }
                    } label: {
                        HStack {
                            Label("Box", systemImage: "archivebox.fill").font(.title3.weight(.bold))
                            Text("\(box.count)").font(.headline.monospacedDigit()).foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.subheadline.weight(.bold))
                                .rotationEffect(.degrees(showBox ? 0 : -90))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 6)
                    }
                    .buttonStyle(.plain)
                    if showBox {
                        VStack(spacing: 10) {
                            ForEach(box) { link in
                                Button { editing = link } label: { LinkRow(link: link, save: save) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }

                routesCard

                if !dead.isEmpty {
                    sectionTitle(L("Friedhof", "Graveyard"), icon: "xmark.seal.fill", count: "\(dead.count)") { EmptyView() }
                    VStack(spacing: 10) {
                        ForEach(dead) { link in
                            Button { editing = link } label: { LinkRow(link: link, save: save) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                rulesCard

                shareCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(save.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { newEncounter = EncounterPreset() } label: { Image(systemName: "plus") }
                    .accessibilityLabel(L("Neuer Fang", "New catch"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: RunFile(data: RunTransfer.data(save), name: RunTransfer.fileName(save)),
                              preview: SharePreview(save.displayName)) {
                        Label(L("Run teilen", "Share run"), systemImage: "square.and.arrow.up")
                    }
                    Button { showRoutes = true } label: { Label(L("Routen", "Routes"), systemImage: "map") }
                    Button { showRules = true } label: { Label(L("Regeln", "Rules"), systemImage: "list.bullet.clipboard") }
                    Button { showEdit = true } label: { Label(L("Bearbeiten", "Edit"), systemImage: "pencil") }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label(L("Run löschen", "Delete run"), systemImage: "trash") }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .sheet(item: $newEncounter) { preset in
            EncounterSheet(save: save, preset: preset)
        }
        .sheet(item: $editing) { link in
            LinkSheet(link: link, save: save) { member in
                editing = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { path.append(member) }
            }
        }
        .sheet(isPresented: $showRules) { RulesSheet(save: save) }
        .sheet(isPresented: $showRoutes) {
            RouteListSheet(save: save) { route, id in
                showRoutes = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { newEncounter = EncounterPreset(route: route, locationId: id) }
            } onOpen: { link in
                showRoutes = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { editing = link }
            }
        }
        .sheet(isPresented: $showEdit) { SavegameEditSheet(save: save, suggested: nil) { _ in } }
        .guardedDelete($confirmDelete, area: .saves, doubleConfirm: true, title: L("Run löschen?", "Delete run?"),
                       message: L("Alle Fänge, Teams und der Friedhof werden gelöscht.", "All catches, teams and the graveyard will be deleted.")) {
            context.delete(save)
            dismiss()
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: save.mode.icon)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(game.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(save.displayName).font(.title2.weight(.bold)).lineLimit(2)
                HStack(spacing: 6) {
                    Text(save.mode.title)
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(save.mode == .soulLink ? AnyShapeStyle(Color.purple.gradient) : AnyShapeStyle(Color.orange.gradient), in: Capsule())
                    Text(game.compactTitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(game.gradient, in: Capsule())
                    Label(save.platform.shortTitle, systemImage: save.platform.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if save.mode == .soulLink {
                    Text("\(save.playerName(1)) & \(save.playerName(2))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    private var teamButtons: some View {
        HStack(spacing: 10) {
            ForEach(save.players, id: \.self) { p in
                Button {
                    path.append(save.runTeam(p, context: context))
                } label: {
                    Label(save.mode == .soulLink ? L("Team \(save.playerName(p))", "\(save.playerName(p))’s team") : L("Team-Builder", "Team builder"),
                          systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.appSecondary)
            }
        }
    }

    private var routesCard: some View {
        let routes = Wiki.shared.routes(in: game)
        let used = Set(save.links.map { $0.route.lowercased() })
        let done = routes.filter { used.contains($0.name.lowercased()) }.count
        return Button { showRoutes = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "map.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Color.teal.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Routen", "Routes")).font(.headline).foregroundStyle(.primary)
                    Text(routes.isEmpty
                         ? L("\(save.links.count) Begegnungen · keine Routenliste für dieses Spiel", "\(save.links.count) encounters · no route list for this game")
                         : L("\(done) von \(routes.count) Gebieten mit Begegnung", "\(done) of \(routes.count) areas with an encounter"))
                        .font(.caption).foregroundStyle(.secondary)
                    if !routes.isEmpty {
                        ProgressView(value: Double(done), total: Double(max(routes.count, 1)))
                            .tint(.teal)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .card()
        }
        .buttonStyle(.plain)
    }

    private var rulesCard: some View {
        let r = save.rules
        var active: [String] = []
        if r.firstEncounterOnly { active.append(L("Erste Begegnung", "First encounter")) }
        if r.faintIsDeath { active.append(L("Besiegt = tot", "Fainted = dead")) }
        if r.nicknames { active.append(L("Spitznamen", "Nicknames")) }
        if r.dupesClause { active.append(L("Dupes-Klausel", "Dupes clause")) }
        if r.shinyClause { active.append(L("Shiny-Klausel", "Shiny clause")) }
        if r.levelCapOn { active.append(L("Level-Cap \(r.levelCap)", "Level cap \(r.levelCap)")) }
        if r.noItemsInBattle { active.append(L("Keine Items im Kampf", "No items in battle")) }
        if r.setMode { active.append(L("Set-Modus", "Set mode")) }
        if r.noLegendaries { active.append(L("Keine Legendären", "No legendaries")) }
        if save.mode == .soulLink && r.typeClause { active.append(L("Typ-Klausel", "Type clause")) }
        if save.mode == .soulLink && r.typeClauseShared { active.append(L("Typ-Klausel (beide)", "Type clause (both)")) }
        return Button { showRules = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(L("Regeln", "Rules"), systemImage: "list.bullet.clipboard").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                FlowLayout(spacing: 6) {
                    ForEach(active, id: \.self) { text in
                        Text(text)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                }
            }
            .foregroundStyle(.primary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .buttonStyle(.plain)
    }

    private var shareCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(save.mode == .soulLink ? L("Mit Partner teilen", "Share with your partner") : L("Run teilen", "Share run"),
                  systemImage: "square.and.arrow.up")
                .font(.headline)
            Text(save.mode == .soulLink
                 ? L("Schick den aktuellen Stand als Datei (AirDrop, WhatsApp, Nachrichten). Öffnet dein Partner sie mit ArcDex, hat er denselben Run – oder sein Stand wird aktualisiert. Nach Änderungen einfach neu schicken.",
                     "Send the current state as a file (AirDrop, WhatsApp, Messages). When your partner opens it with ArcDex, they get the same run – or their state is updated. Send it again after changes.")
                 : L("Schick den Stand als Datei, z. B. als Backup oder an ein anderes Gerät.", "Send the state as a file, e.g. as a backup or to another device."))
                .font(.footnote)
                .foregroundStyle(.secondary)
            ShareLink(item: RunFile(data: RunTransfer.data(save), name: RunTransfer.fileName(save)),
                      preview: SharePreview(save.displayName)) {
                Label(L("Stand senden", "Send state"), systemImage: "paperplane.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.appPrimary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func sectionTitle<A: View>(_ title: String, icon: String, count: String, @ViewBuilder accessory: () -> A) -> some View {
        HStack {
            Label(title, systemImage: icon).font(.title3.weight(.bold))
            Text(count).font(.headline.monospacedDigit()).foregroundStyle(.secondary)
            Spacer()
            accessory()
                .menuStyle(.button)
                .buttonStyle(.appIcon)
                .menuIndicator(.hidden)
        }
        .padding(.top, 6)
    }
}

struct EncounterPreset: Identifiable {
    let id = UUID()
    var route = ""
    var locationId: Int?
}

// MARK: - Rows & cards

struct LinkRow: View {
    let link: NuzlockeLink
    let save: Savegame

    var body: some View {
        let dead = link.status == .dead
        Group {
            if link.status == .missed {
                HStack(spacing: 12) {
                    Image(systemName: "slash.circle").font(.title2).foregroundStyle(.secondary).frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(link.route.isEmpty ? L("Ohne Route", "No route") : link.route).font(.headline)
                        Text(L("Verpasst / nichts gefangen", "Missed / nothing caught")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            } else if save.mode == .soulLink {
                HStack(spacing: 8) {
                    pokemonColumn(link.member(1))
                    VStack(spacing: 4) {
                        Text(link.nickname.isEmpty ? L("Ohne Namen", "No name") : link.nickname)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(link.nickname.isEmpty ? Color.secondary : Color.primary)
                        Image(systemName: dead ? "link.badge.plus" : "link")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(dead ? Color.secondary : Color.purple)
                        if !link.route.isEmpty {
                            Text(link.route).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    pokemonColumn(link.member(2))
                }
            } else {
                HStack(spacing: 12) {
                    sprite(link.member(1)).frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(link.displayName).font(.headline).lineLimit(1)
                        if let m = link.member(1) {
                            Text("\(m.species?.name ?? "?") · Lv. \(m.level)").font(.caption).foregroundStyle(.secondary)
                        }
                        if !link.route.isEmpty {
                            Text(link.route).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if let m = link.member(1) { typeDots(m) }
                }
            }
        }
        .padding(12)
        .card()
        .overlay(alignment: .topTrailing) {
            if dead, !link.deathNote.isEmpty {
                Text(link.deathNote)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                    .padding(8)
            }
        }
        .saturation(dead ? 0 : 1)
        .opacity(dead ? 0.7 : 1)
    }

    private func pokemonColumn(_ m: TeamMember?) -> some View {
        VStack(spacing: 3) {
            sprite(m).frame(width: 54, height: 54)
            Text(m?.species?.name ?? "–").font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            if let m {
                HStack(spacing: 4) {
                    Text("Lv. \(m.level)").font(.caption2).foregroundStyle(.secondary)
                    typeDots(m)
                }
            }
        }
        .frame(width: 92)
    }

    @ViewBuilder private func sprite(_ m: TeamMember?) -> some View {
        if let m {
            ZStack(alignment: .topTrailing) {
                PokemonSprite(pokemonId: m.battleForm(in: save.game)?.id ?? m.pokemonId, shiny: m.shiny)
                if m.shiny { ShinyBadge() }
            }
        } else {
            Image(systemName: "questionmark").foregroundStyle(.tertiary)
        }
    }

    private func typeDots(_ m: TeamMember) -> some View {
        HStack(spacing: 3) {
            ForEach(m.types(in: save.game), id: \.self) { t in
                Circle().fill(TypeColor.color(t)).frame(width: 7, height: 7)
            }
        }
    }
}

struct WarningsCard: View {
    let warnings: [RuleWarning]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(warnings) { w in
                Label { Text(w.text).font(.subheadline) } icon: { Image(systemName: w.icon).foregroundStyle(.orange) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct EmptyRunCard: View {
    let save: Savegame
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: save.mode.icon)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 70, height: 70)
                .background(save.game.gradient, in: Circle())
            Text(L("Noch keine Fänge", "No catches yet")).font(.headline)
            Text(save.mode == .soulLink
                 ? L("Tragt eure erste Begegnung ein – beide Pokémon bekommen denselben Spitznamen und landen im selben Slot.",
                     "Add your first encounter – both Pokémon share one nickname and the same slot.")
                 : L("Trag deine erste Begegnung ein.", "Add your first encounter."))
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(action: onAdd) {
                Label(L("Fang eintragen", "Add catch"), systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.appPrimary)
            .controlSize(.large)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .card()
    }
}

// MARK: - New encounter

struct EncounterSheet: View {
    @Bindable var save: Savegame
    var preset: EncounterPreset
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultLevel") private var defaultLevel = 50

    @State private var route = ""
    @State private var locationId: Int?
    @State private var caught = true
    @State private var species: [Int: Int] = [:]
    @State private var shiny: [Int: Bool] = [:]
    @State private var nickname = ""
    @State private var level = 5
    @State private var toTeam = true
    @State private var picking: Int?
    @State private var showRoutes = false
    @State private var loaded = false

    private var game: Game { save.game }
    private var status: LinkStatus { caught ? (toTeam && !save.teamIsFull ? .team : .box) : .missed }
    private var complete: Bool { !caught || save.players.allSatisfy { species[$0] != nil } }

    var body: some View {
        let warnings = NuzlockeCheck.encounter(save: save, route: route, species: caught ? species : [:], shiny: shiny,
                                               nickname: nickname, status: status)
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField(L("Route oder Gebiet", "Route or area"), text: $route)
                            .onChange(of: route) { _, new in
                                if let id = locationId, Wiki.shared.locationName(id) != new { locationId = nil }
                            }
                        Button { showRoutes = true } label: { Image(systemName: "list.bullet") }
                            .accessibilityLabel(L("Aus Liste wählen", "Pick from list"))
                    }
                    Picker(L("Ergebnis", "Result"), selection: $caught) {
                        Text(L("Gefangen", "Caught")).tag(true)
                        Text(L("Verpasst", "Missed")).tag(false)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text(L("Begegnung", "Encounter"))
                } footer: {
                    Text(L("Aus der Liste wählen oder selbst eintippen.", "Pick from the list or type it yourself."))
                }

                if caught {
                    Section {
                        ForEach(save.players, id: \.self) { p in
                            Button { picking = p } label: {
                                HStack(spacing: 12) {
                                    if let id = species[p] {
                                        PokemonSprite(pokemonId: id, shiny: shiny[p] ?? false).frame(width: 48, height: 48)
                                    } else {
                                        Image(systemName: "plus.circle.fill").font(.title2).frame(width: 48, height: 48)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        if save.mode == .soulLink {
                                            Text(save.playerName(p)).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Text(species[p].flatMap { Dex.shared.pokemon($0)?.name } ?? L("Pokémon wählen", "Choose Pokémon"))
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                    }
                                    Spacer()
                                }
                            }
                            if species[p] != nil {
                                Toggle(isOn: Binding(get: { shiny[p] ?? false }, set: { shiny[p] = $0 })) {
                                    Label("Shiny", systemImage: "sparkles")
                                }
                            }
                        }
                    } header: {
                        Text(save.mode == .soulLink ? L("Pokémon (verlinkt)", "Pokémon (linked)") : "Pokémon")
                    }

                    Section {
                        TextField(L("Spitzname", "Nickname"), text: $nickname)
                        AppStepper(value: $level, in: 1...100) {
                            HStack {
                                Text("Level")
                                Spacer()
                                Text("\(level)").monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        Picker(L("Ziel", "Goes to"), selection: $toTeam) {
                            Text("Team").tag(true)
                            Text("Box").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .disabled(save.teamIsFull)
                    } footer: {
                        Text(save.mode == .soulLink
                             ? L("Der Spitzname gilt für beide Pokémon. Im Team landen beide im selben Slot.", "The nickname is used for both Pokémon. In the team both get the same slot.")
                             : (save.teamIsFull ? L("Das Team ist voll – der Fang kommt in die Box.", "The team is full – the catch goes to the box.") : ""))
                    }
                }

                if !warnings.isEmpty {
                    Section(L("Regeln", "Rules")) {
                        ForEach(warnings) { w in
                            Label { Text(w.text).font(.subheadline) } icon: { Image(systemName: w.icon).foregroundStyle(.orange) }
                        }
                    }
                }
            }
            .navigationTitle(L("Neuer Fang", "New catch"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Eintragen", "Add")) {
                        NuzlockeActions.addEncounter(to: save, route: route, locationId: locationId, species: caught ? species : [:],
                                                     nickname: nickname, level: level, shiny: shiny, status: status, context: context)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!complete)
                }
            }
            .sheet(item: Binding(get: { picking.map { PlayerPick(player: $0) } }, set: { picking = $0?.player })) { pick in
                OptionPicker(title: save.mode == .soulLink ? save.playerName(pick.player) : L("Pokémon wählen", "Choose Pokémon"),
                             options: routeFirstOptions(), selected: species[pick.player]) { id in
                    if let id { species[pick.player] = id }
                }
            }
            .sheet(isPresented: $showRoutes) {
                RouteListSheet(save: save, picking: true) { name, id in
                    route = name
                    locationId = id
                    showRoutes = false
                } onOpen: { _ in }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            route = preset.route
            locationId = preset.locationId
            toTeam = !save.teamIsFull
            let lastLevels = save.links.flatMap(\.members).map(\.level)
            level = lastLevels.isEmpty ? 5 : max(2, min(lastLevels.max() ?? 5, 100))
        }
    }

    /// Pokémon of the chosen route first.
    private func routeFirstOptions() -> [PickerOption] {
        let all = PickerOptions.pokemon(game: game)
        guard let loc = locationId else { return all }
        let here = Set(Wiki.shared.pokemon(at: loc, game: game))
        guard !here.isEmpty else { return all }
        let first = all.filter { here.contains($0.id) }.map {
            PickerOption(id: $0.id, title: $0.title, subtitle: $0.subtitle, detail: L("Auf dieser Route", "On this route"),
                         accessory: .pokemon($0.id), types: $0.types)
        }
        return first + all.filter { !here.contains($0.id) }
    }
}

private struct PlayerPick: Identifiable {
    let player: Int
    var id: Int { player }
}

// MARK: - Edit a pair

struct LinkSheet: View {
    @Bindable var link: NuzlockeLink
    let save: Savegame
    var onOpenMember: (TeamMember) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var picking: Int?
    @State private var askDeath = false
    @State private var deathNote = ""
    @State private var confirmDelete = false

    private var game: Game { save.game }

    var body: some View {
        let warnings = link.status == .missed ? [] : NuzlockeCheck.encounter(
            save: save, route: link.route, species: Dictionary(link.members.map { ($0.player, $0.pokemonId) }, uniquingKeysWith: { a, _ in a }),
            shiny: Dictionary(link.members.map { ($0.player, $0.shiny) }, uniquingKeysWith: { a, _ in a }), nickname: link.nickname,
            status: link.status, ignoring: link)
        NavigationStack {
            Form {
                Section {
                    TextField(L("Spitzname", "Nickname"), text: Binding(get: { link.nickname }, set: { name in
                        link.nickname = name
                        for m in link.members { m.nickname = name }
                    }))
                    .font(.headline)
                    TextField(L("Route oder Gebiet", "Route or area"), text: $link.route)
                } footer: {
                    if save.mode == .soulLink { Text(L("Der Spitzname gilt für beide Pokémon.", "The nickname is used for both Pokémon.")) }
                }

                if link.status != .missed {
                    ForEach(save.players, id: \.self) { p in
                        if let m = link.member(p) {
                            Section(save.mode == .soulLink ? save.playerName(p) : "Pokémon") {
                                Button { picking = p } label: {
                                    HStack(spacing: 12) {
                                        PokemonSprite(pokemonId: m.battleForm(in: game)?.id ?? m.pokemonId, shiny: m.shiny)
                                            .frame(width: 52, height: 52)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(m.species?.name ?? "?").font(.headline).foregroundStyle(.primary)
                                            Text(L("Tippen zum Ändern (z. B. nach einer Entwicklung)", "Tap to change (e.g. after evolving)"))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                }
                                AppStepper(value: Binding(get: { m.level }, set: { m.level = $0; m.team?.touch() }), in: 1...100) {
                                    HStack { Text("Level"); Spacer(); Text("\(m.level)").monospacedDigit().foregroundStyle(.secondary) }
                                }
                                Toggle(isOn: Binding(get: { m.shiny }, set: { m.shiny = $0 })) { Label("Shiny", systemImage: "sparkles") }
                                Button { onOpenMember(m) } label: {
                                    Label(L("Attacken, Item & Werte bearbeiten", "Edit moves, item & stats"), systemImage: "slider.horizontal.3")
                                }
                            }
                        }
                    }

                    Section(L("Status", "Status")) {
                        if link.status != .team {
                            Button {
                                NuzlockeActions.set(link, to: .team, in: save, context: context)
                            } label: { Label(link.status == .dead ? L("Wiederbeleben ins Team", "Revive into team") : L("Ins Team", "To team"), systemImage: "square.grid.2x2.fill") }
                            .disabled(save.teamIsFull)
                        }
                        if link.status != .box {
                            Button {
                                NuzlockeActions.set(link, to: .box, in: save, context: context)
                            } label: { Label(link.status == .dead ? L("Wiederbeleben in die Box", "Revive into box") : L("In die Box", "To box"), systemImage: "archivebox.fill") }
                        }
                        if link.status != .dead {
                            Button(role: .destructive) {
                                deathNote = ""
                                askDeath = true
                            } label: {
                                Label(save.mode == .soulLink ? L("Gestorben – beide auf den Friedhof", "Fainted – both to the graveyard") : L("Gestorben", "Fainted"),
                                      systemImage: "xmark.seal.fill")
                            }
                        } else if !link.deathNote.isEmpty {
                            LabeledContent(L("Todesursache", "Cause"), value: link.deathNote)
                        }
                    }
                }

                if !warnings.isEmpty {
                    Section(L("Regeln", "Rules")) {
                        ForEach(warnings) { w in
                            Label { Text(w.text).font(.subheadline) } icon: { Image(systemName: w.icon).foregroundStyle(.orange) }
                        }
                    }
                }

                Section {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label(L("Eintrag löschen", "Delete entry"), systemImage: "trash")
                    }
                } footer: {
                    Text(L("Löschen entfernt den Eintrag ganz (z. B. bei einem Tippfehler). Für gestorbene Pokémon besser „Gestorben“ nutzen.",
                           "Deleting removes the entry completely (e.g. a typo). For fainted Pokémon use “Fainted” instead."))
                }
            }
            .navigationTitle(link.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Fertig", "Done")) { dismiss() }.fontWeight(.semibold) }
            }
            .sheet(item: Binding(get: { picking.map { PlayerPick(player: $0) } }, set: { picking = $0?.player })) { pick in
                OptionPicker(title: L("Pokémon wählen", "Choose Pokémon"), options: PickerOptions.pokemon(game: game),
                             selected: link.member(pick.player)?.pokemonId) { id in
                    if let id, let m = link.member(pick.player) {
                        m.setPokemon(id)
                        m.team?.touch()
                    }
                }
            }
            .alert(L("Woran ist es gestorben?", "What caused it?"), isPresented: $askDeath) {
                TextField(L("z. B. Rivale, kritischer Treffer", "e.g. rival, critical hit"), text: $deathNote)
                Button(L("Auf den Friedhof", "To the graveyard"), role: .destructive) {
                    NuzlockeActions.set(link, to: .dead, in: save, note: deathNote.trimmingCharacters(in: .whitespaces), context: context)
                    dismiss()
                }
                Button(L("Abbrechen", "Cancel"), role: .cancel) {}
            } message: {
                Text(save.mode == .soulLink ? L("Beide verlinkten Pokémon kommen auf den Friedhof.", "Both linked Pokémon go to the graveyard.") : "")
            }
            .confirmationDialog(L("Eintrag löschen?", "Delete entry?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(L("Löschen", "Delete"), role: .destructive) {
                    NuzlockeActions.delete(link, from: save, context: context)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Routes

struct RouteListSheet: View {
    let save: Savegame
    /// true = only choose a name (from the new-catch screen)
    var picking = false
    var onPick: (String, Int?) -> Void
    var onOpen: (NuzlockeLink) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var custom = ""

    var body: some View {
        let routes = Wiki.shared.routes(in: save.game)
        let byRoute = Dictionary(grouping: save.links, by: { $0.route.lowercased() })
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = q.isEmpty ? routes : routes.filter { $0.name.lowercased().contains(q) }
        let known = Set(routes.map { $0.name.lowercased() })
        let customUsed = save.links.filter { !$0.route.isEmpty && !known.contains($0.route.lowercased()) }
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField(L("Eigene Route eingeben", "Type a route"), text: $custom)
                        Button(L("Übernehmen", "Use")) { onPick(custom.trimmingCharacters(in: .whitespaces), nil) }
                            .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } footer: {
                    if routes.isEmpty {
                        Text(L("Für dieses Spiel gibt es keine Routenliste in der Datenbank – trag die Gebiete selbst ein.",
                               "There is no route list for this game in the database – type the areas yourself."))
                    }
                }
                if !customUsed.isEmpty && q.isEmpty {
                    Section(L("Selbst eingetragen", "Typed in")) {
                        ForEach(customUsed) { link in row(name: link.route, id: nil, links: [link]) }
                    }
                }
                if !filtered.isEmpty {
                    Section(L("Gebiete mit wilden Pokémon", "Areas with wild Pokémon")) {
                        ForEach(filtered, id: \.id) { r in
                            row(name: r.name, id: r.id, links: byRoute[r.name.lowercased()] ?? [])
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: L("Gebiet suchen", "Search area"))
            .navigationTitle(L("Routen", "Routes"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Schließen", "Close")) { dismiss() } }
            }
        }
    }

    private func row(name: String, id: Int?, links: [NuzlockeLink]) -> some View {
        Button {
            if !picking, let first = links.first { onOpen(first) } else { onPick(name, id) }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).foregroundStyle(.primary)
                    if let link = links.first {
                        Text(statusText(link)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let link = links.first {
                    if link.status == .missed {
                        Image(systemName: "slash.circle").foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: -6) {
                            ForEach(link.members.sorted { $0.player < $1.player }) { m in
                                PokemonSprite(pokemonId: m.pokemonId, shiny: m.shiny).frame(width: 34, height: 34)
                            }
                        }
                        .saturation(link.status == .dead ? 0 : 1)
                    }
                } else {
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func statusText(_ link: NuzlockeLink) -> String {
        switch link.status {
        case .missed: return L("Verpasst", "Missed")
        case .dead: return L("\(link.displayName) · gestorben", "\(link.displayName) · fainted")
        default: return "\(link.displayName) · \(link.status.title)"
        }
    }
}

// MARK: - Rules

struct RulesSheet: View {
    @Bindable var save: Savegame
    @Environment(\.dismiss) private var dismiss
    @State private var rules = NuzlockeRules()
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(L("Nur die erste Begegnung pro Gebiet", "Only the first encounter per area"), isOn: $rules.firstEncounterOnly)
                    Toggle(L("Besiegt = gestorben", "Fainted = dead"), isOn: $rules.faintIsDeath)
                    Toggle(L("Spitznamen für alle", "Nickname everything"), isOn: $rules.nicknames)
                } header: {
                    Text(L("Grundregeln", "Core rules"))
                }

                Section {
                    Toggle(L("Dupes-Klausel", "Dupes clause"), isOn: $rules.dupesClause)
                    Toggle(L("Shiny-Klausel", "Shiny clause"), isOn: $rules.shinyClause)
                    Toggle(L("Keine Legendären", "No legendaries"), isOn: $rules.noLegendaries)
                } header: {
                    Text(L("Klauseln", "Clauses"))
                } footer: {
                    Text(L("Dupes: schon gefangene Entwicklungsreihen zählen nicht. Shiny: Shinys dürfen immer gefangen werden, auch zusätzlich.",
                           "Dupes: evolution lines you already caught don't count. Shiny: shinies may always be caught, even as an extra."))
                }

                Section {
                    Toggle(L("Level-Cap", "Level cap"), isOn: $rules.levelCapOn)
                    if rules.levelCapOn {
                        AppStepper(value: $rules.levelCap, in: 2...100) {
                            HStack { Text(L("Aktueller Cap", "Current cap")); Spacer(); Text("\(rules.levelCap)").monospacedDigit().foregroundStyle(.secondary) }
                        }
                    }
                    Toggle(L("Keine Items im Kampf", "No items in battle"), isOn: $rules.noItemsInBattle)
                    Toggle(L("Set-Modus (kein Wechseln nach K.O.)", "Set mode (no switch after a KO)"), isOn: $rules.setMode)
                } header: {
                    Text(L("Schwierigkeit", "Difficulty"))
                } footer: {
                    Text(L("Den Level-Cap trägst du selbst ein (z. B. Level des nächsten Arena-Asses). Items im Kampf und Set-Modus sind Erinnerungen – die App kann das nicht prüfen.",
                           "Set the level cap yourself (e.g. the next gym leader's ace). Items in battle and set mode are reminders – the app can't check them."))
                }

                if save.mode == .soulLink {
                    Section {
                        Toggle(L("Primärtyp nur einmal pro Team", "Primary type once per team"), isOn: $rules.typeClause)
                        Toggle(L("Primärtyp nur einmal über beide Teams", "Primary type once across both teams"), isOn: $rules.typeClauseShared)
                    } header: {
                        Text("Soul Link")
                    } footer: {
                        Text(L("Verlinkte Pokémon sterben und wandern immer gemeinsam – das macht die App automatisch.",
                               "Linked Pokémon always faint and move together – the app does that automatically."))
                    }
                }

                Section {
                    Text(L("Regelverstöße werden als Warnung angezeigt, aber nicht blockiert. Die Regeln gelten nur für diesen Run.",
                           "Rule breaks are shown as warnings, not blocked. These rules only apply to this run."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L("Regeln", "Rules"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Fertig", "Done")) { save.rules = rules; save.touch(); dismiss() }.fontWeight(.semibold)
                }
            }
            .onChange(of: rules) { _, new in save.rules = new }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            rules = save.rules
        }
    }
}
