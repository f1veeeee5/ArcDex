import ActivityKit
import SwiftData
import UIKit

/// The one database of the app – shared with the Live Activity buttons, which run inside the app.
enum AppData {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Team.self, TeamMember.self, FavoritePokemon.self, Savegame.self, ShinyHunt.self)
        } catch {
            fatalError("Could not open the database: \(error)")
        }
    }()
}

/// Starts, updates and ends the shiny counter on the Lock Screen / Dynamic Island.
enum HuntActivityManager {
    static func setUp() {
        HuntIntentBridge.handler = { id, amount in
            // awaited completely: iOS suspends the app again right after the button action,
            // so the Lock Screen must be updated before the action returns
            await handleButton(huntID: id, amount: amount)
        }
    }

    private static func activities(for hunt: ShinyHunt) -> [Activity<HuntActivityAttributes>] {
        let id = hunt.uuid.uuidString
        return Activity<HuntActivityAttributes>.activities.filter { $0.attributes.huntID == id }
    }

    static func isRunning(_ hunt: ShinyHunt) -> Bool { !activities(for: hunt).isEmpty }

    private static func state(_ hunt: ShinyHunt) -> HuntActivityAttributes.ContentState {
        let odds = hunt.odds
        let chance = odds.cumulative(after: hunt.count)
        let percent = chance > 0 && chance < 0.001
            ? "< 0,1 %"
            : chance.formatted(.percent.precision(.fractionLength(chance < 0.1 ? 1 : 0)).locale(Lang.current.locale))
        return .init(count: hunt.count,
                     odds: odds.label(at: hunt.count),
                     chance: chance,
                     chanceText: L("\(percent) Chance bisher", "\(percent) chance so far"),
                     timerStart: hunt.timerStartedAt.map { $0.addingTimeInterval(-hunt.elapsed) },
                     elapsed: hunt.totalTime(),
                     phase: hunt.phases.count + 1)
    }

    /// Returns an error text when the Live Activity can't be shown.
    @discardableResult
    static func start(_ hunt: ShinyHunt) -> String? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return L("Live-Aktivitäten sind für ArcDex ausgeschaltet (Einstellungen → ArcDex → Live-Aktivitäten).",
                     "Live Activities are turned off for ArcDex (Settings → ArcDex → Live Activities).")
        }
        guard !isRunning(hunt) else { return nil }
        let game = hunt.game
        let attributes = HuntActivityAttributes(
            huntID: hunt.uuid.uuidString,
            pokemonName: hunt.name,
            pokemonId: hunt.pokemonId,
            gameTitle: game.compactTitle,
            methodTitle: hunt.method.title,
            unit: hunt.method.unit,
            step: hunt.step,
            colorA: game.colorHexes.first ?? 0xF5C400,
            colorB: game.colorHexes.last ?? 0xE5007E,
            spriteData: spriteData(for: hunt))
        do {
            _ = try Activity.request(attributes: attributes, content: .init(state: state(hunt), staleDate: nil))
            return nil
        } catch where attributes.spriteData != nil {
            // e.g. too much data – try once more without the picture
            var plain = attributes
            plain.spriteData = nil
            do {
                _ = try Activity.request(attributes: plain, content: .init(state: state(hunt), staleDate: nil))
                return nil
            } catch {
                return L("Konnte nicht gestartet werden: \(error.localizedDescription)", "Could not start: \(error.localizedDescription)")
            }
        } catch {
            return L("Konnte nicht gestartet werden: \(error.localizedDescription)", "Could not start: \(error.localizedDescription)")
        }
    }

    static func update(_ hunt: ShinyHunt) {
        let list = activities(for: hunt)
        guard !list.isEmpty else { return }
        let content = ActivityContent(state: state(hunt), staleDate: nil)
        for activity in list {
            Task { await activity.update(content) }
        }
    }

    /// Settings like method or step size are fixed in a running Live Activity – restart it.
    static func restartIfNeeded(_ hunt: ShinyHunt) {
        guard isRunning(hunt) else { return }
        let list = activities(for: hunt)
        Task {
            for activity in list { await activity.end(nil, dismissalPolicy: .immediate) }
            await MainActor.run { _ = start(hunt) }
        }
    }

    static func end(hunt: ShinyHunt) {
        for activity in activities(for: hunt) {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    static func end(huntsOf save: Savegame) {
        for hunt in save.hunts { end(hunt: hunt) }
    }

    /// Called when a button on the Live Activity is pressed (also on the locked Lock Screen).
    private static func handleButton(huntID: String, amount: Int) async {
        guard let uuid = UUID(uuidString: huntID) else { return }
        let context = AppData.container.mainContext
        let descriptor = FetchDescriptor<ShinyHunt>(predicate: #Predicate { $0.uuid == uuid })
        let list = Activity<HuntActivityAttributes>.activities.filter { $0.attributes.huntID == huntID }
        guard let hunt = try? context.fetch(descriptor).first else {
            // the hunt was deleted – remove its leftover Live Activity
            for activity in list { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        hunt.add(amount)
        try? context.save()
        let content = ActivityContent(state: state(hunt), staleDate: nil)
        for activity in list { await activity.update(content) }
    }

    /// Brings every running Live Activity up to date (e.g. when the app comes back to the foreground).
    static func syncAll() {
        let context = AppData.container.mainContext
        let hunts = (try? context.fetch(FetchDescriptor<ShinyHunt>())) ?? []
        for activity in Activity<HuntActivityAttributes>.activities {
            if let hunt = hunts.first(where: { $0.uuid.uuidString == activity.attributes.huntID }), !hunt.isFound {
                let content = ActivityContent(state: state(hunt), staleDate: nil)
                Task { await activity.update(content) }
            } else {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
        }
    }

    private static func pixelURL(for hunt: ShinyHunt) -> URL? {
        SpriteURLs.pokemon(hunt.pokemonId, shiny: true, style: .pixel).first
    }

    /// Loads the pixel sprite ahead of time, so the Live Activity can start instantly.
    static func prepareSprite(for hunt: ShinyHunt) async {
        guard let url = pixelURL(for: hunt) else { return }
        _ = await ImageCache.shared.image(for: url)
    }

    /// Small, cropped PNG of the shiny pixel sprite.
    private static func spriteData(for hunt: ShinyHunt) -> Data? {
        guard let url = pixelURL(for: hunt), let image = ImageCache.shared.cached(url),
              let cg = image.cgImage else { return nil }
        let cropped = cg.croppedToContent() ?? cg
        // Live Activities may only carry about 4 KB in total – keep the picture small
        for side in [44, 36, 28] {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
            let data = renderer.pngData { ctx in
                ctx.cgContext.interpolationQuality = .none
                let w = CGFloat(cropped.width), h = CGFloat(cropped.height)
                let scale = CGFloat(side) / max(w, h)
                let rect = CGRect(x: (CGFloat(side) - w * scale) / 2, y: (CGFloat(side) - h * scale) / 2, width: w * scale, height: h * scale)
                UIImage(cgImage: cropped).draw(in: rect)
            }
            if data.count <= 2000 { return data }
        }
        return nil
    }
}

private extension CGImage {
    /// Crops away transparent borders.
    func croppedToContent() -> CGImage? {
        let w = width, h = height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(self, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 8 {
                minX = Swift.min(minX, x); maxX = Swift.max(maxX, x)
                minY = Swift.min(minY, y); maxY = Swift.max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }
}
