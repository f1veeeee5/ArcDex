import SwiftUI
import SwiftData

struct GuideTrainerRoute: Hashable {
    let game: Game
    let trainerId: String
}

/// "Games" tab: starters, legendaries, the way through the region and the important trainers of a game.
struct GamesView: View {
    @Query(sort: \Savegame.updatedAt, order: .reverse) private var saves: [Savegame]
    @AppStorage("guideGame") private var gameRaw = ""
    @State private var path = NavigationPath()
    @State private var routeOpen = false

    private var game: Game {
        Game(rawValue: gameRaw) ?? saves.first?.game ?? .swsh
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                let guide = GuideData.shared.guide(for: game)
                VStack(alignment: .leading, spacing: 22) {
                    gameHeader
                    if let guide {
                        if !guide.starters.isEmpty {
                            pokemonRow(L("Starter", "Starters"), icon: "leaf.fill", ids: guide.starters.map { ($0, nil) })
                        }
                        if let legends = guide.legendaries, !legends.isEmpty {
                            pokemonRow(L("Legendäre", "Legendaries"), icon: "sparkles",
                                       ids: legends.map { l in (l.p, l.version.map { Game.versionTitle($0) } ?? l.note?.text) })
                        }
                        if let route = guide.route, !route.isEmpty {
                            routeSection(route, guide: guide)
                        }
                        if guide.hasTrainers {
                            ForEach(GuideTrainer.Role.allCases, id: \.self) { role in
                                let list = guide.trainers(role)
                                if !list.isEmpty { trainerSection(role, list) }
                            }
                            Text(L("Teams laut Bulbapedia und Serebii – die Quellen stehen bei jedem Trainer.",
                                   "Teams according to Bulbapedia and Serebii – sources are listed with each trainer."))
                                .font(.caption).foregroundStyle(.tertiary)
                        } else {
                            comingSoon
                        }
                    } else {
                        comingSoon
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L("Spiele", "Games"))
            .navigationDestination(for: GuideTrainerRoute.self) { route in
                TrainerDetailView(game: route.game, trainerId: route.trainerId)
            }
            .navigationDestination(for: DexRoute.self) { route in
                PokemonDetailView(pokemonId: route.pokemonId, preferredGame: route.game)
            }
        }
    }

    // MARK: Sections

    private var gameHeader: some View {
        Menu {
            Picker(selection: Binding(get: { game.rawValue }, set: { gameRaw = $0 })) {
                GameMenuItems(games: Game.allCases.filter { !$0.isChampions })
            } label: { EmptyView() }
            .pickerStyle(.inline)
        } label: {
            GameCoverCard(game: game)
                .frame(height: 130)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.25), in: Circle())
                        .padding(10)
                }
        }
        .buttonStyle(.plain)
    }

    private var comingSoon: some View {
        Label(L("Trainer, Weg durch die Region und Match-up gibt es bisher für Schwert/Schild – die anderen Spiele folgen.",
                "Trainers, the way through the region and match-ups are available for Sword/Shield so far – the other games will follow."),
              systemImage: "hammer.fill")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.title3.weight(.bold))
    }

    private func pokemonRow(_ title: String, icon: String, ids: [(Int, String?)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(title, icon: icon)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(ids.enumerated()), id: \.offset) { _, item in
                        NavigationLink(value: DexRoute(pokemonId: item.0, game: game)) {
                            VStack(spacing: 4) {
                                PokemonSprite(pokemonId: item.0).frame(width: 72, height: 72)
                                Text(Dex.shared.pokemon(item.0)?.name ?? "?").font(.caption.weight(.semibold)).lineLimit(1)
                                if let note = item.1 {
                                    Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .frame(width: 100)
                            .padding(.vertical, 10)
                            .card()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func routeSection(_ route: [GuideStop], guide: GameGuide) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { routeOpen.toggle() }
            } label: {
                HStack {
                    sectionTitle(L("Weg durch die Region", "Way through the region"), icon: "map.fill")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(routeOpen ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 0) {
                let stops = routeOpen ? route : route.filter { $0.trainer != nil }
                ForEach(Array(stops.enumerated()), id: \.offset) { i, stop in
                    RouteStopRow(stop: stop, guide: guide, game: game, isFirst: i == 0, isLast: i == stops.count - 1)
                }
                if !routeOpen {
                    Text(L("Tippe oben, um alle \(route.count) Orte zu sehen.", "Tap above to see all \(route.count) places."))
                        .font(.caption).foregroundStyle(.tertiary)
                        .padding(.top, 8)
                }
            }
            .padding(16)
            .card()
        }
    }

    private func trainerSection(_ role: GuideTrainer.Role, _ list: [GuideTrainer]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(role.title, icon: role.icon)
            ForEach(list) { trainer in
                NavigationLink(value: GuideTrainerRoute(game: game, trainerId: trainer.id)) {
                    TrainerCard(trainer: trainer, game: game)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One place on the way through the region.
private struct RouteStopRow: View {
    let stop: GuideStop
    let guide: GameGuide
    let game: Game
    let isFirst: Bool
    let isLast: Bool

    private var trainers: [GuideTrainer] {
        guard let key = stop.trainer else { return [] }
        if key == "cup" { return guide.trainers(.champion) }
        return key.split(separator: "|").compactMap { guide.trainer(String($0)) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Rectangle().fill(isFirst ? Color.clear : Color(.separator)).frame(width: 2, height: 8)
                Circle()
                    .fill(trainers.isEmpty ? Color(.tertiaryLabel) : (trainers.first?.type.map { TypeColor.color($0) } ?? .orange))
                    .frame(width: trainers.isEmpty ? 8 : 14, height: trainers.isEmpty ? 8 : 14)
                Rectangle().fill(isLast ? Color.clear : Color(.separator)).frame(width: 2).frame(maxHeight: .infinity)
            }
            .frame(width: 14)
            VStack(alignment: .leading, spacing: 4) {
                Text(stop.name)
                    .font(trainers.isEmpty ? .subheadline : .subheadline.weight(.semibold))
                    .foregroundStyle(trainers.isEmpty ? .secondary : .primary)
                if let note = stop.note {
                    Text(note.text).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(trainers) { t in
                    NavigationLink(value: GuideTrainerRoute(game: game, trainerId: t.id)) {
                        HStack(spacing: 6) {
                            Image(systemName: t.role.icon).font(.caption.weight(.bold))
                            Text(t.name.text).font(.caption.weight(.semibold))
                            if let v = t.version { Text("· " + Game.versionTitle(v)).font(.caption) }
                            Text("· Lv. \(t.aceLevel)").font(.caption)
                            Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(t.type.map { TypeColor.color($0) } ?? .orange)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 10)
            Spacer(minLength: 0)
        }
    }
}

/// Trainer in the list: name, place, team sprites.
struct TrainerCard: View {
    let trainer: GuideTrainer
    let game: Game

    var body: some View {
        let color = trainer.type.map { TypeColor.color($0) } ?? Color.orange
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(trainer.name.text).font(.headline)
                if let v = trainer.version {
                    Text(Game.versionTitle(v))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
                if trainer.double {
                    Text(L("Doppel", "Doubles"))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
                Spacer()
                Text("Lv. \(trainer.aceLevel)").font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(color)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            Label(trainer.location, systemImage: "mappin.and.ellipse")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                ForEach(Array((trainer.teams.first?.team ?? []).enumerated()), id: \.offset) { _, p in
                    PokemonSprite(pokemonId: p.p).frame(width: 40, height: 40)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .accentCard(trainer.type.map { [TypeColor.color($0)] } ?? [Color.orange, Color.pink])
    }
}
