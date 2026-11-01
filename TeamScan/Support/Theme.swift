import SwiftUI

// MARK: - Themes
//
// To rename a theme, change its name in `title` below (German first, then English).
// To add one: add a case, a name in `title` and the two colours in `accent`.

enum AppTheme: String, CaseIterable, Identifiable {
    case classic, purple, ocean

    var id: String { rawValue }

    /// Name shown in the settings.
    var title: String {
        switch self {
        case .classic: return L("Klassisch", "Classic")
        case .purple: return L("Lila", "Purple")
        case .ocean: return L("Ozean", "Ocean")
        }
    }

    /// Accent colour: buttons, tab bar, links, selections. (light mode, dark mode)
    var accent: Color {
        switch self {
        case .classic: return .dynamic(light: (0.910, 0.220, 0.310), dark: (1.000, 0.380, 0.440))
        case .purple: return .dynamic(light: (0.486, 0.302, 0.949), dark: (0.690, 0.561, 1.000))
        case .ocean: return .dynamic(light: (0.000, 0.533, 0.737), dark: (0.290, 0.776, 0.949))
        }
    }

    /// The theme that is selected in the settings.
    static var current: AppTheme {
        AppTheme(rawValue: UserDefaults.standard.string(forKey: "appTheme") ?? "") ?? .classic
    }
}

extension Color {
    /// Accent colour of the selected theme.
    static var appAccent: Color { AppTheme.current.accent }

    /// A colour with its own value for light and dark mode (RGB 0…1).
    static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

/// Theme choice in the settings: one coloured circle per theme.
struct ThemePicker: View {
    @AppStorage("appTheme") private var themeRaw = AppTheme.classic.rawValue

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTheme.allCases) { theme in
                let selected = theme.rawValue == themeRaw
                Button {
                    withAnimation(.snappy) { themeRaw = theme.rawValue }
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle().fill(theme.accent.gradient).frame(width: 44, height: 44)
                            if selected {
                                Image(systemName: "checkmark").font(.headline.weight(.bold)).foregroundStyle(.white)
                            }
                        }
                        .overlay {
                            Circle().strokeBorder(theme.accent, lineWidth: 2).padding(-5).opacity(selected ? 1 : 0)
                        }
                        Text(theme.title)
                            .font(.caption.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .sensoryFeedback(.selection, trigger: themeRaw)
    }
}

// MARK: - Buttons
//
// All buttons of the app use these two styles, so a later theme only has to change them here.
// The colour comes from the environment tint (`.tint(...)`, by default the app's accent colour) –
// a theme can set a different tint for the whole app.

/// Filled capsule for the main action of a screen or card ("Use set", "Calculate damage").
/// Soft capsule (tinted fill, tinted text) for everything else.
struct AppButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    var kind: Kind

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        let vertical: CGFloat = switch controlSize {
        case .mini, .small: 6
        case .large, .extraLarge: 14
        default: 10
        }
        configuration.label
            .font(controlSize == .large || controlSize == .extraLarge ? .headline : .subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.vertical, vertical)
            .padding(.horizontal, controlSize == .small || controlSize == .mini ? 12 : 16)
            .foregroundStyle(kind == .primary ? AnyShapeStyle(Color.white) : AnyShapeStyle(.tint))
            .background {
                switch kind {
                case .primary: Capsule().fill(.tint)
                case .secondary: Capsule().fill(.tint.opacity(0.15))
                }
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    /// Main action: filled capsule in the tint colour.
    static var appPrimary: AppButtonStyle { AppButtonStyle(kind: .primary) }
    /// Other actions: soft capsule in the tint colour.
    static var appSecondary: AppButtonStyle { AppButtonStyle(kind: .secondary) }
}

/// Small icon button without any background (e.g. the "+" next to a section title).
struct AppIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.tint)
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AppIconButtonStyle {
    /// Icon only, no capsule behind it.
    static var appIcon: AppIconButtonStyle { AppIconButtonStyle() }
}
