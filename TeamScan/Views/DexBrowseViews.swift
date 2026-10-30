import SwiftUI

// MARK: - Sections of the Pokédex tab

enum DexSection: String, CaseIterable, Identifiable {
    case pokemon, moves, abilities, items

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pokemon: return "Pokémon"
        case .moves: return L("Attacken", "Moves")
        case .abilities: return L("Fähigkeiten", "Abilities")
        case .items: return "Items"
        }
    }

    var searchPrompt: String {
        switch self {
        case .pokemon: return L("Name oder Nummer (Deutsch/Englisch)", "Name or number (German/English)")
        case .moves: return L("Attacke suchen (Deutsch/Englisch)", "Search moves (German/English)")
        case .abilities: return L("Fähigkeit suchen (Deutsch/Englisch)", "Search abilities (German/English)")
        case .items: return L("Item suchen (Deutsch/Englisch)", "Search items (German/English)")
        }
    }
}

struct DexMoveRoute: Hashable { let id: Int; let game: Game? }
struct DexAbilityRoute: Hashable { let id: Int; let game: Game? }
struct DexItemRoute: Hashable { let id: Int; let game: Game? }
struct DexItemGroupRoute: Hashable { let key: String; let game: Game? }

/// Many near-identical items (300 Dynamax Crystals, 80 Candies …) are shown as one group.
struct ItemGroup: Identifiable {
    let key: String
    let items: [ExtraItem]
    var id: String { key }

    var title: String {
        guard let first = items.first else { return "" }
        switch first.cat {
        case 49: return L("Dynamax-Kristalle", "Dynamax Crystals")
        case 47: return L("Pokémon-Bonbons", "Species Candies")
        case 32: return L("Mulch", "Mulch")
        default: return DexExtra.shared.categoryName(first.cat) ?? first.name
        }
    }

    static let minimumSize = 8

    static func key(_ item: ExtraItem) -> String { "\(item.cat)|\(item.t.last ?? "")" }

    /// Items grouped (only groups with many entries) – the rest stays single.
    static func build(_ items: [ExtraItem]) -> [Either] {
        let groups = Dictionary(grouping: items, by: { key($0) }).filter { $0.value.count >= minimumSize }
        var seen = Set<String>()
        var result: [Either] = []
        for item in items {
            let k = key(item)
            if let members = groups[k] {
                if seen.insert(k).inserted { result.append(.group(ItemGroup(key: k, items: members))) }
            } else {
                result.append(.single(item))
            }
        }
        return result
    }

    enum Either: Identifiable {
        case single(ExtraItem)
        case group(ItemGroup)
        var id: String {
            switch self {
            case .single(let i): return "i\(i.id)"
            case .group(let g): return "g" + g.key
            }
        }
    }
}

private func matches(_ query: String, _ names: String...) -> Bool {
    let q = Fuzzy.normalize(query)
    guard !q.isEmpty else { return true }
    return names.contains { Fuzzy.normalize($0).contains(q) }
}

// MARK: - Lists

struct MoveList: View {
    let query: String
    let game: Game?
    @Binding var typeFilter: Int

    var body: some View {
        let moves = Dex.shared.moves
            .filter { game == nil || $0.g <= game!.gen }
            .filter { typeFilter == 0 || $0.t == typeFilter }
            .filter { matches(query, $0.de, $0.en) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        LazyVStack(spacing: 8) {
            ForEach(moves) { m in
                NavigationLink(value: DexMoveRoute(id: m.id, game: game)) { MoveListRow(move: m) }
                    .buttonStyle(.plain)
            }
            if moves.isEmpty { ContentUnavailableView.search(text: query).padding(.top, 40) }
        }
    }
}

struct MoveListRow: View {
    let move: DexMove

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(TypeColor.color(move.t)).frame(width: 5, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(move.name).font(.headline).lineLimit(1)
                HStack(spacing: 6) {
                    TypeBadge(typeId: move.t, small: true)
                    CategoryBadge(category: move.c)
                    if move.altName != move.name {
                        Text(move.altName).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(move.p > 0 ? "\(move.p)" : "–").font(.headline.monospacedDigit())
                Text(move.a > 0 ? "\(move.a) %" : "–").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct AbilityList: View {
    let query: String
    let game: Game?

    var body: some View {
        let list = Dex.shared.abilities
            .filter { a in
                guard let game else { return true }
                return game.hasAbilities && (DexExtra.shared.abilityGeneration(a.id) ?? 3) <= game.gen
            }
            .filter { matches(query, $0.de, $0.en) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        LazyVStack(spacing: 8) {
            ForEach(list) { a in
                NavigationLink(value: DexAbilityRoute(id: a.id, game: game)) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(a.name).font(.headline)
                            if a.altName != a.name { Text(a.altName).font(.caption).foregroundStyle(.tertiary) }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        if let text = Wiki.shared.abilityText(a.id) {
                            Text(text).font(.subheadline).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            if game.map({ !$0.hasAbilities }) == true {
                ContentUnavailableView(L("Keine Fähigkeiten", "No abilities"), systemImage: "sparkles",
                                       description: Text(L("In \(game!.title) gibt es keine Fähigkeiten.", "\(game!.title) has no abilities.")))
                    .padding(.top, 40)
            } else if list.isEmpty {
                ContentUnavailableView.search(text: query).padding(.top, 40)
            }
        }
    }
}

struct ItemList: View {
    let query: String
    let game: Game?
    @Binding var pocket: Int

    var body: some View {
        let list = DexExtra.shared.items
            .filter { $0.cat != 23 }   // "unused" items without real text
            .filter { game == nil || $0.g.isEmpty || $0.g.contains(game!.gen) }
            .filter { pocket == 0 || $0.p == pocket }
            .filter { matches(query, $0.de, $0.en) }
        // while searching every item is shown on its own, otherwise big families are grouped
        let entries: [ItemGroup.Either] = query.trimmingCharacters(in: .whitespaces).isEmpty ? ItemGroup.build(list) : list.map { .single($0) }
        LazyVStack(spacing: 8) {
            ForEach(entries) { entry in
                switch entry {
                case .single(let item):
                    NavigationLink(value: DexItemRoute(id: item.id, game: game)) { ItemListRow(item: item) }
                        .buttonStyle(.plain)
                case .group(let group):
                    NavigationLink(value: DexItemGroupRoute(key: group.key, game: game)) { ItemGroupRow(group: group) }
                        .buttonStyle(.plain)
                }
            }
            if list.isEmpty { ContentUnavailableView.search(text: query).padding(.top, 40) }
        }
    }
}

struct ItemListRow: View {
    let item: ExtraItem

    var body: some View {
        HStack(spacing: 12) {
            ItemPicture(key: item.key).frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.headline).lineLimit(1)
                if let text = item.text {
                    Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct ItemGroupRow: View {
    let group: ItemGroup

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                ForEach(Array(group.items.prefix(3).enumerated()), id: \.offset) { i, item in
                    ItemPicture(key: item.key)
                        .frame(width: 30, height: 30)
                        .offset(x: CGFloat(i) * 6 - 6, y: CGFloat(i) * -4 + 4)
                }
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(group.title).font(.headline).lineLimit(1)
                    Text(L("\(group.items.count) Varianten", "\(group.items.count) variants"))
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
                if let text = group.items.first?.text {
                    Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// All variants of a grouped item family.
struct ItemGroupView: View {
    let key: String
    let game: Game?
    @State private var query = ""

    var body: some View {
        let all = DexExtra.shared.items.filter { ItemGroup.key($0) == key }
            .filter { game == nil || $0.g.isEmpty || $0.g.contains(game!.gen) }
        let group = ItemGroup(key: key, items: all)
        let list = all.filter { matches(query, $0.de, $0.en) }
        ScrollView {
            LazyVStack(spacing: 8) {
                if let text = all.first?.text {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)
                }
                ForEach(list) { item in
                    NavigationLink(value: DexItemRoute(id: item.id, game: game)) {
                        HStack(spacing: 12) {
                            ItemPicture(key: item.key).frame(width: 32, height: 32)
                            Text(item.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                if list.isEmpty { ContentUnavailableView.search(text: query).padding(.top, 40) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .searchable(text: $query, prompt: L("Variante suchen", "Search variants"))
        .navigationTitle(L("\(group.title) (\(all.count))", "\(group.title) (\(all.count))"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ItemPicture: View {
    let key: String
    var body: some View {
        if let url = SpriteURLs.item(key) {
            RemoteImage(urls: [url], pixelated: true, placeholder: "bag")
        } else {
            Image(systemName: "bag").foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Detail pages

struct MoveDetailView: View {
    let moveId: Int
    let preferredGame: Game?
    @State private var game: Game?

    var body: some View {
        let dex = Dex.shared
        if let move = dex.move(moveId) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(move.name).font(.largeTitle.weight(.bold))
                        if move.altName != move.name { Text(move.altName).font(.subheadline).foregroundStyle(.secondary) }
                        HStack(spacing: 8) {
                            TypeBadge(typeId: move.t)
                            CategoryBadge(category: move.c)
                            Text(L("Gen. \(move.g)", "Gen \(move.g)")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)

                    HStack(spacing: 10) {
                        statTile(L("Stärke", "Power"), move.p > 0 ? "\(move.p)" : "–")
                        statTile(L("Genauigkeit", "Accuracy"), move.a > 0 ? "\(move.a) %" : "–")
                        statTile(L("AP", "PP"), "\(move.pp)")
                        statTile(L("Priorität", "Priority"), move.pr > 0 ? "+\(move.pr)" : "\(move.pr)")
                    }

                    if let text = DexExtra.shared.moveDescription(move.id) {
                        DetailCard(title: L("Beschreibung", "Description")) {
                            Text(text).font(.body)
                        }
                    }

                    learners(move)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(move.name)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if game == nil { game = preferredGame.flatMap { $0.hasLearnsets ? $0 : nil } ?? dex.newestGame(withMove: move.id) }
            }
        }
    }

    @ViewBuilder private func learners(_ move: DexMove) -> some View {
        if let game {
            let list = Dex.shared.learners(of: move.id, game: game)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L("Wer lernt es?", "Who learns it?")).font(.title3.weight(.bold))
                    Spacer()
                    Menu {
                        Picker(selection: Binding(get: { game }, set: { self.game = $0 })) {
                            GameMenuItems(games: Game.allCases.filter(\.hasLearnsets), asGame: true)
                        } label: { EmptyView() }
                        .pickerStyle(.inline)
                    } label: {
                        HStack(spacing: 6) {
                            Text(game.compactTitle).lineLimit(1)
                            Image(systemName: "chevron.down").font(.caption.weight(.bold))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(game.gradient, in: Capsule())
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                }
                Text(L("\(list.count) Pokémon in \(game.title) (Level, TM, Zucht oder Tutor)",
                       "\(list.count) Pokémon in \(game.title) (level-up, TM, breeding or tutor)"))
                    .font(.caption).foregroundStyle(.secondary)
                LazyVStack(spacing: 8) {
                    ForEach(list) { p in
                        NavigationLink(value: DexRoute(pokemonId: p.id, game: game)) { DexRow(pokemon: p) }
                            .buttonStyle(.plain)
                    }
                }
                if list.isEmpty {
                    Text(L("Kein Pokémon lernt diese Attacke in \(game.title).", "No Pokémon learns this move in \(game.title)."))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func statTile(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.weight(.bold).monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .card()
    }
}

struct AbilityDetailView: View {
    let abilityId: Int
    let game: Game?

    var body: some View {
        let dex = Dex.shared
        if let ability = dex.ability(abilityId) {
            let holders = dex.pokemon(withAbility: ability.id, game: game)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ability.name).font(.largeTitle.weight(.bold))
                        if ability.altName != ability.name { Text(ability.altName).font(.subheadline).foregroundStyle(.secondary) }
                        if let gen = DexExtra.shared.abilityGeneration(ability.id) {
                            Text(L("Seit Generation \(gen)", "Since Generation \(gen)")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)

                    if let text = Wiki.shared.abilityText(ability.id) {
                        DetailCard(title: L("Wirkung", "Effect")) { Text(text) }
                    }

                    pokemonSection(L("Pokémon mit dieser Fähigkeit", "Pokémon with this ability"), holders.normal)
                    pokemonSection(L("Als versteckte Fähigkeit", "As hidden ability"), holders.hidden)
                    if holders.normal.isEmpty && holders.hidden.isEmpty {
                        Text(game.map { L("Kein Pokémon hat diese Fähigkeit in \($0.title).", "No Pokémon has this ability in \($0.title).") }
                             ?? L("Kein Pokémon hat diese Fähigkeit.", "No Pokémon has this ability."))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(ability.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder private func pokemonSection(_ title: String, _ list: [DexPokemon]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.title3.weight(.bold))
                    Text("\(list.count)").font(.headline.monospacedDigit()).foregroundStyle(.secondary)
                }
                LazyVStack(spacing: 8) {
                    ForEach(list) { p in
                        NavigationLink(value: DexRoute(pokemonId: p.id, game: game)) { DexRow(pokemon: p) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct ItemDetailView: View {
    let itemId: Int
    let game: Game?

    var body: some View {
        let dex = Dex.shared
        if let item = DexExtra.shared.item(itemId) {
            let megas = dex.pokemon.filter { $0.stone == item.id }
            let evolving = Wiki.shared.species(evolvingWith: item.id).compactMap { dex.defaultPokemon(species: $0) }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        ItemPicture(key: item.key)
                            .frame(width: 64, height: 64)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).font(.title.weight(.bold))
                            if item.altName != item.name { Text(item.altName).font(.subheadline).foregroundStyle(.secondary) }
                            HStack(spacing: 6) {
                                if let pocket = ItemPocket(rawValue: item.p) {
                                    Label(pocket.title, systemImage: pocket.icon)
                                }
                                if let cat = DexExtra.shared.categoryName(item.cat) {
                                    Text("· \(cat)")
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)

                    if let text = item.text {
                        DetailCard(title: L("Beschreibung", "Description")) { Text(text) }
                    }

                    if !item.g.isEmpty {
                        DetailCard(title: L("Vorkommen", "Available in")) {
                            Text(L("Generation ", "Generation ") + item.g.map(String.init).joined(separator: ", "))
                                .font(.subheadline)
                        }
                    }

                    pokemonSection(L("Mega-Entwicklung", "Mega Evolution"), megas)
                    pokemonSection(L("Entwickelt damit", "Evolves with it"), evolving)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder private func pokemonSection(_ title: String, _ list: [DexPokemon]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.title3.weight(.bold))
                LazyVStack(spacing: 8) {
                    ForEach(list) { p in
                        NavigationLink(value: DexRoute(pokemonId: p.id, game: game)) { DexRow(pokemon: p) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
