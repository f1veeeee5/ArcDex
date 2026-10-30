import SwiftUI
import SwiftData

@main
struct TeamScanApp: App {
    @AppStorage("appLanguage") private var language = AppLanguage.system.rawValue
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue

    init() {
        _ = Dex.shared
        HuntActivityManager.setUp()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .id(language)
                .environment(\.locale, Lang.current.locale)
                .preferredColorScheme((Appearance(rawValue: appearance) ?? .system).colorScheme)
        }
        .modelContainer(AppData.container)
    }
}
