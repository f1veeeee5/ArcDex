import SwiftUI
import SwiftData

struct PokemonDetailView: View {
    let pokemonId: Int
    var preferredGame: Game?

    @Environment(\.modelContext) private var context
    @Query private var favorites: [FavoritePokemon]
    @State private var game: Game = .swsh
    @State private var tab = 0
    @State private var shiny = false
    @State private var statMode = 0
    @State private var didSetup = false

    private var dex: Dex { .shared }
    private var wiki: Wiki { .shared }
    private var pokemon: DexPokemon? { dex.pokemon(pokemonId) }
    private var games: [Game] { dex.games(for: pokemonId) }

    var body: some View {
        if let p = pokemon {
            ScrollView {
                VStack(spacing: 18) {
                    header(p)
                    Picker("", selection: $tab) {
                        Text(L("Info", "About")).tag(0)
                        Text(L("Werte", "Stats")).tag(1)
                        Text(L("Fundorte", "Locations")).tag(2)
                    }
                    .pickerStyle(.segmented)

                    switch tab {
                    case 0: aboutTab(p)
                    case 1: statsTab(p)
                    default: locationsTab(p)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(p.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { favoriteMenu(p) }
            }
            .onAppear {
                guard !didSetup else { return }
                didSetup = true
                if let preferredGame, games.contains(preferredGame) { game = preferredGame }
                else { game = games.last ?? .swsh }
            }
        } else {
            ContentUnavailableView(L("Nicht gefunden", "Not found"), systemImage: "questionmark")
        }
    }

    // MARK: Header

    private func header(_ p: DexPokemon) -> some View {
        let colors = p.types(gen: game.gen).map { TypeColor.color($0) }
        return VStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .bottom) {
                    BattlePlatform(colors: colors)
                        .frame(width: 210, height: 58)
                        .padding(.bottom, 16)
                    AnimatedPokemonSprite(pokemonId: p.id, shiny: shiny)
                        .frame(width: 190, height: 190)
                        .padding(.bottom, 34)
                        .id("\(p.id)-\(shiny)")
                        .transition(.scale.combined(with: .opacity))
                }
                .frame(width: 240, height: 240)
                Button {
                    withAnimation(.spring) { shiny.toggle() }
                } label: {
                    Image(systemName: shiny ? "sparkles" : "sparkle")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(shiny ? AnyShapeStyle(Color.yellow.gradient) : AnyShapeStyle(Color.secondary))
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Shiny anzeigen", "Show shiny"))
            }
            VStack(spacing: 4) {
                Text("\(p.dexNumber) · \(L("Nationaler Pokédex", "National Pokédex"))")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(p.name).font(.largeTitle.weight(.bold)).multilineTextAlignment(.center)
                if p.altName != p.name {
                    Text(p.altName).font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) { ForEach(p.types(gen: game.gen), id: \.self) { TypeBadge(typeId: $0) } }
                    .padding(.top, 4)
                if p.types(gen: game.gen) != p.t {
                    Text(L("Typen in \(game.title) – heute: \(p.t.compactMap { dex.type($0)?.name }.joined(separator: "/"))",
                           "Types in \(game.title) – today: \(p.t.compactMap { dex.type($0)?.name }.joined(separator: "/"))"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            gamePicker
        }
        .padding(.top, 4)
    }

    private var gamePicker: some View {
        Menu {
            Picker(selection: $game.animation(.snappy)) {
                GameMenuItems(games: games, asGame: true)
            } label: { EmptyView() }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 8) {
                Text(game.title).font(.subheadline.weight(.semibold))
                if games.count > 1 { Image(systemName: "chevron.down").font(.caption.weight(.bold)) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(game.gradient, in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(games.count <= 1)
        .overlay {
            if games.isEmpty {
                Text(L("In keinem der Spiele", "Not in any of the games")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Favorites

    private func isFavorite(shiny: Bool) -> FavoritePokemon? {
        favorites.first { $0.pokemonId == pokemonId && $0.shiny == shiny }
    }

    private func toggleFavorite(shiny: Bool) {
        if let f = isFavorite(shiny: shiny) { context.delete(f) }
        else { context.insert(FavoritePokemon(pokemonId: pokemonId, shiny: shiny)) }
    }

    private func favoriteMenu(_ p: DexPokemon) -> some View {
        let normal = isFavorite(shiny: false) != nil
        let shinyFav = isFavorite(shiny: true) != nil
        return Menu {
            Button { toggleFavorite(shiny: false) } label: {
                Label(normal ? L("Aus Favoriten entfernen", "Remove from favorites") : L("Favorisieren", "Add to favorites"),
                      systemImage: normal ? "heart.slash" : "heart")
            }
            Button { toggleFavorite(shiny: true) } label: {
                Label(shinyFav ? L("Shiny-Favorit entfernen", "Remove shiny favorite") : L("Als Shiny favorisieren", "Add as shiny favorite"),
                      systemImage: shinyFav ? "sparkles" : "sparkle")
            }
        } label: {
            Image(systemName: normal || shinyFav ? "heart.fill" : "heart")
                .foregroundStyle(normal || shinyFav ? Color.pink : Color.primary)
        }
    }

    // MARK: About

    @ViewBuilder
    private func aboutTab(_ p: DexPokemon) -> some View {
        let species = wiki.species(p.sp)
        DetailCard(title: wiki.genus(p.sp) ?? L("Pokémon", "Pokémon")) {
            if let flavor = wiki.flavor(species: p.sp, game: game) {
                Text(flavor.text).font(.body).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                if let from = flavor.from {
                    Text(L("Text aus \(from.title)", "Text from \(from.title)")).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            HStack(spacing: 0) {
                if let hw = wiki.heightWeight(p) {
                    InfoTile(icon: "ruler", value: String(format: "%.1f m", hw.0), label: L("Größe", "Height"))
                    Divider().frame(height: 44)
                    InfoTile(icon: "scalemass", value: String(format: "%.1f kg", hw.1), label: L("Gewicht", "Weight"))
                    Divider().frame(height: 44)
                }
                genderTile(species?.gr ?? -1)
            }
            .padding(.top, 6)
            if let s = species, s.leg > 0 || s.baby {
                Label(s.leg == 2 ? L("Mysteriöses Pokémon", "Mythical Pokémon") : (s.leg == 1 ? L("Legendäres Pokémon", "Legendary Pokémon") : L("Baby-Pokémon", "Baby Pokémon")),
                      systemImage: "crown.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.orange)
            }
        }

        if let s = species {
            evolutionCard(s, current: p)
        }

        formsCard(p)

        DetailCard(title: L("Fähigkeiten", "Abilities")) {
            let abilities = game.hasAbilities ? dex.abilities(for: p, gen: game.gen) : []
            let hidden = p.abilitySlots(gen: game.gen).hidden
            if !game.hasAbilities {
                Text(L("In \(game.title) gibt es keine Fähigkeiten.", "\(game.title) has no abilities."))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if abilities.isEmpty {
                Text(L("Keine Daten", "No data")).foregroundStyle(.secondary)
            }
            ForEach(abilities) { a in
                NavigationLink(value: DexAbilityRoute(id: a.id, game: game)) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(a.name).font(.headline).foregroundStyle(TypeColor.color(p.t.first ?? 1))
                        if a.id == hidden {
                            Text(L("Versteckt", "Hidden")).font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    if let text = wiki.abilityText(a.id) {
                        Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func genderTile(_ rate: Int) -> some View {
        VStack(spacing: 6) {
            if rate < 0 {
                Image(systemName: "circle.slash").font(.title3)
                Text(L("Geschlechtslos", "Genderless")).font(.caption).foregroundStyle(.secondary)
            } else {
                let female = Double(rate) / 8
                HStack(spacing: 6) {
                    Text("♂ \(Int((1 - female) * 100 + 0.5))%").foregroundStyle(.blue)
                    Text("♀ \(Int(female * 100 + 0.5))%").foregroundStyle(.pink)
                }
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Rectangle().fill(.blue).frame(width: geo.size.width * (1 - female))
                        Rectangle().fill(.pink)
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 6)
                .padding(.horizontal, 12)
                Text(L("Geschlecht", "Gender")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func evolutionCard(_ s: WikiSpecies, current: DexPokemon) -> some View {
        let stages = wiki.stages(chain: s.ch)
        if stages.flatMap({ $0 }).count > 1 {
            DetailCard(title: L("Entwicklung", "Evolution chain")) {
                // fits the card width – no horizontal scrolling
                HStack(alignment: .center, spacing: 4) {
                    ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                        if index > 0 {
                            Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                        }
                        VStack(spacing: 8) {
                            ForEach(stage, id: \.self) { sid in
                                evolutionMember(sid, isCurrent: sid == current.sp)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func evolutionMember(_ sid: Int, isCurrent: Bool) -> some View {
        if let p = dex.defaultPokemon(species: sid) {
            let content = VStack(spacing: 4) {
                PokemonSprite(pokemonId: p.id, shiny: shiny).frame(width: 64, height: 64)
                HStack(spacing: 3) {
                    ForEach(p.t, id: \.self) { Circle().fill(TypeColor.color($0)).frame(width: 7, height: 7) }
                }
                Text(p.name).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                if let cond = wiki.evolutionText(species: sid, game: game) {
                    Text(cond).font(.caption2).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 2)
            .padding(.vertical, 6)
            .background(isCurrent ? Color(.tertiarySystemFill) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if isCurrent {
                content
            } else {
                NavigationLink(value: DexRoute(pokemonId: p.id, game: game)) { content }
                    .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func formsCard(_ p: DexPokemon) -> some View {
        let forms = dex.forms(ofSpecies: p.sp).filter { $0.id != p.id }
        if !forms.isEmpty {
            DetailCard(title: L("Formen", "Forms")) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(forms) { f in
                            NavigationLink(value: DexRoute(pokemonId: f.id, game: game)) {
                                VStack(spacing: 4) {
                                    PokemonSprite(pokemonId: f.id, shiny: shiny).frame(width: 70, height: 70)
                                    Text(f.name).font(.caption2.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
                                    if f.kind == "mega" {
                                        MechanicBadge(mechanic: .mega, size: 20)
                                    } else if f.kind == "gmax" {
                                        MechanicBadge(mechanic: .gmax, size: 20)
                                    } else if f.kind == "primal" {
                                        MechanicChip(text: "PROTO")
                                    }
                                }
                                .frame(width: 96)
                                .opacity(dex.appears(f.id, in: game) ? 1 : 0.45)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text(L("Blasse Formen gibt es in \(game.title) nicht.", "Faded forms are not in \(game.title)."))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Stats

    @ViewBuilder
    private func statsTab(_ p: DexPokemon) -> some View {
        DetailCard(title: L("Basiswerte", "Base stats")) {
            Picker("", selection: $statMode) {
                Text(L("Basis", "Base")).tag(0)
                Text("Min").tag(1)
                Text("Max").tag(2)
            }
            .pickerStyle(.segmented)
            let names = StatNames.short
            ForEach(0..<6, id: \.self) { i in
                let base = p.s[i]
                let value = statValue(base: base, index: i)
                let maxValue: Double = statMode == 0 ? 200 : (i == 0 ? 600 : 500)
                HStack(spacing: 10) {
                    Text(names[i]).font(.subheadline).frame(width: 70, alignment: .leading)
                    GeometryReader { geo in
                        Capsule().fill(Color(.tertiarySystemFill))
                            .overlay(alignment: .leading) {
                                Capsule().fill(statColor(base).gradient)
                                    .frame(width: geo.size.width * min(Double(value) / maxValue, 1))
                            }
                    }
                    .frame(height: 10)
                    Text("\(value)").font(.subheadline.weight(.bold).monospacedDigit()).frame(width: 40, alignment: .trailing)
                }
            }
            HStack {
                Spacer()
                Text(L("Gesamt", "Total")).foregroundStyle(.secondary)
                Text("\((0..<6).map { statValue(base: p.s[$0], index: $0) }.reduce(0, +))").font(.headline.monospacedDigit())
            }
            Text(statMode == 0
                 ? L("Basiswerte zeigen das Potenzial des Pokémon.", "Base stats show the Pokémon's potential.")
                 : L("Werte auf Level 100. Min: 0 IVs, 0 EVs, negatives Wesen. Max: 31 IVs, 252 EVs, positives Wesen.",
                     "Stats at level 100. Min: 0 IVs, 0 EVs, hindering nature. Max: 31 IVs, 252 EVs, beneficial nature."))
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
        }

        typeDefenseCard(p)
    }

    private func statValue(base: Int, index: Int) -> Int {
        switch statMode {
        case 1:
            return index == 0 ? 2 * base + 110 : Int(Double(2 * base + 5) * 0.9)
        case 2:
            return index == 0 ? 2 * base + 204 : Int(Double(2 * base + 99) * 1.1)
        default:
            return base
        }
    }

    private func statColor(_ v: Int) -> Color {
        switch v {
        case ..<50: return .red
        case ..<80: return .orange
        case ..<100: return .yellow
        case ..<130: return .green
        default: return .teal
        }
    }

    private func typeDefenseCard(_ p: DexPokemon) -> some View {
        let all = dex.battleTypes(gen: game.gen).map { ($0.id, TypeChart.multiplier(attack: $0.id, defense: p.types(gen: game.gen), gen: game.gen)) }
        func ids(_ match: (Double) -> Bool) -> [Int] { all.filter { match($0.1) }.map { $0.0 } }
        let groups: [DefenseGroup] = [
            DefenseGroup(title: L("Sehr schwach", "Very weak"), factor: "4×", types: ids { $0 >= 4 }),
            DefenseGroup(title: L("Schwach", "Weak"), factor: "2×", types: ids { $0 == 2 }),
            DefenseGroup(title: L("Resistent", "Resistant"), factor: "½×", types: ids { $0 == 0.5 }),
            DefenseGroup(title: L("Sehr resistent", "Very resistant"), factor: "¼×", types: ids { $0 > 0 && $0 <= 0.25 }),
            DefenseGroup(title: L("Immun", "Immune"), factor: "0×", types: ids { $0 == 0 }),
        ]
        return DetailCard(title: L("Typ-Verteidigung", "Type defenses")) {
            ForEach(groups.filter { !$0.types.isEmpty }) { g in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(g.title).font(.headline)
                        Text(g.factor).font(.subheadline).foregroundStyle(.secondary)
                    }
                    FlowLayout(spacing: 6) {
                        ForEach(g.types, id: \.self) { TypeBadge(typeId: $0) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(L("Ohne Fähigkeiten wie Schwebe berechnet.", "Calculated without abilities like Levitate."))
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: Locations

    @ViewBuilder
    private func locationsTab(_ p: DexPokemon) -> some View {
        if p.isBattleForm {
            DetailCard(title: L("Kampf-Form", "Battle form")) {
                Text(p.kind == "gmax"
                     ? L("Gigadynamax-Formen entstehen nur im Kampf. Pokémon mit Gigadynamax-Faktor findest du in Dyna-Raids – siehe Fundorte der normalen Form.",
                         "Gigantamax forms only exist in battle. Pokémon with the Gigantamax Factor appear in Max Raid Battles – see the locations of the normal form.")
                     : L("Mega- und Proto-Formen entstehen nur im Kampf mit dem passenden Item. Sie können nicht gefangen werden.",
                         "Mega and Primal forms only appear in battle with the right item. They can't be caught."))
                    .font(.subheadline).foregroundStyle(.secondary)
                if let base = p.base {
                    NavigationLink(value: DexRoute(pokemonId: base, game: game)) {
                        Label(L("Normale Form ansehen", "View normal form"), systemImage: "arrow.right.circle.fill")
                    }
                }
            }
        } else {
            if !game.isChampions { catchRateCard(p) }
            encountersCard(p)
        }
    }

    @ViewBuilder
    private func catchRateCard(_ p: DexPokemon) -> some View {
        if let rate = wiki.species(p.sp)?.cr {
            DetailCard(title: L("Fangrate", "Catch rate")) {
                HStack {
                    Text(L("Fangrate", "Catch rate")).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(rate) / 255").font(.headline.monospacedDigit())
                }
                HStack(spacing: 0) {
                    BallChance(name: L("Pokéball", "Poké Ball"), image: "ball-poke", chance: Wiki.catchChance(rate: rate, ball: 1))
                    BallChance(name: L("Superball", "Great Ball"), image: "ball-great", chance: Wiki.catchChance(rate: rate, ball: 1.5))
                    BallChance(name: L("Hyperball", "Ultra Ball"), image: "ball-ultra", chance: Wiki.catchChance(rate: rate, ball: 2))
                }
                Text(L("Ungefähre Chance pro Wurf bei vollen KP und ohne Statusproblem.", "Approximate chance per throw at full HP without status conditions."))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func encountersCard(_ p: DexPokemon) -> some View {
        let result = wiki.encounters(p, game: game)
        DetailCard(title: L("Fundorte in \(game.title)", "Locations in \(game.title)")) {
            if game.isChampions {
                Label(L("In Pokémon Champions fängt man keine Pokémon. Du rekrutierst sie im Spiel oder bringst sie über Pokémon HOME mit.",
                        "Pokémon Champions has no catching. You recruit Pokémon in the game or bring them over via Pokémon HOME."),
                      systemImage: "info.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if !game.hasEncounterData {
                Label(L("Für \(game.title) gibt es in der Datenbank leider keine Fundort-Daten. Ich zeige hier lieber nichts, als etwas Falsches.",
                        "There is no location data for \(game.title) in the database. Rather nothing than something wrong."),
                      systemImage: "info.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if !dex.appears(p.id, in: game) {
                Label(L("\(p.name) gibt es in \(game.title) nicht.", "\(p.name) is not in \(game.title)."), systemImage: "xmark.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if result.list.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L("Keine wilden Fundorte in \(game.title) bekannt.", "No known wild locations in \(game.title)."), systemImage: "leaf")
                        .font(.subheadline.weight(.semibold))
                    if game.encounterDataPartial {
                        Text(L("Achtung: Für \(game.title) sind die Daten unvollständig.", "Note: the data for \(game.title) is incomplete."))
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if let from = wiki.species(p.sp)?.from, from > 0, let pre = dex.defaultPokemon(species: from) {
                        NavigationLink(value: DexRoute(pokemonId: pre.id, game: game)) {
                            Text(L("Entwickle \(pre.name) – Fundorte ansehen", "Evolve \(pre.name) – see its locations"))
                                .font(.subheadline)
                        }
                    } else {
                        Text(L("Es kann z. B. per Tausch, Zucht oder Event erhältlich sein.", "It may be available via trade, breeding or events."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                if game.encounterDataPartial {
                    Label(L("Die Datenbank hat für \(game.title) nur einen Teil der Fundorte. Es kann weitere geben.",
                            "The database only has part of the locations for \(game.title). There may be more."),
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                if result.fromBase {
                    Text(L("Die Daten gelten für alle Formen dieses Pokémon.", "This data applies to all forms of this Pokémon."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(result.list, id: \.self) { e in
                    EncounterRow(encounter: e, game: game)
                }
            }
        }
    }
}

// MARK: - Pieces

private struct DefenseGroup: Identifiable {
    let title: String
    let factor: String
    let types: [Int]
    var id: String { factor }
}

struct DetailCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.weight(.bold))
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct InfoTile: View {
    let icon: String
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3)
            Text(value).font(.subheadline.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BallChance: View {
    let name: String
    /// pixel sprite from the games (asset catalog)
    let image: String
    let chance: Double
    var body: some View {
        VStack(spacing: 6) {
            Image(image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            Text(chance >= 1 ? "100 %" : String(format: "%.1f %%", chance * 100))
                .font(.subheadline.weight(.bold).monospacedDigit())
            Text(name).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct EncounterRow: View {
    let encounter: WikiEncounter
    let game: Game

    var body: some View {
        let wiki = Wiki.shared
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "mappin.and.ellipse").foregroundStyle(game.colors[0])
                Text(wiki.locationName(encounter.l)).font(.headline)
                Spacer()
                Text(encounter.lv[0] == encounter.lv[1] ? "Lv. \(encounter.lv[0])" : "Lv. \(encounter.lv[0])–\(encounter.lv[1])")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(encounter.m.map { wiki.methodName($0) }.uniqued().joined(separator: " · "))
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                let all = Set(game.versionNames)
                let has = Set(encounter.v)
                if has != all && game != .sm {
                    ForEach(encounter.v, id: \.self) { v in
                        Text(L("nur \(Game.localizedVersion(v))", "\(v) only")).font(.caption2.weight(.bold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2), in: Capsule())
                    }
                } else if game == .sm {
                    ForEach(encounter.v, id: \.self) { v in
                        Text(Game.localizedVersion(v)).font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                }
                if let dens = encounter.d, !dens.isEmpty {
                    Text(L("Dyna-Nest \(dens.joined(separator: ", "))", "Max Den \(dens.joined(separator: ", "))"))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.pink.opacity(0.18), in: Capsule())
                }
                if encounter.r > 0 && encounter.r < 100 {
                    Text(L("bis \(encounter.r) %", "up to \(encounter.r) %")).font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemFill).opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Simple wrapping layout for badges.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width && x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += s.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}


/// Flat oval like the battle platforms in the games, tinted in the type colours.
struct BattlePlatform: View {
    let colors: [Color]

    var body: some View {
        let tint = colors.isEmpty ? [Color.gray] : colors
        ZStack {
            // body of the platform
            Ellipse()
                .fill(LinearGradient(colors: tint.map { $0.opacity(0.55) }, startPoint: .leading, endPoint: .trailing))
            // lighter top surface
            Ellipse()
                .fill(LinearGradient(colors: tint.map { $0.opacity(0.35) } + [Color.white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 12)
            Ellipse()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1.5)
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 12)
            // shadow under the Pokémon
            Ellipse()
                .fill(RadialGradient(colors: [.black.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 50))
                .frame(width: 110, height: 22)
                .offset(y: -4)
        }
        .shadow(color: (tint.first ?? .gray).opacity(0.35), radius: 14, y: 6)
    }
}
