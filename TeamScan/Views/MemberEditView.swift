import SwiftUI
import SwiftData

struct MemberEditView: View {
    @Bindable var member: TeamMember
    let game: Game
    /// true inside the swipe pager – the pager then shows title and toolbar itself
    var embedded = false
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
    @AppStorage("showMovesetTips") private var showMovesetTips = true
    @Environment(\.pagerSwipeLock) private var swipeLock

    private var dex: Dex { .shared }
    private var species: DexPokemon? { member.species }

    var body: some View {
        Form {
            heroSection
            movesSection
            if showMovesetTips { MovesetSuggestionsSection(member: member, game: game) }
            detailsSection
            if game.hasMega || game.hasDynamax || game.hasTera { mechanicSection }
            statsSection
            if game.hasEVs { evSection }
            Section {
                Button { showSummaryScan = true } label: {
                    Label(L("Übersichtsseite scannen", "Scan summary screen"), systemImage: "text.viewfinder")
                }
                if let link = member.link, let run = link.savegame {
                    Button {
                        NuzlockeActions.set(link, to: .box, in: run, context: context)
                        dismiss()
                    } label: {
                        Label(run.mode == .soulLink ? L("In die Box (beide)", "To box (both)") : L("In die Box", "To box"), systemImage: "archivebox")
                    }
                    .disabled(link.status != .team)
                    Button(role: .destructive) {
                        NuzlockeActions.set(link, to: .dead, in: run, context: context)
                        dismiss()
                    } label: {
                        Label(run.mode == .soulLink ? L("Gestorben (beide)", "Fainted (both)") : L("Gestorben", "Fainted"), systemImage: "xmark.seal")
                    }
                    .disabled(link.status == .dead)
                } else {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label(L("Aus dem Team entfernen", "Remove from team"), systemImage: "trash")
                    }
                }
            } footer: {
                Text(L("Beim Scannen der Übersicht werden Pokémon, Level, Item, Fähigkeit, Wesen und sichtbare Attacken erkannt.",
                       "Scanning the summary detects Pokémon, level, item, ability, nature and visible moves."))
            }
        }
        .modifier(EditorChrome(enabled: !embedded, member: member, game: game))
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
                    AnimatedPokemonSprite(pokemonId: member.battleForm(in: game)?.id ?? member.pokemonId, shiny: member.shiny)
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
                    MoveRow(move: i < member.moves.count ? member.moves[i] : nil,
                            isZMove: i < member.moves.count && ZCrystal.zMoves(for: member, game: game).contains(member.moves[i].id))
                }
                .buttonStyle(.plain)
                // no swipe-to-delete here: horizontal swipes switch to the next Pokémon.
                // Removing a move works via "None" in the move picker.
            }
            if let hint = ZCrystal.hint(for: member, game: game) {
                Label { Text(hint).font(.footnote) } icon: { MechanicLogo(mechanic: .zMove, size: 18) }
                    .foregroundStyle(.secondary)
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
                    .onChange(of: member.nickname) { NuzlockeActions.nicknameChanged(member) }
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
            }
            if let fixed = game.fixedLevel {
                HStack {
                    Text(L("Level", "Level"))
                    Spacer()
                    Text(L("\(fixed) (fest in \(game.title))", "\(fixed) (fixed in \(game.title))")).foregroundStyle(.secondary)
                }
                .onAppear { if member.level != fixed { member.level = fixed } }
            } else {
                Stepper(value: $member.level, in: 1...100) {
                    HStack {
                        Text(L("Level", "Level"))
                        Spacer()
                        Text("\(member.level)").monospacedDigit().foregroundStyle(.secondary)
                    }
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
                if game.hasZMoves {
                    // Z-Moves come from the held Z-Crystal and are marked in the moves list
                    MechanicLogo(mechanic: .mega, size: 16)
                    Text(L("Mega-Entwicklung", "Mega Evolution"))
                } else {
                    GameMechanicIcon(game: game, size: 16)
                    Text(game.mechanic)
                }
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

    private var showsRealStats: Bool { game.hasEVs }
    private var statLevel: Int { game.fixedLevel ?? member.level }

    private var statsSection: some View {
        Section {
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
                        if showsRealStats {
                            realStatBar(index: i, base: value)
                        } else {
                            GeometryReader { geo in
                                Capsule().fill(Color(.tertiarySystemFill))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(statColor(value).gradient).frame(width: geo.size.width * min(Double(value) / 200, 1))
                                    }
                            }
                            .frame(height: 8)
                        }
                        if showsRealStats {
                            Text(verbatim: String(member.stat(i, base: value, level: statLevel, game: game)))
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(up ? .red : (down ? .blue : .primary))
                                .lineLimit(1)
                                .fixedSize()
                                .frame(minWidth: 36, alignment: .trailing)
                        }
                    }
                }
                HStack {
                    Text(L("Gesamt", "Total")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(form.s.reduce(0, +))").font(.caption.weight(.bold).monospacedDigit())
                    if showsRealStats {
                        // no thousands separator and never wrapped (totals at Lv. 100 have 4 digits)
                        Text(verbatim: String((0..<6).map { member.stat($0, base: form.s[$0], level: statLevel, game: game) }.reduce(0, +)))
                            .font(.caption.weight(.bold).monospacedDigit())
                            .lineLimit(1)
                            .fixedSize()
                            .frame(minWidth: 36, alignment: .trailing)
                    }
                }
            }
        } header: {
            HStack {
                Text(L("Basiswerte", "Base stats"))
                Spacer()
                if showsRealStats {
                    Text(L("Wert auf Lv. \(statLevel)", "Stat at Lv. \(statLevel)")).textCase(nil)
                }
            }
        } footer: {
            if showsRealStats {
                let realText = game.isChampions
                    ? L("Rechts: echte Werte auf Level 50 mit deinen Punkten und deinem Wesen (rot = erhöht, blau = gesenkt).",
                        "Right: real stats at level 50 with your points and nature (red = raised, blue = lowered).")
                    : L("Rechts: echte Werte mit Level, EVs, IVs und Wesen.", "Right: real stats with level, EVs, IVs and nature.")
                let barText = L("Balken: kräftig = Wert ohne EVs, hell = Zuwachs durch EVs und Wesen, blau = durch das Wesen gesenkt.",
                                "Bars: solid = value without EVs, light = gain from EVs and nature, blue = lowered by the nature.")
                Text("\(realText) \(barText)")
            }
        }
    }

    /// Real stat with chosen EVs / nature factor (IVs of the Pokémon).
    private func realStat(_ i: Int, base: Int, ev: Int, natureFactor: Double) -> Int {
        let iv = game.hasIVs ? member.ivs[i] : 31
        let level = statLevel
        let core = (2 * base + iv + ev / 4) * level / 100
        if i == 0 { return base == 1 ? 1 : core + level + 10 }
        return Int(Double(core + 5) * natureFactor)
    }

    /// Bar of the real stat: solid part = without EVs and nature, light part = what EVs and nature add,
    /// blue part = what a lowering nature takes away. Grows live while the EV sliders move.
    private func realStatBar(index i: Int, base: Int) -> some View {
        let actual = member.stat(i, base: base, level: statLevel, game: game)
        let plain = realStat(i, base: base, ev: 0, natureFactor: 1)
        // scale: a very strong stat (base 200, full EVs, raising nature) fills the bar
        let maxRef = Double(max(realStat(i, base: 200, ev: 252, natureFactor: i == 0 ? 1 : 1.1), 1))
        let color = statColor(base)
        return GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                if actual < plain {
                    Capsule().fill(Color.blue.opacity(0.35)).frame(width: w * min(Double(plain) / maxRef, 1))
                }
                if actual > plain {
                    Capsule().fill(color.opacity(0.45)).frame(width: w * min(Double(actual) / maxRef, 1))
                }
                Capsule().fill(color.gradient).frame(width: w * min(Double(min(plain, actual)) / maxRef, 1))
            }
            .animation(.snappy, value: actual)
        }
        .frame(height: 8)
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
                    .holdsPagerSwipe(swipeLock)
                }
                HStack {
                    Text(L("Gesamt", "Total"))
                    Spacer()
                    let total = member.evs.reduce(0, +)
                    Text("\(total) / 510").monospacedDigit().foregroundStyle(total > 510 ? .red : .secondary)
                }
                Button(L("EVs zurücksetzen", "Reset EVs")) { member.evs = [0, 0, 0, 0, 0, 0] }
            } label: {
                Label(game.isChampions ? L("Stat-Punkte", "Stat points") : L("EVs (Fleißpunkte)", "EVs"), systemImage: "chart.bar")
            }
            if game.hasIVs {
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
                    .holdsPagerSwipe(swipeLock)
                }
            } label: {
                Label(L("IVs (Individualwerte)", "IVs"), systemImage: "dial.medium")
            }
            }
        } footer: {
            if game.isChampions {
                Text(L("In Champions sind die Individualwerte immer maximal – die EV-Regler stehen für deine verteilten Punkte.",
                       "In Champions IVs are always maxed – the EV sliders stand for your distributed points."))
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
    var isZMove = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(move.map { TypeColor.color($0.t) } ?? Color(.tertiarySystemFill))
                .frame(width: 5, height: 36)
            if let move {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(move.name).font(.body.weight(.semibold))
                        if isZMove {
                            HStack(spacing: 3) {
                                MechanicLogo(mechanic: .zMove, size: 13)
                                Text("Z").font(.caption2.weight(.heavy))
                            }
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.yellow.opacity(0.2), in: Capsule())
                            .foregroundStyle(.yellow)
                            .accessibilityLabel(L("Wird zur Z-Attacke", "Becomes a Z-Move"))
                        }
                    }
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


/// Title and Pokédex button of the editor (left out when the pager shows them).
private struct EditorChrome: ViewModifier {
    let enabled: Bool
    let member: TeamMember
    let game: Game

    func body(content: Content) -> some View {
        if enabled {
            content
                .navigationTitle(member.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { PokedexLinkButton(member: member, game: game) }
                }
        } else {
            content
        }
    }
}

struct PokedexLinkButton: View {
    let member: TeamMember
    let game: Game

    var body: some View {
        NavigationLink(value: DexRoute(pokemonId: member.battleForm(in: game)?.id ?? member.pokemonId, game: game)) {
            Image(systemName: "book.closed")
        }
        .accessibilityLabel(L("Im Pokédex ansehen", "View in Pokédex"))
    }
}

/// Swipe left / right to go through the team. Opens on the tapped Pokémon.
/// Deliberately not a paging TabView: the editor's Form must stay the page's own scroll view,
/// otherwise iOS can't shrink the tab bar or blur the navigation bar while scrolling.
struct MemberPagerView: View {
    let team: Team
    @State private var currentId: UUID
    @State private var forward = true
    @State private var dragOffset: CGFloat = 0
    @State private var swipeLock = PagerSwipeLock()

    init(team: Team, start: TeamMember) {
        self.team = team
        _currentId = State(initialValue: start.uuid)
    }

    var body: some View {
        let members = team.sortedMembers
        let game = team.game
        let index = members.firstIndex { $0.uuid == currentId } ?? 0
        let current = members.indices.contains(index) ? members[index] : nil

        Group {
            if let current {
                MemberEditView(member: current, game: game, embedded: true)
                    .environment(\.pagerSwipeLock, swipeLock)
                    .id(current.uuid)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
        }
        .offset(x: dragOffset)
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    // a horizontal list inside the editor (moveset suggestions) is being scrolled – don't switch Pokémon
                    guard !swipeLock.isActive else { dragOffset = 0; return }
                    // only follow clearly horizontal drags, vertical scrolling stays untouched
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                    dragOffset = value.translation.width * 0.25
                }
                .onEnded { value in
                    guard !swipeLock.isActive else {
                        withAnimation(.spring(duration: 0.3)) { dragOffset = 0 }
                        return
                    }
                    let dx = value.translation.width
                    let horizontal = abs(dx) > abs(value.translation.height) * 1.4
                    let predicted = value.predictedEndTranslation.width
                    if horizontal && (dx < -70 || predicted < -160), index + 1 < members.count {
                        switchTo(members[index + 1].uuid, forward: true)
                    } else if horizontal && (dx > 70 || predicted > 160), index > 0 {
                        switchTo(members[index - 1].uuid, forward: false)
                    } else {
                        withAnimation(.spring(duration: 0.3)) { dragOffset = 0 }
                    }
                }
        )
        .background(Color(.systemGroupedBackground))
        .navigationTitle(current?.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let current {
                ToolbarItem(placement: .topBarTrailing) { PokedexLinkButton(member: current, game: game) }
            }
        }
        .sensoryFeedback(.selection, trigger: currentId)
        .onDisappear { team.touch() }
    }

    private func switchTo(_ id: UUID, forward: Bool) {
        self.forward = forward
        withAnimation(.snappy(duration: 0.32)) {
            currentId = id
            dragOffset = 0
        }
    }
}


/// Lets horizontal scroll areas inside the editor stop the swipe to the next Pokémon.
final class PagerSwipeLock {
    var scrolling = false
    var lastScroll = Date.distantPast
    var isActive: Bool { scrolling || Date().timeIntervalSince(lastScroll) < 0.4 }
}

extension EnvironmentValues {
    @Entry var pagerSwipeLock: PagerSwipeLock? = nil
}

extension View {
    /// Use on sliders / steppers inside the editor: while a finger is on them, swiping never switches the Pokémon.
    func holdsPagerSwipe(_ lock: PagerSwipeLock?) -> some View {
        // starts only after a few points of movement – a plain tap (stepper +/−) must reach the control
        simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { _ in lock?.scrolling = true }
                .onEnded { _ in
                    lock?.scrolling = false
                    lock?.lastScroll = Date()
                }
        )
    }

    /// Use on horizontal scroll views inside the editor.
    func blocksPagerSwipe(_ lock: PagerSwipeLock?) -> some View {
        onScrollPhaseChange { _, phase in
            lock?.scrolling = phase != .idle
            lock?.lastScroll = Date()
        }
    }
}
