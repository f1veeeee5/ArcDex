import AppIntents
import SwiftData

/// "Shiny +1" for the Action Button (and the Shortcuts app): counts the shiny hunt you used last.
struct ShinyCountUpIntent: AppIntent {
    static let title: LocalizedStringResource = "Shiny +1"
    static let description = IntentDescription("Zählt beim zuletzt benutzten Shiny-Hunt eins hoch (bzw. um den eingestellten Schritt).")
    static let openAppWhenRun = false
    /// works with a locked iPhone, too
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    /// No dialog: a dialog would have to be closed with "Done" before the next press.
    /// The Lock Screen counter (Live Activity) shows the new number instead.
    @MainActor
    func perform() async throws -> some IntentResult {
        guard let hunt = HuntActivityManager.currentHunt() else { return .result() }
        hunt.add(hunt.step)
        try? AppData.container.mainContext.save()
        await HuntActivityManager.updateAndWait(hunt)
        return .result()
    }
}

struct ArcDexShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ShinyCountUpIntent(),
                    phrases: ["\(.applicationName) Shiny plus eins", "Shiny +1 in \(.applicationName)"],
                    shortTitle: "Shiny +1",
                    systemImageName: "sparkles")
    }
}
