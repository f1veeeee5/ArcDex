import SwiftUI
import AVKit

/// All shinies a profile has found – tap one to see its catch proof.
struct ShinyCollectionView: View {
    let hunts: [ShinyHunt]
    let owner: String

    var body: some View {
        ScrollView {
            if hunts.isEmpty {
                ContentUnavailableView(L("Noch keine Shinys", "No shinies yet"), systemImage: "sparkles",
                                       description: Text(L("Gefundene Shinys aus allen Spielständen erscheinen hier.", "Shinies found in all save files show up here.")))
                    .padding(.top, 60)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                    ForEach(hunts) { hunt in
                        NavigationLink {
                            ShinyShowcaseView(hunt: hunt)
                        } label: {
                            VStack(spacing: 4) {
                                FoundShinyTile(hunt: hunt)
                                Text(hunt.game.compactTitle).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(L("Shinys von \(owner)", "\(owner)'s shinies"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One shiny with its numbers and the proof photo / video, as others would see it.
struct ShinyShowcaseView: View {
    let hunt: ShinyHunt
    @State private var image: UIImage?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ZStack(alignment: .bottom) {
                    BattlePlatform(colors: (hunt.species?.types(gen: hunt.game.gen) ?? []).map { TypeColor.color($0) })
                        .frame(width: 190, height: 50)
                        .padding(.bottom, 6)
                    AnimatedPokemonSprite(pokemonId: hunt.pokemonId, shiny: true, grounded: true)
                        .frame(width: 160, height: 160)
                        .padding(.bottom, 26)
                }
                .frame(height: 200)

                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Text(hunt.name).font(.largeTitle.weight(.bold))
                        ShinyBadge()
                    }
                    Text(hunt.game.title).font(.subheadline).foregroundStyle(.secondary)
                }

                // numbers of the hunt
                VStack(spacing: 0) {
                    row(hunt.method.unit, "\(hunt.count)")
                    Divider().padding(.leading, 14)
                    row(L("Methode", "Method"), hunt.method.title)
                    Divider().padding(.leading, 14)
                    row(L("Chance", "Odds"), hunt.odds.label(at: hunt.count))
                    if hunt.totalTime() > 0 {
                        Divider().padding(.leading, 14)
                        row(L("Dauer", "Time"), duration(hunt.totalTime()))
                    }
                    if let found = hunt.foundAt {
                        Divider().padding(.leading, 14)
                        row(L("Gefunden", "Found"), found.formatted(.dateTime.day().month(.wide).year().hour().minute()))
                    }
                }
                .card()

                // proof
                VStack(alignment: .leading, spacing: 12) {
                    let state = ProofState(hunt: hunt)
                    Label(L("Fang-Beleg", "Catch proof"), systemImage: hunt.proofFile == nil ? "seal" : state.icon)
                        .font(.headline)
                        .foregroundStyle(hunt.proofFile == nil ? Color.secondary : state.color)
                    if let file = hunt.proofFile {
                        Group {
                            if hunt.proofIsVideo {
                                VideoPlayer(player: AVPlayer(url: ProofStore.url(file)))
                                    .frame(height: 240)
                            } else if let image {
                                Image(uiImage: image).resizable().scaledToFit()
                            } else {
                                Color(.tertiarySystemFill).frame(height: 200)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        if let taken = hunt.proofTakenAt {
                            Text(L("Aufgenommen mit der App-Kamera am \(taken.formatted(.dateTime.day().month().year().hour().minute()))",
                                   "Taken with the app camera on \(taken.formatted(.dateTime.day().month().year().hour().minute()))"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let check = hunt.proofCheck, !check.items.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(check.items) { item in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Image(systemName: item.status == .pass ? "checkmark.circle.fill" : item.status == .fail ? "xmark.circle.fill" : "questionmark.circle.fill")
                                            .foregroundStyle(item.status == .pass ? Color.green : item.status == .fail ? Color.orange : Color.secondary)
                                        Text(Lang.current == .de ? item.de : item.en).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } else {
                        Text(L("Für dieses Shiny gibt es keinen Fang-Beleg.", "There is no catch proof for this shiny."))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(hunt.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: hunt.proofFile) {
            if hunt.proofFile != nil && !hunt.proofIsVideo { image = await ProofStore.thumbnail(for: hunt) }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func duration(_ t: TimeInterval) -> String {
        let h = Int(t / 3600), m = Int(t.truncatingRemainder(dividingBy: 3600) / 60)
        return h > 0 ? "\(h) h \(m) min" : "\(m) min"
    }
}
