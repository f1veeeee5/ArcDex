import SwiftUI
import SwiftData

struct DexRoute: Hashable {
    let pokemonId: Int
    let game: Game?
}

struct PokedexView: View {
    @Query(sort: \FavoritePokemon.addedAt, order: .reverse) private var favorites: [FavoritePokemon]
    @AppStorage("dexGameFilter") private var filterRaw = "all"
    @AppStorage("dexCategory") private var categoryRaw = DexCategory.all.rawValue
    @State private var showFavorites = false
    @State private var query = ""
    @State private var path: [DexRoute] = []
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var titleCollapsed = false

    private static let searchIndex: [Int: String] = Dictionary(uniqueKeysWithValues: Dex.shared.pokemon.map {
        ($0.id, Fuzzy.normalize($0.de) + "|" + Fuzzy.normalize($0.en) + "|" + String($0.sp))
    })

    private var filter: Game? { Game(rawValue: filterRaw) }
    private var category: DexCategory { DexCategory(rawValue: categoryRaw) ?? .all }

    private var allEntries: [DexPokemon] {
        let dex = Dex.shared
        var list = dex.pokemon.sorted { ($0.sp, $0.isBattleForm ? 1 : 0, $0.id) < ($1.sp, $1.isBattleForm ? 1 : 0, $1.id) }
        if let filter { list = list.filter { dex.appears($0.id, in: filter) } }
        if category != .all { list = list.filter { category.matches($0) } }
        let q = Fuzzy.normalize(query)
        if !q.isEmpty { list = list.filter { Self.searchIndex[$0.id]?.contains(q) ?? false } }
        return list
    }

    private var favoriteEntries: [(DexPokemon, Bool)] {
        let q = Fuzzy.normalize(query)
        return favorites.compactMap { f in
            guard let p = Dex.shared.pokemon(f.pokemonId) else { return nil }
            if let filter, !Dex.shared.appears(p.id, in: filter) { return nil }
            if category != .all && !category.matches(p) { return nil }
            if !q.isEmpty && !(Self.searchIndex[p.id]?.contains(q) ?? false) { return nil }
            return (p, f.shiny)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: 14) {
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
            .onChange(of: categoryRaw) { _, _ in scrollToTop() }
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
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: DexRoute.self) { route in
                PokemonDetailView(pokemonId: route.pokemonId, preferredGame: route.game)
            }
        }
    }

    private func scrollToTop() {
        withAnimation(.snappy) { scrollPosition.scrollTo(edge: .top) }
    }

    /// Title and search field – they stay at the top while the list scrolls underneath.
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pokédex")
                .font(titleCollapsed ? .headline : .largeTitle.weight(.bold))
                .frame(maxWidth: .infinity, alignment: titleCollapsed ? .center : .leading)
                .padding(.top, titleCollapsed ? 0 : 4)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Name oder Nummer (Deutsch/Englisch)", "Name or number (German/English)"), text: $query)
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

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            controlRow
            if category != .all {
                Button {
                    withAnimation(.snappy) { categoryRaw = DexCategory.all.rawValue }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: category.icon)
                        Text(category.title)
                        Image(systemName: "xmark").font(.caption2.weight(.bold))
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.indigo.gradient, in: Capsule())
                }
                .buttonStyle(.plain)
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

            Menu {
                Picker(selection: $categoryRaw.animation(.snappy)) {
                    ForEach(DexCategory.allCases) { c in
                        Label(c.title, systemImage: c.icon).tag(c.rawValue)
                    }
                } label: { EmptyView() }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: category == .all ? "slider.horizontal.3" : category.icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(category == .all ? Color.primary : Color.white)
                    .frame(width: 38, height: 38)
                    .background(category == .all ? AnyShapeStyle(Color(.secondarySystemGroupedBackground)) : AnyShapeStyle(Color.indigo.gradient), in: Circle())
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel(L("Kategorie filtern", "Filter by category"))

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
                if let kind = pokemon.kind {
                    Text(kind == "gmax" ? "G-MAX" : (kind == "primal" ? "PROTO" : "MEGA"))
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
    case all, legendary, mythical, ultraBeast, paradox, mega, gmax, primal, zMove, regional, baby

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return L("Alle Pokémon", "All Pokémon")
        case .legendary: return L("Legendär", "Legendary")
        case .mythical: return L("Mysteriös", "Mythical")
        case .ultraBeast: return L("Ultrabestien", "Ultra Beasts")
        case .paradox: return L("Paradox-Pokémon", "Paradox Pokémon")
        case .mega: return L("Mega-Entwicklungen", "Mega Evolutions")
        case .gmax: return L("Gigadynamax", "Gigantamax")
        case .primal: return L("Proto-Formen", "Primal forms")
        case .zMove: return L("Eigene Z-Attacke", "Exclusive Z-Move")
        case .regional: return L("Regionalformen", "Regional forms")
        case .baby: return L("Baby-Pokémon", "Baby Pokémon")
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .legendary: return "crown.fill"
        case .mythical: return "sparkle"
        case .ultraBeast: return "hurricane"
        case .paradox: return "hourglass"
        case .mega: return "sparkles"
        case .gmax: return "arrow.up.left.and.arrow.down.right"
        case .primal: return "flame.fill"
        case .zMove: return "bolt.fill"
        case .regional: return "map.fill"
        case .baby: return "heart.circle.fill"
        }
    }

    // Species ids (national dex numbers)
    private static let ultraBeastSpecies: Set<Int> = [793, 794, 795, 796, 797, 798, 799, 803, 804, 805, 806]
    private static let paradoxSpecies: Set<Int> = Set(984...995).union([1005, 1006, 1009, 1010, 1020, 1021, 1022, 1023])
    /// Pokémon with a species-exclusive Z-Crystal (Sun/Moon & Ultra Sun/Ultra Moon)
    private static let zMoveSpecies: Set<Int> = [25, 26, 133, 143, 151, 724, 727, 730, 745, 778, 784, 785, 786, 787, 788, 791, 792, 800, 802]

    func matches(_ p: DexPokemon) -> Bool {
        let wiki = Wiki.shared
        switch self {
        case .all: return true
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
        case .regional:
            return ["-alola", "-galar", "-hisui", "-paldea"].contains { p.key.contains($0) } && !p.isBattleForm
        case .baby: return wiki.species(p.sp)?.baby == true
        }
    }
}
