import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TeamDetailView: View {
    @Bindable var team: Team
    /// navigation path of the Teams tab – the editor is pushed onto it so links inside it (Pokédex) open on top
    @Binding var path: NavigationPath
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Savegame.updatedAt, order: .reverse) private var saves: [Savegame]
    @AppStorage("spriteStyle") private var styleRaw = SpriteStyle.home.rawValue
    @AppStorage("defaultLevel") private var defaultLevel = 50

    @State private var pendingEdit: TeamMember?
    @State private var showAdd = false
    @State private var showScan = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var copied = false
    @State private var confirmDelete = false
    @State private var dragging: TeamMember?
    @State private var dragActive = false

    private var members: [TeamMember] { team.sortedMembers }
    private var game: Game { team.game }

    var body: some View {
        let analysis = TeamAnalysis(members: members, game: game, format: game.isChampions ? team.format : nil)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(members) { m in
                        Button { path.append(m) } label: { MemberCard(member: m, game: game) }
                            .buttonStyle(.plain)
                            .opacity(dragging === m && dragActive ? 0.35 : 1)
                            .onDrag {
                                dragging = m
                                dragActive = true
                                return NSItemProvider(object: m.uuid.uuidString as NSString)
                            } preview: {
                                MemberCard(member: m, game: game)
                                    .frame(width: 170)
                            }
                            .onDrop(of: [.text], delegate: MemberDropDelegate(target: m, team: team, dragging: $dragging, active: $dragActive))
                            .contextMenu {
                                Button { move(m, by: -1) } label: { Label(L("Nach vorne", "Move up"), systemImage: "arrow.left") }
                                Button { move(m, by: 1) } label: { Label(L("Nach hinten", "Move down"), systemImage: "arrow.right") }
                                Button(role: .destructive) { remove(m) } label: { Label(L("Entfernen", "Remove"), systemImage: "trash") }
                            }
                    }
                    if !team.isFull {
                        AddMemberCard(onAdd: { showAdd = true }, onScan: { showScan = true })
                    }
                }

                if members.count > 1 {
                    Label(L("Gedrückt halten und ziehen, um die Reihenfolge zu ändern", "Press and hold, then drag to reorder"), systemImage: "hand.draw")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                SectionHeader(title: L("Typ-Abdeckung", "Type coverage"), icon: "shield.lefthalf.filled")
                CoverageView(analysis: analysis)

                SectionHeader(title: L("Tipps", "Tips"), icon: "lightbulb")
                TipsView(tips: analysis.tips)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
            .onDrop(of: [.text], isTargeted: nil) { _ in
                dragging = nil
                dragActive = false
                return true
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(team.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = Showdown.export(team: team)
                    withAnimation { copied = true }
                    Task { try? await Task.sleep(for: .seconds(1.6)); withAnimation { copied = false } }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .accessibilityLabel(L("Für Showdown kopieren", "Copy for Showdown"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: Showdown.export(team: team)) {
                        Label(L("Als Showdown-Text teilen", "Share as Showdown text"), systemImage: "square.and.arrow.up")
                    }
                    Button { showScan = true } label: { Label(L("Pokémon scannen", "Scan Pokémon"), systemImage: "camera.viewfinder") }
                        .disabled(team.isFull)
                    Picker(selection: $styleRaw) {
                        ForEach(SpriteStyle.allCases) { Text($0.label).tag($0.rawValue) }
                    } label: { Label(L("Sprites", "Sprites"), systemImage: "photo") }
                    Menu {
                        ForEach(saves) { save in
                            Button {
                                team.savegame = save
                                team.game = save.game
                                team.touch()
                                save.touch()
                            } label: {
                                if save === team.savegame {
                                    Label(save.displayName, systemImage: "checkmark")
                                } else {
                                    Text(save.name.isEmpty ? save.displayName : "\(save.displayName) · \(save.game.compactTitle)")
                                }
                            }
                        }
                    } label: { Label(L("In Spielstand verschieben", "Move to save file"), systemImage: "folder") }
                    Divider()
                    Button { renameText = team.name; showRename = true } label: { Label(L("Umbenennen", "Rename"), systemImage: "pencil") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label(L("Team löschen", "Delete team"), systemImage: "trash") }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .overlay(alignment: .bottom) {
            if copied {
                Label(L("Kopiert – in Showdown einfügen", "Copied – paste into Showdown"), systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showAdd, onDismiss: {
            if let p = pendingEdit { pendingEdit = nil; path.append(p) }
        }) {
            OptionPicker(title: L("Pokémon wählen", "Choose Pokémon"), options: PickerOptions.pokemon(game: game), selected: nil) { id in
                guard let id else { return }
                pendingEdit = addMember(pokemonId: id)
            }
        }
        .sheet(isPresented: $showScan) {
            MemberScanSheet(game: game, mode: .team) { scanned in
                for s in scanned {
                    guard let pid = s.pokemonId, !team.isFull else { continue }
                    let m = addMember(pokemonId: pid)
                    m.level = game.fixedLevel ?? s.level ?? m.level
                    m.apply(s, replaceSpecies: false)
                }
            }
        }
        .alert(L("Team umbenennen", "Rename team"), isPresented: $showRename) {
            TextField(L("Name", "Name"), text: $renameText)
            Button(L("Sichern", "Save")) { team.name = renameText; team.touch() }
            Button(L("Abbrechen", "Cancel"), role: .cancel) {}
        }
        .confirmationDialog(L("Team wirklich löschen?", "Delete this team?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("Löschen", "Delete"), role: .destructive) {
                context.delete(team)
                dismiss()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            if game.isChampions {
                Picker(L("Format", "Format"), selection: Binding(get: { team.format }, set: { team.format = $0; team.touch() })) {
                    ForEach(BattleFormat.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Text(game.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(game.gradient, in: Capsule())
            HStack(spacing: 5) {
                GameMechanicIcon(game: game, size: 15)
                Text(game.mechanic).lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            Spacer()
            Text("\(members.count)/6").font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.top, 6)
    }

    @discardableResult
    private func addMember(pokemonId: Int) -> TeamMember {
        let m = TeamMember(pokemonId: pokemonId, order: (members.map(\.order).max() ?? -1) + 1, level: game.fixedLevel ?? defaultLevel)
        context.insert(m)
        m.team = team
        team.touch()
        return m
    }

    private func remove(_ m: TeamMember) {
        context.delete(m)
        team.touch()
    }

    private func move(_ m: TeamMember, by delta: Int) {
        var list = members
        guard let i = list.firstIndex(where: { $0 === m }) else { return }
        let j = i + delta
        guard list.indices.contains(j) else { return }
        list.swapAt(i, j)
        for (k, member) in list.enumerated() { member.order = k }
        team.touch()
    }
}

/// Reorders team members live while a card is dragged over another one.
struct MemberDropDelegate: DropDelegate {
    let target: TeamMember
    let team: Team
    @Binding var dragging: TeamMember?
    @Binding var active: Bool

    func dropEntered(info: DropInfo) {
        guard let source = dragging, source !== target else { return }
        var list = team.sortedMembers
        guard let from = list.firstIndex(where: { $0 === source }),
              let to = list.firstIndex(where: { $0 === target }) else { return }
        withAnimation(.snappy) {
            list.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            for (i, m) in list.enumerated() { m.order = i }
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        active = false
        team.touch()
        return true
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String
    var body: some View {
        Label(title, systemImage: icon)
            .font(.title3.weight(.bold))
            .padding(.top, 6)
    }
}

// MARK: - Member card

struct MemberCard: View {
    let member: TeamMember
    let game: Game

    var body: some View {
        let form = member.battleForm(in: game)
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: member.types(in: game).map { TypeColor.color($0).opacity(0.28) } + [Color(.tertiarySystemFill)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                AnimatedPokemonSprite(pokemonId: form?.id ?? member.pokemonId, shiny: member.shiny)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                HStack {
                    Text("Lv. \(member.level)").font(.caption2.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                    if member.shiny { ShinyBadge() }
                    if member.megaFormId != nil { MechanicBadge(mechanic: .mega) }
                    if member.gigantamax && game.hasDynamax { MechanicBadge(mechanic: .gmax) }
                }
                .padding(8)
                if let item = member.item {
                    ItemIcon(item: item).frame(width: 26, height: 26)
                        .padding(4)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .aspectRatio(1.25, contentMode: .fit)

            VStack(alignment: .leading, spacing: 4) {
                Text(member.displayName).font(.headline).lineLimit(1)
                HStack(spacing: 4) {
                    ForEach(member.types(in: game), id: \.self) { TypeBadge(typeId: $0, small: true) }
                    if game.hasTera, let tera = member.teraTypeId {
                        Image(systemName: "diamond.fill").font(.system(size: 9)).foregroundStyle(TypeColor.color(tera))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    if i < member.moves.count {
                        let mv = member.moves[i]
                        HStack(spacing: 5) {
                            Circle().fill(TypeColor.color(mv.t)).frame(width: 7, height: 7)
                            Text(mv.name).font(.caption).lineLimit(1)
                        }
                    } else {
                        HStack(spacing: 5) {
                            Circle().strokeBorder(Color(.tertiaryLabel), lineWidth: 1).frame(width: 7, height: 7)
                            Text("—").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(10)
        .card()
    }
}

struct MechanicChip: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 9, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing), in: Capsule())
    }
}

struct AddMemberCard: View {
    var onAdd: () -> Void
    var onScan: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Button(action: onAdd) {
                Label(L("Hinzufügen", "Add"), systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button(action: onScan) {
                Label(L("Scannen", "Scan"), systemImage: "camera.viewfinder").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 220)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(Color(.tertiaryLabel))
        }
    }
}
