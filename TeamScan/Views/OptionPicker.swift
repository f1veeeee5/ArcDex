import SwiftUI

struct PickerOption: Identifiable {
    enum Accessory {
        case none
        case pokemon(Int)
        case item(DexItem)
        case move(DexMove)
        case type(Int)
    }

    let id: Int
    let title: String
    let subtitle: String
    let detail: String
    let accessory: Accessory
    let search: String
    var types: [Int] = []

    init(id: Int, title: String, subtitle: String, detail: String = "", accessory: Accessory = .none, types: [Int] = []) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.accessory = accessory
        self.types = types
        self.search = Fuzzy.normalize(title) + "|" + Fuzzy.normalize(subtitle)
    }
}

enum PickerOptions {
    static func pokemon(game: Game) -> [PickerOption] {
        Dex.shared.availablePokemon(in: game).map {
            PickerOption(id: $0.id, title: $0.name, subtitle: $0.altName, detail: $0.dexNumber, accessory: .pokemon($0.id), types: $0.t)
        }
    }

    static func moves(_ moves: [DexMove]) -> [PickerOption] {
        moves.map { m in
            var detail: [String] = []
            if m.p > 0 { detail.append(L("Stärke \(m.p)", "Power \(m.p)")) }
            if m.a > 0 { detail.append(L("Genau. \(m.a)", "Acc. \(m.a)")) }
            detail.append(L("AP \(m.pp)", "PP \(m.pp)"))
            return PickerOption(id: m.id, title: m.name, subtitle: m.altName, detail: detail.joined(separator: " · "), accessory: .move(m))
        }
    }

    static func items(game: Game) -> [PickerOption] {
        Dex.shared.items(for: game).map { PickerOption(id: $0.id, title: $0.name, subtitle: $0.altName, accessory: .item($0)) }
    }

    static func abilities(_ list: [DexAbility], hidden: Int) -> [PickerOption] {
        list.map { PickerOption(id: $0.id, title: $0.name, subtitle: $0.altName, detail: $0.id == hidden ? L("Versteckte Fähigkeit", "Hidden ability") : "") }
    }

    static func allAbilities() -> [PickerOption] {
        Dex.shared.abilities.sorted { $0.name < $1.name }.map { PickerOption(id: $0.id, title: $0.name, subtitle: $0.altName) }
    }

    static func natures() -> [PickerOption] {
        let names = StatNames.short
        return Dex.shared.natures.sorted { $0.name < $1.name }.map { n in
            let detail = n.isNeutral ? L("neutral", "neutral") : "+\(names[n.up - 1])  −\(names[n.down - 1])"
            return PickerOption(id: n.id, title: n.name, subtitle: n.altName, detail: detail)
        }
    }

    static func types(_ list: [DexType]) -> [PickerOption] {
        list.map { PickerOption(id: $0.id, title: $0.name, subtitle: $0.altName, accessory: .type($0.id)) }
    }
}

struct OptionPicker: View {
    let title: String
    let options: [PickerOption]
    var selected: Int?
    var allowNone = false
    var footer: String?
    var onSelect: (Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [PickerOption] {
        let q = Fuzzy.normalize(query)
        guard !q.isEmpty else { return options }
        return options.filter { $0.search.contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if allowNone && query.isEmpty {
                    Button {
                        onSelect(nil)
                        dismiss()
                    } label: {
                        Label(L("Keins", "None"), systemImage: "xmark.circle").foregroundStyle(.secondary)
                    }
                }
                ForEach(filtered) { option in
                    Button {
                        onSelect(option.id)
                        dismiss()
                    } label: {
                        OptionRow(option: option, isSelected: option.id == selected)
                    }
                    .buttonStyle(.plain)
                }
                if let footer {
                    Text(footer).font(.footnote).foregroundStyle(.secondary).listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: L("Suchen (Deutsch oder Englisch)", "Search (German or English)"))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen", "Cancel")) { dismiss() }
                }
            }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }
}

struct OptionRow: View {
    let option: PickerOption
    var isSelected = false

    var body: some View {
        HStack(spacing: 12) {
            switch option.accessory {
            case .pokemon(let id):
                PokemonSprite(pokemonId: id).frame(width: 44, height: 44)
            case .item(let item):
                ItemIcon(item: item).frame(width: 30, height: 30)
            case .move(let m):
                RoundedRectangle(cornerRadius: 4).fill(TypeColor.color(m.t)).frame(width: 6, height: 34)
            case .type(let t):
                Circle().fill(TypeColor.color(t)).frame(width: 14, height: 14)
            case .none:
                EmptyView()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title).font(.body.weight(.medium))
                HStack(spacing: 6) {
                    if option.subtitle != option.title {
                        Text(option.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    if !option.detail.isEmpty {
                        Text(option.detail).font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 4)
            if case .move(let m) = option.accessory {
                VStack(alignment: .trailing, spacing: 3) {
                    TypeBadge(typeId: m.t, small: true)
                    CategoryBadge(category: m.c)
                }
            }
            if !option.types.isEmpty {
                HStack(spacing: 3) { ForEach(option.types, id: \.self) { TypeBadge(typeId: $0, small: true) } }
            }
            if isSelected {
                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }
}
