import Foundation

enum Fuzzy {
    /// Lowercase, no accents, only letters and digits. "Donner-Blitz " -> "donnerblitz"
    static func normalize(_ s: String) -> String {
        let folded = s.replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "♀", with: "f")
            .replacingOccurrences(of: "♂", with: "m")
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// Fixes common OCR mix-ups before matching.
    static func ocrClean(_ s: String) -> String {
        s.replacingOccurrences(of: "0", with: "o")
            .replacingOccurrences(of: "1", with: "l")
            .replacingOccurrences(of: "5", with: "s")
    }

    static func distance(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar], limit: Int) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            var rowMin = cur[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = Swift.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                rowMin = Swift.min(rowMin, cur[j])
            }
            if rowMin > limit { return limit + 1 }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    static func similarity(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar], minimum: Double) -> Double {
        let maxLen = Swift.max(a.count, b.count)
        guard maxLen > 0 else { return 0 }
        let limit = Int((1 - minimum) * Double(maxLen))
        if abs(a.count - b.count) > limit { return 0 }
        let d = distance(a, b, limit: limit)
        return 1 - Double(d) / Double(maxLen)
    }
}

/// A searchable list of names (German + English) for fuzzy OCR matching.
struct FuzzyIndex {
    struct Entry {
        let id: Int
        let scalars: [Unicode.Scalar]
    }

    struct Match {
        let id: Int
        let score: Double
        let wordRange: Range<Int>
    }

    let entries: [Entry]

    init(_ items: [(id: Int, names: [String])]) {
        var list: [Entry] = []
        for item in items {
            var seen = Set<String>()
            for n in item.names {
                let norm = Fuzzy.normalize(n)
                guard norm.count >= 3, seen.insert(norm).inserted else { continue }
                list.append(Entry(id: item.id, scalars: Array(norm.unicodeScalars)))
            }
        }
        entries = list
    }

    init<T: Bilingual & Identifiable>(_ items: [T]) where T.ID == Int {
        self.init(items.map { (id: $0.id, names: [$0.de, $0.en]) })
    }

    /// Finds all non-overlapping matches in one OCR line.
    func matches(in text: String, threshold: Double, maxWords: Int = 4) -> [Match] {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0 == "|" || $0 == "/" }).map(String.init)
        guard !words.isEmpty else { return [] }
        var candidates: [Match] = []
        for start in 0..<words.count {
            for len in 1...Swift.min(maxWords, words.count - start) {
                let joined = Fuzzy.normalize(words[start..<start + len].joined())
                guard joined.count >= 3 else { continue }
                let variants = [joined, Fuzzy.ocrClean(joined)].uniqued()
                var best: (Int, Double)?
                for variant in variants {
                    let w = Array(variant.unicodeScalars)
                    for e in entries {
                        // very short names must match exactly
                        let needed = e.scalars.count <= 4 ? 1.0 : threshold
                        let s = Fuzzy.similarity(w, e.scalars, minimum: needed)
                        if s >= needed && s > (best?.1 ?? 0) {
                            best = (e.id, s)
                        }
                    }
                }
                if let best {
                    candidates.append(Match(id: best.0, score: best.1 + Double(len) * 0.001, wordRange: start..<start + len))
                }
            }
        }
        var picked: [Match] = []
        for c in candidates.sorted(by: { $0.score > $1.score }) {
            if picked.contains(where: { $0.wordRange.overlaps(c.wordRange) || $0.id == c.id }) { continue }
            picked.append(c)
        }
        return picked.sorted { $0.wordRange.lowerBound < $1.wordRange.lowerBound }
    }

    func best(in text: String, threshold: Double, maxWords: Int = 4) -> Match? {
        matches(in: text, threshold: threshold, maxWords: maxWords).max { $0.score < $1.score }
    }
}
