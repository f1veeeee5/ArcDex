import SwiftUI
import UIKit
import ImageIO

// MARK: - URLs

extension SpriteURLs {
    /// Animated sprites in the Gen-5 pixel style (Black/White and community sprites for later Pokémon).
    /// Only when `includeShowdown` is on, the Showdown animations (3D-like look) fill the gaps.
    static func animated(_ id: Int, shiny: Bool, includeShowdown: Bool) -> [URL] {
        // no fallback to the base species for real forms (Alola, Mega …) – a wrong animation is worse than a still image
        let all = Dex.shared.pokemon(id)?.spriteKeys ?? [String(id)]
        let keys = id >= 20000 ? all : Array(all.prefix(1))
        let s = shiny ? "shiny/" : ""
        let root = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/"
        var list = keys.map { "\(root)versions/generation-v/black-white/animated/\(s)\($0).gif" }
        if includeShowdown {
            list += keys.map { "\(root)other/showdown/\(s)\($0).gif" }
        }
        return list.compactMap(URL.init(string:))
    }

    /// Still Black/White sprite (same look as the animations, Pokémon up to Gen 5).
    static func gen5Still(_ id: Int, shiny: Bool) -> [URL] {
        guard id <= 649 else { return [] }
        let s = shiny ? "shiny/" : ""
        return [URL(string: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/\(s)\(id).png")].compactMap { $0 }
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
    private var running: [URL: Task<Fetch, Never>] = [:]
    private let directory: URL

    private final class AnimationBox {
        let value: Animation
        init(_ value: Animation) { self.value = value }
    }

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("animated-sprites", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memory.countLimit = 40
    }

    private func file(for url: URL) -> URL {
        // full path, so "black-white/animated/shiny/1.gif" and "showdown/shiny/1.gif" never share a file
        let name = url.pathComponents.drop { $0 != "pokemon" }.joined(separator: "_")
        return directory.appendingPathComponent(name)
    }

    func cached(_ url: URL) -> Animation? { memory.object(forKey: url as NSURL)?.value }

    /// Result of one download: the animation, "does not exist" (404) or a temporary problem (no network …).
    private enum Fetch {
        case found(Animation)
        case missing
        case temporary
    }

    func animation(for url: URL) async -> Animation? {
        if let a = cached(url) { return a }
        if failed.contains(url) { return nil }
        if let task = running[url] {
            if case .found(let a) = await task.value { return a }
            return nil
        }
        let path = file(for: url)
        let task = Task<Fetch, Never> {
            if let data = try? Data(contentsOf: path),
               let a = await Task.detached(priority: .userInitiated, operation: { GIFCache.decode(data) }).value {
                return .found(a)
            }
            // two tries – a single hiccup must not make the animation disappear until the next app start
            for attempt in 0..<2 {
                if attempt > 0 { try? await Task.sleep(for: .milliseconds(600)) }
                guard let (d, response) = try? await URLSession.shared.data(from: url),
                      let http = response as? HTTPURLResponse else { continue }
                if http.statusCode == 404 { return .missing }
                guard http.statusCode == 200,
                      let a = await Task.detached(priority: .userInitiated, operation: { GIFCache.decode(d) }).value else { continue }
                try? d.write(to: path)
                return .found(a)
            }
            return .temporary
        }
        running[url] = task
        let result = await task.value
        running[url] = nil
        switch result {
        case .found(let a):
            memory.setObject(AnimationBox(a), forKey: url as NSURL)
            return a
        case .missing:
            failed.insert(url)
            return nil
        case .temporary:
            return nil
        }
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
    /// true: the feet sit on the bottom edge of the frame (for the Pokédex platform),
    /// instead of the sprite being centred with its empty border
    var grounded = false
    @AppStorage("spriteStyle") private var styleRaw = SpriteStyle.home.rawValue
    @AppStorage("animatedSprites") private var animatedOn = true
    @AppStorage("animatedFallback") private var fallbackOn = false
    @State private var animation: GIFCache.Animation?
    @State private var missing = false
    /// empty rows below the Pokémon in the still picture (rows, picture size)
    @State private var footing: SpriteFooting.Result?

    private var wantsAnimation: Bool { animatedOn && styleRaw == SpriteStyle.pixel.rawValue }

    private var stillURLs: [URL] {
        wantsAnimation
            ? SpriteURLs.gen5Still(pokemonId, shiny: shiny) + SpriteURLs.pokemon(pokemonId, shiny: shiny, style: .pixel)
            : SpriteURLs.pokemon(pokemonId, shiny: shiny, style: SpriteStyle(rawValue: styleRaw) ?? .home)
    }

    var body: some View {
        Group {
            if wantsAnimation, let animation {
                GIFView(animation: animation, grounded: grounded)
            } else if grounded {
                GeometryReader { geo in
                    still
                        .frame(width: geo.size.width, height: geo.size.height)
                        .offset(y: stillOffset(in: geo.size))
                }
            } else {
                still
            }
        }
        .task(id: "\(pokemonId)-\(shiny)-\(wantsAnimation)-\(fallbackOn)") {
            animation = nil
            missing = false
            if wantsAnimation {
                for url in SpriteURLs.animated(pokemonId, shiny: shiny, includeShowdown: fallbackOn) {
                    if let a = await GIFCache.shared.animation(for: url) {
                        animation = a
                        return
                    }
                }
                missing = true
            }
        }
        .task(id: "\(pokemonId)-\(shiny)-\(styleRaw)-\(grounded)-foot") {
            footing = nil
            guard grounded else { return }
            for url in stillURLs {
                if let img = await ImageCache.shared.image(for: url) {
                    footing = SpriteFooting.measure([img])
                    return
                }
            }
        }
    }

    @ViewBuilder private var still: some View {
        if wantsAnimation {
            // still picture in the same Gen-5 style while the animation loads or when there is none
            RemoteImage(urls: stillURLs, pixelated: true)
        } else {
            PokemonSprite(pokemonId: pokemonId, shiny: shiny)
        }
    }

    /// How far to move the still picture down so its lowest pixel touches the bottom edge.
    private func stillOffset(in size: CGSize) -> CGFloat {
        guard let f = footing, f.width > 0, f.height > 0 else { return 0 }
        let scale = min(size.width / f.width, size.height / f.height)
        let shown = f.height * scale
        return (size.height - shown) / 2 + f.emptyRows * scale
    }
}

/// Measures how many fully transparent rows a sprite has below the Pokémon.
enum SpriteFooting {
    struct Result: Equatable {
        let emptyRows: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    /// For several frames: the smallest gap (lowest point over the whole animation).
    static func measure(_ images: [UIImage]) -> Result? {
        var best: Result?
        for image in images {
            guard let r = measure(image) else { continue }
            if best == nil || r.emptyRows < best!.emptyRows { best = r }
        }
        return best
    }

    private static func measure(_ image: UIImage) -> Result? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0, w * h <= 1_200_000 else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        // the context's memory starts with the top row
        var empty = 0
        rows: for row in stride(from: h - 1, through: 0, by: -1) {
            let start = row * w * 4
            for x in 0..<w where pixels[start + x * 4 + 3] > 24 { break rows }
            empty += 1
        }
        guard empty < h else { return nil }
        // image size in points (frames of a GIF are in pixels = points here)
        let factor = image.size.height / CGFloat(h)
        return Result(emptyRows: CGFloat(empty) * factor, width: image.size.width, height: image.size.height)
    }
}

/// Plays a decoded GIF with sharp pixels, scaled like the classic 96 px sprites.
struct GIFView: UIViewRepresentable {
    let animation: GIFCache.Animation
    var grounded = false

    func makeUIView(context: Context) -> GIFContainer { GIFContainer() }

    func updateUIView(_ view: GIFContainer, context: Context) {
        view.grounded = grounded
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
    /// empty rows below the Pokémon (over all frames), in sprite pixels
    private var emptyBottom: CGFloat = 0
    var grounded = false { didSet { if grounded != oldValue { setNeedsLayout() } } }

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
        if let f = SpriteFooting.measure(animation.frames), f.height > 0 {
            emptyBottom = f.emptyRows * spriteSize.height / f.height
        } else {
            emptyBottom = 0
        }
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
        // grounded: lowest pixel on the bottom edge, otherwise centred
        let y = grounded ? bounds.height - size.height + emptyBottom * scale : (bounds.height - size.height) / 2
        imageView.frame = CGRect(x: (bounds.width - size.width) / 2, y: y,
                                 width: size.width, height: size.height)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, !current.isEmpty, !imageView.isAnimating { imageView.startAnimating() }
    }
}
