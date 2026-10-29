import SwiftUI

/// All main series games. Raw values are stored in saved teams – never rename existing ones.
enum Game: String, CaseIterable, Identifiable, Codable {
    case rb, y, gs, c, rs, e, frlg, dp, pt, hgss, bw, b2w2, xy, oras, sm, lgpe, swsh, bdsp, pla, sv, za

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rb: return L("Rot / Blau", "Red / Blue")
        case .y: return L("Gelb", "Yellow")
        case .gs: return L("Gold / Silber", "Gold / Silver")
        case .c: return L("Kristall", "Crystal")
        case .rs: return L("Rubin / Saphir", "Ruby / Sapphire")
        case .e: return L("Smaragd", "Emerald")
        case .frlg: return L("Feuerrot / Blattgrün", "FireRed / LeafGreen")
        case .dp: return L("Diamant / Perl", "Diamond / Pearl")
        case .pt: return L("Platin", "Platinum")
        case .hgss: return "HeartGold / SoulSilver"
        case .bw: return L("Schwarz / Weiß", "Black / White")
        case .b2w2: return L("Schwarz 2 / Weiß 2", "Black 2 / White 2")
        case .xy: return "X / Y"
        case .oras: return L("Omega Rubin / Alpha Saphir", "Omega Ruby / Alpha Sapphire")
        case .sm: return L("Sonne / Mond", "Sun / Moon")
        case .lgpe: return L("Let's Go Pikachu / Evoli", "Let's Go Pikachu / Eevee")
        case .swsh: return L("Schwert / Schild", "Sword / Shield")
        case .bdsp: return L("Strahlender Diamant / Leuchtende Perle", "Brilliant Diamond / Shining Pearl")
        case .pla: return L("Legenden: Arceus", "Legends: Arceus")
        case .sv: return L("Karmesin / Purpur", "Scarlet / Violet")
        case .za: return L("Legenden: Z-A", "Legends: Z-A")
        }
    }

    /// Title that fits into a small button: full name when short, otherwise an abbreviation like "HG/SS".
    var compactTitle: String {
        let t = title.replacingOccurrences(of: " / ", with: "/")
        if t.count <= 15 { return t }
        switch self {
        case .frlg: return L("FR/BG", "FR/LG")
        case .hgss: return "HG/SS"
        case .b2w2: return L("S2/W2", "B2/W2")
        case .oras: return "ΩR/αS"
        case .lgpe: return "Let's Go"
        case .bdsp: return L("SD/LP", "BD/SP")
        case .pla: return L("Leg. Arceus", "Leg. Arceus")
        case .za: return "Leg. Z-A"
        case .sv: return L("Karm./Purpur", "Scarlet/Violet")
        case .swsh: return L("Schwert/Schild", "Sword/Shield")
        default: return String(t.prefix(14)) + "…"
        }
    }

    var shortTitle: String {
        switch self {
        case .rb: return L("RB", "RB")
        case .y: return L("Ge", "Y")
        case .gs: return L("GS", "GS")
        case .c: return L("Kr", "C")
        case .rs: return "RS"
        case .e: return L("Sm", "E")
        case .frlg: return L("FrBg", "FRLG")
        case .dp: return "DP"
        case .pt: return "Pt"
        case .hgss: return "HGSS"
        case .bw: return L("SW", "BW")
        case .b2w2: return L("S2W2", "B2W2")
        case .xy: return "XY"
        case .oras: return "ORAS"
        case .sm: return L("SoMo", "SM")
        case .lgpe: return "LGPE"
        case .swsh: return "SwSh"
        case .bdsp: return "BDSP"
        case .pla: return "PLA"
        case .sv: return L("KaPu", "SV")
        case .za: return "Z-A"
        }
    }

    var gen: Int {
        switch self {
        case .rb, .y: return 1
        case .gs, .c: return 2
        case .rs, .e, .frlg: return 3
        case .dp, .pt, .hgss: return 4
        case .bw, .b2w2: return 5
        case .xy, .oras: return 6
        case .sm, .lgpe: return 7
        case .swsh, .bdsp, .pla: return 8
        case .sv, .za: return 9
        }
    }

    /// Latest PokéAPI version group that belongs to this game (incl. DLC / Ultra versions).
    var maxVersionGroup: Int {
        switch self {
        case .rb: return 1
        case .y: return 2
        case .gs: return 3
        case .c: return 4
        case .rs: return 5
        case .e: return 6
        case .frlg: return 7
        case .dp: return 8
        case .pt: return 9
        case .hgss: return 10
        case .bw: return 11
        case .b2w2: return 14
        case .xy: return 15
        case .oras: return 16
        case .sm: return 18
        case .lgpe: return 19
        case .swsh: return 22
        case .bdsp: return 23
        case .pla: return 24
        case .sv: return 27
        case .za: return 31
        }
    }

    static var generations: [(gen: Int, games: [Game])] {
        (1...9).map { g in (g, allCases.filter { $0.gen == g }) }
    }

    // MARK: Mechanics

    var hasMega: Bool { [.xy, .oras, .sm, .lgpe, .za].contains(self) }
    var hasZMoves: Bool { self == .sm }
    var hasDynamax: Bool { self == .swsh }
    var hasTera: Bool { self == .sv }
    var hasHeldItems: Bool { gen >= 2 && self != .lgpe && self != .pla }
    var hasAbilities: Bool { gen >= 3 && self != .lgpe && self != .pla }
    var hasHiddenAbilities: Bool { gen >= 5 && hasAbilities }
    var hasNatures: Bool { gen >= 3 }
    var hasGender: Bool { gen >= 2 }
    var hasShiny: Bool { gen >= 2 }
    /// Classic EVs / IVs (Let's Go uses AVs, Legends: Arceus effort levels, Gen 1–2 stat experience).
    var hasEVs: Bool { gen >= 3 && ![.lgpe, .pla, .za].contains(self) }
    var hasFairy: Bool { gen >= 6 }

    var hasEncounterData: Bool { ![.bdsp, .pla, .sv, .za].contains(self) }
    /// The database only has part of the locations for these games.
    var encounterDataPartial: Bool { self == .oras }
    /// No move lists in the database – all moves of the generation are offered.
    var hasLearnsets: Bool { self != .za }

    var mechanic: String {
        switch self {
        case .xy, .oras, .lgpe, .za: return L("Mega-Entwicklung", "Mega Evolution")
        case .sm: return L("Z-Attacken & Mega", "Z-Moves & Mega")
        case .swsh: return L("Dynamax & Gigadynamax", "Dynamax & Gigantamax")
        case .sv: return L("Terakristallisierung", "Terastallization")
        default: return L("Generation \(gen)", "Generation \(gen)")
        }
    }

    /// Real logo of the battle mechanic (Mega, Z-Moves, Dynamax, Tera).
    var mechanicLogo: Mechanic? {
        switch self {
        case .xy, .oras, .lgpe, .za: return .mega
        case .sm: return .zMove
        case .swsh: return .gmax
        case .sv: return .tera
        default: return nil
        }
    }

    var mechanicIcon: String {
        switch self {
        case .xy, .oras, .lgpe, .za: return "sparkles"
        case .sm: return "bolt.fill"
        case .swsh: return "arrow.up.left.and.arrow.down.right"
        case .sv: return "diamond.fill"
        default: return "gamecontroller.fill"
        }
    }

    var showdownFormat: String { self == .lgpe ? "gen7letsgo" : (self == .bdsp ? "gen8bdsp" : "gen\(gen)") }

    var colors: [Color] {
        switch self {
        case .rb: return [Color(hex: 0xE3350D), Color(hex: 0x3B6BD6)]
        case .y: return [Color(hex: 0xF7C600), Color(hex: 0xE89A00)]
        case .gs: return [Color(hex: 0xC9A227), Color(hex: 0x9AA4B5)]
        case .c: return [Color(hex: 0x4FC3D9), Color(hex: 0x6E7CCC)]
        case .rs: return [Color(hex: 0xD62C3A), Color(hex: 0x2F5FCF)]
        case .e: return [Color(hex: 0x1FAE6B), Color(hex: 0x0E7A55)]
        case .frlg: return [Color(hex: 0xF0642D), Color(hex: 0x4CAF50)]
        case .dp: return [Color(hex: 0x5E9BE8), Color(hex: 0xE58BB8)]
        case .pt: return [Color(hex: 0x8C8F99), Color(hex: 0x4A4E5A)]
        case .hgss: return [Color(hex: 0xE2A72E), Color(hex: 0xA8B4C8)]
        case .bw: return [Color(hex: 0x3A3A3A), Color(hex: 0x9A9A9A)]
        case .b2w2: return [Color(hex: 0x2B4A73), Color(hex: 0xC94A4A)]
        case .xy: return [Color(hex: 0x2F6BFF), Color(hex: 0xE8384F)]
        case .oras: return [Color(hex: 0xC8102E), Color(hex: 0x1D4ED8)]
        case .sm: return [Color(hex: 0xF7A81B), Color(hex: 0x7B4AE2)]
        case .lgpe: return [Color(hex: 0xF5C400), Color(hex: 0xB0703A)]
        case .swsh: return [Color(hex: 0x00A7E1), Color(hex: 0xE5007E)]
        case .bdsp: return [Color(hex: 0x3D8BFF), Color(hex: 0xF27EB0)]
        case .pla: return [Color(hex: 0x3E6E8E), Color(hex: 0xC9A66B)]
        case .sv: return [Color(hex: 0xE4362B), Color(hex: 0x8C3BCB)]
        case .za: return [Color(hex: 0x2BB673), Color(hex: 0x1C6B8A)]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Menu content listing all games grouped by generation.
struct GameMenuItems: View {
    var games: [Game] = Game.allCases
    var counts: [Game: Int]? = nil
    /// tag with the Game itself instead of its raw value
    var asGame = false

    var body: some View {
        ForEach(Game.generations, id: \.gen) { group in
            let list = group.games.filter { games.contains($0) }
            if !list.isEmpty {
                Section("Generation \(group.gen)") {
                    ForEach(list) { game in
                        let label = counts.map { game.title + "  (\($0[game] ?? 0))" } ?? game.title
                        if asGame {
                            Text(label).tag(game)
                        } else {
                            Text(label).tag(game.rawValue)
                        }
                    }
                }
            }
        }
    }
}
