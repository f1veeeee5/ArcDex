import SwiftUI
import SwiftData

// MARK: - Hunt screen

struct HuntView: View {
    @Bindable var hunt: ShinyHunt
    @Binding var path: NavigationPath
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showSettings = false
    @State private var showEditCount = false
    @State private var countText = ""
    @State private var showPhasePicker = false
    @State private var confirmFound = false
    @State private var confirmDelete = false
    @State private var celebrate = false
    @State private var liveActive = false
    @State private var liveError: String?

    private var game: Game { hunt.game }
    private var odds: ShinyOdds { hunt.odds }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                if hunt.isFound {
                    foundBanner
                    ShinyProofCard(hunt: hunt)
                } else {
                    counter
                }
                statsCard
                if !hunt.isFound { timerCard }
                if !hunt.isFound { liveActivityCard }
                if !hunt.phases.isEmpty { phasesCard }
                settingsSummary
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
            // exactly as wide as the screen – the page only scrolls up and down
            .containerRelativeFrame(.horizontal)
            .clipped()
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(hunt.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showSettings = true } label: { Label(L("Hunt bearbeiten", "Edit hunt"), systemImage: "slider.horizontal.3") }
                    Button { countText = "\(hunt.count)"; showEditCount = true } label: { Label(L("Zähler setzen", "Set counter"), systemImage: "number") }
                    if !hunt.isFound {
                        Button { showPhasePicker = true } label: { Label(L("Anderes Shiny (Phase)", "Other shiny (phase)"), systemImage: "arrow.triangle.branch") }
                    } else {
                        Button { hunt.foundAt = nil } label: { Label(L("Weiter-Hunten", "Resume hunt"), systemImage: "arrow.uturn.backward") }
                    }
                    Button { path.append(DexRoute(pokemonId: hunt.pokemonId, game: game)) } label: { Label("Pokédex", systemImage: "book.closed") }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label(L("Hunt löschen", "Delete hunt"), systemImage: "trash") }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .sensoryFeedback(.increase, trigger: hunt.count)
        .sensoryFeedback(.success, trigger: celebrate)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            liveActive = HuntActivityManager.isRunning(hunt)
            HuntActivityManager.markUsed(hunt)
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .task(id: hunt.pokemonId) { await HuntActivityManager.prepareSprite(for: hunt) }
        .onChange(of: hunt.count) { HuntActivityManager.update(hunt) }
        .onChange(of: hunt.timerStartedAt) { HuntActivityManager.update(hunt) }
        .sheet(isPresented: $showSettings) {
            HuntSettingsSheet(game: game, hunt: hunt) { draft in
                draft.apply(to: hunt)
                hunt.updatedAt = Date()
                HuntActivityManager.restartIfNeeded(hunt)
            }
        }
        .sheet(isPresented: $showPhasePicker) {
            OptionPicker(title: L("Welches Shiny kam?", "Which shiny appeared?"), options: PickerOptions.pokemon(game: game), selected: nil, allowNone: true) { id in
                var list = hunt.phases
                list.append(HuntPhase(count: hunt.count, pokemonId: id))
                hunt.phases = list
                hunt.updatedAt = Date()
            }
        }
        .alert(L("Zähler setzen", "Set counter"), isPresented: $showEditCount) {
            TextField("0", text: $countText).keyboardType(.numberPad)
            Button(L("Sichern", "Save")) {
                if let n = Int(countText.filter(\.isNumber)) { hunt.count = n; hunt.updatedAt = Date() }
            }
            Button(L("Abbrechen", "Cancel"), role: .cancel) {}
        }
        .confirmationDialog(L("Shiny gefunden?", "Found the shiny?"), isPresented: $confirmFound, titleVisibility: .visible) {
            Button(L("Ja, \(hunt.name) ist shiny! ✨", "Yes, \(hunt.name) is shiny! ✨")) {
                withAnimation(.spring(duration: 0.5)) { hunt.markFound() }
                celebrate.toggle()
                HuntActivityManager.end(hunt: hunt)
                liveActive = false
            }
        } message: {
            Text(L("Der Hunt wird nach \(hunt.count) \(hunt.method.unit) abgeschlossen.", "The hunt ends after \(hunt.count) \(hunt.method.unit.lowercased())."))
        }
        .guardedDelete($confirmDelete, area: .hunts, doubleConfirm: true,
                       title: hunt.isFound ? L("Gefundenes Shiny löschen?", "Delete found shiny?") : L("Hunt löschen?", "Delete hunt?"),
                       message: L("\(hunt.name) · \(hunt.count) \(hunt.method.unit)", "\(hunt.name) · \(hunt.count) \(hunt.method.unit.lowercased())")) {
            HuntActivityManager.end(hunt: hunt)
            context.delete(hunt)
            dismiss()
        }
    }

    // MARK: Parts

    private var hero: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color.yellow.opacity(hunt.isFound ? 0.45 : 0.22), .clear], center: .center, startRadius: 10, endRadius: 120))
                    .frame(width: 220, height: 220)
                AnimatedPokemonSprite(pokemonId: hunt.pokemonId, shiny: true)
                    .frame(width: 150, height: 150)
                    .scaleEffect(celebrate ? 1.08 : 1)
                    .animation(.spring(duration: 0.4, bounce: 0.5), value: celebrate)
                ShinyBadge().font(.title).offset(x: 70, y: -62)
            }
            .frame(height: 190)
            Text(hunt.name).font(.largeTitle.weight(.bold))
            HStack(spacing: 6) {
                Text(game.compactTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(game.gradient, in: Capsule())
                Label(hunt.method.title, systemImage: hunt.method.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private var counter: some View {
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                Text("\(hunt.count)")
                    .font(.system(size: 72, weight: .heavy, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText(value: Double(hunt.count)))
                    .animation(.snappy, value: hunt.count)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(hunt.phases.isEmpty ? hunt.method.unit
                     : L("\(hunt.method.unit) · \(hunt.countInPhase) in Phase \(hunt.phases.count + 1)",
                         "\(hunt.method.unit) · \(hunt.countInPhase) in phase \(hunt.phases.count + 1)"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .onTapGesture { countText = "\(hunt.count)"; showEditCount = true }

            HStack(spacing: 12) {
                Button {
                    hunt.add(-1)
                } label: {
                    Image(systemName: "minus")
                        .font(.title2.weight(.bold))
                        .frame(width: 64, height: 64)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(hunt.count == 0)
                .accessibilityLabel(L("Eins weniger", "Minus one"))

                Button {
                    hunt.add(hunt.step)
                    if hunt.timerStartedAt == nil && hunt.elapsed == 0 { hunt.startTimer() }
                } label: {
                    Label("+\(hunt.step)", systemImage: "plus")
                        .labelStyle(.titleOnly)
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 84)
                        .background(game.gradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .shadow(color: game.colors.first?.opacity(0.35) ?? .clear, radius: 12, y: 6)
                }
                .buttonStyle(CounterButtonStyle())
                .accessibilityLabel(L("Plus \(hunt.step)", "Plus \(hunt.step)"))
            }

            Button {
                confirmFound = true
            } label: {
                Label(L("Shiny gefunden!", "Found it!"), systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.appSecondary)
            .tint(.orange)
            .controlSize(.large)
        }
        .padding(16)
        .card()
    }

    private var foundBanner: some View {
        VStack(spacing: 8) {
            Label(L("Gefunden!", "Found!"), systemImage: "sparkles")
                .font(.title2.weight(.heavy))
                .foregroundStyle(.orange)
            Text(L("Nach \(hunt.count) \(hunt.method.unit)", "After \(hunt.count) \(hunt.method.unit.lowercased())"))
                .font(.headline)
            if let date = hunt.foundAt {
                Text(date, format: .dateTime.day().month(.wide).year())
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .card()
    }

    private var statsCard: some View {
        let p = odds.cumulative(after: hunt.count)
        let current = odds.probability(at: hunt.count)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                statBlock(L("Chance pro Versuch", "Odds per try"), odds.label(at: hunt.count),
                          hint: odds.method.isChain ? L("steigt mit der Kette", "grows with the chain") : nil)
                Spacer()
                statBlock(L("Schon gehabt hätten", "Should have had it"), percent(p), alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: min(p, 1))
                    .tint(LinearGradient(colors: [.yellow, .orange, .pink], startPoint: .leading, endPoint: .trailing))
                Text(luckText(p: p, perTry: current))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .card()
    }

    private func statBlock(_ title: String, _ value: String, hint: String? = nil, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.bold).monospacedDigit())
            if let hint { Text(hint).font(.caption2).foregroundStyle(.tertiary) }
        }
    }

    private func percent(_ p: Double) -> String {
        if p > 0 && p < 0.001 { return "< 0,1 %" }
        return p.formatted(.percent.precision(.fractionLength(p < 0.1 ? 1 : 0)).locale(Lang.current.locale))
    }

    private func luckText(p: Double, perTry: Double) -> String {
        let average = Int((1 / perTry).rounded())
        if hunt.count == 0 {
            return L("Im Schnitt braucht man etwa \(average) Versuche – aber jeder Versuch ist ein neuer Würfelwurf.",
                     "On average it takes about \(average) tries – but every try is a fresh roll.")
        }
        let base = L("Mit \(hunt.count) Versuchen hätte man das Shiny mit \(percent(p)) Wahrscheinlichkeit schon gehabt.",
                     "After \(hunt.count) tries you would have found it with a \(percent(p)) chance.")
        if p >= 0.9 { return base + L(" Du hast echt Pech – dranbleiben! 💪", " Rough luck – keep going! 💪") }
        if p >= 0.5 { return base + L(" Du bist über dem Durchschnitt.", " You are past the average.") }
        return base
    }

    private var timerCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "timer").font(.title3).foregroundStyle(.secondary)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(HuntTime.format(hunt.totalTime(at: ctx.date)))
                    .font(.title3.weight(.semibold).monospacedDigit())
            }
            Spacer()
            if hunt.totalTime() > 0 && !hunt.timerRunning {
                Button { hunt.elapsed = 0 } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.appSecondary)
                    .accessibilityLabel(L("Timer zurücksetzen", "Reset timer"))
            }
            Button {
                withAnimation(.snappy) { hunt.timerRunning ? hunt.stopTimer() : hunt.startTimer() }
            } label: {
                Label(hunt.timerRunning ? L("Pause", "Pause") : L("Start", "Start"),
                      systemImage: hunt.timerRunning ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.appPrimary)
            .tint(hunt.timerRunning ? .orange : .appAccent)
        }
        .padding(16)
        .card()
    }

    private var liveActivityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { liveActive }, set: { on in
                if on {
                    if let error = HuntActivityManager.start(hunt) {
                        liveError = error
                        liveActive = false
                    } else {
                        liveActive = true
                    }
                } else {
                    HuntActivityManager.end(hunt: hunt)
                    liveActive = false
                }
            })) {
                Label(L("Auf dem Sperrbildschirm zählen", "Count on the Lock Screen"), systemImage: "lock.iphone")
                    .font(.subheadline.weight(.semibold))
            }
            Text(liveError ?? L("Zeigt den Zähler mit +\(hunt.step)-Knopf auf dem Sperrbildschirm und in der Dynamic Island.",
                                "Shows the counter with a +\(hunt.step) button on the Lock Screen and in the Dynamic Island."))
                .font(.footnote)
                .foregroundStyle(liveError == nil ? Color.secondary : Color.red)
            Divider().padding(.vertical, 2)
            Label {
                Text(L("Action-Button: Einstellungen → Action-Button → Kurzbefehl → ArcDex → „Shiny +1“. Gezählt wird der zuletzt geöffnete Hunt.",
                       "Action Button: Settings → Action Button → Shortcut → ArcDex → “Shiny +1”. It counts the hunt you opened last."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "button.vertical.left.press.fill").foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .card()
    }

    private var phasesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("Phasen", "Phases"), systemImage: "arrow.triangle.branch").font(.headline)
            ForEach(Array(hunt.phases.enumerated()), id: \.element.id) { i, phase in
                HStack(spacing: 10) {
                    if let id = phase.pokemonId {
                        PokemonSprite(pokemonId: id, shiny: true).frame(width: 40, height: 40)
                    } else {
                        Image(systemName: "sparkles").frame(width: 40, height: 40).foregroundStyle(.yellow)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(phase.pokemonId.flatMap { Dex.shared.pokemon($0)?.name } ?? L("Anderes Shiny", "Other shiny"))
                            .font(.subheadline.weight(.semibold))
                        Text(L("Phase \(i + 1) · bei \(phase.count)", "Phase \(i + 1) · at \(phase.count)"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(phase.date, format: .dateTime.day().month(.abbreviated))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        var list = hunt.phases
                        list.removeAll { $0.id == phase.id }
                        hunt.phases = list
                    } label: { Label(L("Entfernen", "Remove"), systemImage: "trash") }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var settingsSummary: some View {
        Button { showSettings = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(L("Methode & Boni", "Method & bonuses"), systemImage: "slider.horizontal.3").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                FlowLayout(spacing: 6) {
                    ForEach(HuntDraft(hunt: hunt).bonusLabels(game: game), id: \.self) { text in
                        Text(text)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                }
                Text(L("Gestartet am \(hunt.startedAt.formatted(.dateTime.day().month(.wide).year()))",
                       "Started \(hunt.startedAt.formatted(.dateTime.day().month(.wide).year()))"))
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .buttonStyle(.plain)
    }
}

struct CounterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.5), value: configuration.isPressed)
    }
}

enum HuntTime {
    static func format(_ t: TimeInterval) -> String {
        let s = Int(t)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }
}

// MARK: - Settings (new / edit)

/// Editable copy of the hunt settings.
struct HuntDraft {
    var pokemonId: Int?
    var method: HuntMethod = .encounter
    var shinyCharm = false
    var sparklingPower = 0
    var research = 0
    var outbreakTier = 0
    var lure = false
    var customOdds = 4096
    var step = 1
    var startCount = 0

    init() {}

    init(hunt: ShinyHunt) {
        pokemonId = hunt.pokemonId
        method = hunt.method
        shinyCharm = hunt.shinyCharm
        sparklingPower = hunt.sparklingPower
        research = hunt.research
        outbreakTier = hunt.outbreakTier
        lure = hunt.lure
        customOdds = hunt.customOdds
        step = hunt.step
        startCount = hunt.count
    }

    func odds(game: Game) -> ShinyOdds {
        ShinyOdds(game: game, method: method, charm: shinyCharm, sparklingPower: sparklingPower, research: research,
                  outbreakTier: outbreakTier, lure: lure, customOdds: customOdds)
    }

    func apply(to hunt: ShinyHunt) {
        if let pokemonId { hunt.pokemonId = pokemonId }
        hunt.method = method
        hunt.shinyCharm = shinyCharm
        hunt.sparklingPower = sparklingPower
        hunt.research = research
        hunt.outbreakTier = outbreakTier
        hunt.lure = lure
        hunt.customOdds = max(1, customOdds)
        hunt.step = max(1, step)
        hunt.count = max(0, startCount)
    }

    /// Short chips like "Schillerpin", "Funkelkraft Lv. 3".
    func bonusLabels(game: Game) -> [String] {
        var list = [method.title]
        if method == .custom {
            list.append("1/\(customOdds)")
        } else {
            if shinyCharm && game.hasShinyCharm { list.append(L("Schillerpin", "Shiny Charm")) }
            if game.hasSparklingPower && sparklingPower > 0 { list.append(L("Funkelkraft Lv. \(sparklingPower)", "Sparkling Power Lv. \(sparklingPower)")) }
            if game == .pla && research > 0 { list.append(research == 2 ? L("Forschung perfekt", "Research perfect") : L("Forschungslevel 10", "Research level 10")) }
            if method == .outbreak && outbreakTier > 0 { list.append(outbreakTier == 2 ? L("60+ besiegt", "60+ defeated") : L("30+ besiegt", "30+ defeated")) }
            if method == .catchCombo && lure { list.append(L("Lockparfüm", "Lure")) }
        }
        if step > 1 { list.append("+\(step) " + L("pro Tipp", "per tap")) }
        return list
    }
}

struct HuntSettingsSheet: View {
    let game: Game
    var hunt: ShinyHunt?
    var onSave: (HuntDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = HuntDraft()
    @State private var loaded = false
    @State private var showPicker = false
    @State private var oddsText = "4096"
    @State private var countText = "0"

    var body: some View {
        let odds = draft.odds(game: game)
        NavigationStack {
            Form {
                Section(L("Pokémon", "Pokémon")) {
                    Button { showPicker = true } label: {
                        HStack(spacing: 12) {
                            if let id = draft.pokemonId {
                                PokemonSprite(pokemonId: id, shiny: true).frame(width: 52, height: 52)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Dex.shared.pokemon(id)?.name ?? "?").font(.headline).foregroundStyle(.primary)
                                    Text(L("Tippen zum Ändern", "Tap to change")).font(.caption).foregroundStyle(.secondary)
                                }
                            } else {
                                Image(systemName: "plus.circle.fill").font(.title2)
                                Text(L("Pokémon wählen", "Choose Pokémon"))
                            }
                            Spacer()
                        }
                    }
                }

                Section {
                    Picker(L("Methode", "Method"), selection: $draft.method) {
                        ForEach(HuntMethod.available(in: game)) { m in
                            Label(m.title, systemImage: m.icon).tag(m)
                        }
                    }
                    if draft.method == .custom {
                        HStack {
                            Text(L("Chance 1 zu", "Odds 1 in"))
                            TextField("4096", text: $oddsText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: oddsText) { _, new in draft.customOdds = max(1, Int(new.filter(\.isNumber)) ?? 1) }
                        }
                    } else {
                        if game.hasShinyCharm {
                            Toggle(L("Schillerpin", "Shiny Charm"), isOn: $draft.shinyCharm)
                        }
                        if game.hasSparklingPower {
                            Picker(L("Funkelkraft", "Sparkling Power"), selection: $draft.sparklingPower) {
                                Text(L("Keine", "None")).tag(0)
                                ForEach(1...3, id: \.self) { Text("Lv. \($0)").tag($0) }
                            }
                        }
                        if game == .pla {
                            Picker(L("Pokédex-Forschung", "Pokédex research"), selection: $draft.research) {
                                Text(L("Unter Level 10", "Below level 10")).tag(0)
                                Text(L("Level 10", "Level 10")).tag(1)
                                Text(L("Perfekt", "Perfect")).tag(2)
                            }
                        }
                        if draft.method == .outbreak {
                            Picker(L("Im Ausbruch besiegt", "Defeated in outbreak"), selection: $draft.outbreakTier) {
                                Text("0–29").tag(0)
                                Text("30–59").tag(1)
                                Text("60+").tag(2)
                            }
                        }
                        if draft.method == .catchCombo {
                            Toggle(L("Lockparfüm aktiv", "Lure active"), isOn: $draft.lure)
                        }
                    }
                } header: {
                    Text(L("Methode & Boni", "Method & bonuses"))
                } footer: {
                    Text(methodFooter)
                }

                Section {
                    HStack {
                        Text(L("Chance", "Odds"))
                        Spacer()
                        Text(odds.method.isChain
                             ? L("\(odds.label(at: 0)) → \(odds.label(at: 31))", "\(odds.label(at: 0)) → \(odds.label(at: 31))")
                             : odds.label(at: draft.startCount))
                            .font(.headline.monospacedDigit())
                    }
                }

                Section {
                    AppStepper(L("Pro Tippen: +\(draft.step)", "Per tap: +\(draft.step)"), value: $draft.step, in: 1...10)
                    HStack {
                        Text(hunt == nil ? L("Startwert", "Start at") : L("Zählerstand", "Counter"))
                        TextField("0", text: $countText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: countText) { _, new in draft.startCount = Int(new.filter(\.isNumber)) ?? 0 }
                    }
                } footer: {
                    Text(L("+5 ist z. B. praktisch für Horden-Begegnungen. Den Startwert brauchst du nur, wenn du einen Hunt schon vorher begonnen hast.",
                           "+5 is handy for horde encounters. Set a start value only if you already started this hunt elsewhere."))
                }
            }
            .navigationTitle(hunt == nil ? L("Neuer Shiny-Hunt", "New shiny hunt") : L("Hunt bearbeiten", "Edit hunt"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(hunt == nil ? L("Starten", "Start") : L("Sichern", "Save")) {
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.pokemonId == nil)
                }
            }
            .sheet(isPresented: $showPicker) {
                OptionPicker(title: L("Pokémon wählen", "Choose Pokémon"), options: PickerOptions.pokemon(game: game), selected: draft.pokemonId) { id in
                    if let id { draft.pokemonId = id }
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let hunt {
                draft = HuntDraft(hunt: hunt)
            } else {
                // open the Pokémon list right away – after the sheet has finished appearing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showPicker = true }
            }
            oddsText = "\(draft.customOdds)"
            countText = "\(draft.startCount)"
        }
    }

    private var methodFooter: String {
        switch draft.method {
        case .masuda: return L("Eltern aus Spielen in verschiedenen Sprachen.", "Parents from games of different languages.")
        case .sos: return L("Die Chance steigt ab 11, 21 und 31 Rufen in Folge. Zähle die Kettenlänge.", "Odds rise at 11, 21 and 31 calls in a row. Count the chain length.")
        case .catchCombo: return L("Die Chance steigt ab einer Fang-Kombo von 11, 21 und 31.", "Odds rise at a catch combo of 11, 21 and 31.")
        case .outbreak: return L("Ab 30 bzw. 60 besiegten Pokémon im Ausbruch steigt die Chance.", "Odds rise after defeating 30 or 60 Pokémon in the outbreak.")
        case .dynamaxAdventure: return L("Feste Chance für das Legendäre am Ende: 1/300, mit Schillerpin 1/100.", "Fixed odds for the legendary at the end: 1/300, 1/100 with the Shiny Charm.")
        case .plaOutbreak, .plaMassiveOutbreak, .encounter, .softReset, .egg:
            return game == .pla ? L("Schillerpin gibt es erst ab Forschungslevel 10.", "The Shiny Charm needs research level 10.") : ""
        case .custom: return L("Für Methoden, die hier fehlen – trage die Chance selbst ein.", "For methods that are missing here – enter the odds yourself.")
        }
    }
}

// MARK: - Cards

/// Small card for the "active hunts" strip on the start page.
struct HuntMiniCard: View {
    @Bindable var hunt: ShinyHunt
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    PokemonSprite(pokemonId: hunt.pokemonId, shiny: true)
                        .frame(width: 56, height: 56)
                    Spacer(minLength: 0)
                    Text(hunt.game.shortTitle)
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(hunt.game.gradient, in: Capsule())
                }
                Text(hunt.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(hunt.count)")
                    .font(.title2.weight(.heavy).monospacedDigit())
                    .contentTransition(.numericText(value: Double(hunt.count)))
            }
            .padding(12)
            .frame(width: 150, alignment: .leading)
            .card()
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            Button {
                withAnimation(.snappy) { hunt.add(hunt.step) }
                HuntActivityManager.update(hunt)
                HuntActivityManager.markUsed(hunt)
            } label: {
                Image(systemName: "plus")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(hunt.game.gradient, in: Circle())
            }
            .buttonStyle(CounterButtonStyle())
            .padding(10)
            .accessibilityLabel(L("Plus \(hunt.step)", "Plus \(hunt.step)"))
        }
        .sensoryFeedback(.increase, trigger: hunt.count)
    }
}

/// Row card inside a save file.
struct HuntRowCard: View {
    @Bindable var hunt: ShinyHunt
    var onOpen: () -> Void

    var body: some View {
        let odds = hunt.odds
        Button(action: onOpen) {
            HStack(spacing: 12) {
                PokemonSprite(pokemonId: hunt.pokemonId, shiny: true)
                    .frame(width: 60, height: 60)
                    .background(Color(.tertiarySystemFill), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(hunt.name).font(.headline)
                    Label(hunt.method.title, systemImage: hunt.method.icon)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(odds.label(at: hunt.count)).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.orange)
                }
                Spacer(minLength: 4)
                Text("\(hunt.count)")
                    .font(.title.weight(.heavy).monospacedDigit())
                    .contentTransition(.numericText(value: Double(hunt.count)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.trailing, 50)
            }
            .padding(14)
            .card()
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            Button {
                withAnimation(.snappy) { hunt.add(hunt.step) }
                HuntActivityManager.update(hunt)
                HuntActivityManager.markUsed(hunt)
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(hunt.game.gradient, in: Circle())
            }
            .buttonStyle(CounterButtonStyle())
            .padding(.trailing, 14)
            .accessibilityLabel(L("Plus \(hunt.step)", "Plus \(hunt.step)"))
        }
        .sensoryFeedback(.increase, trigger: hunt.count)
    }
}

struct StartHuntCard: View {
    let game: Game
    var onStart: () -> Void

    var body: some View {
        Button(action: onStart) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Shiny-Hunt starten", "Start a shiny hunt")).font(.headline).foregroundStyle(.primary)
                    Text(L("Zähle Begegnungen und sieh deine Chancen in \(game.compactTitle).",
                           "Count encounters and see your odds in \(game.compactTitle)."))
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .card()
        }
        .buttonStyle(.plain)
    }
}

struct FoundShinyTile: View {
    let hunt: ShinyHunt

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                PokemonSprite(pokemonId: hunt.pokemonId, shiny: true)
                    .frame(width: 70, height: 70)
                ShinyBadge()
            }
            HStack(spacing: 3) {
                Text(hunt.name).font(.caption.weight(.semibold)).lineLimit(1)
                if hunt.proofFile != nil {
                    let state = ProofState(hunt: hunt)
                    Image(systemName: state.icon)
                        .font(.caption)
                        .foregroundStyle(state.color)
                        .accessibilityLabel(L("Fang-Beleg: \(state.label)", "Catch proof: \(state.label)"))
                }
            }
            Text("\(hunt.count) · \(hunt.foundAt?.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)) ?? "")")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .card()
    }
}
