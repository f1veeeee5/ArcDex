import Foundation

struct Tip: Identifiable {
    enum Level: Int { case problem = 0, warning, info, good }
    let id = UUID()
    let level: Level
    let title: String
    let detail: String
}

struct TeamAnalysis {
    struct DefenseEntry: Identifiable {
        let type: DexType
        /// multiplier per member
        let multipliers: [Double]
        var id: Int { type.id }
        var weak: Int { multipliers.filter { $0 > 1 }.count }
        var resist: Int { multipliers.filter { $0 > 0 && $0 < 1 }.count }
        var immune: Int { multipliers.filter { $0 == 0 }.count }
        var balance: Int { resist + immune - weak }
    }

    struct OffenseEntry: Identifiable {
        let type: DexType
        /// best multiplier any move of the team reaches against this type
        let best: Double
        /// members that have a super effective damaging move against it
        let hitters: Int
        var id: Int { type.id }
    }

    let defense: [DefenseEntry]
    let offense: [OffenseEntry]
    let tips: [Tip]
    let hasMoves: Bool

    init(members: [TeamMember], game: Game) {
        let dex = Dex.shared
        let types = dex.battleTypes(gen: game.gen)

        defense = types.map { attack in
            DefenseEntry(type: attack, multipliers: members.map {
                TypeChart.multiplier(attack: attack.id, defense: $0.types(in: game), abilityKey: game.hasAbilities ? $0.ability?.key : nil, gen: game.gen)
            })
        }

        let damaging = members.map { $0.moves.filter(\.isDamaging) }
        hasMoves = damaging.contains { !$0.isEmpty }
        offense = types.map { def in
            var best = 0.0
            var hitters = 0
            for moves in damaging {
                let m = moves.map { TypeChart.multiplier(attack: $0.t, defense: [def.id], gen: game.gen) }.max() ?? 0
                best = max(best, m)
                if m > 1 { hitters += 1 }
            }
            return OffenseEntry(type: def, best: best, hitters: hitters)
        }

        tips = TeamAnalysis.makeTips(members: members, game: game, defense: defense, offense: offense, hasMoves: hasMoves)
    }

    // MARK: Tips

    private static func typeList(_ ids: [Int], limit: Int = 4) -> String {
        ids.prefix(limit).compactMap { Dex.shared.type($0)?.name }.joined(separator: ", ")
    }

    private static func makeTips(members: [TeamMember], game: Game, defense: [DefenseEntry], offense: [OffenseEntry], hasMoves: Bool) -> [Tip] {
        var tips: [Tip] = []
        let dex = Dex.shared

        if members.isEmpty {
            return [Tip(level: .info, title: L("Noch leer", "Still empty"),
                        detail: L("Füge Pokémon hinzu oder scanne dein Team, um eine Analyse zu sehen.",
                                  "Add Pokémon or scan your team to see an analysis."))]
        }

        // Team size
        if members.count < 6 {
            tips.append(Tip(level: .info, title: L("\(members.count) von 6 Pokémon", "\(members.count) of 6 Pokémon"),
                            detail: L("Es ist noch Platz für \(6 - members.count) weitere Pokémon.",
                                      "There is room for \(6 - members.count) more Pokémon.")))
        }

        // Species clause
        let speciesCounts = Dictionary(grouping: members, by: { $0.species?.sp ?? 0 })
        for (_, list) in speciesCounts where list.count > 1 {
            tips.append(Tip(level: .problem, title: L("Doppeltes Pokémon", "Duplicate Pokémon"),
                            detail: L("\(list[0].species?.name ?? "?") ist mehrfach im Team. In offiziellen Kämpfen ist jedes Pokémon nur einmal erlaubt.",
                                      "\(list[0].species?.name ?? "?") is on the team more than once. Official battles only allow each Pokémon once.")))
        }

        // Shared weaknesses
        let worst = defense.filter { $0.weak >= 3 || ($0.weak >= 2 && $0.resist + $0.immune == 0 && members.count <= 3) }
            .sorted { $0.balance < $1.balance }
        for entry in worst.prefix(3) {
            let helpers = typeList(TypeChart.resisters(of: entry.type.id, gen: game.gen), limit: 3)
            let level: Tip.Level = entry.balance <= -3 ? .problem : .warning
            tips.append(Tip(level: level,
                            title: L("Schwach gegen \(entry.type.name)", "Weak to \(entry.type.name)"),
                            detail: L("\(entry.weak) Pokémon sind anfällig, nur \(entry.resist + entry.immune) halten es aus. Ein Pokémon vom Typ \(helpers) würde helfen.",
                                      "\(entry.weak) Pokémon are weak, only \(entry.resist + entry.immune) can take it. A \(helpers) type would help.")))
        }

        // 4× weaknesses
        for m in members {
            let quad = defense.filter { e in
                guard let i = members.firstIndex(where: { $0 === m }) else { return false }
                return e.multipliers[i] >= 4
            }
            if !quad.isEmpty {
                tips.append(Tip(level: .info, title: L("4×-Schwäche bei \(m.displayName)", "4× weakness on \(m.displayName)"),
                                detail: L("\(m.displayName) nimmt vierfachen Schaden von \(quad.map(\.type.name).joined(separator: ", ")). Ein Item wie Fokusgurt oder eine passende Beere kann helfen.",
                                          "\(m.displayName) takes 4× damage from \(quad.map(\.type.name).joined(separator: ", ")). An item like Focus Sash or a resist berry can help.")))
            }
        }

        // Stacked types
        var typeCounts: [Int: Int] = [:]
        for m in members { for t in m.types(in: game) { typeCounts[t, default: 0] += 1 } }
        for (t, c) in typeCounts where c >= 3 {
            tips.append(Tip(level: .warning, title: L("Viele \(dex.type(t)?.name ?? "")-Pokémon", "Lots of \(dex.type(t)?.name ?? "") types"),
                            detail: L("\(c) Pokémon teilen sich diesen Typ und damit auch dieselben Schwächen.",
                                      "\(c) Pokémon share this type and therefore the same weaknesses.")))
        }

        // Moves
        let missing = members.filter { $0.moveIds.count < 4 }
        if !missing.isEmpty {
            let names = missing.map(\.displayName).joined(separator: ", ")
            tips.append(Tip(level: .info, title: L("Attacken fehlen", "Moves missing"),
                            detail: L("\(names) \(missing.count == 1 ? "hat" : "haben") noch keine 4 Attacken. Tipp: Attacken einfach abfotografieren.",
                                      "\(names) \(missing.count == 1 ? "has" : "have") fewer than 4 moves. Tip: just take a photo of the moves.")))
        }

        if hasMoves {
            // Offensive gaps
            let uncovered = offense.filter { $0.hitters == 0 }
            let walled = offense.filter { $0.best < 1 }
            if !walled.isEmpty {
                tips.append(Tip(level: .problem, title: L("Kaum Schaden gegen \(walled.map(\.type.name).joined(separator: ", "))", "Little damage against \(walled.map(\.type.name).joined(separator: ", "))"),
                                detail: L("Keine deiner Attacken trifft diese Typen auch nur neutral. Gute Optionen: \(typeList(walled.flatMap { TypeChart.counters(of: $0.type.id, gen: game.gen) }.uniqued()))-Attacken.",
                                          "None of your moves hits these types even neutrally. Good options: \(typeList(walled.flatMap { TypeChart.counters(of: $0.type.id, gen: game.gen) }.uniqued())) moves.")))
            } else if uncovered.count >= 3 {
                let names = uncovered.prefix(5).map(\.type.name).joined(separator: ", ")
                let counter = typeList(TypeChart.bestCover(for: uncovered.map(\.type.id), gen: game.gen), limit: 3)
                tips.append(Tip(level: .warning, title: L("Lücken in der Abdeckung", "Coverage gaps"),
                                detail: L("Nichts ist sehr effektiv gegen \(names). Am meisten davon decken \(counter)-Attacken ab.",
                                          "Nothing is super effective against \(names). \(counter) moves would cover most of them.")))
            } else if !uncovered.isEmpty {
                let names = uncovered.map(\.type.name).joined(separator: ", ")
                tips.append(Tip(level: .info, title: L("Kleine Lücke: \(names)", "Small gap: \(names)"),
                                detail: L("Gegen \(names) hast du keine sehr effektive Attacke.", "You have no super effective move against \(names).")))
            }

            // Physical / special balance
            let all = members.flatMap(\.moves).filter(\.isDamaging)
            let phys = all.filter(\.isPhysical).count
            let spec = all.filter(\.isSpecial).count
            if all.count >= 6 && (phys == 0 || spec == 0) {
                let onlyPhys = spec == 0
                tips.append(Tip(level: .warning, title: onlyPhys ? L("Nur physische Attacken", "Only physical moves") : L("Nur Spezial-Attacken", "Only special moves"),
                                detail: onlyPhys
                                    ? L("Pokémon mit hoher Verteidigung oder Verbrennung stoppen dein Team. Ein Spezial-Angreifer macht es schwerer berechenbar.",
                                        "High-Defense Pokémon or a burn can stop your team. A special attacker makes you less predictable.")
                                    : L("Pokémon mit hoher Spezial-Verteidigung stoppen dein Team. Ein physischer Angreifer bringt Balance.",
                                        "High Special Defense Pokémon can stop your team. A physical attacker adds balance.")))
            }

            // STAB
            for m in members where m.moveIds.count >= 2 {
                let types = m.types(in: game)
                if !m.moves.contains(where: { $0.isDamaging && types.contains($0.t) }) {
                    tips.append(Tip(level: .info, title: L("Keine STAB-Attacke bei \(m.displayName)", "No STAB move on \(m.displayName)"),
                                    detail: L("Attacken vom eigenen Typ machen 1,5× Schaden. Eine \(typeList(types))-Attacke würde \(m.displayName) stärker machen.",
                                              "Moves of its own type deal 1.5× damage. A \(typeList(types)) move would make \(m.displayName) hit harder.")))
                }
            }

            // Priority & speed control
            let allMoves = members.flatMap(\.moves)
            if members.count >= 4 && !allMoves.contains(where: { $0.pr > 0 && $0.isDamaging }) {
                tips.append(Tip(level: .info, title: L("Keine Erstschlag-Attacke", "No priority move"),
                                detail: L("Attacken wie Tempohieb, Patronenhieb oder Mach Punch helfen gegen schnelle, angeschlagene Gegner.",
                                          "Moves like Quick Attack, Bullet Punch or Mach Punch help against fast, weakened foes.")))
            }
            let speedKeys: Set<String> = ["tailwind", "trick-room", "icy-wind", "electroweb", "thunder-wave", "sticky-web", "scary-face", "rock-tomb", "bulldoze", "glare", "nuzzle", "string-shot", "cotton-spore"]
            if members.count >= 4 && !allMoves.contains(where: { speedKeys.contains($0.key) }) {
                tips.append(Tip(level: .info, title: L("Keine Speed-Kontrolle", "No speed control"),
                                detail: L("Rückenwind, Eissturm, Donnerwelle oder Elektronetz helfen, schneller als der Gegner zu sein. Im Doppelkampf auch Bizarroraum.",
                                          "Tailwind, Icy Wind, Thunder Wave or Electroweb help you outspeed. In doubles Trick Room is an option too.")))
            }
        }

        // Items
        let withItem = members.compactMap(\.itemId)
        let dupItems = Dictionary(grouping: withItem, by: { $0 }).filter { $0.value.count > 1 }.keys
        for id in dupItems {
            tips.append(Tip(level: .warning, title: L("Item doppelt", "Duplicate item"),
                            detail: L("\(dex.item(id)?.name ?? "?") ist mehrfach vergeben. In offiziellen Doppelkämpfen gilt die Item-Klausel.",
                                      "\(dex.item(id)?.name ?? "?") is used more than once. Official doubles use the item clause.")))
        }
        let noItem = members.filter { $0.itemId == nil }
        if game.hasHeldItems && !noItem.isEmpty && members.count >= 3 {
            tips.append(Tip(level: .info, title: L("Ohne Item", "No item"),
                            detail: L("\(noItem.map(\.displayName).joined(separator: ", ")) \(noItem.count == 1 ? "trägt" : "tragen") kein Item.",
                                      "\(noItem.map(\.displayName).joined(separator: ", ")) \(noItem.count == 1 ? "holds" : "hold") no item.")))
        }

        // Mechanics
        if game.hasMega {
            let megas = members.filter { $0.megaFormId != nil }
            if megas.count > 1 {
                tips.append(Tip(level: .warning, title: L("Mehrere Mega-Entwicklungen", "Multiple Mega Evolutions"),
                                detail: L("Pro Kampf kann sich nur ein Pokémon mega-entwickeln.", "Only one Pokémon can Mega Evolve per battle.")))
            }
            for m in megas {
                if let form = m.megaFormId.flatMap({ dex.pokemon($0) }), let stone = form.stone, m.itemId != stone {
                    tips.append(Tip(level: .warning, title: L("Mega-Stein fehlt", "Mega Stone missing"),
                                    detail: L("\(m.displayName) braucht \(dex.item(stone)?.name ?? "den Mega-Stein"), um sich zu entwickeln.",
                                              "\(m.displayName) needs \(dex.item(stone)?.name ?? "its Mega Stone") to Mega Evolve.")))
                }
            }
        }
        if game.hasZMoves {
            let z = members.filter { $0.item?.isZCrystal == true }
            if z.isEmpty && members.count >= 4 && !members.contains(where: { $0.megaFormId != nil }) {
                tips.append(Tip(level: .info, title: L("Kein Z-Kristall", "No Z-Crystal"),
                                detail: L("In Sonne/Mond kannst du einmal pro Kampf eine Z-Attacke einsetzen.", "In Sun/Moon you can use one Z-Move per battle.")))
            }
        }
        if game.hasDynamax {
            let gmax = members.filter(\.gigantamax)
            if gmax.count > 2 {
                tips.append(Tip(level: .info, title: L("Viele Gigadynamax-Pokémon", "Many Gigantamax Pokémon"),
                                detail: L("Pro Kampf kannst du nur einmal dynamaximieren – \(gmax.count) Gigadynamax-Formen sind meist zu viel.",
                                          "You can only Dynamax once per battle – \(gmax.count) Gigantamax forms are usually too many.")))
            }
        }
        if game.hasTera {
            let noTera = members.filter { $0.teraTypeId == nil }
            if !noTera.isEmpty && members.count >= 3 {
                tips.append(Tip(level: .info, title: L("Tera-Typ fehlt", "Tera Type missing"),
                                detail: L("\(noTera.map(\.displayName).joined(separator: ", ")) \(noTera.count == 1 ? "hat" : "haben") keinen Tera-Typ. Ein defensiver Tera-Typ kann Schwächen auflösen.",
                                          "\(noTera.map(\.displayName).joined(separator: ", ")) \(noTera.count == 1 ? "has" : "have") no Tera Type. A defensive Tera Type can remove weaknesses.")))
            }
        }

        if tips.allSatisfy({ $0.level == .info }) && members.count == 6 && hasMoves {
            tips.insert(Tip(level: .good, title: L("Starkes Team!", "Strong team!"),
                            detail: L("Keine großen Schwächen und eine gute Typ-Abdeckung.", "No big weaknesses and good type coverage.")), at: 0)
        }

        return tips.sorted { $0.level.rawValue < $1.level.rawValue }
    }
}

extension TypeChart {
    /// Attacking types sorted by how many of the given defending types they hit super effectively.
    static func bestCover(for defenders: [Int], gen: Int = 9) -> [Int] {
        Dex.shared.battleTypes(gen: gen).map(\.id).map { atk in (atk, defenders.filter { multiplier(attack: atk, defense: [$0], gen: gen) > 1 }.count) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
