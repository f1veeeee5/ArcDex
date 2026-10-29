import Foundation
import CoreGraphics

/// Turns recognized text into Pokémon, moves, items, … (German and English).
enum ScanEngine {
    struct MoveHit: Identifiable, Hashable {
        let moveId: Int
        let line: String
        let order: Int
        var id: Int { moveId }
    }

    // MARK: Moves

    static func moves(from lines: [OCRLine], game: Game, pokemonId: Int?) -> [MoveHit] {
        let dex = Dex.shared
        let learnable = pokemonId.map { dex.learnset(for: $0, game: game) } ?? []
        let learnIndex = FuzzyIndex(learnable)
        let allIndex = FuzzyIndex(dex.allMoves(for: game))
        let learnIds = Set(learnable.map(\.id))

        var hits: [MoveHit] = []
        var seen = Set<Int>()
        for (i, line) in lines.enumerated() {
            var found = learnIndex.matches(in: line.text, threshold: 0.72)
            if found.isEmpty {
                found = allIndex.matches(in: line.text, threshold: 0.86)
            }
            for m in found where seen.insert(m.id).inserted {
                hits.append(MoveHit(moveId: m.id, line: line.text, order: i))
            }
        }
        // Moves the Pokémon can actually learn first, keep the screen order otherwise.
        return hits.sorted {
            let a = learnIds.contains($0.moveId), b = learnIds.contains($1.moveId)
            if a != b && learnIds.count > 0 && hits.count > 4 { return a }
            return $0.order < $1.order
        }
    }

    // MARK: Pokémon (summary screen or team screen)

    private static let levelRegex = try? Regex(#"(?i)(?:lv|lvl|nv|level|stufe)\s*\.?\s*:?\s*(\d{1,3})"#)

    static func level(in text: String) -> Int? {
        guard let regex = levelRegex, let m = text.firstMatch(of: regex), m.output.count > 1,
              let sub = m.output[1].substring, let v = Int(sub), (1...100).contains(v) else { return nil }
        return v
    }

    /// - Parameter single: true for one summary screen (everything belongs to one Pokémon).
    static func members(from lines: [OCRLine], game: Game, single: Bool, fallbackPokemonId: Int? = nil) -> [ScannedMember] {
        let dex = Dex.shared
        let speciesIndex = FuzzyIndex(dex.availablePokemon(in: game).map { p -> (id: Int, names: [String]) in
            // also allow the plain species name for forms ("Vulnona" for "Alola-Vulnona")
            (id: p.id, names: [p.de, p.en])
        })
        let itemIndex = FuzzyIndex(dex.items(for: game))
        let abilityIndex = FuzzyIndex(dex.abilities)
        let natureIndex = FuzzyIndex(dex.natures)

        struct Anchor {
            var pokemonId: Int
            var score: Double
            var center: CGPoint
            var lineIndex: Int
        }

        // 1. Find Pokémon names
        var anchors: [Anchor] = []
        var used = Set<Int>()
        for (i, line) in lines.enumerated() {
            guard let m = speciesIndex.best(in: line.text, threshold: 0.8, maxWords: 3) else { continue }
            if let j = anchors.firstIndex(where: { $0.pokemonId == m.id && hypot($0.center.x - line.center.x, $0.center.y - line.center.y) < 0.15 }) {
                if m.score > anchors[j].score { anchors[j] = Anchor(pokemonId: m.id, score: m.score, center: line.center, lineIndex: i) }
                continue
            }
            anchors.append(Anchor(pokemonId: m.id, score: m.score, center: line.center, lineIndex: i))
            used.insert(i)
        }

        if single {
            if let best = anchors.max(by: { $0.score < $1.score }) {
                anchors = [best]
            } else {
                anchors = [Anchor(pokemonId: fallbackPokemonId ?? -1, score: 0, center: CGPoint(x: 0.5, y: 0.5), lineIndex: -1)]
            }
        }
        guard !anchors.isEmpty else { return [] }

        // Sort top-to-bottom, left-to-right (rows with a small tolerance)
        anchors.sort { a, b in
            if abs(a.center.y - b.center.y) > 0.06 { return a.center.y < b.center.y }
            return a.center.x < b.center.x
        }
        anchors = Array(anchors.prefix(6))

        var results = anchors.map { a in
            ScannedMember(pokemonId: a.pokemonId > 0 && a.score > 0 ? a.pokemonId : nil)
        }
        let movePokemon = anchors.map { $0.pokemonId > 0 ? $0.pokemonId : nil }

        func nearest(to p: CGPoint) -> Int {
            if results.count == 1 { return 0 }
            var best = 0
            var bestD = Double.infinity
            for (i, a) in anchors.enumerated() {
                // text usually sits below or right of the name, weight vertical distance a bit more
                let dx = Double(p.x - a.center.x)
                var dy = Double(p.y - a.center.y)
                if dy < 0 { dy *= 2.5 }
                let d = dx * dx + dy * dy * 1.6
                if d < bestD { bestD = d; best = i }
            }
            return best
        }

        // 2. Attach level / item / ability / nature
        for (i, line) in lines.enumerated() {
            let target = nearest(to: line.center)
            if let lv = level(in: line.text), results[target].level == nil {
                results[target].level = lv
                continue
            }
            if single || !used.contains(i) {
                if results[target].itemId == nil, let m = itemIndex.best(in: line.text, threshold: 0.84) {
                    results[target].itemId = m.id
                    continue
                }
                if results[target].abilityId == nil, let m = abilityIndex.best(in: line.text, threshold: 0.84) {
                    let legal = results[target].pokemonId.flatMap { dex.pokemon($0) }.map { dex.abilities(for: $0).map(\.id) }
                    if legal == nil || legal!.contains(m.id) {
                        results[target].abilityId = m.id
                        continue
                    }
                }
                if results[target].natureId == nil, let m = natureIndex.best(in: line.text, threshold: 0.86, maxWords: 2) {
                    results[target].natureId = m.id
                    continue
                }
            }
        }

        // 3. Moves (per Pokémon, using its learnset)
        var moveLines: [Int: [OCRLine]] = [:]
        for (i, line) in lines.enumerated() where !used.contains(i) || single {
            moveLines[nearest(to: line.center), default: []].append(line)
        }
        for (idx, ls) in moveLines {
            guard let pid = movePokemon[idx] else { continue }
            let learn = dex.learnset(for: pid, game: game)
            let index = FuzzyIndex(learn)
            var ids: [Int] = []
            for line in ls {
                for m in index.matches(in: line.text, threshold: 0.8) where !ids.contains(m.id) {
                    ids.append(m.id)
                }
            }
            results[idx].moveIds = Array(ids.prefix(4))
        }
        return results
    }
}
