import SwiftUI
import SwiftData

/// Profile tab: name, avatar and numbers of the active profile, switching between local profiles, settings.
struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query private var everySave: [Savegame]
    @AppStorage(ProfileStore.key) private var activeProfile = ""

    @State private var editingName = false
    @State private var nameDraft = ""
    @State private var showAvatars = false
    @State private var deleting: UserProfile?

    private var profile: UserProfile? { profiles.first { $0.uuid.uuidString == activeProfile } ?? profiles.first }

    private func saves(of p: UserProfile) -> [Savegame] {
        everySave.filter { $0.profileID == p.uuid }
    }

    var body: some View {
        NavigationStack {
            List {
                if let profile {
                    Section {
                        header(profile)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    Section {
                        stats(profile)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }

                Section {
                    ForEach(profiles) { p in
                        profileRow(p)
                            .swipeActions {
                                if profiles.count > 1 {
                                    Button(role: .destructive) { deleting = p } label: { Label(L("Löschen", "Delete"), systemImage: "trash") }
                                }
                            }
                    }
                    Button {
                        addProfile()
                    } label: {
                        Label(L("Neues Profil", "New profile"), systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text(L("Profile auf diesem iPhone", "Profiles on this iPhone"))
                } footer: {
                    Text(L("Jedes Profil hat eigene Spielstände, Teams und Hunts. Pokédex-Favoriten und Einstellungen gelten für alle.",
                           "Each profile has its own save files, teams and hunts. Pokédex favourites and settings are shared."))
                }

                Section {
                    NavigationLink {
                        SettingsView(showsDone: false, embedded: true)
                    } label: {
                        Label(L("Einstellungen", "Settings"), systemImage: "gearshape.fill")
                    }
                }
            }
            .navigationTitle(L("Profil", "Profile"))
            .alert(L("Anzeigename", "Display name"), isPresented: $editingName) {
                TextField(L("Name", "Name"), text: $nameDraft)
                Button(L("Sichern", "Save")) {
                    profile?.name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    try? context.save()
                }
                Button(L("Abbrechen", "Cancel"), role: .cancel) {}
            }
            .sheet(isPresented: $showAvatars) {
                if let profile { AvatarPicker(profile: profile) }
            }
            .confirmationDialog(L("Profil löschen?", "Delete profile?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible, presenting: deleting) { p in
                Button(L("\(p.displayName) und alle Spielstände löschen", "Delete \(p.displayName) and all save files"), role: .destructive) {
                    delete(p)
                }
            } message: { p in
                Text(L("\(saves(of: p).count) Spielstände mit allen Teams und Hunts werden gelöscht. Das kann nicht rückgängig gemacht werden.",
                       "\(saves(of: p).count) save files with all teams and hunts will be deleted. This can't be undone."))
            }
        }
    }

    // MARK: Header

    private func header(_ p: UserProfile) -> some View {
        VStack(spacing: 6) {
            Button { showAvatars = true } label: {
                ZStack(alignment: .bottom) {
                    BattlePlatform(colors: [Color.appAccent])
                        .frame(width: 150, height: 40)
                        .padding(.bottom, 4)
                    TrainerSprite(avatar: p.avatar)
                        .frame(width: 140, height: 140)
                        .padding(.bottom, 14)
                }
                .frame(height: 170)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "pencil")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.appAccent, in: Circle())
                        .offset(x: -6, y: 10)
                }
            }
            .buttonStyle(.plain)

            Button {
                nameDraft = p.name
                editingName = true
            } label: {
                HStack(spacing: 6) {
                    Text(p.displayName).font(.title.weight(.bold)).foregroundStyle(.primary)
                    Image(systemName: "pencil").font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                }
            }
            .buttonStyle(.plain)
            Text(L("Trainer seit \(p.createdAt.formatted(.dateTime.month(.wide).year()))",
                   "Trainer since \(p.createdAt.formatted(.dateTime.month(.wide).year()))"))
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func stats(_ p: UserProfile) -> some View {
        let list = saves(of: p)
        let normal = list.filter { !$0.mode.isRun }
        let teams = normal.reduce(0) { $0 + $1.teams.count }
        let shinies = list.reduce(0) { $0 + $1.foundHunts.count }
        let runs = list.filter { $0.mode.isRun }.count
        return HStack(spacing: 10) {
            statTile("\(list.count)", L("Spielstände", "Saves"), icon: "square.grid.2x2.fill")
            statTile("\(teams)", "Teams", icon: "person.3.fill")
            statTile("\(shinies)", "Shinys", icon: "sparkles")
            statTile("\(runs)", "Runs", icon: "flag.fill")
        }
    }

    private func statTile(_ value: String, _ title: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
            Text(verbatim: value).font(.title3.weight(.bold).monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .card()
    }

    // MARK: Profiles

    private func profileRow(_ p: UserProfile) -> some View {
        let active = p.uuid.uuidString == activeProfile
        return Button {
            withAnimation(.snappy) { ProfileStore.activate(p) }
        } label: {
            HStack(spacing: 12) {
                TrainerSprite(avatar: p.avatar)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.displayName).font(.body.weight(active ? .semibold : .regular)).foregroundStyle(.primary)
                    Text(L("\(saves(of: p).count) Spielstände", "\(saves(of: p).count) save files"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if active {
                    Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addProfile() {
        let p = UserProfile(name: L("Profil \(profiles.count + 1)", "Profile \(profiles.count + 1)"),
                            avatar: ProfileStore.avatars.randomElement() ?? "red")
        context.insert(p)
        try? context.save()
        withAnimation(.snappy) { ProfileStore.activate(p) }
    }

    private func delete(_ p: UserProfile) {
        for s in saves(of: p) { context.delete(s) }
        let wasActive = p.uuid.uuidString == activeProfile
        context.delete(p)
        try? context.save()
        if wasActive, let next = profiles.first(where: { $0.uuid != p.uuid }) {
            ProfileStore.activate(next)
        }
        deleting = nil
    }
}

/// Grid of trainer sprites to pick the avatar.
struct AvatarPicker: View {
    @Bindable var profile: UserProfile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                    ForEach(ProfileStore.avatars, id: \.self) { name in
                        let selected = profile.avatar == name
                        Button {
                            profile.avatar = name
                            dismiss()
                        } label: {
                            TrainerSprite(avatar: name)
                                .frame(width: 76, height: 76)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(selected ? Color.appAccent.opacity(0.15) : Color(.secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(Color.appAccent, lineWidth: selected ? 2 : 0)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L("Avatar wählen", "Choose avatar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
            }
        }
    }
}
