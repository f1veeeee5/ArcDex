import SwiftUI
import UIKit
import ImageIO

// MARK: - URLs

extension SpriteURLs {
    /// Animated 2D sprites (Showdown style) from the PokeAPI sprite repository.
    static func animated(_ id: Int, shiny: Bool) -> [URL] {
        let keys = Dex.shared.pokemon(id)?.spriteKeys ?? [String(id)]
        let s = shiny ? "shiny/" : ""
        return keys.compactMap {
            URL(string: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/showdown/\(s)\($0).gif")
        }
    }
}

// MARK: - GIF cache

/// Memory + disk cache for animated GIFs (kept as decoded frames).
final class GIFCache {
    static let shared = GIFCache()

    struct Animation {
        let frames: [UIImage]
        let duration: TimeInterval
        let size: CGSize
    }

    private let memory = NSCache<NSURL, AnimationBox>()
    private var failed = Set<URL>()
    private var running: [URL: Task<Animation?, Never>] = [:]
    private let directory: URL

    private final class AnimationBox {
        let value: Animation
        init(_ value: Animation) { self.value = value }
    }

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("animated", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memory.countLimit = 40
    }

    private func file(for url: URL) -> URL {
        let name = url.pathComponents.suffix(2).joined(separator: "_")
        return directory.appendingPathComponent(name)
    }

    func cached(_ url: URL) -> Animation? { memory.object(forKey: url as NSURL)?.value }

    func animation(for url: URL) async -> Animation? {
        if let a = cached(url) { return a }
        if failed.contains(url) { return nil }
        if let task = running[url] { return await task.value }
        let path = file(for: url)
        let task = Task<Animation?, Never> {
            var data = try? Data(contentsOf: path)
            if data == nil {
                guard let (d, response) = try? await URLSession.shared.data(from: url),
                      (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                try? d.write(to: path)
                data = d
            }
            guard let data else { return nil }
            return await Task.detached(priority: .userInitiated) { GIFCache.decode(data) }.value
        }
        running[url] = task
        let result = await task.value
        running[url] = nil
        if let result { memory.setObject(AnimationBox(result), forKey: url as NSURL) } else { failed.insert(url) }
        return result
    }

    nonisolated static func decode(_ data: Data) -> Animation? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        var frames: [UIImage] = []
        var total: TimeInterval = 0
        var size = CGSize.zero
        // Every frame is repeated as often as needed to keep its own delay (UIImage animations use one fixed frame time).
        let tick: TimeInterval = 0.02
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            var delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            if delay < 0.02 { delay = 0.1 }
            let image = UIImage(cgImage: cg)
            size = CGSize(width: max(size.width, CGFloat(cg.width)), height: max(size.height, CGFloat(cg.height)))
            let repeats = max(1, Int((delay / tick).rounded()))
            frames.append(contentsOf: Array(repeating: image, count: repeats))
            total += Double(repeats) * tick
        }
        guard !frames.isEmpty else { return nil }
        return Animation(frames: frames, duration: total, size: size)
    }
}

// MARK: - Views

/// Pokémon sprite that plays the animated 2D sprite (endless loop) when the user allows it,
/// otherwise – or when no animation exists – the normal sprite.
struct AnimatedPokemonSprite: View {
    let pokemonId: Int
    var shiny = false
    @AppStorage("spriteStyle") private var styleRaw = SpriteStyle.home.rawValue
    @AppStorage("animatedSprites") private var animatedOn = true
    @State private var animation: GIFCache.Animation?
    @State private var missing = false

    private var wantsAnimation: Bool { animatedOn && styleRaw == SpriteStyle.pixel.rawValue }

    var body: some View {
        Group {
            if wantsAnimation, let animation {
                GIFView(animation: animation)
            } else {
                // static sprite while the animation loads, when it is turned off or does not exist
                PokemonSprite(pokemonId: pokemonId, shiny: shiny)
            }
        }
        .task(id: "\(pokemonId)-\(shiny)-\(wantsAnimation)") {
            animation = nil
            missing = false
            guard wantsAnimation else { return }
            for url in SpriteURLs.animated(pokemonId, shiny: shiny) {
                if let a = await GIFCache.shared.animation(for: url) {
                    animation = a
                    return
                }
            }
            missing = true
        }
    }
}

/// Plays a decoded GIF with sharp pixels, scaled like the classic 96 px sprites.
struct GIFView: UIViewRepresentable {
    let animation: GIFCache.Animation

    func makeUIView(context: Context) -> GIFContainer { GIFContainer() }

    func updateUIView(_ view: GIFContainer, context: Context) {
        view.set(animation)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: GIFContainer, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? animation.size.width, height: proposal.height ?? animation.size.height)
    }
}

final class GIFContainer: UIView {
    private let imageView = UIImageView()
    private var current: [UIImage] = []
    private var spriteSize = CGSize(width: 96, height: 96)

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.layer.magnificationFilter = .nearest
        imageView.contentMode = .scaleToFill
        addSubview(imageView)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(_ animation: GIFCache.Animation) {
        guard current.first !== animation.frames.first || current.count != animation.frames.count else { return }
        current = animation.frames
        spriteSize = animation.size
        imageView.stopAnimating()
        imageView.animationImages = animation.frames
        imageView.animationDuration = animation.duration
        imageView.animationRepeatCount = 0
        imageView.image = animation.frames.first
        imageView.startAnimating()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard spriteSize.width > 0, spriteSize.height > 0, bounds.width > 0 else { return }
        // same scale for every Pokémon (based on the 96 px game sprites), so big Pokémon look bigger –
        // but never larger than the available space
        let classic = min(bounds.width, bounds.height) / 96
        let fit = min(bounds.width / spriteSize.width, bounds.height / spriteSize.height)
        let scale = min(classic, fit)
        let size = CGSize(width: spriteSize.width * scale, height: spriteSize.height * scale)
        imageView.frame = CGRect(x: (bounds.width - size.width) / 2,
                                 y: (bounds.height - size.height) / 2,
                                 width: size.width, height: size.height)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, !current.isEmpty, !imageView.isAnimating { imageView.startAnimating() }
    }
}
