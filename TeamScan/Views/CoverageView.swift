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
                        .font(.title3)
                        .foregroundStyle(color(tip.level))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tip.title).font(.subheadline.weight(.semibold))
                        Text(tip.detail).font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .card()
            }
        }
    }

    private func icon(_ l: Tip.Level) -> String {
        switch l {
        case .problem: return "exclamationmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "lightbulb.fill"
        case .good: return "checkmark.seal.fill"
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
