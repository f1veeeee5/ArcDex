import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var language = AppLanguage.system.rawValue
    @AppStorage("spriteStyle") private var styleRaw = SpriteStyle.home.rawValue
    @AppStorage("defaultLevel") private var defaultLevel = 50

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L("Sprache", "Language"), selection: $language) {
                        ForEach(AppLanguage.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                } header: {
                    Text(L("Sprache", "Language"))
                } footer: {
                    Text(L("Gilt für die App und alle Pokémon-, Attacken- und Item-Namen. Der Scanner erkennt immer Deutsch und Englisch.",
                           "Applies to the app and all Pokémon, move and item names. The scanner always reads German and English."))
                }

                Section(L("Sprites", "Sprites")) {
                    Picker(L("Stil", "Style"), selection: $styleRaw) {
                        ForEach(SpriteStyle.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: 20) {
                        Spacer()
                        PokemonSprite(pokemonId: 6).frame(width: 90, height: 90)
                        PokemonSprite(pokemonId: 6, shiny: true).frame(width: 90, height: 90)
                            .overlay(alignment: .topTrailing) { ShinyBadge() }
                        Spacer()
                    }
                    .id(styleRaw)
                }

                Section(L("Neue Pokémon", "New Pokémon")) {
                    Stepper(value: $defaultLevel, in: 1...100) {
                        HStack {
                            Text(L("Standard-Level", "Default level"))
                            Spacer()
                            Text("\(defaultLevel)").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    LabeledContent(L("Daten", "Data"), value: "PokéAPI")
                    LabeledContent(L("Spiele", "Games"), value: Game.allCases.map(\.shortTitle).joined(separator: ", "))
                    LabeledContent(L("Pokémon", "Pokémon"), value: "\(Dex.shared.pokemon.count)")
                    LabeledContent(L("Attacken", "Moves"), value: "\(Dex.shared.moves.count)")
                } header: {
                    Text(L("Über", "About"))
                } footer: {
                    Text(L("Pokémon und alle zugehörigen Namen sind Marken von Nintendo, Game Freak und The Pokémon Company. Diese App ist ein inoffizielles Fan-Projekt.",
                           "Pokémon and all related names are trademarks of Nintendo, Game Freak and The Pokémon Company. This app is an unofficial fan project."))
                }
            }
            .navigationTitle(L("Einstellungen", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Fertig", "Done")) { dismiss() } }
            }
        }
    }
}

struct ShowdownImportView: View {
    let game: Game
    var onImport: (Showdown.ImportedTeam) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var parsed: Showdown.ImportedTeam { Showdown.parse(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(.footnote.monospaced())
                        .frame(minHeight: 260)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button {
                        text = UIPasteboard.general.string ?? text
                    } label: {
                        Label(L("Aus Zwischenablage einfügen", "Paste from clipboard"), systemImage: "doc.on.clipboard")
                    }
                } footer: {
                    Text(L("Füge den Export-Text aus Pokémon Showdown ein. Das Team wird in \(game.title) gespeichert.",
                           "Paste the export text from Pokémon Showdown. The team will be saved in \(game.title)."))
                }
                if !text.isEmpty {
                    Section(L("Erkannt", "Detected")) {
                        if parsed.members.isEmpty {
                            Text(L("Noch keine Pokémon erkannt", "No Pokémon detected yet")).foregroundStyle(.secondary)
                        }
                        ForEach(Array(parsed.members.prefix(6).enumerated()), id: \.offset) { _, m in
                            HStack(spacing: 10) {
                                PokemonSprite(pokemonId: m.pokemonId).frame(width: 40, height: 40)
                                VStack(alignment: .leading) {
                                    Text(Dex.shared.pokemon(m.pokemonId)?.name ?? "?").font(.subheadline.weight(.semibold))
                                    Text(L("\(m.moveIds.count) Attacken", "\(m.moveIds.count) moves")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(L("Showdown-Import", "Showdown import"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Importieren", "Import")) {
                        onImport(parsed)
                        dismiss()
                    }
                    .disabled(parsed.members.isEmpty)
                }
            }
        }
    }
}
