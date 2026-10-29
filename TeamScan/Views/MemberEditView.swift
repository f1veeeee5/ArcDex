import SwiftUI
import SwiftData

struct MemberEditView: View {
    @Bindable var member: TeamMember
    let game: Game
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private enum ActivePicker: Identifiable {
        case species, item, ability, nature, tera, move(Int)
        var id: String {
            switch self {
            case .species: return "species"
            case .item: return "item"
            case .ability: return "ability"
            case .nature: return "nature"
            case .tera: return "tera"
            case .move(let i): return "move\(i)"
            }
        }
    }

    @State private var picker: ActivePicker?
    @State private var showMoveScan = false
    @State private var showSummaryScan = false
    @State private var confirmDelete = false

    private var dex: Dex { .shared }
    private var species: DexPokemon? { member.species }

    var body: some View {
        Form {
            heroSection
            movesSection
            detailsSection
            if game.hasMega || game.hasDynamax || game.hasTera { mechanicSection }
            statsSection
            if game.hasEVs { evSection }
            Section {
                Button { showSummaryScan = true } label: {
                    Label(L("Übersichtsseite scannen", "Scan summary screen"), systemImage: "text.viewfinder")
                }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label(L("Aus dem Team entfernen", "Remove from team"), systemImage: "trash")
                }
            } footer: {
                Text(L("Beim Scannen der Übersicht werden Pokémon, Level, Item, Fähigkeit, Wesen und sichtbare Attacken erkannt.",
                       "Scanning the summary detects Pokémon, level, item, ability, nature and visible moves."))
            }
        }
        .navigationTitle(member.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: DexRoute(pokemonId: member.battleForm(in: game)?.id ?? member.pokemonId, game: game)) {
                    Image(systemName: "book.closed")
                }
                .accessibilityLabel(L("Im Pokédex ansehen", "View in Pokédex"))
            }
        }
        .sheet(item: $picker) { p in pickerSheet(p) }
        .sheet(isPresented: $showMoveScan) {
            MoveScanSheet(member: member, game: game)
        }
        .sheet(isPresented: $showSummaryScan) {
            MemberScanSheet(game: game, mode: .single(member.pokemonId)) { result in
                if let s = result.first { member.apply(s, replaceSpecies: true) }
            }
        }
        .confirmationDialog(L("\(member.displayName) entfernen?", "Remove \(member.displayName)?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("Entfernen", "Remove"), role: .destructive) {
                let team = member.team
                context.delete(member)
                team?.touch()
                dismiss()
            }
        }
    }

    // MARK: Hero

    private var heroSection: some View {
        Section {
            VStack(spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(RadialGradient(colors: member.types(in: game).map { TypeColor.color($0).opacity(0.35) } + [.clear],
                                             center: .center, startRadius: 10, endRadius: 120))
                        .frame(width: 200, height: 200)
                    PokemonSprite(pokemonId: member.battleForm(in: game)?.id ?? member.pokemonId, shiny: member.shiny)
                        .frame(width: 170, height: 170)
                        .padding(15)
                        .id("\(member.pokemonId)-\(member.megaFormId ?? 0)-\(member.gigantamax)-\(member.shiny)")
                        .transition(.scale.combined(with: .opacity))
                }
                .frame(maxWidth: .infinity)
                .onTapGesture { picker = .species }

                VStack(spacing: 6) {
                    Text(member.battleForm(in: game)?.name ?? "?").font(.title2.weight(.bold))
                    if let s = species {
                        Text("\(s.dexNumber) · \(s.altName)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        ForEach(member.types(in: game), id: \.self) { TypeBadge(typeId: $0) }
                    }
                }

                HStack(spacing: 10) {
                    if game.hasShiny {
                        Button {
                            withAnimation(.spring) { member.shiny.toggle() }
                        } label: {
                            Label(member.shiny ? L("Shiny", "Shiny") : L("Nicht shiny", "Not shiny"), systemImage: member.shiny ? "sparkles" : "sparkle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(member.shiny ? .yellow : .gray)
                    }

                    Button { picker = .species } label: {
                        Label(L("Ändern", "Change"), systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: Moves

    private var movesSection: some View {
        Section {
            Button { showMoveScan = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(game.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Attacken scannen", "Scan moves")).font(.headline).foregroundStyle(.primary)
                        Text(L("Foto vom Attacken-Bildschirm – Deutsch oder Englisch", "Photo of the moves screen – German or English"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            ForEach(0..<4, id: \.self) { i in
                Button { picker = .move(i) } label: {
                    MoveRow(move: i < member.moves.count ? member.moves[i] : nil)
                }
                .buttonStyle(.plain)
                .swipeActions {
                    if i < member.moveIds.count {
                        Button(role: .destructive) { member.setMove(nil, at: i) } label: { Label(L("Löschen", "Delete"), systemImage: "trash") }
                    }
                }
            }
        } header: {
            Text(L("Attacken", "Moves"))
        }
    }

    // MARK: Details

    private var detailsSection: some View {
        Section(L("Details", "Details")) {
            HStack {
                Text(L("Spitzname", "Nickname"))
                TextField(species?.name ?? "", text: $member.nickname)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
            }
            Stepper(value: $member.level, in: 1...100) {
                HStack {
                    Text(L("Level", "Level"))
                    Spacer()
                    Text("\(member.level)").monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if game.hasHeldItems {
                row(L("Item", "Item"), value: member.item?.name, icon: { ItemIcon(item: member.item).frame(width: 24, height: 24) }) { picker = .item }
            }
            if game.hasAbilities {
                row(L("Fähigkeit", "Ability"), value: member.ability?.name) { picker = .ability }
            }
            if game.hasNatures {
                row(L("Wesen", "Nature"), value: natureText) { picker = .nature }
            }
            if game.hasGender {
                Picker(L("Geschlecht", "Gender"), selection: $member.gender) {
                    Text("–").tag("")
                    Text("♂").tag("M")
                    Text("♀").tag("F")
                }
                .pickerStyle(.segmented)
            }
            if !game.hasHeldItems || !game.hasAbilities {
                Text(L("Ausgeblendete Felder gibt es in \(game.title) nicht.", "Hidden fields don't exist in \(game.title)."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var natureText: String? {
        guard let n = member.nature else { return nil }
        if n.isNeutral { return n.name }
        let s = StatNames.short
        return "\(n.name) (+\(s[n.up - 1]) −\(s[n.down - 1]))"
    }

    private func row(_ title: String, value: String?, action: @escaping () -> Void) -> some View {
        row(title, value: value, icon: { EmptyView() }, action: action)
    }

    private func row<Icon: View>(_ title: String, value: String?, @ViewBuilder icon: () -> Icon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                icon()
                Text(value ?? L("Wählen", "Choose")).foregroundStyle(value == nil ? .tertiary : .secondary)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Mechanics

    private var mechanicSection: some View {
        Section {
            if game.hasMega {
                let megas = dex.megaForms(for: member.pokemonId, game: game)
                if megas.isEmpty {
                    Label { Text(L("Keine Mega-Entwicklung verfügbar", "No Mega Evolution available")) } icon: { MechanicLogo(mechanic: .mega, size: 20) }
                        .foregroundStyle(.secondary)
                } else {
                    Picker(selection: Binding(get: { member.megaFormId ?? 0 }, set: { setMega($0 == 0 ? nil : $0) })) {
                        Text(L("Aus", "Off")).tag(0)
                        ForEach(megas) { Text($0.name).tag($0.id) }
                    } label: {
                        Label { Text(L("Mega-Entwicklung", "Mega Evolution")) } icon: { MechanicLogo(mechanic: .mega, size: 20).foregroundStyle(.tint) }
                    }
                }
            }
            if game.hasDynamax {
                if dex.gmaxForm(for: member.pokemonId, game: game) != nil {
                    Toggle(isOn: $member.gigantamax.animation(.spring)) {
                        Label { Text(L("Gigadynamax-Faktor", "Gigantamax Factor")) } icon: { MechanicLogo(mechanic: .gmax, size: 22).foregroundStyle(Color(hex: 0xE5007E)) }
                    }
                } else {
                    Label { Text(L("Dynamax möglich, keine Gigadynamax-Form", "Can Dynamax, no Gigantamax form")) } icon: { MechanicLogo(mechanic: .gmax, size: 22) }
                        .foregroundStyle(.secondary)
                }
            }
            if game.hasTera {
                row(L("Tera-Typ", "Tera Type"), value: member.teraTypeId.flatMap { dex.type($0)?.name }, icon: {
                    MechanicLogo(mechanic: .tera, size: 20)
                        .foregroundStyle(member.teraTypeId.map { TypeColor.color($0) } ?? Color.secondary)
                }) { picker = .tera }
            }
        } header: {
            HStack(spacing: 6) {
                GameMechanicIcon(game: game, size: 16)
                Text(game.mechanic)
            }
        }
    }

    private func setMega(_ id: Int?) {
        withAnimation(.spring) {
            member.megaFormId = id
            if let id, let stone = dex.pokemon(id)?.stone { member.itemId = stone }
        }
    }

    // MARK: Stats

    private var statsSection: some View {
        Section(L("Basiswerte", "Base stats")) {
            if let form = member.battleForm(in: game) {
                let names = StatNames.short
                ForEach(0..<6, id: \.self) { i in
                    let value = form.s[i]
                    let nature = member.nature
                    let up = nature.map { !$0.isNeutral && $0.up == i + 1 } ?? false
                    let down = nature.map { !$0.isNeutral && $0.down == i + 1 } ?? false
                    HStack(spacing: 10) {
                        Text(names[i]).font(.caption.weight(.semibold)).frame(width: 64, alignment: .leading)
                            .foregroundStyle(up ? .red : (down ? .blue : .secondary))
                        Text("\(value)").font(.caption.monospacedDigit().weight(.bold)).frame(width: 30, alignment: .trailing)
                        GeometryReader { geo in
                            Capsule().fill(Color(.tertiarySystemFill))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(statColor(value).gradient).frame(width: geo.size.width * min(Double(value) / 200, 1))
                                }
                        }
                        .frame(height: 8)
                    }
                }
                HStack {
                    Text(L("Gesamt", "Total")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(form.s.reduce(0, +))").font(.caption.weight(.bold).monospacedDigit())
                }
            }
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

    private var evSection: some View {
        Section {
            DisclosureGroup {
                let names = StatNames.short
                ForEach(0..<6, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(names[i]).font(.subheadline)
                            Spacer()
                            Text("\(member.evs[i])").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(get: { Double(member.evs[i]) }, set: { setEV(i, Int($0)) }), in: 0...252, step: 4)
                    }
                }
                HStack {
                    Text(L("Gesamt", "Total"))
                    Spacer()
                    let total = member.evs.reduce(0, +)
                    Text("\(total) / 510").monospacedDigit().foregroundStyle(total > 510 ? .red : .secondary)
                }
                Button(L("EVs zurücksetzen", "Reset EVs")) { member.evs = [0, 0, 0, 0, 0, 0] }
            } label: {
                Label(L("EVs (Fleißpunkte)", "EVs"), systemImage: "chart.bar")
            }
            DisclosureGroup {
                let names = StatNames.short
                ForEach(0..<6, id: \.self) { i in
                    Stepper(value: Binding(get: { member.ivs[i] }, set: { v in var a = member.ivs; a[i] = v; member.ivs = a }), in: 0...31) {
                        HStack {
                            Text(names[i])
                            Spacer()
                            Text("\(member.ivs[i])").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            } label: {
                Label(L("IVs (Individualwerte)", "IVs"), systemImage: "dial.medium")
            }
        }
    }

    private func setEV(_ i: Int, _ value: Int) {
        var a = member.evs
        let others = a.enumerated().filter { $0.offset != i }.map(\.element).reduce(0, +)
        a[i] = min(value, max(0, 510 - others))
        member.evs = a
    }

    // MARK: Picker sheets

    @ViewBuilder
    private func pickerSheet(_ p: ActivePicker) -> some View {
        switch p {
        case .species:
            OptionPicker(title: L("Pokémon wählen", "Choose Pokémon"), options: PickerOptions.pokemon(game: game), selected: member.pokemonId) { id in
                if let id { withAnimation { member.setPokemon(id) } }
            }
        case .item:
            OptionPicker(title: L("Item wählen", "Choose item"), options: PickerOptions.items(game: game), selected: member.itemId, allowNone: true) { id in
                member.itemId = id
                if let id, let form = member.megaForm(forStone: id), game.hasMega { member.megaFormId = form }
                else if member.megaFormId != nil, let mega = member.megaFormId.flatMap({ dex.pokemon($0) }), mega.stone != nil, mega.stone != id {
                    member.megaFormId = nil
                }
            }
        case .ability:
            let options: [PickerOption] = {
                guard let s = species else { return PickerOptions.allAbilities() }
                let slots = s.abilitySlots(gen: game.gen)
                return PickerOptions.abilities(dex.abilities(for: s, gen: game.gen), hidden: slots.hidden)
            }()
            OptionPicker(title: L("Fähigkeit wählen", "Choose ability"), options: options, selected: member.abilityId) { member.abilityId = $0 }
        case .nature:
            OptionPicker(title: L("Wesen wählen", "Choose nature"), options: PickerOptions.natures(), selected: member.natureId, allowNone: true) { member.natureId = $0 }
        case .tera:
            OptionPicker(title: L("Tera-Typ wählen", "Choose Tera Type"), options: PickerOptions.types(dex.teraTypes), selected: member.teraTypeId, allowNone: true) { member.teraTypeId = $0 }
        case .move(let i):
            let learn = dex.learnset(for: member.pokemonId, game: game)
            OptionPicker(title: L("Attacke \(i + 1)", "Move \(i + 1)"), options: PickerOptions.moves(learn),
                         selected: i < member.moveIds.count ? member.moveIds[i] : nil, allowNone: i < member.moveIds.count,
                         footer: game.hasLearnsets
                            ? L("Zeigt nur Attacken, die \(species?.name ?? "das Pokémon") in \(game.title) lernen kann.",
                                "Only shows moves \(species?.name ?? "this Pokémon") can learn in \(game.title).")
                            : L("Für \(game.title) gibt es keine Attackenlisten in der Datenbank – es werden alle Attacken gezeigt.",
                                "There are no move lists for \(game.title) in the database – all moves are shown.")) { id in
                member.setMove(id, at: i)
            }
        }
    }
}

struct MoveRow: View {
    let move: DexMove?

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(move.map { TypeColor.color($0.t) } ?? Color(.tertiarySystemFill))
                .frame(width: 5, height: 36)
            if let move {
                VStack(alignment: .leading, spacing: 3) {
                    Text(move.name).font(.body.weight(.semibold))
                    HStack(spacing: 6) {
                        TypeBadge(typeId: move.t, small: true)
                        CategoryBadge(category: move.c)
                        if move.p > 0 { Text(L("Stärke \(move.p)", "Power \(move.p)")).font(.caption2).foregroundStyle(.secondary) }
                        Text(L("AP \(move.pp)", "PP \(move.pp)")).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(L("Attacke wählen", "Choose move")).foregroundStyle(.tertiary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
