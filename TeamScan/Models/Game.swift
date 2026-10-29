import SwiftUI

enum Game: String, CaseIterable, Identifiable, Codable {
    case xy, sm, swsh, sv

    var id: String { rawValue }

    var title: String {
        switch self {
        case .xy: return "X / Y"
        case .sm: return L("Sonne / Mond", "Sun / Moon")
        case .swsh: return L("Schwert / Schild", "Sword / Shield")
        case .sv: return L("Karmesin / Purpur", "Scarlet / Violet")
        }
    }

    var shortTitle: String {
        switch self {
        case .xy: return "XY"
        case .sm: return L("SoMo", "SM")
        case .swsh: return "SwSh"
        case .sv: return L("KaPu", "SV")
        }
    }

    var gen: Int {
        switch self {
        case .xy: return 6
        case .sm: return 7
        case .swsh: return 8
        case .sv: return 9
        }
    }

    /// Latest PokéAPI version group that belongs to this game (incl. DLC / Ultra versions).
    var maxVersionGroup: Int {
        switch self {
        case .xy: return 15
        case .sm: return 18
        case .swsh: return 22
        case .sv: return 27
        }
    }

    var hasMega: Bool { self == .xy || self == .sm }
    var hasZMoves: Bool { self == .sm }
    var hasDynamax: Bool { self == .swsh }
    var hasTera: Bool { self == .sv }

    var mechanic: String {
        switch self {
        case .xy: return L("Mega-Entwicklung", "Mega Evolution")
        case .sm: return L("Z-Attacken & Mega", "Z-Moves & Mega")
        case .swsh: return L("Dynamax & Gigadynamax", "Dynamax & Gigantamax")
        case .sv: return L("Terakristallisierung", "Terastallization")
        }
    }

    var mechanicIcon: String {
        switch self {
        case .xy: return "sparkles"
        case .sm: return "bolt.fill"
        case .swsh: return "arrow.up.left.and.arrow.down.right"
        case .sv: return "diamond.fill"
        }
    }

    var showdownFormat: String { "gen\(gen)" }

    var colors: [Color] {
        switch self {
        case .xy: return [Color(hex: 0x2F6BFF), Color(hex: 0xE8384F)]
        case .sm: return [Color(hex: 0xF7A81B), Color(hex: 0x7B4AE2)]
        case .swsh: return [Color(hex: 0x00A7E1), Color(hex: 0xE5007E)]
        case .sv: return [Color(hex: 0xE4362B), Color(hex: 0x8C3BCB)]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
