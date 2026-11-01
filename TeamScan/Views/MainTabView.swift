import SwiftUI

struct MainTabView: View {
    @AppStorage("selectedTab") private var tab = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var receivedRun: ReceivedRun?
    @State private var receivedBackup: LoadedBackup?

    var body: some View {
        TabView(selection: $tab) {
            Tab(L("Spielstände", "Saves"), systemImage: "square.grid.2x2.fill", value: 0) {
                RootView()
            }
            Tab("Pokédex", systemImage: "book.closed.fill", value: 1) {
                PokedexView()
            }
            Tab(L("Spiele", "Games"), systemImage: "map.fill", value: 3) {
                GamesView()
            }
            // the "search" role puts the tab in its own bubble on the right side of the tab bar
            Tab(L("Profil", "Profile"), systemImage: "person.crop.circle.fill", value: 2, role: .search) {
                ProfileView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onOpenURL { url in
            // an .arcdex file sent by the partner (AirDrop, WhatsApp, Files …)
            guard url.isFileURL else { return }
            if url.pathExtension.lowercased() == "arcdexbackup", let backup = Backup.read(url) {
                receivedBackup = LoadedBackup(backup: backup)
            } else if let run = RunTransfer.read(url) {
                tab = 0
                receivedRun = ReceivedRun(run: run)
            } else if let backup = Backup.read(url) {
                receivedBackup = LoadedBackup(backup: backup)
            }
        }
        .sheet(item: $receivedBackup) { item in
            BackupRestoreSheet(backup: item.backup) { receivedBackup = nil }
        }
        .sheet(item: $receivedRun) { item in
            RunImportSheet(run: item.run) { _ in receivedRun = nil }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { HuntActivityManager.syncAll() }
        }
    }
}

struct ReceivedRun: Identifiable {
    let id = UUID()
    let run: RunExport
}
