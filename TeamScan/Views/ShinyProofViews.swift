import SwiftUI
import AVKit
import UIKit
import UniformTypeIdentifiers

// MARK: - Storage

/// Photos / videos of the catch proof, kept in the app's Documents folder.
enum ProofStore {
    /// How long after the find a proof can still be added.
    static let window: TimeInterval = 24 * 60 * 60

    static var folder: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("ShinyProof", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(_ file: String) -> URL { folder.appendingPathComponent(file) }

    static func deadline(for hunt: ShinyHunt) -> Date? { hunt.foundAt.map { $0.addingTimeInterval(window) } }

    static func canAdd(_ hunt: ShinyHunt, now: Date = Date()) -> Bool {
        guard let d = deadline(for: hunt) else { return false }
        return now < d
    }

    static func save(image: UIImage, for hunt: ShinyHunt) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let name = "\(hunt.uuid.uuidString)-\(Int(Date().timeIntervalSince1970)).jpg"
        guard (try? data.write(to: url(name))) != nil else { return }
        replace(hunt, with: name, video: false)
    }

    static func save(video: URL, for hunt: ShinyHunt) {
        let name = "\(hunt.uuid.uuidString)-\(Int(Date().timeIntervalSince1970)).\(video.pathExtension.isEmpty ? "mov" : video.pathExtension)"
        guard (try? FileManager.default.copyItem(at: video, to: url(name))) != nil else { return }
        replace(hunt, with: name, video: true)
    }

    private static func replace(_ hunt: ShinyHunt, with name: String, video: Bool) {
        if let old = hunt.proofFile { try? FileManager.default.removeItem(at: url(old)) }
        hunt.proofFile = name
        hunt.proofIsVideo = video
        hunt.proofTakenAt = Date()
    }

    /// Picture for thumbnails and the share card (first frame of a video).
    static func thumbnail(for hunt: ShinyHunt) async -> UIImage? {
        guard let file = hunt.proofFile else { return nil }
        let u = url(file)
        if !hunt.proofIsVideo { return UIImage(contentsOfFile: u.path) }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: u))
        gen.appliesPreferredTrackTransform = true
        guard let (cg, _) = try? await gen.image(at: .zero) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Camera (photo or video, no photo library)

struct ProofCamera: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    var onVideo: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoMaximumDuration = 30
        picker.videoQuality = .typeMedium
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ProofCamera
        init(_ parent: ProofCamera) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let video = info[.mediaURL] as? URL {
                parent.onVideo(video)
            } else if let img = info[.originalImage] as? UIImage {
                parent.onImage(img)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - Proof card in the hunt

struct ShinyProofCard: View {
    @Bindable var hunt: ShinyHunt
    @State private var showCamera = false
    @State private var showViewer = false
    @State private var thumb: UIImage?
    @State private var cardImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L("Fang-Beleg", "Catch proof"), systemImage: hunt.proofFile != nil ? "checkmark.seal.fill" : "seal")
                    .font(.headline)
                    .foregroundStyle(hunt.proofFile != nil ? Color.green : Color.primary)
                Spacer()
                if hunt.proofFile != nil {
                    Text(L("belegt", "proven"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Color.green.opacity(0.15), in: Capsule())
                }
            }

            if hunt.proofFile != nil {
                Button { showViewer = true } label: {
                    ZStack {
                        if let thumb {
                            Image(uiImage: thumb).resizable().scaledToFill()
                        } else {
                            Color(.tertiarySystemFill)
                        }
                        if hunt.proofIsVideo {
                            Image(systemName: "play.circle.fill").font(.system(size: 44)).foregroundStyle(.white).shadow(radius: 6)
                        }
                    }
                    .frame(height: 190)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                if let taken = hunt.proofTakenAt, let found = hunt.foundAt {
                    Text(L("Aufgenommen \(taken.formatted(.dateTime.day().month().hour().minute())) · \(delay(taken.timeIntervalSince(found))) nach dem Fund",
                           "Taken \(taken.formatted(.dateTime.day().month().hour().minute())) · \(delay(taken.timeIntervalSince(found))) after the find"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(L("Fotografiere oder filme den Bildschirm deiner Konsole mit dem Shiny. Nur direkt mit der App-Kamera – nicht aus der Galerie.",
                       "Take a photo or video of your console screen with the shiny. Only with the app camera – not from the gallery."))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TimelineView(.periodic(from: .now, by: 60)) { context in
                if ProofStore.canAdd(hunt, now: context.date), let deadline = ProofStore.deadline(for: hunt) {
                    VStack(spacing: 6) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { showCamera = true } label: {
                                Label(hunt.proofFile == nil ? L("Fang-Beleg aufnehmen", "Record catch proof") : L("Neu aufnehmen", "Record again"),
                                      systemImage: "camera.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(hunt.proofFile == nil ? AppButtonStyle(kind: .primary) : AppButtonStyle(kind: .secondary))
                        }
                        Text(L("Noch \(remaining(deadline.timeIntervalSince(context.date))) Zeit", "\(remaining(deadline.timeIntervalSince(context.date))) left"))
                            .font(.caption).foregroundStyle(.secondary)
                        #if DEBUG
                        Button { ProofStore.save(image: ProofStore.mockImage(for: hunt), for: hunt) } label: {
                            Label(L("Test-Foto einsetzen (nur Entwickler)", "Insert test photo (developer only)"), systemImage: "hammer.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.appSecondary)
                        .tint(.gray)
                        #endif
                    }
                } else if hunt.proofFile == nil {
                    Label(L("Kein Fang-Beleg – die 24 Stunden nach dem Fund sind vorbei.", "No catch proof – the 24 hours after the find are over."),
                          systemImage: "clock.badge.xmark")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if let cardImage {
                ShareLink(item: Image(uiImage: cardImage), preview: SharePreview(L("Shiny \(hunt.name)", "Shiny \(hunt.name)"), image: Image(uiImage: cardImage))) {
                    Label(L("Shiny-Karte teilen", "Share shiny card"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.appSecondary)
            }
        }
        .padding(16)
        .card()
        .fullScreenCover(isPresented: $showCamera) {
            ProofCamera(onImage: { ProofStore.save(image: $0, for: hunt) },
                        onVideo: { ProofStore.save(video: $0, for: hunt) })
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showViewer) { ProofViewer(hunt: hunt) }
        .task(id: "\(hunt.proofFile ?? "")-\(hunt.count)-\(hunt.foundAt?.timeIntervalSince1970 ?? 0)") {
            thumb = await ProofStore.thumbnail(for: hunt)
            cardImage = await ShinyShareCard.render(hunt: hunt, proof: thumb)
        }
    }

    private func delay(_ t: TimeInterval) -> String {
        let minutes = Int(max(t, 0) / 60)
        if minutes < 1 { return L("direkt", "right") }
        if minutes < 60 { return L("\(minutes) Min.", "\(minutes) min") }
        return L("\(minutes / 60) Std. \(minutes % 60) Min.", "\(minutes / 60) h \(minutes % 60) min")
    }

    private func remaining(_ t: TimeInterval) -> String {
        let minutes = Int(max(t, 0) / 60)
        return minutes >= 60 ? L("\(minutes / 60) Std. \(minutes % 60) Min.", "\(minutes / 60) h \(minutes % 60) min") : L("\(minutes) Min.", "\(minutes) min")
    }
}

/// Shows the proof photo or plays the video.
struct ProofViewer: View {
    let hunt: ShinyHunt
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let file = hunt.proofFile {
                    if hunt.proofIsVideo {
                        VideoPlayer(player: AVPlayer(url: ProofStore.url(file)))
                    } else if let img = UIImage(contentsOfFile: ProofStore.url(file).path) {
                        Image(uiImage: img).resizable().scaledToFit()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .navigationTitle(L("Fang-Beleg", "Catch proof"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Fertig", "Done")) { dismiss() } }
            }
        }
    }
}

// MARK: - Share card

/// Picture to share: shiny sprite, numbers of the hunt and – if there is one – the proof photo.
struct ShinyShareCard: View {
    let name: String
    let sprite: UIImage?
    let pixel: Bool
    let proof: UIImage?
    let rows: [(String, String)]
    let gameTitle: String
    let colors: [Color]

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label("Shiny!", systemImage: "sparkles").font(.title2.weight(.heavy))
                Spacer()
                Text(gameTitle).font(.subheadline.weight(.semibold)).opacity(0.85)
            }
            .foregroundStyle(.white)

            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle().fill(.white.opacity(0.18))
                    if let sprite {
                        Image(uiImage: sprite).resizable().interpolation(pixel ? .none : .high).scaledToFit().padding(10)
                    }
                }
                .frame(width: 150, height: 150)
                VStack(alignment: .leading, spacing: 8) {
                    Text(name).font(.title.weight(.bold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(row.0).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                            Text(row.1).font(.subheadline.weight(.bold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            if let proof {
                ZStack(alignment: .topLeading) {
                    Image(uiImage: proof).resizable().scaledToFill()
                        .frame(width: 332, height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Label(L("Fang-Beleg", "Catch proof"), systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.green, in: Capsule())
                        .padding(10)
                }
            }

            HStack {
                Spacer()
                Text("ArcDex").font(.caption.weight(.heavy)).foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    /// Loads the shiny sprite first – ImageRenderer can't wait for images from the internet.
    @MainActor
    static func render(hunt: ShinyHunt, proof: UIImage?) async -> UIImage? {
        let style = SpriteStyle(rawValue: UserDefaults.standard.string(forKey: "spriteStyle") ?? "") ?? .home
        var sprite: UIImage?
        for url in SpriteURLs.pokemon(hunt.pokemonId, shiny: true, style: style) {
            if let img = await ImageCache.shared.image(for: url) { sprite = img; break }
        }
        let hours = Int(hunt.totalTime() / 3600), minutes = Int(hunt.totalTime().truncatingRemainder(dividingBy: 3600) / 60)
        var rows: [(String, String)] = [
            (hunt.method.unit, "\(hunt.count)"),
            (L("Methode", "Method"), hunt.method.title),
            (L("Chance", "Odds"), hunt.odds.label(at: hunt.count)),
        ]
        if hunt.totalTime() > 0 { rows.append((L("Dauer", "Time"), hours > 0 ? "\(hours) h \(minutes) min" : "\(minutes) min")) }
        if let found = hunt.foundAt { rows.append((L("Gefunden", "Found"), found.formatted(.dateTime.day().month().year()))) }
        let card = ShinyShareCard(name: hunt.name, sprite: sprite, pixel: style == .pixel, proof: proof, rows: rows,
                                  gameTitle: hunt.game.title, colors: [Color(hex: 0xF7B733), Color(hex: 0xFC4A1A)])
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }
}
