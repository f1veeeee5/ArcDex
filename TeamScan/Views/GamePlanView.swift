import SwiftUI

/// "Game plan" card in the team overview: create with AI, sections to fold open and closed.
struct GamePlanView: View {
    @Bindable var team: Team
    @State private var loading = false
    @State private var error: String?
    @State private var open: Set<String> = ["summary"]

    var body: some View {
        let plan = team.gamePlan
        let engine = GamePlanner.engine
        VStack(alignment: .leading, spacing: 12) {
            if loading {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Spielplan wird geschrieben …", "Writing game plan …")).font(.subheadline.weight(.semibold))
                        Text(L("mit \(engine.title) · \(team.battleFormat.title)", "with \(engine.title) · \(team.battleFormat.title)")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .card()
            } else if let plan {
                if plan.signature != team.planSignature {
                    Label(L("Das Team hat sich geändert – der Plan passt vielleicht nicht mehr.", "The team changed – the plan may be outdated."),
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                VStack(spacing: 0) {
                    section("summary", L("Überblick", "Overview"), icon: "text.alignleft", color: .indigo) { BulletList(points: plan.summary, color: .indigo) }
                    Divider().padding(.leading, 52)
                    section("lead", L("Lead – wer startet", "Lead – who starts"), icon: "flag.fill", color: .green) { BulletList(points: plan.lead, color: .green) }
                    Divider().padding(.leading, 52)
                    section("win", L("Siegbedingung", "Win condition"), icon: "trophy.fill", color: .yellow) { BulletList(points: plan.winCondition, color: .yellow) }
                    Divider().padding(.leading, 52)
                    section("threats", L("Gefahren & Konter", "Threats & answers"), icon: "exclamationmark.shield.fill", color: .red) { BulletList(points: plan.threats, color: .red) }
                    if !plan.roles.isEmpty {
                        Divider().padding(.leading, 52)
                        section("roles", L("Rollen", "Roles"), icon: "person.3.fill", color: .blue) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(plan.roles) { role in
                                    HStack(alignment: .top, spacing: 10) {
                                        if let m = member(named: role.pokemon) {
                                            PokemonSprite(pokemonId: m.battleForm(in: team.game)?.id ?? m.pokemonId, shiny: m.shiny)
                                                .frame(width: 34, height: 34)
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(role.pokemon).font(.body.weight(.semibold))
                                            BulletList(points: role.points, color: .blue)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .card()
                HStack {
                    Label(L("KI-Vorschlag · \(engineName(plan.engine))", "AI suggestion · \(engineName(plan.engine))"), systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { generate() } label: {
                        Label(L("Neu erstellen", "Recreate"), systemImage: "arrow.clockwise").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .disabled(isUnavailable(engine))
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Lass dir erklären, wie du mit diesem Team spielst: wer startet, wie du gewinnst und worauf du aufpassen musst.",
                           "Get an explanation of how to play this team: who leads, how you win and what to watch out for."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if case .none(let reason) = engine {
                        Label(reason, systemImage: "info.circle").font(.footnote).foregroundStyle(.orange)
                    } else {
                        Button { generate() } label: {
                            Label(L("Spielplan erstellen", "Create game plan"), systemImage: "sparkles")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(team.members.isEmpty)
                        Text(L("mit \(engine.title)", "with \(engine.title)")).font(.caption).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
                .card()
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func isUnavailable(_ engine: GamePlanner.Engine) -> Bool {
        if case .none = engine { return true }
        return false
    }

    private func engineName(_ id: String) -> String {
        if id == "apple" { return "Apple Intelligence" }
        return ClaudeModel(rawValue: id)?.title ?? "Claude"
    }

    private func member(named name: String) -> TeamMember? {
        let n = name.lowercased()
        return team.sortedMembers.first { m in
            m.displayName.lowercased() == n || m.species?.name.lowercased() == n || n.contains(m.displayName.lowercased())
        }
    }

    private func generate() {
        error = nil
        loading = true
        Task {
            do {
                let plan = try await GamePlanner.makePlan(for: team)
                withAnimation(.snappy) {
                    team.gamePlan = plan
                    open = ["summary", "lead", "win", "threats", "roles"]
                }
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            loading = false
        }
    }

    private func section<Content: View>(_ key: String, _ title: String, icon: String, color: Color,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) {
                    if open.contains(key) { open.remove(key) } else { open.insert(key) }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(color)
                        .frame(width: 30, height: 30)
                        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(open.contains(key) ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open.contains(key) {
                content()
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 42)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
    }
}

/// Settings: Claude key and model for the game plans.
struct AISettingsSection: View {
    @AppStorage("claudeModel") private var model = ClaudeModel.sonnet.rawValue
    @State private var key = ""
    @State private var hasKey = APIKeyStore.key != nil
    @State private var editing = false

    var body: some View {
        Section {
            if hasKey && !editing {
                LabeledContent(L("Claude-Schlüssel", "Claude key"), value: L("gespeichert", "saved"))
                Button(L("Schlüssel ändern", "Change key")) { key = ""; editing = true }
                Button(L("Schlüssel entfernen", "Remove key"), role: .destructive) {
                    APIKeyStore.save("")
                    hasKey = false
                }
            } else {
                SecureField(L("Claude-API-Schlüssel (sk-ant-…)", "Claude API key (sk-ant-…)"), text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(L("Sichern", "Save")) {
                    APIKeyStore.save(key)
                    hasKey = APIKeyStore.key != nil
                    editing = false
                    key = ""
                }
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Picker(L("Claude-Modell", "Claude model"), selection: $model) {
                ForEach(ClaudeModel.allCases) { m in
                    Text("\(m.title) – \(m.hint)").tag(m.rawValue)
                }
            }
            LabeledContent(L("Wird benutzt", "In use")) {
                Text({
                    switch GamePlanner.engine {
                    case .none: return L("keine KI verfügbar", "no AI available")
                    case let e: return e.title
                    }
                }())
            }
        } header: {
            Text(L("KI-Spielpläne", "AI game plans"))
        } footer: {
            Text(L("Ohne Schlüssel schreibt Apple Intelligence die Pläne – kostenlos und direkt auf dem iPhone. Mit einem eigenen Claude-Schlüssel (Claude Console, separat vom Claude-Abo) werden die Pläne genauer; jeder Plan kostet dann einen Bruchteil eines Cents bis ca. 1 Cent. Der Schlüssel liegt im Schlüsselbund des iPhones.",
                   "Without a key Apple Intelligence writes the plans – free and on the iPhone. With your own Claude key (Claude Console, separate from the Claude subscription) the plans are more precise; each plan then costs a fraction of a cent up to about 1 cent. The key is kept in the iPhone's keychain."))
        }
    }
}


/// Short bullet points; **bold** (Markdown) for Pokémon and moves.
struct BulletList: View {
    let points: [String]
    var color: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(color).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                    Text((try? AttributedString(markdown: point)) ?? AttributedString(point))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
