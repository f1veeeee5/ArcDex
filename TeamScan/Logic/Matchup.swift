import Foundation

/// Rough estimate of how a team does against a trainer: for every opposing Pokémon the best answer
/// from the team (1-on-1: who knocks out whom first). Not a battle simulation – no random rolls,
/// items, status or AI behaviour.
struct Matchup {
    enum Verdict { case good, close, hard }
    enum Grade { case safe, even, lost }

    struct Answer {
        let opponent: GuidePokemon
        let member: TeamMember?
        let grade: Grade
        /// share of the opponent's HP per hit by the best answer (0…)
        let damage: Double
        /// share of the answer's HP per hit taken from the opponent
        let taken: Double
        let faster: Bool
        let moveId: Int?
    }

    struct Tip: Identifiable {
        enum Kind { case problem, warning, info, good }
        let id = UUID()
        let kind: Kind
        let text: String
    }

    let verdict: Verdict
    let answers: [Answer]
    let tips: [Tip]
    let averageLevel: Int
    let aceLevel: Int

    // MARK: - Calculation

    static func evaluate(team: Team, against trainer: GuideTrainer, teamIndex: Int, game: Game) -> Matchup {
        let opponents = trainer.teams[min(teamIndex, trainer.teams.count - 1)].team
        let members = team.sortedMembers
        let dex = Dex.shared
        let gen = game.gen

        var answers: [Answer] = []
        for opp in opponents {
            var best: (score: Double, answer: Answer)?
            for m in members {
                let r = duel(member: m, opp: opp, game: game)
                let grade: Grade = r.myTurns < r.theirTurns ? .safe
                    : (r.myTurns == r.theirTurns && r.faster) ? .even : .lost
                // more turns to spare and less damage taken = better
                let score = Double(r.theirTurns - r.myTurns) + (r.faster ? 0.5 : 0) + r.damage * 0.3 - r.taken * 0.3
                let answer = Answer(opponent: opp, member: m, grade: grade, damage: r.damage, taken: r.taken, faster: r.faster, moveId: r.moveId)
                if best == nil || score > best!.score { best = (score, answer) }
            }
            answers.append(best?.answer ?? Answer(opponent: opp, member: nil, grade: .lost, damage: 0, taken: 1, faster: false, moveId: nil))
        }

        let lost = answers.filter { $0.grade == .lost }.count
        let even = answers.filter { $0.grade == .even }.count
        let avg = members.isEmpty ? 0 : members.map(\.level).reduce(0, +) / members.count
        let ace = opponents.map(\.l).max() ?? 0

        var verdict: Verdict = lost == 0 ? (even <= 1 ? .good : .close) : (lost == 1 ? .close : .hard)
        if avg + 6 <= ace { verdict = verdict == .good ? .close : .hard }

        // MARK: tips
        var tips: [Tip] = []
        func typeName(_ t: Int) -> String { dex.type(t)?.name ?? "?" }

        if members.isEmpty {
            return Matchup(verdict: .hard, answers: answers, tips: [Tip(kind: .problem, text: L("Das Team ist leer.", "The team is empty."))],
                           averageLevel: 0, aceLevel: ace)
        }

        // level
        if avg + 3 <= ace {
            tips.append(Tip(kind: avg + 6 <= ace ? .problem : .warning,
                            text: L("Dein Team ist im Schnitt Lv. \(avg) – das stärkste Pokémon des Gegners ist Lv. \(ace). Ein paar Level mehr helfen.",
                                    "Your team averages Lv. \(avg) – the opponent's strongest Pokémon is Lv. \(ace). A few more levels will help.")))
        } else if avg >= ace + 5 {
            tips.append(Tip(kind: .good, text: L("Dein Team ist im Level klar vorne (Ø Lv. \(avg) gegen Lv. \(ace)).",
                                                "Your team is clearly ahead in level (avg. Lv. \(avg) vs Lv. \(ace)).")))
        }

        // attacking types that hit most of the opponents super effectively
        let teamMoveTypes = Set(members.flatMap { $0.moves.filter { $0.c != 1 }.map(\.t) })
        let teamTypes = Set(members.flatMap { $0.types(in: game) })
        let candidates = dex.battleTypes(gen: gen).map(\.id).map { t -> (Int, Int) in
            let hits = opponents.filter { o in
                guard let p = dex.pokemon(o.p) else { return false }
                return TypeChart.multiplier(attack: t, defense: p.types(gen: gen), abilityKey: o.a.flatMap { dex.ability($0)?.key }, gen: gen) > 1
            }.count
            return (t, hits)
        }
        .filter { $0.1 * 2 >= opponents.count && $0.1 > 0 }
        .sorted { $0.1 > $1.1 }
        if let top = candidates.first {
            if !teamMoveTypes.contains(top.0) {
                let name = typeName(top.0)
                let hint = teamTypes.contains(top.0)
                    ? L("Gib deinem \(name)-Pokémon eine \(name)-Attacke.", "Give your \(name) Pokémon a \(name) move.")
                    : L("Ein \(name)-Pokémon fehlt im Team.", "A \(name) type Pokémon is missing from the team.")
                tips.append(Tip(kind: lost > 0 ? .problem : .warning,
                                text: L("Keine \(name)-Attacke: sie trifft \(top.1) von \(opponents.count) Pokémon sehr effektiv. ",
                                        "No \(name) move: it hits \(top.1) of \(opponents.count) Pokémon super effectively. ") + hint))
            } else {
                tips.append(Tip(kind: .good, text: L("Gut: du hast \(typeName(top.0))-Attacken – sie treffen \(top.1) von \(opponents.count) Pokémon sehr effektiv.",
                                                    "Good: you have \(typeName(top.0)) moves – they hit \(top.1) of \(opponents.count) Pokémon super effectively.")))
            }
        }

        // the opponent's attacking types that many team members are weak to
        let oppMoveTypes = Set(opponents.flatMap { o in o.m.compactMap { dex.move($0) }.filter { $0.c != 1 }.map(\.t) })
        for t in oppMoveTypes.sorted() {
            let weak = members.filter { m in
                TypeChart.multiplier(attack: t, defense: m.types(in: game), abilityKey: m.ability?.key, gen: gen) > 1
            }
            if weak.count * 2 > members.count, weak.count >= 2 {
                tips.append(Tip(kind: .warning, text: L("\(weak.count) deiner Pokémon sind schwach gegen \(typeName(t))-Attacken, die der Gegner einsetzt.",
                                                        "\(weak.count) of your Pokémon are weak to \(typeName(t)) moves the opponent uses.")))
            }
        }

        // opponents without a good answer
        for a in answers where a.grade == .lost {
            guard let p = dex.pokemon(a.opponent.p) else { continue }
            let good = dex.battleTypes(gen: gen).map(\.id).filter {
                TypeChart.multiplier(attack: $0, defense: p.types(gen: gen), abilityKey: a.opponent.a.flatMap { dex.ability($0)?.key }, gen: gen) > 1
            }.prefix(3).map(typeName)
            tips.append(Tip(kind: .problem,
                            text: L("Gegen \(p.name) (Lv. \(a.opponent.l)) hast du keine sichere Antwort",
                                    "You have no safe answer to \(p.name) (Lv. \(a.opponent.l))")
                                + (good.isEmpty ? "." : L(" – \(good.joined(separator: ", ")) trifft es sehr effektiv.",
                                                         " – \(good.joined(separator: ", ")) hits it super effectively."))))
        }

        // members without attacking moves
        for m in members where !m.moves.contains(where: { $0.c != 1 }) {
            tips.append(Tip(kind: .warning, text: m.moves.isEmpty
                            ? L("\(m.displayName) hat keine Attacken eingetragen – es wird nicht mitgerechnet.", "\(m.displayName) has no moves entered – it isn't counted.")
                            : L("\(m.displayName) hat keine Angriffsattacke.", "\(m.displayName) has no attacking move.")))
        }

        if trainer.double {
            tips.append(Tip(kind: .info, text: L("Doppelkampf: Attacken, die beide Gegner treffen, und Schutzschild sind hier viel wert.",
                                                "Double battle: moves that hit both opponents and Protect are worth a lot here.")))
        }

        return Matchup(verdict: verdict, answers: answers, tips: tips, averageLevel: avg, aceLevel: ace)
    }

    // MARK: 1-on-1

    private struct Duel {
        let myTurns: Int
        let theirTurns: Int
        let faster: Bool
        let damage: Double
        let taken: Double
        let moveId: Int?
    }

    private static func duel(member m: TeamMember, opp: GuidePokemon, game: Game) -> Duel {
        let dex = Dex.shared
        let gen = game.gen
        guard let me = m.battleForm(in: game) ?? m.species, let them = dex.pokemon(opp.p) else {
            return Duel(myTurns: 99, theirTurns: 1, faster: false, damage: 0, taken: 1, moveId: nil)
        }
        let myTypes = m.types(in: game)
        let theirTypes = them.types(gen: gen)
        let myStats = (0..<6).map { m.stat($0, base: me.s[$0], level: m.level, game: game) }
        let theirStats = (0..<6).map { trainerStat($0, base: them.s[$0], level: opp.l) }
        let theirAbility = opp.a.flatMap { dex.ability($0)?.key } ?? dex.ability(them.ab.first ?? -1)?.key

        // my best hit
        var bestMine = 0.0
        var bestMove: Int?
        for move in m.moves where move.c != 1 {
            let d = share(move: move, level: m.level, atk: myStats, def: theirStats, attackerTypes: myTypes,
                          defenderTypes: theirTypes, defenderAbility: theirAbility, gen: gen)
            if d > bestMine { bestMine = d; bestMove = move.id }
        }
        // their best hit (moves unknown -> a 70 power move of each own type)
        var bestTheirs = 0.0
        let theirMoves = opp.m.compactMap { dex.move($0) }.filter { $0.c != 1 }
        if theirMoves.isEmpty {
            for t in theirTypes {
                let physical = them.s[1] >= them.s[3]
                let d = rawShare(power: 70, type: t, physical: physical, level: opp.l, atk: theirStats, def: myStats,
                                 attackerTypes: theirTypes, defenderTypes: myTypes, defenderAbility: m.ability?.key, gen: gen)
                bestTheirs = max(bestTheirs, d)
            }
        } else {
            for move in theirMoves {
                bestTheirs = max(bestTheirs, share(move: move, level: opp.l, atk: theirStats, def: myStats, attackerTypes: theirTypes,
                                                   defenderTypes: myTypes, defenderAbility: m.ability?.key, gen: gen))
            }
        }
        let myTurns = bestMine > 0 ? Int((1 / bestMine).rounded(.up)) : 99
        let theirTurns = bestTheirs > 0 ? Int((1 / bestTheirs).rounded(.up)) : 99
        return Duel(myTurns: min(myTurns, 99), theirTurns: min(theirTurns, 99), faster: myStats[5] > theirStats[5],
                    damage: bestMine, taken: bestTheirs, moveId: bestMove)
    }

    /// In-game trainers: no EVs, average IVs, neutral nature (the real values vary per game).
    private static func trainerStat(_ i: Int, base: Int, level: Int) -> Int {
        let core = (2 * base + 20) * level / 100
        return i == 0 ? core + level + 10 : core + 5
    }

    private static func share(move: DexMove, level: Int, atk: [Int], def: [Int], attackerTypes: [Int], defenderTypes: [Int],
                              defenderAbility: String?, gen: Int) -> Double {
        // moves with variable power (Heavy Slam, Gyro Ball …) count as 60
        let power = move.p > 0 ? move.p : 60
        // up to Gen 3 the type decides physical / special
        let physical: Bool = gen <= 3
            ? [T.normal, T.fighting, T.flying, T.poison, T.ground, T.rock, T.bug, T.ghost, T.steel].contains(move.t)
            : move.c == 2
        return rawShare(power: power, type: move.t, physical: physical, level: level, atk: atk, def: def,
                        attackerTypes: attackerTypes, defenderTypes: defenderTypes, defenderAbility: defenderAbility, gen: gen)
    }

    private static func rawShare(power: Int, type: Int, physical: Bool, level: Int, atk: [Int], def: [Int], attackerTypes: [Int],
                                 defenderTypes: [Int], defenderAbility: String?, gen: Int) -> Double {
        let a = Double(physical ? atk[1] : atk[3])
        let d = Double(max(physical ? def[2] : def[4], 1))
        let eff = TypeChart.multiplier(attack: type, defense: defenderTypes, abilityKey: defenderAbility, gen: gen)
        let stab = attackerTypes.contains(type) ? 1.5 : 1
        let base = (Double(2 * level) / 5 + 2) * Double(power) * a / d / 50 + 2
        // 0.925 = average random roll
        let damage = base * stab * eff * 0.925
        return damage / Double(max(def[0], 1))
    }
}
