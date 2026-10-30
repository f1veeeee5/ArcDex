import SwiftUI

struct MainTabView: View {
    @AppStorage("selectedTab") private var tab = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $tab) {
            Tab(L("Spielstände", "Saves"), systemImage: "square.grid.2x2.fill", value: 0) {
                RootView()
            }
            Tab("Pokédex", systemImage: "book.closed.fill", value: 1) {
                PokedexView()
            }
            Tab(L("Einstellungen", "Settings"), systemImage: "gearshape.fill", value: 2) {
                SettingsView(showsDone: false)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { HuntActivityManager.syncAll() }
        }
    }
}
