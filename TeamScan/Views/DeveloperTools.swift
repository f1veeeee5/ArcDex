#if DEBUG
import SwiftUI
import SwiftData

/// Test helpers – only in builds from Xcode (Debug), never in the App Store version.
struct DeveloperSection: View {
    @Environment(\.modelContext) private var context
    @State private var message: String?

    var body: some View {
        Section {
            Button { createFoundHunt() } label: {
                Label(L("Test-Shiny anlegen (gefunden)", "Create test shiny (found)"), systemImage: "sparkles")
            }
            Button { shiftLatestFind(hours: -23.5) } label: {
                Label(L("Letzten Fund 23,5 Std. zurückdatieren", "Move last find back 23.5 h"), systemImage: "clock.arrow.circlepath")
            }
            Button { shiftLatestFind(hours: -25) } label: {
                Label(L("Letzten Fund 25 Std. zurückdatieren", "Move last find back 25 h"), systemImage: "clock.badge.xmark")
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text(L("Entwickler", "Developer"))
        } footer: {
            Text(L("Nur in Test-Versionen aus Xcode sichtbar. Der Test-Shiny landet im aktiven Profil.",
                   "Only visible in test builds from Xcode. The test shiny goes into the active profile."))
        }
    }

    private func createFoundHunt() {
        let saves = ((try? context.fetch(FetchDescriptor<Savegame>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? [])
            .filter { $0.profileID == ProfileStore.activeID && $0.game.hasShinyHunting && !$0.mode.isRun }
        let save: Savegame
        if let first = saves.first {
            save = first
        } else {
            save = Savegame(game: .swsh, name: L("Test", "Test"))
            context.insert(save)
        }
        let candidates = Dex.shared.availablePokemon(in: save.game)
        let id = candidates.randomElement()?.id ?? 25
        let hunt = ShinyHunt(pokemonId: id, method: .encounter)
        context.insert(hunt)
        hunt.savegame = save
        hunt.count = Int.random(in: 300...6000)
        hunt.elapsed = Double.random(in: 1800...30000)
        hunt.startedAt = Date().addingTimeInterval(-hunt.elapsed - 600)
        hunt.foundAt = Date()
        hunt.updatedAt = Date()
        save.touch()
        try? context.save()
        message = L("\(hunt.name) in „\(save.displayName)“ angelegt.", "\(hunt.name) created in “\(save.displayName)”.")
    }

    private func shiftLatestFind(hours: Double) {
        let found = ((try? context.fetch(FetchDescriptor<ShinyHunt>())) ?? [])
            .filter { $0.foundAt != nil && $0.savegame?.profileID == ProfileStore.activeID }
            .sorted { ($0.foundAt ?? .distantPast) > ($1.foundAt ?? .distantPast) }
        guard let hunt = found.first else { message = L("Kein gefundener Hunt.", "No found hunt."); return }
        hunt.foundAt = Date().addingTimeInterval(hours * 3600)
        try? context.save()
        message = L("Fund von \(hunt.name) verschoben.", "Find of \(hunt.name) moved.")
    }
}

extension ProofStore {
    /// A made-up "console screen" photo for testing without a camera.
    @MainActor
    static func mockImage(for hunt: ShinyHunt) -> UIImage {
        let view = ZStack {
            LinearGradient(colors: [Color(hex: 0x1B1F3B), Color(hex: 0x3A2B5C)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 60)).foregroundStyle(.yellow)
                Text(hunt.name).font(.system(size: 44, weight: .bold)).foregroundStyle(.white)
                Text("TEST-FOTO · \(Date().formatted(.dateTime.hour().minute().second()))")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: 800, height: 450)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.uiImage ?? UIImage()
    }
}
#endif
