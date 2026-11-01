import SwiftUI

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
