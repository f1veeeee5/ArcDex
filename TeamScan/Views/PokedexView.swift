import SwiftUI
import SwiftData

struct DexRoute: Hashable {
    let pokemonId: Int
    let game: Game?
}

struct PokedexView: View {
    @Query(sort: \FavoritePokemon.addedAt, order: .reverse) private var favorites: [FavoritePokemon]
    @AppStorage("dexGameFilter") private var filterRaw = "all"
    @AppStorage("dexFilter") private var dexFilterRaw = ""
    @State private var showFilterSheet = false
    @State private var showFavorites = false
    @State private var query = ""
    @State private var path = NavigationPath()
    @AppStorage("dexSection") private var sectionRaw = DexSection.pokemon.rawValue
    @State private var moveType = 0
    @State private var itemPocket = 0
    private var section: DexSection { DexSection(rawValue: sectionRaw) ?? .pokemon }
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var titleCollapsed = false

    private static let searchIndex: [Int: String] = Dictionary(uniqueKeysWithValues: Dex.shared.pokemon.map {
        ($0.id, Fuzzy.normalize($0.de) + "|" + Fuzzy.normalize($0.en) + "|" + String($0.sp))
    })

    private var filter: Game? { Game(rawValue: filterRaw) }
    private var dexFilter: DexFilter { DexFilter(encoded: dexFilterRaw) }
    private var dexFilterBinding: Binding<DexFilter> {
        Binding(get: { DexFilter(encoded: dexFilterRaw) }, set: { new in withAnimation(.snappy) { dexFilterRaw = new.encoded } })
    }

    private var allEntries: [DexPokemon] {
        let dex = Dex.shared
        var list = dex.pokemon.sorted { ($0.sp, $0.isBattleForm ? 1 : 0, $0.id) < ($1.sp, $1.isBattleForm ? 1 : 0, $1.id) }
        if let filter { list = list.filter { dex.appears($0.id, in: filter) } }
        let f = dexFilter
        if !f.isEmpty { list = list.filter { f.matches($0) } }
        let q = Fuzzy.normalize(query)
        if !q.isEmpty { list = list.filter { Self.searchIndex[$0.id]?.contains(q) ?? false } }
        return list
    }

    private var favoriteEntries: [(DexPokemon, Bool)] {
        let q = Fuzzy.normalize(query)
        let df = dexFilter
        return favorites.compactMap { f in
            guard let p = Dex.shared.pokemon(f.pokemonId) else { return nil }
            if let filter, !Dex.shared.appears(p.id, in: filter) { return nil }
            if !df.isEmpty && !df.matches(p) { return nil }
            if !q.isEmpty && !(Self.searchIndex[p.id]?.contains(q) ?? false) { return nil }
            return (p, f.shiny)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if section != .pokemon {
                        sectionControls
                        switch section {
                        case .moves: MoveList(query: query, game: filter, typeFilter: $moveType)
                        case .abilities: AbilityList(query: query, game: filter)
                        default: ItemList(query: query, game: filter, pocket: $itemPocket)
                        }
                    } else {
                    controls
                    if showFavorites {
                        let favs = favoriteEntries
                        if favs.isEmpty {
                            ContentUnavailableView(L("Noch keine Favoriten", "No favorites yet"), systemImage: "heart",
                                                   description: Text(L("Öffne ein Pokémon und tippe auf das Herz – normal oder shiny.",
                                                                       "Open a Pokémon and tap the heart – normal or shiny.")))
                                .padding(.top, 40)
                        }
                        LazyVStack(spacing: 10) {
                            ForEach(Array(favs.enumerated()), id: \.offset) { _, entry in
                                NavigationLink(value: DexRoute(pokemonId: entry.0.id, game: filter)) {
                                    DexRow(pokemon: entry.0, shiny: entry.1)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        let entries = allEntries
                        LazyVStack(spacing: 10) {
                            ForEach(entries) { p in
                                NavigationLink(value: DexRoute(pokemonId: p.id, game: filter)) {
                                    DexRow(pokemon: p, shiny: false)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if entries.isEmpty {
                            ContentUnavailableView.search(text: query).padding(.top, 40)
                        }
                    }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, offset in
                // hysteresis so the title doesn't flicker while the header changes size
                let collapse = titleCollapsed ? offset > 4 : offset > 40
                if collapse != titleCollapsed {
                    withAnimation(.snappy(duration: 0.25)) { titleCollapsed = collapse }
                }
            }
            .onChange(of: query) { _, _ in scrollToTop() }
            .onChange(of: filterRaw) { _, _ in scrollToTop() }
            .onChange(of: showFavorites) { _, _ in scrollToTop() }
            .onChange(of: dexFilterRaw) { _, _ in scrollToTop() }
            .onChange(of: sectionRaw) { _, _ in query = ""; scrollToTop() }
            .onChange(of: moveType) { _, _ in scrollToTop() }
            .onChange(of: itemPocket) { _, _ in scrollToTop() }
            .sheet(isPresented: $showFilterSheet) { DexFilterSheet(filter: dexFilterBinding) }
            .safeAreaInset(edge: .top, spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .background {
                        LinearGradient(stops: [
                            .init(color: Color(.systemGroupedBackground), location: 0),
                            .init(color: Color(.systemGroupedBackground).opacity(0.95), location: 0.55),
                            .init(color: Color(.systemGroupedBackground).opacity(0.7), location: 0.75),
                            .init(color: Color(.systemGroupedBackground).opacity(0), location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                        // reaches further down than the header itself so the fade is visible
                        .padding(.bottom, -56)
                        .ignoresSafeArea(edges: .top)
                        // only once the list is scrolled – at the top it would cover the filter row
                        .opacity(titleCollapsed ? 1 : 0)
                        .allowsHitTesting(false)
                    }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Pokédex")
            // the bar is hidden – "inline" keeps it from collapsing a large title while scrolling,
            // which would change the top inset and make the list jump (after coming back from a Pokémon)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: DexRoute.self) { route in
                PokemonDetailView(pokemonId: route.pokemonId, preferredGame: route.game)
            }
            .navigationDestination(for: DexMoveRoute.self) { route in
                MoveDetailView(moveId: route.id, preferredGame: route.game)
            }
            .navigationDestination(for: DexAbilityRoute.self) { route in
                AbilityDetailView(abilityId: route.id, game: route.game)
            }
            .navigationDestination(for: DexItemRoute.self) { route in
                ItemDetailView(itemId: route.id, game: route.game)
            }
            .navigationDestination(for: DexItemGroupRoute.self) { route in
                ItemGroupView(key: route.key, game: route.game)
            }
        }
    }

    private func scrollToTop() {
        withAnimation(.snappy) { scrollPosition.scrollTo(edge: .top) }
    }

    /// Title and search field – they stay at the top while the list scrolls underneath.
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Same height in both states – otherwise the list would jump when the title shrinks.
            ZStack {
                Text("Pokédex")
                    .font(.largeTitle.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .scaleEffect(titleCollapsed ? 0.85 : 1, anchor: .leading)
                    .opacity(titleCollapsed ? 0 : 1)
                Text("Pokédex")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .opacity(titleCollapsed ? 1 : 0)
            }
            .frame(height: 44)
            Picker(L("Bereich", "Section"), selection: $sectionRaw.animation(.snappy)) {
                ForEach(DexSection.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(section.searchPrompt, text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("Suche löschen", "Clear search"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Game filter (+ type / bag pocket) for moves, abilities and items.
    private var sectionControls: some View {
        HStack(spacing: 10) {
            gameMenu
            Spacer()
            if section == .moves {
                Menu {
                    Picker(selection: $moveType.animation(.snappy)) {
                        Text(L("Alle Typen", "All types")).tag(0)
                        ForEach(Dex.shared.battleTypes) { Text($0.name).tag($0.id) }
                    } label: { EmptyView() }
                    .pickerStyle(.inline)
                } label: {
                    filterChip(moveType == 0 ? L("Alle Typen", "All types") : (Dex.shared.type(moveType)?.name ?? ""),
                               color: moveType == 0 ? nil : TypeColor.color(moveType))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
            } else if section == .items {
                Menu {
                    Picker(selection: $itemPocket.animation(.snappy)) {
                        Text(L("Alle Taschen", "All pockets")).tag(0)
                        ForEach(ItemPocket.allCases) { Label($0.title, systemImage: $0.icon).tag($0.rawValue) }
                    } label: { EmptyView() }
                    .pickerStyle(.inline)
                } label: {
                    filterChip(ItemPocket(rawValue: itemPocket)?.title ?? L("Alle Taschen", "All pockets"),
                               color: itemPocket == 0 ? nil : .indigo)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
            }
        }
    }

    private func filterChip(_ text: String, color: Color?) -> some View {
        HStack(spacing: 6) {
            Text(text).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption.weight(.bold))
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(color == nil ? Color.primary : Color.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(color.map { AnyShapeStyle($0.gradient) } ?? AnyShapeStyle(Color(.secondarySystemGroupedBackground)), in: Capsule())
        .contentShape(Capsule())
    }

    private var gameMenu: some View {
        Menu {
            Picker(selection: $filterRaw.animation(.snappy)) {
                Text(L("Alle Spiele", "All games")).tag("all")
                GameMenuItems()
            } label: { EmptyView() }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease").font(.subheadline.weight(.bold))
                Text(filter?.compactTitle ?? L("Alle Spiele", "All games"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
            }
            .foregroundStyle(filter == nil ? Color.primary : Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                Capsule().fill(filter.map { AnyShapeStyle($0.gradient) } ?? AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            }
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .layoutPriority(1)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            controlRow
            if !dexFilter.isEmpty {
                let f = dexFilter
                let names = f.categories.map(\.title) + f.regions.map(\.title) + f.types.sorted().compactMap { Dex.shared.type($0)?.name }
                HStack(spacing: 8) {
                    Button { showFilterSheet = true } label: {
                        Text(names.sorted().joined(separator: " · "))
                            .lineLimit(1)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.indigo.gradient, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Button {
                        withAnimation(.snappy) { dexFilterRaw = "" }
                    } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(7)
                            .background(Color(.secondarySystemGroupedBackground), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("Filter entfernen", "Clear filters"))
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var controlRow: some View {
        HStack(spacing: 10) {
            Menu {
                Picker(selection: $filterRaw.animation(.snappy)) {
                    Text(L("Alle Spiele", "All games")).tag("all")
                    GameMenuItems()
                } label: { EmptyView() }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease").font(.subheadline.weight(.bold))
                    Text(filter?.compactTitle ?? L("Alle Spiele", "All games"))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption.weight(.bold))
                }
                .foregroundStyle(filter == nil ? Color.primary : Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background {
                    Capsule().fill(filter.map { AnyShapeStyle($0.gradient) } ?? AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
                }
                .contentShape(Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .layoutPriority(1)

            Spacer()

            Button { showFilterSheet = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(dexFilter.isEmpty ? Color.primary : Color.white)
                    .frame(width: 38, height: 38)
                    .background(dexFilter.isEmpty ? AnyShapeStyle(Color(.secondarySystemGroupedBackground)) : AnyShapeStyle(Color.indigo.gradient), in: Circle())
                    .overlay(alignment: .topTrailing) {
                        if dexFilter.count > 0 {
                            Text("\(dexFilter.count)")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(.indigo)
                                .padding(4)
                                .background(Color.white, in: Circle())
                                .offset(x: 4, y: -4)
                        }
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Filter", "Filters"))

            Button {
                withAnimation(.snappy) { showFavorites.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showFavorites ? "heart.fill" : "heart")
                    Text(L("Favoriten", "Favorites")).lineLimit(1)
                    if !favorites.isEmpty { Text("\(favorites.count)").monospacedDigit() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(showFavorites ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(showFavorites ? AnyShapeStyle(Color.pink.gradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

struct DexRow: View {
    let pokemon: DexPokemon
    var shiny = false

    var body: some View {
        let colors = pokemon.t.map { TypeColor.color($0) }
        HStack(spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                PokemonSprite(pokemonId: pokemon.id, shiny: shiny)
                    .frame(width: 72, height: 72)
                if pokemon.kind == "mega" {
                    MechanicBadge(mechanic: .mega)
                } else if pokemon.kind == "gmax" {
                    MechanicBadge(mechanic: .gmax)
                } else if pokemon.kind == "primal" {
                    Text("PROTO")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing), in: Capsule())
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(pokemon.name).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                    if shiny { ShinyBadge() }
                }
                HStack(spacing: 4) {
                    ForEach(pokemon.t, id: \.self) { TypeBadge(typeId: $0, small: true) }
                }
            }
            Spacer(minLength: 4)
            Text(pokemon.dexNumber)
                .font(.title3.weight(.heavy).monospacedDigit())
                .foregroundStyle(.primary.opacity(0.35))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: colors.map { $0.opacity(0.32) } + (colors.count == 1 ? [colors[0].opacity(0.12)] : []),
                                     startPoint: .leading, endPoint: .trailing))
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}


/// Special groups of Pokémon for the Pokédex filter.
enum DexCategory: String, CaseIterable, Identifiable {
    case legendary, mythical, ultraBeast, paradox, mega, gmax, primal, zMove, baby

    var id: String { rawValue }

    var title: String {
        switch self {
        case .legendary: return L("Legendär", "Legendary")
        case .mythical: return L("Mysteriös", "Mythical")
        case .ultraBeast: return L("Ultrabestien", "Ultra Beasts")
        case .paradox: return L("Paradox-Pokémon", "Paradox Pokémon")
        case .mega: return L("Mega-Entwicklungen", "Mega Evolutions")
        case .gmax: return L("Gigadynamax", "Gigantamax")
        case .primal: return L("Proto-Formen", "Primal forms")
        case .zMove: return L("Eigene Z-Attacke", "Exclusive Z-Move")
        case .baby: return L("Baby-Pokémon", "Baby Pokémon")
        }
    }

    var icon: String {
        switch self {
        case .legendary: return "crown.fill"
        case .mythical: return "sparkle"
        case .ultraBeast: return "hurricane"
        case .paradox: return "hourglass"
        case .mega: return "sparkles"
        case .gmax: return "arrow.up.left.and.arrow.down.right"
        case .primal: return "flame.fill"
        case .zMove: return "bolt.fill"
        case .baby: return "heart.circle.fill"
        }
    }

    // Species ids (national dex numbers)
    private static let ultraBeastSpecies: Set<Int> = [793, 794, 795, 796, 797, 798, 799, 803, 804, 805, 806]
    private static let paradoxSpecies: Set<Int> = Set(984...995).union([1005, 1006, 1009, 1010, 1020, 1021, 1022, 1023])
    /// Pokémon with a species-exclusive Z-Crystal (Sun/Moon & Ultra Sun/Ultra Moon)
    private static let zMoveSpecies: Set<Int> = [25, 26, 133, 143, 151, 724, 727, 730, 745, 778, 784, 785, 786, 787, 788, 791, 792, 800, 802]

    /// Real logo for the filter chip, if there is one.
    var mechanic: Mechanic? {
        switch self {
        case .mega: return .mega
        case .gmax: return .gmax
        case .zMove: return .zMove
        default: return nil
        }
    }

    func matches(_ p: DexPokemon) -> Bool {
        let wiki = Wiki.shared
        switch self {
        case .legendary: return wiki.species(p.sp)?.leg == 1
        case .mythical: return wiki.species(p.sp)?.leg == 2
        case .ultraBeast: return Self.ultraBeastSpecies.contains(p.sp)
        case .paradox: return Self.paradoxSpecies.contains(p.sp)
        case .mega: return p.kind == "mega"
        case .gmax: return p.kind == "gmax"
        case .primal: return p.kind == "primal"
        case .zMove:
            guard Self.zMoveSpecies.contains(p.sp), !p.isBattleForm else { return false }
            // only Alolan Raichu has its own Z-Move, not the normal one
            if p.sp == 26 { return p.key == "raichu-alola" }
            return true
        case .baby: return wiki.species(p.sp)?.baby == true
        }
    }
}
