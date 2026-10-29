import Foundation

/// The language the user picked in the settings.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, de, en
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return L("Systemsprache", "System language")
        case .de: return "Deutsch"
        case .en: return "English"
        }
    }
}

/// The language that is actually used for UI texts and Pokémon data.
enum Lang {
    case de, en

    static var current: Lang {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.system.rawValue
        switch AppLanguage(rawValue: raw) ?? .system {
        case .de: return .de
        case .en: return .en
        case .system:
            return (Locale.preferredLanguages.first ?? "en").hasPrefix("de") ? .de : .en
        }
    }

    var locale: Locale { self == .de ? Locale(identifier: "de_DE") : Locale(identifier: "en_US") }
}

/// Picks the German or English text depending on the current language.
func L(_ de: String, _ en: String) -> String {
    Lang.current == .de ? de : en
}

/// Anything with a German and an English name.
protocol Bilingual {
    var de: String { get }
    var en: String { get }
}

extension Bilingual {
    var name: String { Lang.current == .de ? de : en }
    var altName: String { Lang.current == .de ? en : de }
}
