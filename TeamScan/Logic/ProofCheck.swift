import Foundation
import UIKit

/// Reads the proof photo (summary page of the Pokémon) and compares it with the hunt.
/// Not a proof against cheating – it only shows whether the photo fits the hunt.
nonisolated struct ProofCheck: Codable, Equatable {
    enum Status: String, Codable { case verified, mismatch, unchecked }
    enum ItemStatus: String, Codable { case pass, fail, unknown }

    struct Item: Codable, Equatable, Identifiable {
        enum Kind: String, Codable { case pokemon, date, event, ot, id }
        let kind: Kind
        let status: ItemStatus
        /// explanation in both languages
        let de: String
        let en: String
        var id: String { kind.rawValue }
    }

    let status: Status
    let items: [Item]
    let checkedAt: Date
}

extension ShinyHunt {
    var proofCheck: ProofCheck? {
        get { proofCheckData.flatMap { try? JSONDecoder().decode(ProofCheck.self, from: $0) } }
        set { proofCheckData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }
}

enum ProofChecker {
    /// Reads the photo / first video frame and stores the result in the hunt.
    @MainActor
    static func run(for hunt: ShinyHunt) async {
        guard hunt.proofFile != nil else { hunt.proofCheck = nil; return }
        guard let image = await ProofStore.thumbnail(for: hunt),
              let lines = try? await TextScanner.recognize(image) else {
            hunt.proofCheck = ProofCheck(status: .unchecked, items: [], checkedAt: Date())
            return
        }
        hunt.proofCheck = check(lines.map(\.text), hunt: hunt)
    }

    @MainActor
    static func check(_ lines: [String], hunt: ShinyHunt) -> ProofCheck {
        let text = lines.joined(separator: "\n")
        let norm = normalize(text)
        var items: [ProofCheck.Item] = []

        // too little text: probably not a summary page (or a blurry photo / video frame)
        guard lines.count >= 4 else {
            return ProofCheck(status: .unchecked, items: [], checkedAt: Date())
        }

        // 1. Pokémon
        let species = hunt.species
        let names = [species?.de, species?.en].compactMap { $0 }.map(normalize).filter { !$0.isEmpty }
        if names.contains(where: { norm.contains($0) }) {
            items.append(.init(kind: .pokemon, status: .pass, de: "\(hunt.name) erkannt", en: "\(hunt.name) recognised"))
        } else {
            items.append(.init(kind: .pokemon, status: .fail,
                               de: "\(hunt.name) steht nicht auf dem Foto", en: "\(hunt.name) is not on the photo"))
        }

        // 2. Event Pokémon ("fateful encounter")
        let eventWords = ["fatefulencounter", "fateful", "schicksalhaft", "schicksalhafte"]
        if eventWords.contains(where: { norm.contains($0) }) {
            items.append(.init(kind: .event, status: .fail,
                               de: "Event-Pokémon (schicksalhafte Begegnung) – nicht selbst gefangen",
                               en: "Event Pokémon (fateful encounter) – not caught in the wild"))
        } else {
            items.append(.init(kind: .event, status: .pass, de: "Kein Event-Pokémon", en: "Not an event Pokémon"))
        }

        // 3. catch date = find date
        let dates = findDates(in: text)
        let found = hunt.foundAt ?? Date()
        let cal = Calendar.current
        let df = DateFormatter()
        df.dateStyle = .medium
        df.locale = Lang.current.locale
        if dates.isEmpty {
            items.append(.init(kind: .date, status: .unknown, de: "Kein Fangdatum lesbar", en: "No catch date readable"))
        } else if dates.contains(where: { abs(cal.dateComponents([.day], from: cal.startOfDay(for: $0), to: cal.startOfDay(for: found)).day ?? 99) <= 1 }) {
            items.append(.init(kind: .date, status: .pass, de: "Fangdatum passt zum Fund", en: "Catch date matches the find"))
        } else {
            let shown = dates.map { df.string(from: $0) }.joined(separator: ", ")
            let foundText = df.string(from: found)
            items.append(.init(kind: .date, status: .fail,
                               de: "Fangdatum \(shown) – Hunt gefunden am \(foundText)",
                               en: "Catch date \(shown) – hunt found on \(foundText)"))
        }

        // 4. OT name
        let ot = hunt.savegame?.trainerName ?? ""
        if ot.isEmpty {
            items.append(.init(kind: .ot, status: .unknown, de: "OT-Name im Spielstand nicht eingetragen", en: "OT name not entered in the save file"))
        } else if norm.contains(normalize(ot)) {
            items.append(.init(kind: .ot, status: .pass, de: "OT „\(ot)“ passt", en: "OT “\(ot)” matches"))
        } else {
            items.append(.init(kind: .ot, status: .fail, de: "Dein OT „\(ot)“ steht nicht auf dem Foto", en: "Your OT “\(ot)” is not on the photo"))
        }

        // 5. ID No.
        let id = hunt.savegame?.trainerID ?? ""
        if id.isEmpty {
            items.append(.init(kind: .id, status: .unknown, de: "ID-Nr. im Spielstand nicht eingetragen", en: "ID No. not entered in the save file"))
        } else {
            let numbers = idCandidates(in: text)
            if numbers.contains(where: { trimZeros($0) == trimZeros(id) }) {
                items.append(.init(kind: .id, status: .pass, de: "ID-Nr. \(id) passt", en: "ID No. \(id) matches"))
            } else {
                let seen = numbers.isEmpty ? "" : L(" (auf dem Foto: \(numbers.joined(separator: ", ")))", " (on the photo: \(numbers.joined(separator: ", ")))")
                items.append(.init(kind: .id, status: .fail, de: "Deine ID-Nr. \(id) steht nicht auf dem Foto" + seen,
                                   en: "Your ID No. \(id) is not on the photo" + seen))
            }
        }

        let status: ProofCheck.Status
        if items.contains(where: { $0.status == .fail }) {
            status = .mismatch
        } else if items.first(where: { $0.kind == .pokemon })?.status == .pass && items.first(where: { $0.kind == .date })?.status == .pass {
            status = .verified
        } else {
            status = .unchecked
        }
        return ProofCheck(status: status, items: items, checkedAt: Date())
    }

    // MARK: Helpers

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func trimZeros(_ s: String) -> String {
        let t = s.drop { $0 == "0" }
        return t.isEmpty ? "0" : String(t)
    }

    /// 5–6 digit numbers (the ID No. is shown with 5 or 6 digits depending on the game).
    private static func idCandidates(in text: String) -> [String] {
        let regex = /\b([0-9]{5,6})\b/
        var result: [String] = []
        for m in text.matches(of: regex) where !result.contains(String(m.1)) { result.append(String(m.1)) }
        return result
    }

    /// Dates like 01.11.2026, 11/1/2026, 2026/11/01 – day/month order is tried both ways.
    private static func findDates(in text: String) -> [Date] {
        let regex = /\b([0-9]{1,4})[.\/-]([0-9]{1,2})[.\/-]([0-9]{2,4})\b/
        let cal = Calendar(identifier: .gregorian)
        var result: [Date] = []
        func add(_ y: Int, _ m: Int, _ d: Int) {
            var year = y
            if year < 100 { year += 2000 }
            guard (1996...2100).contains(year), (1...12).contains(m), (1...31).contains(d),
                  let date = cal.date(from: DateComponents(year: year, month: m, day: d)) else { return }
            if !result.contains(date) { result.append(date) }
        }
        for match in text.matches(of: regex) {
            guard let a = Int(match.1), let b = Int(match.2), let c = Int(match.3) else { continue }
            if match.1.count == 4 {
                add(a, b, c)            // 2026/11/01
            } else {
                add(c, b, a)            // 01.11.2026 (day first)
                add(c, a, b)            // 11/01/2026 (month first)
            }
        }
        return result
    }
}
