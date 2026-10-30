import SwiftUI

struct CoverageView: View {
    let analysis: TeamAnalysis
    @State private var mode = 0
    @State private var selected: TeamAnalysis.DefenseEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $mode) {
                Text(L("Defensiv", "Defensive")).tag(0)
                Text(L("Offensiv", "Offensive")).tag(1)
            }
            .pickerStyle(.segmented)

            if mode == 0 { defense } else { offense }
        }
        .padding(14)
        .card()
    }

    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 98), spacing: 8)] }

    private var defense: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Legend(color: .red, text: L("Schwach", "Weak"))
                Legend(color: .green, text: L("Resistent", "Resists"))
                Legend(color: .blue, text: L("Immun", "Immune"))
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(analysis.defense) { e in
                    VStack(spacing: 6) {
                        TypeBadge(typeId: e.type.id)
                        HStack(spacing: 8) {
                            Count(value: e.weak, color: .red)
                            Count(value: e.resist, color: .green)
                            Count(value: e.immune, color: .blue)
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(tint(for: e).opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func tint(for e: TeamAnalysis.DefenseEntry) -> Color {
        if e.weak >= 3 && e.balance < 0 { return .red }
        if e.balance <= -2 { return .orange }
        if e.balance >= 2 { return .green }
        return Color(.systemGray)
    }

    private var offense: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !analysis.hasMoves {
                Label(L("Füge Attacken hinzu, um die offensive Abdeckung zu sehen.", "Add moves to see your offensive coverage."), systemImage: "info.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 14) {
                    Legend(color: .green, text: L("Sehr effektiv", "Super effective"))
                    Legend(color: .gray, text: L("Neutral", "Neutral"))
                    Legend(color: .red, text: L("Schlecht", "Poor"))
                }
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(analysis.offense) { e in
                        let color: Color = e.best > 1 ? .green : (e.best < 1 ? .red : .gray)
                        VStack(spacing: 6) {
                            TypeBadge(typeId: e.type.id)
                            HStack(spacing: 4) {
                                Image(systemName: e.best > 1 ? "checkmark.circle.fill" : (e.best < 1 ? "xmark.circle.fill" : "minus.circle.fill"))
                                    .foregroundStyle(color)
                                Text(e.best > 1 ? "\(e.hitters)×" : (e.best < 1 ? "\(formatted(e.best))" : "1×"))
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                Text(L("Zahl = Pokémon mit sehr effektiver Attacke", "Number = Pokémon with a super effective move"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func formatted(_ v: Double) -> String {
        v == 0 ? "0×" : (v == 0.25 ? "¼×" : "½×")
    }
}

private struct Legend: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct Count: View {
    let value: Int
    let color: Color
    var body: some View {
        Text("\(value)")
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(value == 0 ? Color(.tertiaryLabel) : color)
            .frame(minWidth: 14)
    }
}

struct TipsView: View {
    let tips: [Tip]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(tips) { tip in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon(tip.level))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(color(tip.level))
                        .frame(width: 32, height: 32)
                        .background(color(tip.level).opacity(0.15), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(tip.title).font(.subheadline.weight(.semibold))
                            Spacer(minLength: 4)
                            Text(label(tip.level))
                                .font(.system(size: 10, weight: .heavy))
                                .textCase(.uppercase)
                                .foregroundStyle(color(tip.level))
                        }
                        Text(tip.detail).font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
                .overlay(alignment: .leading) {
                    Capsule().fill(color(tip.level).gradient).frame(width: 4).padding(.vertical, 14)
                }
            }
        }
    }

    private func icon(_ l: Tip.Level) -> String {
        switch l {
        case .problem: return "xmark"
        case .warning: return "exclamationmark"
        case .info: return "info"
        case .good: return "checkmark"
        }
    }

    private func label(_ l: Tip.Level) -> String {
        switch l {
        case .problem: return L("Problem", "Problem")
        case .warning: return L("Achtung", "Heads-up")
        case .info: return L("Hinweis", "Note")
        case .good: return L("Top", "Great")
        }
    }

    private func color(_ l: Tip.Level) -> Color {
        switch l {
        case .problem: return .red
        case .warning: return .orange
        case .info: return .blue
        case .good: return .green
        }
    }
}

// MARK: - Team stats

/// Average base stats of the team and who moves first.
struct TeamStatsView: View {
    let members: [TeamMember]
    let game: Game

    private static let statColors: [Color] = [.green, .red, .orange, .blue, .teal, .pink]

    var body: some View {
        let forms = members.compactMap { m -> (TeamMember, DexPokemon)? in
            guard let p = m.battleForm(in: game) ?? m.species else { return nil }
            return (m, p)
        }
        let count = Double(max(forms.count, 1))
        let averages = (0..<6).map { i in Double(forms.reduce(0) { $0 + $1.1.s[i] }) / count }
        let totals = (0..<6).map { i in forms.reduce(0) { $0 + $1.1.s[i] } }
        let bst = averages.reduce(0, +)
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    HStack(spacing: 10) {
                        Text(StatNames.short[i])
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .leading)
                        Text("\(Int(averages[i].rounded()))")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .frame(width: 34, alignment: .trailing)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.tertiarySystemFill))
                                Capsule().fill(Self.statColors[i].gradient)
                                    .frame(width: geo.size.width * min(averages[i] / 150, 1))
                            }
                        }
                        .frame(height: 8)
                        Text("Σ \(totals[i])")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            HStack {
                Text(L("Ø Basiswert-Summe", "Ø base stat total")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(bst.rounded()))").font(.subheadline.weight(.bold).monospacedDigit())
            }

            // side by side; only when they don't fit, one below the other
            let chips = verdicts(averages)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { ForEach(chips, id: \.self) { chip($0) } }
                VStack(alignment: .leading, spacing: 6) { ForEach(chips, id: \.self) { chip($0) } }
            }

            if forms.count > 1 {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Wer ist am schnellsten?", "Who moves first?")).font(.subheadline.weight(.semibold))
                    ForEach(Array(forms.sorted { speed($0) > speed($1) }.enumerated()), id: \.offset) { i, entry in
                        HStack(spacing: 10) {
                            Text("\(i + 1).").font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(.secondary).frame(width: 20)
                            PokemonSprite(pokemonId: entry.1.id, shiny: entry.0.shiny).frame(width: 32, height: 32)
                            Text(entry.0.displayName).font(.subheadline).lineLimit(1)
                            Spacer()
                            Text("\(speed(entry))").font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                    }
                    Text(game.hasEVs
                         ? L("Echte Initiative auf dem jeweiligen Level (mit EVs, IVs und Wesen).", "Real Speed at each level (with EVs, IVs and nature).")
                         : L("Basiswert Initiative.", "Base Speed."))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(16)
        .card()
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }

    private func speed(_ entry: (TeamMember, DexPokemon)) -> Int {
        guard game.hasEVs else { return entry.1.s[5] }
        return entry.0.stat(5, base: entry.1.s[5], level: game.fixedLevel ?? entry.0.level, game: game)
    }

    /// Short assessment from the average base stats.
    private func verdicts(_ a: [Double]) -> [String] {
        var list: [String] = []
        let spe = a[5]
        if spe >= 95 { list.append(L("⚡️ Schnelles Team", "⚡️ Fast team")) }
        else if spe <= 60 { list.append(L("🐢 Langsames Team – Bizarroraum passt", "🐢 Slow team – Trick Room fits")) }
        else { list.append(L("Mittleres Tempo", "Medium speed")) }
        if a[1] > a[3] * 1.2 { list.append(L("Eher physisch", "Mostly physical")) }
        else if a[3] > a[1] * 1.2 { list.append(L("Eher speziell", "Mostly special")) }
        else { list.append(L("Gemischt angreifend", "Mixed attackers")) }
        let bulk = (a[0] + a[2] + a[4]) / 3
        if bulk >= 90 { list.append(L("🛡️ Robust", "🛡️ Bulky")) }
        else if bulk <= 65 { list.append(L("Eher zerbrechlich", "Rather frail")) }
        return list
    }
}
