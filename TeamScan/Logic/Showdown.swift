import Foundation

/// Export / import in the Pokémon Showdown text format (always English names).
enum Showdown {
    private static let specialNames: [String: String] = [
        "mr-mime": "Mr. Mime", "mime-jr": "Mime Jr.", "mr-rime": "Mr. Rime", "type-null": "Type: Null",
        "ho-oh": "Ho-Oh", "porygon-z": "Porygon-Z", "jangmo-o": "Jangmo-o", "hakamo-o": "Hakamo-o", "kommo-o": "Kommo-o",
        "nidoran-f": "Nidoran-F", "nidoran-m": "Nidoran-M", "farfetchd": "Farfetch’d", "sirfetchd": "Sirfetch’d",
        "flabebe": "Flabébé", "tapu-koko": "Tapu Koko", "tapu-lele": "Tapu Lele", "tapu-bulu": "Tapu Bulu", "tapu-fini": "Tapu Fini",
        "great-tusk": "Great Tusk", "scream-tail": "Scream Tail", "brute-bonnet": "Brute Bonnet", "flutter-mane": "Flutter Mane",
        "slither-wing": "Slither Wing", "sandy-shocks": "Sandy Shocks", "iron-treads": "Iron Treads", "iron-bundle": "Iron Bundle",
        "iron-hands": "Iron Hands", "iron-jugulis": "Iron Jugulis", "iron-moth": "Iron Moth", "iron-thorns": "Iron Thorns",
        "roaring-moon": "Roaring Moon", "iron-valiant": "Iron Valiant", "walking-wake": "Walking Wake", "iron-leaves": "Iron Leaves",
        "gouging-fire": "Gouging Fire", "raging-bolt": "Raging Bolt", "iron-boulder": "Iron Boulder", "iron-crown": "Iron Crown",
        "wo-chien": "Wo-Chien", "chien-pao": "Chien-Pao", "ting-lu": "Ting-Lu", "chi-yu": "Chi-Yu",
    ]

    private static func titleCase(_ key: String) -> String {
        key.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: "-")
    }

    static func speciesName(_ p: DexPokemon) -> String {
        let base = specialNames[p.sk] ?? titleCase(p.sk)
        if p.def || p.key == p.sk { return base }
        let suffix = p.key.hasPrefix(p.sk + "-") ? String(p.key.dropFirst(p.sk.count + 1)) : p.key
        return base + "-" + titleCase(suffix)
    }

    // MARK: Export

    static func export(team: Team) -> String {
        let game = team.game
        var out = "=== [\(game.showdownFormat)] \(team.name) ===\n\n"
        out += team.sortedMembers.map { export(member: $0, game: game) }.joined(separator: "\n\n")
        return out + "\n"
    }

    static func export(member m: TeamMember, game: Game) -> String {
        guard let p = m.species else { return "" }
        var first = speciesName(p)
        if !m.nickname.isEmpty && m.nickname != p.en { first = "\(m.nickname) (\(first))" }
        if game.hasGender {
            if m.gender == "M" { first += " (M)" } else if m.gender == "F" { first += " (F)" }
        }
        if game.hasHeldItems, let item = m.item { first += " @ \(item.en)" }
        var lines = [first]
        if game.hasAbilities, let a = m.ability { lines.append("Ability: \(a.en)") }
        if m.level != 100 { lines.append("Level: \(m.level)") }
        if game.hasShiny && m.shiny { lines.append("Shiny: Yes") }
        if game.hasDynamax && m.gigantamax { lines.append("Gigantamax: Yes") }
        if game.hasTera, let t = m.teraTypeId.flatMap({ Dex.shared.type($0) }) { lines.append("Tera Type: \(t.en)") }
        if game.hasEVs {
            let evs = zip(StatNames.showdown, m.evs).filter { $0.1 > 0 }.map { "\($0.1) \($0.0)" }
            if !evs.isEmpty { lines.append("EVs: " + evs.joined(separator: " / ")) }
        }
        if game.hasNatures, let n = m.nature { lines.append("\(n.en) Nature") }
        if game.hasEVs {
            let ivs = zip(StatNames.showdown, m.ivs).filter { $0.1 < 31 }.map { "\($0.1) \($0.0)" }
            if !ivs.isEmpty { lines.append("IVs: " + ivs.joined(separator: " / ")) }
        }
        for mv in m.moves { lines.append("- \(mv.en)") }
        return lines.joined(separator: "\n")
    }

    // MARK: Import

    struct ImportedTeam {
        var name: String?
        var members: [Imported]
    }

    struct Imported {
        var pokemonId: Int
        var nickname = ""
        var gender = ""
        var itemId: Int?
        var abilityId: Int?
        var level = 100
        var shiny = false
        var gigantamax = false
        var teraTypeId: Int?
        var natureId: Int?
        var evs = [0, 0, 0, 0, 0, 0]
        var ivs = [31, 31, 31, 31, 31, 31]
        var moveIds: [Int] = []
    }

    static func parse(_ text: String) -> ImportedTeam {
        let dex = Dex.shared
        func key(_ s: String) -> String { Fuzzy.normalize(s) }
        var speciesMap: [String: Int] = [:]
        for p in dex.pokemon where !p.isBattleForm {
            speciesMap[key(speciesName(p))] = speciesMap[key(speciesName(p))] ?? p.id
            if p.def { speciesMap[key(p.en)] = speciesMap[key(p.en)] ?? p.id }
            if p.def { speciesMap[key(p.de)] = speciesMap[key(p.de)] ?? p.id }
        }
        let items = Dictionary(dex.items.flatMap { [(key($0.en), $0.id), (key($0.de), $0.id)] }, uniquingKeysWith: { a, _ in a })
        let moves = Dictionary(dex.moves.flatMap { [(key($0.en), $0.id), (key($0.de), $0.id)] }, uniquingKeysWith: { a, _ in a })
        let abilities = Dictionary(dex.abilities.flatMap { [(key($0.en), $0.id), (key($0.de), $0.id)] }, uniquingKeysWith: { a, _ in a })
        let natures = Dictionary(dex.natures.flatMap { [(key($0.en), $0.id), (key($0.de), $0.id)] }, uniquingKeysWith: { a, _ in a })
        let types = Dictionary(dex.teraTypes.flatMap { [(key($0.en), $0.id), (key($0.de), $0.id)] }, uniquingKeysWith: { a, _ in a })

        var result = ImportedTeam(name: nil, members: [])
        var current: Imported?

        func flush() {
            if let c = current { result.members.append(c) }
            current = nil
        }

        func parseStats(_ s: String, into arr: inout [Int]) {
            for part in s.split(separator: "/") {
                let bits = part.trimmingCharacters(in: .whitespaces).split(separator: " ")
                guard bits.count >= 2, let v = Int(bits[0]) else { continue }
                if let i = StatNames.showdown.firstIndex(where: { $0.lowercased() == bits[1].lowercased() }) { arr[i] = v }
            }
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("===") {
                flush()
                var n = line.trimmingCharacters(in: CharacterSet(charactersIn: "= "))
                if let r = n.range(of: "] ") { n = String(n[r.upperBound...]) }
                result.name = n
                continue
            }
            if current == nil {
                // "Nick (Species) (M) @ Item"
                var head = line
                var itemId: Int?
                if let r = head.range(of: " @ ") {
                    itemId = items[key(String(head[r.upperBound...]))]
                    head = String(head[..<r.lowerBound])
                }
                var gender = ""
                if head.hasSuffix(" (M)") { gender = "M"; head.removeLast(4) }
                if head.hasSuffix(" (F)") { gender = "F"; head.removeLast(4) }
                var nickname = ""
                var speciesText = head
                if head.hasSuffix(")"), let open = head.lastIndex(of: "(") {
                    speciesText = String(head[head.index(after: open)..<head.index(before: head.endIndex)])
                    nickname = head[..<open].trimmingCharacters(in: .whitespaces)
                }
                var sk = key(speciesText)
                var gmax = false
                if sk.hasSuffix("gmax") { sk.removeLast(4); gmax = true }
                var megaStone = false
                if sk.hasSuffix("megax") || sk.hasSuffix("megay") { sk.removeLast(5); megaStone = true }
                else if sk.hasSuffix("mega") { sk.removeLast(4); megaStone = true }
                _ = megaStone
                guard let pid = speciesMap[sk] else { continue }
                current = Imported(pokemonId: pid)
                current?.nickname = nickname
                current?.gender = gender
                current?.itemId = itemId
                current?.gigantamax = gmax
                continue
            }
            guard current != nil else { continue }
            if line.hasPrefix("- ") {
                if let id = moves[key(String(line.dropFirst(2)))], current!.moveIds.count < 4 { current!.moveIds.append(id) }
            } else if line.hasPrefix("Ability:") {
                current!.abilityId = abilities[key(String(line.dropFirst(8)))]
            } else if line.hasPrefix("Level:") {
                current!.level = Int(line.dropFirst(6).trimmingCharacters(in: .whitespaces)) ?? 100
            } else if line.hasPrefix("Shiny:") {
                current!.shiny = line.lowercased().contains("yes")
            } else if line.hasPrefix("Gigantamax:") {
                current!.gigantamax = line.lowercased().contains("yes")
            } else if line.hasPrefix("Tera Type:") {
                current!.teraTypeId = types[key(String(line.dropFirst(10)))]
            } else if line.hasPrefix("EVs:") {
                parseStats(String(line.dropFirst(4)), into: &current!.evs)
            } else if line.hasPrefix("IVs:") {
                parseStats(String(line.dropFirst(4)), into: &current!.ivs)
            } else if line.hasSuffix(" Nature") {
                current!.natureId = natures[key(String(line.dropLast(7)))]
            }
        }
        flush()
        return result
    }

    static func makeMember(_ i: Imported, order: Int) -> TeamMember {
        let m = TeamMember(pokemonId: i.pokemonId, order: order, level: i.level)
        m.nickname = i.nickname
        m.gender = i.gender
        m.itemId = i.itemId
        if let a = i.abilityId { m.abilityId = a }
        m.shiny = i.shiny
        m.gigantamax = i.gigantamax
        m.teraTypeId = i.teraTypeId
        m.natureId = i.natureId
        m.evs = i.evs
        m.ivs = i.ivs
        m.moveIds = i.moveIds
        if let item = i.itemId, let form = m.megaForm(forStone: item) { m.megaFormId = form }
        return m
    }
}
