import ActivityKit
import AppIntents
import Foundation

// This file belongs to the app AND the widget extension (Live Activity).
// Keep it free of anything that only exists in the app.

nonisolated struct HuntActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var count: Int
        /// e.g. "1/4096"
        var odds: String
        /// chance (0–1) that the shiny should have appeared by now
        var chance: Double
        /// e.g. "63 % Chance bisher" – already in the language picked in the app
        var chanceText: String
        /// start date for a running timer (already shifted by the time counted before)
        var timerStart: Date?
        /// seconds counted so far (shown when the timer is paused)
        var elapsed: Double
        var phase: Int
    }

    var huntID: String
    var pokemonName: String
    var pokemonId: Int
    var gameTitle: String
    var methodTitle: String
    var unit: String
    var step: Int
    var colorA: UInt32
    var colorB: UInt32
    /// Tiny PNG of the shiny pixel sprite (Live Activities must stay under 4 KB in total).
    var spriteData: Data?
}

/// Lets the app react to the buttons on the Live Activity. The app sets the handler on launch.
enum HuntIntentBridge {
    nonisolated(unsafe) static var handler: ((String, Int) async -> Void)?
}

/// +1 / −1 button on the Lock Screen and in the Dynamic Island.
/// Because this intent is part of the app too, iOS runs it inside the app, which updates the hunt.
struct HuntCountIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Shiny-Zähler ändern"
    static let isDiscoverable = false
    /// Counting must work on the locked Lock Screen – no Face ID / passcode needed.
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    /// Never open the app for a button press.
    static let openAppWhenRun = false

    @Parameter(title: "Hunt")
    var huntID: String

    @Parameter(title: "Amount")
    var amount: Int

    init() {}

    init(huntID: String, amount: Int) {
        self.huntID = huntID
        self.amount = amount
    }

    func perform() async throws -> some IntentResult {
        await HuntIntentBridge.handler?(huntID, amount)
        return .result()
    }
}
