import SwiftUI
import SwiftData

@main
struct TeamScanApp: App {
    @AppStorage("appLanguage") private var language = AppLanguage.system.rawValue
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @AppStorage("appTheme") private var theme = AppTheme.classic.rawValue

    init() {
        _ = Dex.shared
        HuntActivityManager.setUp()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                // a new language or theme rebuilds the views, so every colour is read again
                .id(language + theme)
                .tint((AppTheme(rawValue: theme) ?? .classic).accent)
                .environment(\.locale, Lang.current.locale)
                .preferredColorScheme((Appearance(rawValue: appearance) ?? .system).colorScheme)
        }
        .modelContainer(AppData.container)
    }
}
