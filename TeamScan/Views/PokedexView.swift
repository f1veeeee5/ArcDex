import SwiftUI
import SwiftData

struct DexRoute: Hashable {
    let pokemonId: Int
    let game: Game?
}

struct PokedexView: View {
    @Query(sort: \FavoritePokemon.addedAt, order: .reverse) private var favorites: [FavoritePokemon]
    @AppStorage("dexGameFilter") private var filterRaw = "all"
    @State private var showFavorites = false
    @State private var query = ""
    @State private var path: [DexRoute] = []

    private static let searchIndex: [Int: String] = Dictionary(uniqueKeysWithValues: Dex.shared.pokemon.map {
        ($0.id, Fuzzy.normalize($0.de) + "|" + Fuzzy.normalize($0.en) + "|" + String($0.sp))
    })

    private var filter: Game? { Game(rawValue: filterRaw) }

    private var allEntries: [DexPokemon] {
        let dex = Dex.shared
        var list = dex.pokemon.sorted { ($0.sp, $0.isBattleForm ? 1 : 0, $0.id) < ($1.sp, $1.isBattleForm ? 1 : 0, $1.id) }
        if let filter { list = list.filter { dex.appears($0.id, in: filter) } }
        let q = Fuzzy.normalize(query)
        if !q.isEmpty { list = list.filter { Self.searchIndex[$0.id]?.contains(q) ?? false } }
        return list
    }

    private var favoriteEntries: [(DexPokemon, Bool)] {
        let q = Fuzzy.normalize(query)
        return favorites.compactMap { f in
            guard let p = Dex.shared.pokemon(f.pokemonId) else { return nil }
            if let filter, !Dex.shared.appears(p.id, in: filter) { return nil }
            if !q.isEmpty && !(Self.searchIndex[p.id]?.contains(q) ?? false) { return nil }
            return (p, f.shiny)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 14) {
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
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Pokédex")
            .searchable(text: $query, prompt: L("Name oder Nummer (Deutsch/Englisch)", "Name or number (German/English)"))
            .navigationDestination(for: DexRoute.self) { route in
                PokemonDetailView(pokemonId: route.pokemonId, preferredGame: route.game)
            }
        }
    }

    private var controls: some View {
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
                    Text(filter?.title ?? L("Alle Spiele", "All games")).font(.subheadline.weight(.semibold))
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

            Spacer()

            Button {
                withAnimation(.snappy) { showFavorites.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showFavorites ? "heart.fill" : "heart")
                    Text(L("Favoriten", "Favorites"))
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
