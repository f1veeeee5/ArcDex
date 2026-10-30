import SwiftUI

struct MainTabView: View {
    @AppStorage("selectedTab") private var tab = 0

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
    }
}
