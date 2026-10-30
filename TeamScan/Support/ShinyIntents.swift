import AppIntents
import SwiftData

/// "Shiny +1" for the Action Button (and the Shortcuts app): counts the shiny hunt you used last.
struct ShinyCountUpIntent: AppIntent {
    static let title: LocalizedStringResource = "Shiny +1"
    static let description = IntentDescription("Zählt beim zuletzt benutzten Shiny-Hunt eins hoch (bzw. um den eingestellten Schritt).")
    static let openAppWhenRun = false
    /// works with a locked iPhone, too
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let hunt = HuntActivityManager.currentHunt() else {
            return .result(dialog: IntentDialog(stringLiteral: L("Kein aktiver Shiny-Hunt", "No active shiny hunt")))
        }
        hunt.add(hunt.step)
        try? AppData.container.mainContext.save()
        await HuntActivityManager.updateAndWait(hunt)
        return .result(dialog: IntentDialog(stringLiteral: "\(hunt.name): \(hunt.count)"))
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
