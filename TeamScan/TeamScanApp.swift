import SwiftUI
import SwiftData

@main
struct TeamScanApp: App {
    @AppStorage("appLanguage") private var language = AppLanguage.system.rawValue

    init() {
        _ = Dex.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(language)
                .environment(\.locale, Lang.current.locale)
        }
        .modelContainer(for: [Team.self, TeamMember.self])
    }
}
