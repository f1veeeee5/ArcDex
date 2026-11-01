import Foundation
import SwiftData

/// A local profile on this iPhone: its own name, avatar and save files (like profiles in a streaming app).
/// Later, with iCloud, a profile can become a synced account.
@Model
final class UserProfile {
    var uuid: UUID = UUID()
    var name: String = ""
    /// Pokémon Showdown trainer sprite name
    var avatar: String = "red"
    var createdAt: Date = Date()

    init(name: String, avatar: String = "red") {
        self.name = name
        self.avatar = avatar
    }

    var displayName: String { name.isEmpty ? L("Trainer", "Trainer") : name }
}

enum ProfileStore {
    nonisolated static let key = "activeProfile"

    /// Id of the profile that is active right now.
    nonisolated static var activeID: UUID? {
        UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    static func activate(_ profile: UserProfile) {
        UserDefaults.standard.set(profile.uuid.uuidString, forKey: key)
    }

    /// Trainer sprites to choose from (names checked against Pokémon Showdown's avatar list).
    static let avatars = [
        "red", "ethan", "lyra", "kris", "brendan", "may", "lucas", "dawn", "hilbert", "hilda", "nate", "rosa",
        "calem", "serena", "elio", "selene", "victor", "gloria", "chase", "elaine",
        "cynthia", "steven", "lillie", "gladion", "hau", "penny",
        "leon", "hop", "marnie", "bede", "raihan", "nessa", "kabu", "milo", "bea", "allister", "opal", "piers",
    ]

    /// First launch with profiles: make sure one exists and give it all save files of older app versions.
    @MainActor
    static func migrate(_ context: ModelContext) {
        var profiles = (try? context.fetch(FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        if profiles.isEmpty {
            let first = UserProfile(name: "")
            context.insert(first)
            profiles = [first]
        }
        if activeID == nil || !profiles.contains(where: { $0.uuid == activeID }) {
            activate(profiles[0])
        }
        let saves = (try? context.fetch(FetchDescriptor<Savegame>())) ?? []
        for save in saves where save.profileID == nil || !profiles.contains(where: { $0.uuid == save.profileID }) {
            save.profileID = activeID
        }
        try? context.save()
    }
}
