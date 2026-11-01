import SwiftUI

/// Damage calculator: an own team member against an opponent (from a trainer's team or any Pokémon).
/// Opened pre-filled from the match-up, or from the team editor.
struct DamageCalcView: View {
    let game: Game
    let team: Team
    /// opponents to choose from (the trainer's team), may be empty
    var pool: [GuidePokemon] = []
    var poolTitle: String?

    @Environment(\.dismiss) private var dismiss
    @State private var memberId: UUID?
    @State private var opponent: OpponentChoice
    @State private var options = DamageOptions()
    @State private var showSpeciesPicker = false

    enum OpponentChoice: Equatable {
        case pool(Int)
        case free(pokemonId: Int, level: Int, set: Int)
    }

    init(game: Game, team: Team, member: TeamMember?, pool: [GuidePokemon] = [], poolTitle: String? = nil, opponentIndex: Int? = nil) {
        self.game = game
        self.team = team
        self.pool = pool
        self.poolTitle = poolTitle
        _memberId = State(initialValue: member?.uuid ?? team.sortedMembers.first?.uuid)
        var opts = DamageOptions()
        if game.hasDynamax, let i = opponentIndex, i < pool.count, pool[i].gmax == true { opts.defenderDynamax = true }
        _options = State(initialValue: opts)
        if let i = opponentIndex, i < pool.count {
            _opponent = State(initialValue: .pool(i))
        } else if !pool.isEmpty {
            _opponent = State(initialValue: .pool(0))
        } else {
            // a sensible start: the same Pokémon as the own one, same level
            let m = member ?? team.sortedMembers.first
            _opponent = State(initialValue: .free(pokemonId: m?.pokemonId ?? 25, level: m?.level ?? 50, set: 0))
        }
    }

    private var member: TeamMember? {
        team.sortedMembers.first { $0.uuid == memberId } ?? team.sortedMembers.first
    }

    /// Story set plus the competitive sets of the free opponent.
    private func sets(for pokemonId: Int, level: Int) -> [(title: String, entry: MovesetEntry?)] {
        var list: [(String, MovesetEntry?)] = []
        if let story = Movesets.shared.story(for: pokemonId, game: game, level: level) {
            list.append((L("Story", "Story"), story))
        }
        for c in Movesets.shared.competitive(for: pokemonId, game: game) where c.pokemonId == pokemonId {
            list.append((c.set.sourceTitle + (c.set.roleTitle.map { " · \($0)" } ?? ""), c.set))
        }
        if list.isEmpty { list.append((L("Keine Attacken bekannt", "No moves known"), nil)) }
        return list
    }

    private var defender: Combatant? {
        switch opponent {
        case .pool(let i):
            guard i < pool.count, var c = Combatant.trainer(pool[i], game: game) else { return nil }
            // a Gigantamax trainer Pokémon is shown in its G-Max form while dynamaxed
            if options.defenderDynamax, pool[i].gmax == true, let g = Dex.shared.gmaxForm(for: c.pokemonId, game: game) { c.pokemonId = g.id }
            return c
        case .free(let id, let level, let set):
            let list = sets(for: id, level: level)
            return Combatant.free(pokemonId: id, level: level, set: list[min(set, list.count - 1)].entry, game: game)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let member, let me = Combatant.member(member, game: game), let them = defender {
                        sides(me: me, them: them, myDyna: options.attackerDynamax, theirDyna: options.defenderDynamax)
                        if case .free(let id, let level, let set) = opponent {
                            freeOptions(id: id, level: level, set: set)
                        }
                        optionsCard
                        damageSection(title: L("Deine Attacken", "Your moves"), icon: "arrow.right.circle.fill",
                                      results: DamageCalc.results(attacker: me, defender: them, game: game, options: options),
                                      empty: L("\(member.displayName) hat keine Attacken eingetragen.", "\(member.displayName) has no moves entered."), mine: true)
                        let reverse = DamageOptions(weather: options.weather, critical: options.critical,
                                                    attackerDynamax: options.defenderDynamax, defenderDynamax: options.attackerDynamax)
                        damageSection(title: L("Attacken von \(them.name)", "\(them.name)'s moves"), icon: "arrow.left.circle.fill",
                                      results: DamageCalc.results(attacker: them, defender: me, game: game, options: reverse),
                                      empty: L("Die Attacken dieses Pokémon sind nicht bekannt.", "This Pokémon's moves aren't known."), mine: false)
                        speedLine(me: me, them: them)
                        Text(L("Werte der Gegner im Story-Modus: keine EVs, mittlere DVs/IVs, neutrales Wesen – im Spiel weichen sie leicht ab. Schaden ohne Items/Fähigkeiten-Sonderfälle, Brand oder Doppelkampf-Abzug.",
                               "Opponent stats in story mode: no EVs, average IVs, neutral nature – in the game they differ slightly. Damage without special item/ability cases, burn or the doubles spread reduction."))
                            .font(.caption).foregroundStyle(.tertiary)
                    } else {
                        ContentUnavailableView(L("Kein Pokémon", "No Pokémon"), systemImage: "questionmark")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L("Schadensrechner", "Damage calculator"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Fertig", "Done")) { dismiss() }
                }
            }
            .sheet(isPresented: $showSpeciesPicker) {
                OptionPicker(title: L("Gegner wählen", "Choose opponent"), options: PickerOptions.pokemon(game: game), selected: nil) { id in
                    guard let id else { return }
                    let level: Int = {
                        if case .free(_, let l, _) = opponent { return l }
                        if case .pool(let i) = opponent, i < pool.count { return pool[i].l }
                        return member?.level ?? 50
                    }()
                    opponent = .free(pokemonId: id, level: level, set: 0)
                }
            }
        }
    }

    // MARK: Sides

    private func sides(me: Combatant, them: Combatant, myDyna: Bool, theirDyna: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Menu {
                Picker(selection: Binding(get: { member?.uuid }, set: { memberId = $0 })) {
                    ForEach(team.sortedMembers) { m in
                        Text("\(m.displayName) · Lv. \(m.level)").tag(Optional(m.uuid))
                    }
                } label: { EmptyView() }
                .pickerStyle(.inline)
            } label: {
                sideColumn(me, caption: L("Dein Pokémon", "Your Pokémon"), dynamax: myDyna)
            }
            .buttonStyle(.plain)

            Text("VS")
                .font(.headline.weight(.black))
                .foregroundStyle(.secondary)
                .padding(.top, 60)

            Menu {
                if !pool.isEmpty {
                    Section(poolTitle ?? L("Gegner", "Opponent")) {
                        ForEach(Array(pool.enumerated()), id: \.offset) { i, p in
                            Button("\(Dex.shared.pokemon(p.p)?.name ?? "?") · Lv. \(p.l)") {
                                opponent = .pool(i)
                                if game.hasDynamax { options.defenderDynamax = p.gmax == true }
                            }
                        }
                    }
                }
                Button { showSpeciesPicker = true } label: {
                    Label(L("Anderes Pokémon …", "Other Pokémon …"), systemImage: "magnifyingglass")
                }
            } label: {
                sideColumn(them, caption: L("Gegner", "Opponent"), dynamax: theirDyna)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    private func sideColumn(_ c: Combatant, caption: String, dynamax: Bool) -> some View {
        VStack(spacing: 4) {
            Text(caption).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ZStack(alignment: .bottom) {
                BattlePlatform(colors: c.types.map { TypeColor.color($0) })
                    .frame(width: 110, height: 32)
                    .padding(.bottom, 2)
                AnimatedPokemonSprite(pokemonId: c.pokemonId, shiny: c.shiny, grounded: true)
                    .frame(width: 96, height: 96)
                    .padding(.bottom, 16)
            }
            .frame(height: 116)
            HStack(spacing: 4) {
                Text(c.name).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
            }
            Text(L("Lv. \(c.level) · \(c.stats[0] * (dynamax ? 2 : 1)) KP", "Lv. \(c.level) · \(c.stats[0] * (dynamax ? 2 : 1)) HP"))
                .font(.caption.monospacedDigit()).foregroundStyle(dynamax ? Color.red : Color.secondary)
            HStack(spacing: 3) { ForEach(c.types, id: \.self) { TypeBadge(typeId: $0, small: true) } }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func freeOptions(id: Int, level: Int, set: Int) -> some View {
        let list = sets(for: id, level: level)
        return VStack(spacing: 10) {
            AppStepper(value: Binding(get: { level }, set: { opponent = .free(pokemonId: id, level: min(max($0, 1), 100), set: set) }), in: 1...100) {
                HStack {
                    Text(L("Level des Gegners", "Opponent level"))
                    Spacer()
                    Text(verbatim: "\(level)").font(.body.weight(.semibold).monospacedDigit())
                }
            }
            Divider()
            HStack(spacing: 12) {
                Text(L("Attacken", "Moves"))
                Spacer(minLength: 4)
                Menu {
                    Picker(selection: Binding(get: { min(set, list.count - 1) }, set: { opponent = .free(pokemonId: id, level: level, set: $0) })) {
                        ForEach(Array(list.enumerated()), id: \.offset) { i, s in Text(s.title).tag(i) }
                    } label: { EmptyView() }
                    .pickerStyle(.inline)
                } label: {
                    CompactMenuLabel(text: list[min(set, list.count - 1)].title)
                }
            }
        }
        .padding(14)
        .card()
    }

    private var optionsCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Label(L("Wetter", "Weather"), systemImage: options.weather.icon)
                Spacer(minLength: 4)
                Menu {
                    Picker(selection: $options.weather) {
                        ForEach(Weather.allCases) { w in Label(w.title, systemImage: w.icon).tag(w) }
                    } label: { EmptyView() }
                    .pickerStyle(.inline)
                } label: {
                    CompactMenuLabel(text: options.weather.title)
                }
            }
            Divider()
            Toggle(isOn: $options.critical) { Label(L("Volltreffer", "Critical hit"), systemImage: "scope") }
            if game.hasDynamax {
                Divider()
                Toggle(isOn: $options.attackerDynamax) { Label(L("Du dynamaxt", "You Dynamax"), systemImage: "arrow.up.left.and.arrow.down.right") }
                Toggle(isOn: $options.defenderDynamax) { Label(L("Gegner dynamaxt", "Opponent Dynamaxes"), systemImage: "arrow.up.left.and.arrow.down.right") }
            }
            Divider()
            boostRow(L("Dein Angriff", "Your attack"), value: $options.attackBoost)
            boostRow(L("Verteidigung des Gegners", "Opponent's defense"), value: $options.defenseBoost)
        }
        .padding(14)
        .card()
    }

    private func boostRow(_ title: String, value: Binding<Int>) -> some View {
        AppStepper(value: value, in: -6...6) {
            HStack {
                Text(title)
                Spacer()
                Text(verbatim: value.wrappedValue > 0 ? "+\(value.wrappedValue)" : "\(value.wrappedValue)")
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(value.wrappedValue == 0 ? .secondary : (value.wrappedValue > 0 ? Color.green : Color.red))
            }
        }
    }

    // MARK: Results

    private func damageSection(title: String, icon: String, results: [DamageResult], empty: String, mine: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.title3.weight(.bold))
            if results.isEmpty {
                Text(empty).font(.subheadline).foregroundStyle(.secondary)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.offset) { i, r in
                        if i > 0 { Divider().padding(.leading, 14) }
                        DamageRow(result: r, mine: mine, maxMove: mine ? options.attackerDynamax : options.defenderDynamax)
                    }
                }
                .card()
            }
        }
    }

    private func speedLine(me: Combatant, them: Combatant) -> some View {
        let mine = me.stats[5], theirs = them.stats[5]
        let text: String = mine > theirs
            ? L("Du bist schneller (\(mine) gegen \(theirs) Init.)", "You are faster (\(mine) vs \(theirs) Speed)")
            : mine < theirs
                ? L("\(them.name) ist schneller (\(theirs) gegen \(mine) Init.)", "\(them.name) is faster (\(theirs) vs \(mine) Speed)")
                : L("Gleich schnell (\(mine) Init.) – Zufall entscheidet", "Same Speed (\(mine)) – random")
        return Label(text, systemImage: "hare.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(mine > theirs ? Color.green : mine < theirs ? Color.orange : Color.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
    }
}

/// One move: damage range in % with a bar (in the move's type colour) and the number of hits.
struct DamageRow: View {
    let result: DamageResult
    /// own attack or the opponent's – decides how the number of hits is worded and coloured
    var mine = true
    var maxMove = false

    var body: some View {
        let m = result.move
        let color = TypeColor.color(m.t)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(m.name).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
                    if maxMove && result.note == nil {
                        Text("MAX").font(.caption2.weight(.heavy)).foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(color.opacity(0.16), in: Capsule())
                if result.note == nil, result.effectiveness != 1 {
                    Text(effectivenessText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(result.effectiveness > 1 ? Color.green : Color.orange)
                }
                Spacer(minLength: 4)
                if result.note == nil {
                    Text(verbatim: "\(percent(result.minPercent))–\(percent(result.maxPercent)) %")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                }
            }
            if let note = result.note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            } else {
                // HP bar in the type colour: solid = sure damage, light = random range
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.tertiarySystemFill))
                        Capsule().fill(color.opacity(0.35)).frame(width: w * min(result.maxPercent, 1))
                        Capsule().fill(color.gradient).frame(width: w * min(result.minPercent, 1))
                    }
                }
                .frame(height: 8)
                HStack {
                    if let hits = result.hitsText {
                        Text(verdict.map { "\($0) · \(hits)" } ?? hits)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(hitsColor)
                    }
                    Spacer()
                    Text(verbatim: "\(result.min)–\(result.max) / \(result.defenderHP)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
    }

    /// fewest hits needed for a K.O.
    private var hits: Int {
        result.max > 0 ? Int((Double(result.defenderHP) / Double(result.max)).rounded(.up)) : 99
    }

    /// Own attack: few hits = good. Opponent's attack: few hits = dangerous.
    private var hitsColor: Color {
        switch hits {
        case ...1: return mine ? .green : .red
        case 2: return mine ? .green : .orange
        case 3...4: return .orange
        default: return .secondary
        }
    }

    private var verdict: String? {
        guard !mine else { return nil }
        switch hits {
        case ...1: return L("Gefährlich", "Dangerous")
        case 2: return L("Stark", "Strong")
        case 3...4: return L("Mittel", "Medium")
        default: return L("Harmlos", "Harmless")
        }
    }

    private var effectivenessText: String {
        let e = result.effectiveness
        let x = e == 0.25 ? "¼" : e == 0.5 ? "½" : e == 4 ? "4" : e == 2 ? "2" : String(format: "%.1f", e)
        return "×\(x)"
    }

    private func percent(_ v: Double) -> String {
        String(format: "%.0f", v * 100)
    }
}

/// Menu label that stays on one line inside its row.
struct CompactMenuLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Text(text).lineLimit(1).truncationMode(.tail)
            Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.tint)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
        .frame(maxWidth: 200, alignment: .trailing)
        .fixedSize(horizontal: false, vertical: true)
    }
}
