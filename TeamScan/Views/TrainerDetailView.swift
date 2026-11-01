import SwiftUI
import SwiftData

/// A trainer of the game guide: way there, team and the match-up against an own team.
struct TrainerDetailView: View {
    let game: Game
    let trainerId: String

    @Query(sort: \Team.updatedAt, order: .reverse) private var allTeams: [Team]
    @State private var variant = 0
    @State private var teamId: UUID?

    private var trainer: GuideTrainer? { GuideData.shared.guide(for: game)?.trainer(trainerId) }

    /// Only teams of this game.
    private var teams: [Team] {
        allTeams.filter { $0.game == game && !$0.members.isEmpty }
    }

    private var selectedTeam: Team? {
        teams.first { $0.uuid == teamId } ?? teams.first
    }

    var body: some View {
        if let trainer {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(trainer)
                    if trainer.hint != nil || trainer.mission != nil {
                        infoCard(trainer)
                    }
                    teamSection(trainer)
                    matchupSection(trainer)
                    sources(trainer)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(trainer.name.text)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView(L("Nicht gefunden", "Not found"), systemImage: "questionmark")
        }
    }

    // MARK: Header

    private func header(_ t: GuideTrainer) -> some View {
        let color = t.type.map { TypeColor.color($0) } ?? Color.orange
        return VStack(alignment: .leading, spacing: 10) {
            if t.avatar != nil {
                ZStack(alignment: .bottom) {
                    BattlePlatform(colors: t.type.map { [TypeColor.color($0)] } ?? [.orange, .pink])
                        .frame(width: 170, height: 46)
                        .padding(.bottom, 6)
                    TrainerSprite(avatar: t.avatar)
                        .frame(width: 150, height: 150)
                        .padding(.bottom, 22)
                }
                .frame(maxWidth: .infinity)
            }
            HStack(spacing: 8) {
                Label(t.role.title, systemImage: t.role.icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                if let type = t.type { TypeBadge(typeId: type, small: true) }
                if let v = t.version {
                    Text(L("nur \(Game.versionTitle(v))", "\(Game.versionTitle(v)) only"))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
                if t.double {
                    Text(L("Doppelkampf", "Double battle"))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
            }
            Text(t.name.text).font(.largeTitle.weight(.bold))
            if t.name.de != t.name.en {
                Text(Lang.current == .de ? t.name.en : t.name.de).font(.subheadline).foregroundStyle(.secondary)
            }
            Label(t.location, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private func infoCard(_ t: GuideTrainer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let hint = t.hint {
                infoRow(icon: "figure.walk", color: .blue, title: L("Weg dorthin", "How to get there"), text: hint.text)
            }
            if let mission = t.mission {
                infoRow(icon: "flag.checkered", color: .purple, title: t.role == .gym ? L("Arena-Aufgabe", "Gym mission") : L("Kampf", "Battle"), text: mission.text)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func infoRow(icon: String, color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Team

    private func teamSection(_ t: GuideTrainer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("Team", "Team"), systemImage: "person.3.fill").font(.title3.weight(.bold))
            if t.teams.count > 1 {
                Picker("", selection: $variant) {
                    ForEach(Array(t.teams.enumerated()), id: \.offset) { i, team in
                        Text(team.label?.text ?? "\(i + 1)").tag(i)
                    }
                }
                .pickerStyle(.menu)
                .tint(.primary)
            }
            let team = t.teams[min(variant, t.teams.count - 1)].team
            VStack(spacing: 0) {
                ForEach(Array(team.enumerated()), id: \.offset) { i, p in
                    if i > 0 { Divider().padding(.leading, 70) }
                    NavigationLink(value: DexRoute(pokemonId: p.p, game: game)) {
                        OpponentRow(pokemon: p, game: game)
                    }
                    .buttonStyle(.plain)
                }
            }
            .card()
        }
    }

    // MARK: Match-up

    private func matchupSection(_ t: GuideTrainer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("Match-up", "Match-up"), systemImage: "scalemass.fill").font(.title3.weight(.bold))
            if teams.isEmpty {
                Text(L("Lege ein Team für \(game.title) an, um es mit diesem Trainer zu vergleichen.",
                       "Create a team for \(game.title) to compare it with this trainer."))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
            } else if let team = selectedTeam {
                Menu {
                    Picker(selection: Binding(get: { team.uuid }, set: { teamId = $0 })) {
                        ForEach(teams) { tm in
                            Text(tm.name.isEmpty ? L("Team", "Team") : tm.name).tag(tm.uuid)
                        }
                    } label: { EmptyView() }
                    .pickerStyle(.inline)
                } label: {
                    HStack(spacing: 6) {
                        ForEach(team.sortedMembers) { m in
                            PokemonSprite(pokemonId: m.battleForm(in: team.game)?.id ?? m.pokemonId, shiny: m.shiny)
                                .frame(width: 34, height: 34)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(team.name.isEmpty ? L("Team", "Team") : team.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(L("wechseln", "change")).font(.caption).foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .card()
                }
                .buttonStyle(.plain)

                let result = Matchup.evaluate(team: team, against: t, teamIndex: variant, game: game)
                MatchupResultView(result: result, team: team, game: game)
            }
        }
    }

    private func sources(_ t: GuideTrainer) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Quellen", "Sources")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(t.sources, id: \.self) { s in
                if let url = URL(string: s) {
                    Link(url.host().map { $0 + url.path() } ?? s, destination: url)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// An opposing Pokémon with level, types, ability and moves.
struct OpponentRow: View {
    let pokemon: GuidePokemon
    let game: Game

    var body: some View {
        let dex = Dex.shared
        let p = dex.pokemon(pokemon.p)
        HStack(alignment: .top, spacing: 12) {
            PokemonSprite(pokemonId: pokemon.p).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(p?.name ?? "?").font(.headline)
                    if pokemon.gmax == true {
                        MechanicLogo(mechanic: .gmax, size: 14).foregroundStyle(.red)
                    }
                    Spacer()
                    Text("Lv. \(pokemon.l)").font(.subheadline.weight(.bold).monospacedDigit())
                }
                HStack(spacing: 4) {
                    ForEach(p?.types(gen: game.gen) ?? [], id: \.self) { TypeBadge(typeId: $0, small: true) }
                    if let a = pokemon.a, let ability = dex.ability(a) {
                        Text(ability.name).font(.caption).foregroundStyle(.secondary).padding(.leading, 4)
                    }
                }
                if pokemon.m.isEmpty {
                    Text(L("Attacken unbekannt", "Moves unknown")).font(.caption).foregroundStyle(.tertiary)
                } else {
                    MoveChips(moves: pokemon.m.compactMap { dex.move($0) })
                }
            }
        }
        .padding(12)
        .contentShape(Rectangle())
    }
}

/// Moves as small coloured chips, two per row.
struct MoveChips: View {
    let moves: [DexMove]

    var body: some View {
        let rows = stride(from: 0, to: moves.count, by: 2).map { Array(moves[$0..<min($0 + 2, moves.count)]) }
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(row) { m in
                        HStack(spacing: 4) {
                            Circle().fill(TypeColor.color(m.t)).frame(width: 6, height: 6)
                            Text(m.name).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(TypeColor.color(m.t).opacity(0.13), in: Capsule())
                    }
                    if row.count == 1 { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                }
            }
        }
    }
}

/// Verdict, who answers whom and tips.
struct MatchupResultView: View {
    let result: Matchup
    let team: Team
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            verdictCard
            VStack(spacing: 0) {
                ForEach(Array(result.answers.enumerated()), id: \.offset) { i, a in
                    if i > 0 { Divider().padding(.leading, 14) }
                    answerRow(a)
                }
            }
            .card()
            if !result.tips.isEmpty {
                Label(L("Tipps", "Tips"), systemImage: "checklist").font(.headline).padding(.top, 4)
                ForEach(result.tips) { tip in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon(tip.kind))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(color(tip.kind))
                            .frame(width: 30, height: 30)
                            .background(color(tip.kind).opacity(0.15), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        Text(tip.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .accentCard([color(tip.kind)])
                }
            }
            Text(L("Schätzung aus Typen, Werten, Level und Attacken (jeweils 1 gegen 1). Zufall, Items, Status, Wetter und das Verhalten des Gegners sind nicht eingerechnet.",
                   "Estimate from types, stats, levels and moves (1-on-1 each). Random rolls, items, status, weather and the opponent's behaviour aren't included."))
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var verdictCard: some View {
        let (title, sub, color, icon): (String, String, Color, String) = {
            switch result.verdict {
            case .good: return (L("Gute Chancen", "Good chances"), L("Für jedes Pokémon des Gegners hast du eine Antwort.", "You have an answer to every opposing Pokémon."), .green, "checkmark.seal.fill")
            case .close: return (L("Knapp", "Close"), L("Machbar, aber ein, zwei Pokémon werden eng.", "Doable, but one or two Pokémon will be tight."), .orange, "exclamationmark.triangle.fill")
            case .hard: return (L("Schwer", "Tough"), L("So wird es schwierig – schau dir die Tipps an.", "This will be hard – have a look at the tips."), .red, "xmark.octagon.fill")
            }
        }()
        return HStack(spacing: 14) {
            // traffic light
            VStack(spacing: 5) {
                ForEach([Matchup.Verdict.hard, .close, .good], id: \.self) { v in
                    Circle()
                        .fill(lightColor(v).opacity(v == result.verdict ? 1 : 0.18))
                        .frame(width: 14, height: 14)
                        .shadow(color: v == result.verdict ? lightColor(v).opacity(0.7) : .clear, radius: 5)
                }
            }
            .padding(.vertical, 8).padding(.horizontal, 7)
            .background(Color.black.opacity(0.35), in: Capsule())
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: icon).font(.title3.weight(.bold)).foregroundStyle(color)
                Text(sub).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(L("Dein Team Ø Lv. \(result.averageLevel) · Gegner bis Lv. \(result.aceLevel)",
                       "Your team avg. Lv. \(result.averageLevel) · opponent up to Lv. \(result.aceLevel)"))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .accentCard([color])
    }

    private func lightColor(_ v: Matchup.Verdict) -> Color {
        switch v { case .good: return .green; case .close: return .orange; case .hard: return .red }
    }

    private func answerRow(_ a: Matchup.Answer) -> some View {
        let dex = Dex.shared
        let gradeColor: Color = a.grade == .safe ? .green : a.grade == .even ? .orange : .red
        return HStack(spacing: 10) {
            PokemonSprite(pokemonId: a.opponent.p).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: dex.pokemon(a.opponent.p)?.name ?? "?", font: .subheadline.weight(.semibold), color: .primary)
                Text("Lv. \(a.opponent.l)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(width: 84, alignment: .leading)
            Image(systemName: "arrow.left").font(.caption.weight(.bold)).foregroundStyle(gradeColor)
            if let m = a.member {
                PokemonSprite(pokemonId: m.battleForm(in: team.game)?.id ?? m.pokemonId, shiny: m.shiny).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(text: m.displayName, font: .subheadline.weight(.semibold), color: .primary)
                    if let id = a.moveId, let move = dex.move(id) {
                        HStack(spacing: 4) {
                            Circle().fill(TypeColor.color(move.t)).frame(width: 6, height: 6)
                            MarqueeText(text: L("\(move.name) · ~\(Int(min(a.damage, 9.99) * 100)) % pro Treffer",
                                                "\(move.name) · ~\(Int(min(a.damage, 9.99) * 100)) % per hit"))
                        }
                    } else {
                        MarqueeText(text: L("keine passende Attacke", "no fitting move"))
                    }
                }
            }
            Spacer(minLength: 0)
            Circle().fill(gradeColor).frame(width: 10, height: 10)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func icon(_ k: Matchup.Tip.Kind) -> String {
        switch k { case .problem: return "xmark"; case .warning: return "exclamationmark"; case .info: return "info"; case .good: return "checkmark" }
    }

    private func color(_ k: Matchup.Tip.Kind) -> Color {
        switch k { case .problem: return .red; case .warning: return .orange; case .info: return .blue; case .good: return .green }
    }
}
