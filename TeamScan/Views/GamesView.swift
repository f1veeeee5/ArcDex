import SwiftUI
import SwiftData

struct GuideTrainerRoute: Hashable {
    let game: Game
    let trainerId: String
}

/// "Games" tab: starters, legendaries, the way through the region and the important trainers of a game.
struct GamesView: View {
    @Query(sort: \Savegame.updatedAt, order: .reverse) private var everySave: [Savegame]
    @AppStorage(ProfileStore.key) private var activeProfile = ""
    private var saves: [Savegame] { everySave.filter { $0.profileID?.uuidString == activeProfile } }
    @AppStorage("guideGame") private var gameRaw = ""
    @State private var path = NavigationPath()
    @State private var routeOpen = false
    @State private var showPicker = false

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
        Button { showPicker = true } label: {
            GameCoverCard(game: game)
                .frame(height: 130)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.25), in: Circle())
                        .padding(10)
                }
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showPicker) {
            GameWheelPicker(selected: game) { picked in
                gameRaw = picked.rawValue
            }
        }
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

    /// Pokémon standing on small platforms, spread evenly over the width.
    private func pokemonRow(_ title: String, icon: String, ids: [(Int, String?)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(title, icon: icon)
            HStack(alignment: .top, spacing: 4) {
                ForEach(Array(ids.enumerated()), id: \.offset) { _, item in
                    NavigationLink(value: DexRoute(pokemonId: item.0, game: game)) {
                        PodiumPokemon(pokemonId: item.0, note: item.1, game: game)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
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
        HStack(alignment: .center, spacing: 12) {
        // trainer standing on a small platform in the type colour (no box)
        // the sprites have a wide empty border – so a narrow platform under the feet
        ZStack(alignment: .bottom) {
            // small ground shadow in the type colour (the full platform glows too wide in a list)
            Ellipse()
                .fill(RadialGradient(colors: [color.opacity(0.55), color.opacity(0)], center: .center, startRadius: 0, endRadius: 22))
                .frame(width: 44, height: 10)
                .padding(.bottom, 4)
            TrainerSprite(avatar: trainer.avatar)
                .frame(width: 76, height: 76)
                .padding(.bottom, 4)
        }
        .frame(width: 64, height: 82)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(trainer.name.text).font(.headline).lineLimit(1)
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
            HStack(spacing: 0) {
                ForEach(Array((trainer.teams.first?.team ?? []).enumerated()), id: \.offset) { _, p in
                    PokemonSprite(pokemonId: p.p).frame(width: 34, height: 34)
                }
                Spacer(minLength: 0)
            }
        }
        }
        .padding(14)
        .accentCard(trainer.type.map { [TypeColor.color($0)] } ?? [Color.orange, Color.pink])
    }
}


/// A Pokémon on a small battle platform with its name below.
struct PodiumPokemon: View {
    let pokemonId: Int
    var note: String?
    let game: Game

    var body: some View {
        let p = Dex.shared.pokemon(pokemonId)
        VStack(spacing: 2) {
            ZStack(alignment: .bottom) {
                BattlePlatform(colors: (p?.types(gen: game.gen) ?? []).map { TypeColor.color($0) })
                    .frame(width: 100, height: 30)
                    .padding(.bottom, 2)
                AnimatedPokemonSprite(pokemonId: pokemonId, grounded: true)
                    .frame(width: 86, height: 86)
                    .padding(.bottom, 16)
            }
            .frame(height: 104)
            Text(p?.name ?? "?").font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            if let note {
                Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Full-screen game picker: the game cards on a wheel.
struct GameWheelPicker: View {
    let selected: Game
    var onPick: (Game) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var centered: Game?

    private let games = Game.allCases.filter { !$0.isChampions }
    private let cardHeight: CGFloat = 122

    var body: some View {
        let current = centered ?? selected
        GeometryReader { geo in
            ZStack {
                // the centred game's colours softly in the background
                current.gradient
                    .opacity(0.35)
                    .blur(radius: 60)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.4), value: current)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        ForEach(games) { game in
                            GameCoverCard(game: game, highlighted: game == selected)
                                .frame(height: cardHeight)
                                .padding(.horizontal, 28)
                                .id(game)
                                .scrollTransition(.interactive, axis: .vertical) { content, phase in
                                    content
                                        .rotation3DEffect(.degrees(phase.value * -38), axis: (x: 1, y: 0, z: 0),
                                                          anchor: .center, perspective: 0.6)
                                        .scaleEffect(1 - abs(phase.value) * 0.18)
                                        .opacity(1 - abs(phase.value) * 0.55)
                                }
                                .onTapGesture {
                                    if game == current {
                                        pick(game)
                                    } else {
                                        withAnimation(.snappy) { centered = game }
                                    }
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.vertical, max((geo.size.height - cardHeight) / 2, 0), for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $centered, anchor: .center)
                .sensoryFeedback(.selection, trigger: centered)

                VStack {
                    HStack {
                        Text(L("Spiel wählen", "Choose game")).font(.title2.weight(.bold))
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .frame(width: 40, height: 40)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    Spacer()
                    Button { pick(current) } label: {
                        Text(L("\(current.title) wählen", "Choose \(current.title)"))
                            .font(.headline)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.appPrimary)
                    .tint(current.colors.first ?? .appAccent)
                    .controlSize(.large)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .onAppear { centered = selected }
    }

    private func pick(_ game: Game) {
        onPick(game)
        dismiss()
    }
}
