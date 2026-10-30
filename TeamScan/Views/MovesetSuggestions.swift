import SwiftUI

/// "Moveset suggestions" section in the Pokémon editor: tap once to take over a whole set.
struct MovesetSuggestionsSection: View {
    @Bindable var member: TeamMember
    let game: Game

    private struct Snapshot {
        var moves: [Int], item: Int?, ability: Int?, nature: Int?, evs: [Int], ivs: [Int], tera: Int?, mega: Int?, gmax: Bool
    }

    @State private var undo: Snapshot?
    @State private var appliedKey: String?
    @State private var applyCount = 0
    @Environment(\.pagerSwipeLock) private var swipeLock

    private var doublesFirst: Bool { member.team?.format == .doubles && game.isChampions }

    var body: some View {
        let story = Movesets.shared.story(for: member.pokemonId, game: game, level: member.level)
        let comp = Movesets.shared.competitive(for: member.pokemonId, game: game, doublesFirst: doublesFirst)
        if story != nil || !comp.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        // a plain HStack (not lazy) so every card can grow to the height of the tallest one
                        HStack(alignment: .top, spacing: 12) {
                            if let story {
                                card(story, pokemonId: member.pokemonId, key: "story")
                            }
                            ForEach(Array(comp.enumerated()), id: \.offset) { i, item in
                                card(item.set, pokemonId: item.pokemonId, key: "c\(i)")
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                    .scrollClipDisabled()
                    .mask(edgeFade)
                    .blocksPagerSwipe(swipeLock)

                    if undo != nil {
                        Button {
                            restore()
                        } label: {
                            Label(L("Rückgängig", "Undo"), systemImage: "arrow.uturn.backward")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .padding(.horizontal, 16)
                        .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
                    }
                }
                .padding(.vertical, 8)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } header: {
                Text(L("Moveset-Vorschläge", "Moveset suggestions"))
            } footer: {
                Text(L("Story: aus den Level-Attacken bis Lv. \(member.level) berechnet. Wettkampf-Sets: Pokémon Showdown (Battle Factory, Battle Stadium, Zufallskämpfe). Ausblenden in den Einstellungen.",
                       "Playthrough: calculated from level-up moves up to Lv. \(member.level). Competitive sets: Pokémon Showdown (Battle Factory, Battle Stadium, Random Battles). Hide them in Settings."))
            }
            .sensoryFeedback(.success, trigger: applyCount)
        }
    }

    /// Soft fade at the left and right edge, so the cards don't end with a hard cut.
    private var edgeFade: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 14)
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 14)
        }
    }

    // MARK: Card

    private func card(_ entry: MovesetEntry, pokemonId: Int, key: String) -> some View {
        let dex = Dex.shared
        let moves = entry.m.compactMap { dex.move($0) }
        let isMega = pokemonId != member.pokemonId && dex.pokemon(pokemonId)?.kind == "mega"
        let applied = appliedKey == key && entry.m == Array(member.moveIds.prefix(entry.m.count))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(entry.sourceTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(entry.s == "story" ? AnyShapeStyle(Color.green.gradient) : AnyShapeStyle(game.gradient), in: Capsule())
                if isMega {
                    MechanicBadge(mechanic: .mega, size: 20)
                }
                if entry.g == 1 && game.hasDynamax {
                    MechanicBadge(mechanic: .gmax, size: 20)
                }
                Spacer(minLength: 0)
            }
            if let role = entry.roleTitle {
                Text(role).font(.subheadline.weight(.semibold)).lineLimit(1)
            } else if entry.s == "story" {
                Text(L("Bis Lv. \(member.level)", "Up to Lv. \(member.level)")).font(.subheadline.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(moves) { m in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(TypeColor.color(m.t)).frame(width: 4, height: 18)
                        Text(m.name).font(.subheadline).lineLimit(1)
                        Spacer(minLength: 0)
                        CategoryBadge(category: m.c)
                    }
                }
            }

            if let extras = extrasText(entry) {
                Text(extras)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let alts = entry.x, !alts.isEmpty {
                Text(L("Alternativen: ", "Alternatives: ") + alts.prefix(4).compactMap { dex.move($0)?.name }.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button {
                apply(entry, key: key)
            } label: {
                Label(applied ? L("Übernommen", "Applied") : (entry.isFullSet && hasExtras(entry) ? L("Set übernehmen", "Use set") : L("Attacken übernehmen", "Use moves")),
                      systemImage: applied ? "checkmark" : "arrow.down.doc")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(applied ? .green : .accentColor)
        }
        .padding(14)
        .frame(width: 250, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Things a full set changes besides the moves – only those the game has.
    private func hasExtras(_ e: MovesetEntry) -> Bool {
        (e.i != nil && game.hasHeldItems) || (e.n != nil && game.hasNatures) || (e.e != nil && game.hasEVs)
    }

    private func extrasText(_ e: MovesetEntry) -> String? {
        let dex = Dex.shared
        var parts: [String] = []
        if let i = e.i, game.hasHeldItems, let item = dex.item(i) { parts.append(item.name) }
        if let a = e.a, game.hasAbilities, let ab = dex.ability(a) { parts.append(ab.name) }
        if let n = e.n, game.hasNatures, let nat = dex.nature(n) { parts.append(nat.name) }
        if let t = e.tt, game.hasTera, let type = dex.type(t) { parts.append("Tera \(type.name)") }
        if let evs = e.e, game.hasEVs {
            let names = StatNames.short
            let text = evs.enumerated().filter { $0.element > 0 }.map { "\($0.element) \(names[$0.offset])" }.joined(separator: " / ")
            if !text.isEmpty { parts.append(text) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Apply / undo

    private func apply(_ e: MovesetEntry, key: String) {
        undo = Snapshot(moves: member.moveIds, item: member.itemId, ability: member.abilityId, nature: member.natureId,
                        evs: member.evs, ivs: member.ivs, tera: member.teraTypeId, mega: member.megaFormId, gmax: member.gigantamax)
        withAnimation(.snappy) {
            member.moveIds = Array(e.m.prefix(4))
            if let i = e.i, game.hasHeldItems {
                member.itemId = i
                if game.hasMega, let form = member.megaForm(forStone: i) { member.megaFormId = form }
            }
            if let a = e.a, game.hasAbilities, let p = member.species,
               Dex.shared.abilities(for: p, gen: game.gen).contains(where: { $0.id == a }) {
                member.abilityId = a
            }
            if let n = e.n, game.hasNatures { member.natureId = n }
            if let evs = e.e, game.hasEVs, evs.count == 6 { member.evs = evs }
            if let ivs = e.v, game.hasIVs, ivs.count == 6 { member.ivs = ivs }
            if let t = e.tt, game.hasTera { member.teraTypeId = t }
            if e.g == 1, game.hasDynamax { member.gigantamax = true }
            member.team?.touch()
            appliedKey = key
        }
        applyCount += 1
    }

    private func restore() {
        guard let s = undo else { return }
        withAnimation(.snappy) {
            member.moveIds = s.moves; member.itemId = s.item; member.abilityId = s.ability; member.natureId = s.nature
            member.evs = s.evs; member.ivs = s.ivs; member.teraTypeId = s.tera; member.megaFormId = s.mega; member.gigantamax = s.gmax
            member.team?.touch()
            undo = nil
            appliedKey = nil
        }
    }
}
