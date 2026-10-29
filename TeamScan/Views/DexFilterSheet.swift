import SwiftUI

enum DexRegion: String, CaseIterable, Identifiable {
    case alola, galar, hisui, paldea
    var id: String { rawValue }
    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    func matches(_ p: DexPokemon) -> Bool {
        p.key.contains("-\(rawValue)") && !p.isBattleForm
    }
}

/// All Pokédex filters except the game (the game stays in its own menu).
/// Within one section any selected value may match (OR), sections are combined (AND).
/// Types: the Pokémon must have all selected types (e.g. Fire + Flying).
struct DexFilter: Equatable {
    var categories: Set<DexCategory> = []
    var regions: Set<DexRegion> = []
    var types: Set<Int> = []

    var isEmpty: Bool { categories.isEmpty && regions.isEmpty && types.isEmpty }
    var count: Int { categories.count + regions.count + types.count }

    func matches(_ p: DexPokemon) -> Bool {
        if !categories.isEmpty && !categories.contains(where: { $0.matches(p) }) { return false }
        if !regions.isEmpty && !regions.contains(where: { $0.matches(p) }) { return false }
        if !types.isEmpty && !types.allSatisfy({ p.t.contains($0) }) { return false }
        return true
    }

    // Stored as text in the app settings: "c=mega,gmax;r=alola;t=10,3"
    var encoded: String {
        "c=" + categories.map(\.rawValue).sorted().joined(separator: ",")
            + ";r=" + regions.map(\.rawValue).sorted().joined(separator: ",")
            + ";t=" + types.sorted().map(String.init).joined(separator: ",")
    }

    init() {}

    init(encoded: String) {
        for part in encoded.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let values = kv[1].split(separator: ",").map(String.init)
            switch kv[0] {
            case "c": categories = Set(values.compactMap(DexCategory.init(rawValue:)))
            case "r": regions = Set(values.compactMap(DexRegion.init(rawValue:)))
            case "t": types = Set(values.compactMap(Int.init))
            default: break
            }
        }
    }
}

struct DexFilterSheet: View {
    @Binding var filter: DexFilter
    @Environment(\.dismiss) private var dismiss
    @State private var draft = DexFilter()
    @State private var open: Set<String> = ["category"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Text(L("Wähle aus, was du sehen willst. Innerhalb eines Bereichs reicht ein Treffer, mehrere Bereiche werden kombiniert.",
                           "Pick what you want to see. Within one section any match counts, sections are combined."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 4)

                    section(id: "category", title: L("Kategorie", "Category"), selected: draft.categories.map(\.title)) {
                        FlowLayout(spacing: 8) {
                            ForEach(DexCategory.allCases) { c in
                                FilterChip(title: c.title, icon: c.icon, color: .indigo, isOn: draft.categories.contains(c)) {
                                    toggle(&draft.categories, c)
                                }
                            }
                        }
                    }

                    section(id: "region", title: L("Regionalformen", "Regional forms"), selected: draft.regions.map(\.title)) {
                        FlowLayout(spacing: 8) {
                            ForEach(DexRegion.allCases) { r in
                                FilterChip(title: r.title, icon: "map.fill", color: .teal, isOn: draft.regions.contains(r)) {
                                    toggle(&draft.regions, r)
                                }
                            }
                        }
                    }

                    section(id: "types", title: L("Typen", "Types"),
                            selected: draft.types.sorted().compactMap { Dex.shared.type($0)?.name },
                            footer: L("Mehrere Typen: das Pokémon muss alle haben, z. B. Feuer + Flug.",
                                      "Several types: the Pokémon must have all of them, e.g. Fire + Flying.")) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                            ForEach(Dex.shared.battleTypes) { t in
                                let on = draft.types.contains(t.id)
                                Button {
                                    withAnimation(.snappy) { toggle(&draft.types, t.id) }
                                } label: {
                                    Text(t.name)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .foregroundStyle(on ? Color.white : TypeColor.color(t.id))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                        .background(on ? AnyShapeStyle(TypeColor.color(t.id).gradient) : AnyShapeStyle(TypeColor.color(t.id).opacity(0.15)),
                                                    in: Capsule())
                                        .overlay(Capsule().strokeBorder(TypeColor.color(t.id).opacity(on ? 0 : 0.5), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .disabled(!on && draft.types.count >= 2)
                                .opacity(!on && draft.types.count >= 2 ? 0.4 : 1)
                            }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 90)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) { buttons }
            .navigationTitle(L("Filter", "Filters"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(L("Schließen", "Close"))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { draft = filter }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.snappy) { draft = DexFilter() }
            } label: {
                Label(L("Zurücksetzen", "Clear all"), systemImage: "xmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundStyle(draft.isEmpty ? Color.secondary : Color.primary)
                    .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(draft.isEmpty)

            Button {
                filter = draft
                dismiss()
            } label: {
                Label(draft.isEmpty ? L("Anwenden", "Apply") : L("Anwenden (\(draft.count))", "Apply (\(draft.count))"), systemImage: "checkmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundStyle(.white)
                    .background(draft == filter ? AnyShapeStyle(Color.gray.opacity(0.5)) : AnyShapeStyle(Color.indigo.gradient), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(draft == filter)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background {
            LinearGradient(colors: [Color(.systemGroupedBackground).opacity(0), Color(.systemGroupedBackground)], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        }
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ value: T) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    @ViewBuilder
    private func section<Content: View>(id: String, title: String, selected: [String], footer: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        let isOpen = open.contains(id)
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.snappy) {
                    if isOpen { open.remove(id) } else { open.insert(id) }
                }
            } label: {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title).font(.headline)
                        Text(selected.isEmpty ? L("Kein Filter", "No filter") : selected.sorted().joined(separator: ", "))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(selected.isEmpty ? Color.secondary : Color.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(selected.isEmpty ? AnyShapeStyle(Color(.tertiarySystemFill)) : AnyShapeStyle(Color.indigo.gradient), in: Capsule())
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                content()
                if let footer {
                    Text(footer).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct FilterChip: View {
    let title: String
    let icon: String
    let color: Color
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption.weight(.bold))
                Text(title).font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isOn ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Color(.tertiarySystemFill)), in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? Color.clear : Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}
