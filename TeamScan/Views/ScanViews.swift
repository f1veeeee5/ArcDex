import SwiftUI
import PhotosUI
import UIKit

// MARK: - Image source

struct ImageSourceButtons: View {
    var onImage: (UIImage) -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false

    var body: some View {
        VStack(spacing: 10) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: {
                    Label(L("Foto aufnehmen", "Take photo"), systemImage: "camera.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(L("Screenshot / Foto wählen", "Choose screenshot / photo"), systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    onImage(img)
                }
                photoItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in onImage(img) }
                .ignoresSafeArea()
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Shared pieces

private struct ScanIntro: View {
    let icon: String
    let title: String
    let text: String
    let tips: [String]
    let game: Game

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 86, height: 86)
                .background(game.gradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            Text(title).font(.title2.weight(.bold))
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(tips, id: \.self) { tip in
                    Label(tip, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .card()
        }
    }
}

private struct WorkingView: View {
    let image: UIImage?
    var body: some View {
        VStack(spacing: 18) {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(ScanLineOverlay())
            }
            ProgressView(L("Text wird erkannt …", "Recognizing text …"))
        }
        .padding(.top, 30)
    }
}

private struct ScanLineOverlay: View {
    @State private var phase = false
    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .accentColor.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 40)
                .offset(y: phase ? geo.size.height - 20 : -20)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: phase)
                .onAppear { phase = true }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .allowsHitTesting(false)
    }
}

private struct RecognizedTextView: View {
    let lines: [OCRLine]
    var body: some View {
        DisclosureGroup(L("Erkannter Text (\(lines.count) Zeilen)", "Recognized text (\(lines.count) lines)")) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines) { Text($0.text).font(.caption.monospaced()).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        }
        .font(.subheadline)
        .padding(14)
        .card()
    }
}

// MARK: - Move scan

struct MoveScanSheet: View {
    @Bindable var member: TeamMember
    let game: Game
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case pick, working, review }

    @State private var phase = Phase.pick
    @State private var image: UIImage?
    @State private var lines: [OCRLine] = []
    @State private var hits: [ScanEngine.MoveHit] = []
    @State private var selected: [Int] = []
    @State private var error: String?
    @State private var showManual = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    switch phase {
                    case .pick:
                        ScanIntro(icon: "list.bullet.rectangle",
                                  title: L("Attacken scannen", "Scan moves"),
                                  text: L("Fotografiere den Attacken-Bildschirm von \(member.displayName). Die erkannten Attacken werden direkt eingetragen.",
                                          "Take a photo of \(member.displayName)'s moves screen. The detected moves are added right away."),
                                  tips: [L("Deutsches oder englisches Spiel", "German or English game"),
                                         L("Screenshot der Switch oder Foto vom Bildschirm", "Switch screenshot or photo of the screen"),
                                         L("Attacken-Namen sollten gut lesbar sein", "Move names should be clearly readable")],
                                  game: game)
                        ImageSourceButtons { img in process(img) }
                        if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.footnote) }
                    case .working:
                        WorkingView(image: image)
                    case .review:
                        review
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(member.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                if phase == .review {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Übernehmen", "Apply")) {
                            member.applyScannedMoves(selected)
                            member.team?.touch()
                            dismiss()
                        }
                        .disabled(selected.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $showManual) {
                OptionPicker(title: L("Attacke hinzufügen", "Add move"), options: PickerOptions.moves(Dex.shared.learnset(for: member.pokemonId, game: game)), selected: nil) { id in
                    guard let id else { return }
                    if !hits.contains(where: { $0.moveId == id }) { hits.append(.init(moveId: id, line: "", order: hits.count)) }
                    toggle(id, force: true)
                }
            }
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .frame(maxWidth: .infinity)
            }
            if hits.isEmpty {
                ContentUnavailableView(L("Keine Attacken erkannt", "No moves found"), systemImage: "text.magnifyingglass",
                                       description: Text(L("Versuche ein schärferes Foto oder einen Screenshot.", "Try a sharper photo or a screenshot.")))
            } else {
                Text(L("Gefundene Attacken (\(selected.count)/4 ausgewählt)", "Found moves (\(selected.count)/4 selected)"))
                    .font(.headline)
                VStack(spacing: 0) {
                    ForEach(hits) { hit in
                        if let move = Dex.shared.move(hit.moveId) {
                            Button { toggle(hit.moveId) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selected.contains(hit.moveId) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(selected.contains(hit.moveId) ? Color.accentColor : Color(.tertiaryLabel))
                                    MoveRow(move: move)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 50)
                        }
                    }
                }
                .card()
                Text(L("Die ausgewählten Attacken kommen auf die ersten Plätze, bestehende Attacken füllen den Rest auf.",
                       "Selected moves go into the first slots, existing moves fill the rest."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button { showManual = true } label: { Label(L("Manuell", "Manual"), systemImage: "plus").frame(maxWidth: .infinity) }
                Button { phase = .pick } label: { Label(L("Neues Foto", "New photo"), systemImage: "camera").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            RecognizedTextView(lines: lines)
        }
    }

    private func toggle(_ id: Int, force: Bool = false) {
        if let i = selected.firstIndex(of: id) {
            if !force { selected.remove(at: i) }
        } else if selected.count < 4 {
            selected.append(id)
        }
    }

    private func process(_ img: UIImage) {
        image = img
        error = nil
        phase = .working
        Task {
            do {
                let result = try await TextScanner.recognize(img)
                lines = result
                hits = ScanEngine.moves(from: result, game: game, pokemonId: member.pokemonId)
                selected = Array(hits.prefix(4).map(\.moveId))
                withAnimation { phase = .review }
            } catch {
                self.error = error.localizedDescription
                phase = .pick
            }
        }
    }
}

// MARK: - Pokémon / team scan

struct MemberScanSheet: View {
    enum Mode {
        case team
        /// summary screen of one Pokémon, with the current Pokémon as fallback
        case single(Int?)
    }

    let game: Game
    let mode: Mode
    var onApply: ([ScannedMember]) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Phase { case pick, working, review }
    private enum Field: Identifiable {
        case species(UUID), item(UUID), ability(UUID), nature(UUID)
        var id: String {
            switch self {
            case .species(let u): return "s\(u)"
            case .item(let u): return "i\(u)"
            case .ability(let u): return "a\(u)"
            case .nature(let u): return "n\(u)"
            }
        }
    }

    @State private var phase = Phase.pick
    @State private var image: UIImage?
    @State private var lines: [OCRLine] = []
    @State private var results: [ScannedMember] = []
    @State private var editing: Field?
    @State private var error: String?

    private var isTeam: Bool { if case .team = mode { return true } else { return false } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    switch phase {
                    case .pick:
                        ScanIntro(icon: isTeam ? "person.3.fill" : "text.viewfinder",
                                  title: isTeam ? L("Team scannen", "Scan team") : L("Übersicht scannen", "Scan summary"),
                                  text: isTeam
                                    ? L("Fotografiere den Team-Bildschirm. Erkannt werden Pokémon, Level, Items und mehr.",
                                        "Take a photo of the team screen. Pokémon, levels, items and more are detected.")
                                    : L("Fotografiere die Übersichtsseite eines Pokémon.", "Take a photo of a Pokémon's summary page."),
                                  tips: [L("Funktioniert mit deutschem und englischem Spiel", "Works with German and English games"),
                                         L("Spitznamen werden evtl. nicht erkannt – einfach antippen und korrigieren", "Nicknames may not be detected – just tap to fix"),
                                         L("Danach jede Attacken-Seite einzeln scannen", "Afterwards scan each moves page")],
                                  game: game)
                        ImageSourceButtons { process($0) }
                        if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.footnote) }
                    case .working:
                        WorkingView(image: image)
                    case .review:
                        review
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(isTeam ? L("Team scannen", "Scan team") : L("Übersicht scannen", "Scan summary"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                if phase == .review {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Übernehmen", "Apply")) {
                            onApply(results.filter { $0.include && ($0.pokemonId != nil || !isTeam) })
                            dismiss()
                        }
                        .disabled(!results.contains { $0.include && ($0.pokemonId != nil || !isTeam) })
                    }
                }
            }
            .sheet(item: $editing) { field in fieldPicker(field) }
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .frame(maxWidth: .infinity)
            }
            if results.isEmpty {
                ContentUnavailableView(L("Keine Pokémon erkannt", "No Pokémon found"), systemImage: "text.magnifyingglass",
                                       description: Text(L("Versuche ein schärferes Foto oder füge ein Pokémon manuell hinzu.", "Try a sharper photo or add a Pokémon manually.")))
            }
            ForEach($results) { $r in
                ScannedRow(result: $r, showToggle: isTeam) { field in
                    switch field {
                    case 0: editing = .species(r.id)
                    case 1: editing = .item(r.id)
                    case 2: editing = .ability(r.id)
                    default: editing = .nature(r.id)
                    }
                }
            }
            HStack(spacing: 10) {
                if isTeam && results.count < 6 {
                    Button {
                        let r = ScannedMember()
                        results.append(r)
                        editing = .species(r.id)
                    } label: { Label(L("Pokémon", "Pokémon"), systemImage: "plus").frame(maxWidth: .infinity) }
                }
                Button { phase = .pick } label: { Label(L("Neues Foto", "New photo"), systemImage: "camera").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            RecognizedTextView(lines: lines)
        }
    }

    @ViewBuilder
    private func fieldPicker(_ field: Field) -> some View {
        let dex = Dex.shared
        switch field {
        case .species(let u):
            OptionPicker(title: L("Pokémon wählen", "Choose Pokémon"), options: PickerOptions.pokemon(game: game), selected: value(u)?.pokemonId) { id in
                update(u) { $0.pokemonId = id }
            }
        case .item(let u):
            OptionPicker(title: L("Item wählen", "Choose item"), options: PickerOptions.items(game: game), selected: value(u)?.itemId, allowNone: true) { id in
                update(u) { $0.itemId = id }
            }
        case .ability(let u):
            let options: [PickerOption] = {
                if let pid = value(u)?.pokemonId, let p = dex.pokemon(pid) { return PickerOptions.abilities(dex.abilities(for: p), hidden: p.ha) }
                return PickerOptions.allAbilities()
            }()
            OptionPicker(title: L("Fähigkeit wählen", "Choose ability"), options: options, selected: value(u)?.abilityId, allowNone: true) { id in
                update(u) { $0.abilityId = id }
            }
        case .nature(let u):
            OptionPicker(title: L("Wesen wählen", "Choose nature"), options: PickerOptions.natures(), selected: value(u)?.natureId, allowNone: true) { id in
                update(u) { $0.natureId = id }
            }
        }
    }

    private func value(_ id: UUID) -> ScannedMember? { results.first { $0.id == id } }

    private func update(_ id: UUID, _ change: (inout ScannedMember) -> Void) {
        guard let i = results.firstIndex(where: { $0.id == id }) else { return }
        change(&results[i])
    }

    private func process(_ img: UIImage) {
        image = img
        error = nil
        phase = .working
        Task {
            do {
                let result = try await TextScanner.recognize(img)
                lines = result
                switch mode {
                case .team:
                    results = ScanEngine.members(from: result, game: game, single: false)
                case .single(let fallback):
                    results = ScanEngine.members(from: result, game: game, single: true, fallbackPokemonId: fallback)
                }
                withAnimation { phase = .review }
            } catch {
                self.error = error.localizedDescription
                phase = .pick
            }
        }
    }
}

private struct ScannedRow: View {
    @Binding var result: ScannedMember
    var showToggle: Bool
    var onEdit: (Int) -> Void

    var body: some View {
        let dex = Dex.shared
        let p = result.pokemonId.flatMap { dex.pokemon($0) }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button { onEdit(0) } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color(.tertiarySystemFill))
                            if let p { PokemonSprite(pokemonId: p.id).padding(4) } else { Image(systemName: "questionmark").foregroundStyle(.secondary) }
                        }
                        .frame(width: 54, height: 54)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p?.name ?? L("Pokémon wählen", "Choose Pokémon")).font(.headline).foregroundStyle(p == nil ? .orange : .primary)
                            if let p {
                                HStack(spacing: 4) { ForEach(p.t, id: \.self) { TypeBadge(typeId: $0, small: true) } }
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                if showToggle {
                    Toggle("", isOn: $result.include).labelsHidden()
                }
            }
            AppStepper(value: Binding(get: { result.level ?? 50 }, set: { result.level = $0 }), in: 1...100) {
                HStack {
                    Text(L("Level", "Level")).font(.subheadline)
                    Spacer()
                    Text(result.level.map { "\($0)" } ?? "–").font(.subheadline.monospacedDigit()).foregroundStyle(result.level == nil ? .tertiary : .secondary)
                }
            }
            chip(L("Item", "Item"), result.itemId.flatMap { dex.item($0)?.name }) { onEdit(1) }
            chip(L("Fähigkeit", "Ability"), result.abilityId.flatMap { dex.ability($0)?.name }) { onEdit(2) }
            chip(L("Wesen", "Nature"), result.natureId.flatMap { dex.nature($0)?.name }) { onEdit(3) }
            if !result.moveIds.isEmpty {
                FlowMoves(ids: result.moveIds)
            }
        }
        .padding(14)
        .card()
        .opacity(result.include ? 1 : 0.5)
    }

    private func chip(_ title: String, _ value: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.subheadline).foregroundStyle(.primary)
                Spacer()
                Text(value ?? L("nicht erkannt", "not found")).font(.subheadline).foregroundStyle(value == nil ? .tertiary : .secondary)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct FlowMoves: View {
    let ids: [Int]
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
            ForEach(ids, id: \.self) { id in
                if let m = Dex.shared.move(id) {
                    HStack(spacing: 5) {
                        Circle().fill(TypeColor.color(m.t)).frame(width: 7, height: 7)
                        Text(m.name).font(.caption).lineLimit(1)
                    }
                }
            }
        }
    }
}
