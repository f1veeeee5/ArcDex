import SwiftUI
import CryptoKit

/// What can be protected by the delete password.
enum ProtectedArea: String, CaseIterable, Identifiable {
    case saves, hunts, teams, profiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .saves: return L("Spielstände & Runs löschen", "Deleting save files & runs")
        case .hunts: return L("Shiny-Hunts löschen", "Deleting shiny hunts")
        case .teams: return L("Teams löschen", "Deleting teams")
        case .profiles: return L("Profile löschen", "Deleting profiles")
        }
    }

    var icon: String {
        switch self {
        case .saves: return "square.grid.2x2.fill"
        case .hunts: return "sparkles"
        case .teams: return "person.3.fill"
        case .profiles: return "person.crop.circle.fill"
        }
    }

    /// AppStorage key of the switch in the settings
    var key: String { "protect.\(rawValue)" }
}

/// Delete password: only a hash is stored (on this iPhone, removed with the app).
enum DeletePassword {
    private static let key = "deletePasswordHash"

    static var isSet: Bool { UserDefaults.standard.string(forKey: key) != nil }

    static func set(_ password: String?) {
        if let password { UserDefaults.standard.set(hash(password), forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }

    static func check(_ password: String) -> Bool {
        UserDefaults.standard.string(forKey: key) == hash(password)
    }

    static func isRequired(for area: ProtectedArea) -> Bool {
        isSet && (UserDefaults.standard.object(forKey: area.key) as? Bool ?? true)
    }

    private static func hash(_ s: String) -> String {
        SHA256.hash(data: Data(("arcdex:" + s).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Delete flow: ask → (ask again) → (password) → delete

private struct GuardedDelete<Item>: ViewModifier {
    @Binding var item: Item?
    let area: ProtectedArea
    let doubleConfirm: Bool
    let title: (Item) -> String
    let message: (Item) -> String
    let perform: (Item) -> Void

    @State private var pending: Item?
    @State private var showSecond = false
    @State private var showPassword = false
    @State private var password = ""
    @State private var wrong = false

    func body(content: Content) -> some View {
        content
            .confirmationDialog(item.map(title) ?? "", isPresented: Binding(get: { item != nil }, set: { if !$0 { item = nil } }),
                                titleVisibility: .visible, presenting: item) { it in
                Button(L("Löschen", "Delete"), role: .destructive) {
                    pending = it
                    next(afterFirst: true)
                }
            } message: { it in
                Text(message(it))
            }
            .alert(L("Wirklich endgültig löschen?", "Really delete for good?"), isPresented: $showSecond) {
                Button(L("Endgültig löschen", "Delete for good"), role: .destructive) { next(afterFirst: false) }
                Button(L("Abbrechen", "Cancel"), role: .cancel) { pending = nil }
            } message: {
                Text(L("Das kann nicht rückgängig gemacht werden.", "This can't be undone."))
            }
            .alert(L("Passwort eingeben", "Enter password"), isPresented: $showPassword) {
                SecureField(L("Passwort", "Password"), text: $password)
                Button(L("Löschen", "Delete"), role: .destructive) {
                    if DeletePassword.check(password) { finish() } else { pending = nil; later { wrong = true } }
                    password = ""
                }
                Button(L("Abbrechen", "Cancel"), role: .cancel) { pending = nil; password = "" }
            } message: {
                Text(L("Zum Löschen ist dein Lösch-Passwort nötig.", "Your delete password is needed to delete this."))
            }
            .alert(L("Falsches Passwort", "Wrong password"), isPresented: $wrong) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(L("Es wurde nichts gelöscht.", "Nothing was deleted."))
            }
    }

    private func next(afterFirst: Bool) {
        if afterFirst && doubleConfirm {
            later { showSecond = true }
        } else if DeletePassword.isRequired(for: area) {
            later { showPassword = true }
        } else {
            finish()
        }
    }

    private func finish() {
        if let pending { perform(pending) }
        pending = nil
    }

    /// the next alert can only appear once the previous one is gone
    private func later(_ action: @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            action()
        }
    }
}

extension View {
    /// Delete with confirmation; optionally a second confirmation, and the password if it is switched on for `area`.
    func guardedDelete<Item>(_ item: Binding<Item?>, area: ProtectedArea, doubleConfirm: Bool = false,
                             title: @escaping (Item) -> String, message: @escaping (Item) -> String,
                             perform: @escaping (Item) -> Void) -> some View {
        modifier(GuardedDelete(item: item, area: area, doubleConfirm: doubleConfirm, title: title, message: message, perform: perform))
    }

    /// Same for a simple yes/no trigger.
    func guardedDelete(_ isPresented: Binding<Bool>, area: ProtectedArea, doubleConfirm: Bool = false,
                       title: String, message: String, perform: @escaping () -> Void) -> some View {
        let item = Binding<Bool?>(get: { isPresented.wrappedValue ? true : nil }, set: { isPresented.wrappedValue = $0 != nil })
        return guardedDelete(item, area: area, doubleConfirm: doubleConfirm, title: { _ in title }, message: { _ in message }) { _ in perform() }
    }
}

// MARK: - Settings

/// "Delete protection" in the settings: set / change / remove the password, choose the areas.
struct DeleteProtectionSection: View {
    @State private var isSet = DeletePassword.isSet
    @State private var sheet: PasswordSheet.Mode?

    var body: some View {
        Section {
            if isSet {
                ForEach(ProtectedArea.allCases) { area in
                    AreaToggle(area: area)
                }
                Button(L("Passwort ändern", "Change password")) { sheet = .change }
                Button(L("Passwort entfernen", "Remove password"), role: .destructive) { sheet = .remove }
            } else {
                Button { sheet = .create } label: {
                    Label(L("Lösch-Passwort festlegen", "Set delete password"), systemImage: "lock.fill")
                }
            }
        } header: {
            Text(L("Löschschutz", "Delete protection"))
        } footer: {
            Text(isSet
                 ? L("Wähle, wo beim Löschen das Passwort nötig ist. Shiny-Hunts und Spielstände fragen außerdem immer zweimal nach.",
                     "Choose where the password is needed for deleting. Shiny hunts and save files also always ask twice.")
                 : L("Mit einem Passwort kann niemand aus Versehen (oder ohne dich) Spielstände, Hunts, Teams oder Profile löschen.",
                     "With a password nobody can delete save files, hunts, teams or profiles by accident (or without you)."))
        }
        .sheet(item: $sheet) { mode in
            PasswordSheet(mode: mode) { isSet = DeletePassword.isSet }
        }
    }
}

private struct AreaToggle: View {
    let area: ProtectedArea
    @AppStorage private var on: Bool

    init(area: ProtectedArea) {
        self.area = area
        _on = AppStorage(wrappedValue: true, area.key)
    }

    var body: some View {
        Toggle(isOn: $on) { Label(area.title, systemImage: area.icon) }
    }
}

private struct PasswordSheet: View {
    enum Mode: String, Identifiable { case create, change, remove; var id: String { rawValue } }
    let mode: Mode
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var repeatNew = ""
    @State private var error: String?

    private var title: String {
        switch mode {
        case .create: return L("Passwort festlegen", "Set password")
        case .change: return L("Passwort ändern", "Change password")
        case .remove: return L("Passwort entfernen", "Remove password")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if mode != .create {
                    Section(L("Aktuelles Passwort", "Current password")) {
                        SecureField(L("Passwort", "Password"), text: $current)
                    }
                }
                if mode != .remove {
                    Section {
                        SecureField(L("Neues Passwort", "New password"), text: $new)
                        SecureField(L("Wiederholen", "Repeat"), text: $repeatNew)
                    } footer: {
                        Text(L("Mindestens 4 Zeichen. Es kann nicht wiederhergestellt werden – merk es dir gut.",
                               "At least 4 characters. It can't be recovered – remember it well."))
                    }
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L("Fertig", "Done")) { save() } }
            }
        }
    }

    private func save() {
        if mode != .create && !DeletePassword.check(current) {
            error = L("Das aktuelle Passwort stimmt nicht.", "The current password is wrong.")
            return
        }
        if mode == .remove {
            DeletePassword.set(nil)
        } else {
            guard new.count >= 4 else { error = L("Mindestens 4 Zeichen.", "At least 4 characters."); return }
            guard new == repeatNew else { error = L("Die Passwörter sind nicht gleich.", "The passwords don't match."); return }
            DeletePassword.set(new)
        }
        onDone()
        dismiss()
    }
}
