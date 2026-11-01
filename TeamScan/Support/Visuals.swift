import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

enum TypeColor {
    static func color(_ id: Int) -> Color {
        switch id {
        case T.normal: return Color(hex: 0x9FA19F)
        case T.fighting: return Color(hex: 0xFF8000)
        case T.flying: return Color(hex: 0x81B9EF)
        case T.poison: return Color(hex: 0x9141CB)
        case T.ground: return Color(hex: 0x915121)
        case T.rock: return Color(hex: 0xAFA981)
        case T.bug: return Color(hex: 0x91A119)
        case T.ghost: return Color(hex: 0x704170)
        case T.steel: return Color(hex: 0x60A1B8)
        case T.fire: return Color(hex: 0xE62829)
        case T.water: return Color(hex: 0x2980EF)
        case T.grass: return Color(hex: 0x3FA129)
        case T.electric: return Color(hex: 0xF5C200)
        case T.psychic: return Color(hex: 0xEF4179)
        case T.ice: return Color(hex: 0x3DCEF3)
        case T.dragon: return Color(hex: 0x5060E1)
        case T.dark: return Color(hex: 0x624D4E)
        case T.fairy: return Color(hex: 0xEF70EF)
        case T.stellar: return Color(hex: 0x40B5A5)
        default: return .gray
        }
    }
}

// MARK: - Sprites

enum SpriteStyle: String, CaseIterable, Identifiable {
    case pixel, home
    var id: String { rawValue }
    var label: String { self == .pixel ? L("Pixel", "Pixel") : "3D" }
}

enum SpriteURLs {
    private static let base = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/"

    /// Official type icons: Champions (symbol only) or the pixel label of X / Y (Black 2 / White 2 has no Fairy type yet).
    static func typeIcon(_ id: Int, pixel: Bool) -> [URL] {
        let path = pixel ? "types/generation-vi/x-y/\(id).png" : "types/generation-ix/champions/small/\(id).png"
        return [URL(string: base + path)].compactMap { $0 }
    }

    /// Trainer sprite from Pokémon Showdown (same host as the animated fallback sprites).
    static func trainer(_ name: String) -> URL? {
        URL(string: "https://play.pokemonshowdown.com/sprites/trainers/\(name).png")
    }

    static func pokemon(_ id: Int, shiny: Bool, style: SpriteStyle) -> [URL] {
        let keys = Dex.shared.pokemon(id)?.spriteKeys ?? [String(id)]
        return keys.flatMap { pokemon(key: $0, shiny: shiny, style: style) }
    }

    static func pokemon(key: String, shiny: Bool, style: SpriteStyle) -> [URL] {
        let s = shiny ? "shiny/" : ""
        let pixel = "\(base)pokemon/\(s)\(key).png"
        let home = "\(base)pokemon/other/home/\(s)\(key).png"
        let art = "\(base)pokemon/other/official-artwork/\(s)\(key).png"
        let order = style == .pixel ? [pixel, home, art] : [home, art, pixel]
        return order.compactMap(URL.init(string:))
    }

    static func item(_ key: String) -> URL? {
        URL(string: "\(base)items/\(key).png")
    }
}

/// Small memory + disk cache for sprites.
final class ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSURL, UIImage>()
    private var failed = Set<URL>()
    private var running: [URL: Task<(UIImage?, Bool), Never>] = [:]
    private let directory: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("sprites", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memory.countLimit = 600
    }

    private func file(for url: URL) -> URL {
        let name = url.absoluteString
            .replacingOccurrences(of: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/", with: "")
            .replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent(name)
    }

    func cached(_ url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let img = memory.object(forKey: url as NSURL) { return img }
        if failed.contains(url) { return nil }
        let path = file(for: url)
        if let data = try? Data(contentsOf: path), let img = UIImage(data: data) {
            memory.setObject(img, forKey: url as NSURL)
            return img
        }
        if let task = running[url] { return await task.value.0 }
        let task = Task<(UIImage?, Bool), Never> {
            guard let (data, response) = try? await URLSession.shared.data(from: url) else { return (nil, false) }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200, let img = UIImage(data: data) else { return (nil, status == 404) }
            try? data.write(to: path)
            return (img, false)
        }
        running[url] = task
        let (img, missing) = await task.value
        running[url] = nil
        if let img { memory.setObject(img, forKey: url as NSURL) }
        // only remember real 404s – a network hiccup must not hide the sprite for the rest of the session
        else if missing { failed.insert(url) }
        return img
    }
}

struct RemoteImage: View {
    let urls: [URL]
    var pixelated = false
    var placeholder = "questionmark"

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(pixelated ? .none : .high)
                    .scaledToFit()
            } else if failed {
                Image(systemName: placeholder)
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            } else {
                Color.clear.overlay(ProgressView().controlSize(.small))
            }
        }
        .task(id: urls) {
            if let first = urls.first, let img = ImageCache.shared.cached(first) {
                image = img
                return
            }
            failed = false
            for url in urls {
                if let img = await ImageCache.shared.image(for: url) {
                    image = img
                    return
                }
            }
            image = nil
            failed = true
        }
    }
}

struct PokemonSprite: View {
    let pokemonId: Int
    var shiny = false
    @AppStorage("spriteStyle") private var styleRaw = SpriteStyle.home.rawValue

    var body: some View {
        let style = SpriteStyle(rawValue: styleRaw) ?? .home
        RemoteImage(urls: SpriteURLs.pokemon(pokemonId, shiny: shiny, style: style), pixelated: style == .pixel)
    }
}

struct ItemIcon: View {
    let item: DexItem?
    var body: some View {
        if let item, let url = SpriteURLs.item(item.key) {
            RemoteImage(urls: [url], pixelated: true, placeholder: "bag")
        } else {
            Image(systemName: "bag").foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Badges

struct TypeBadge: View {
    let typeId: Int
    var small = false

    var body: some View {
        Text(Dex.shared.type(typeId)?.name ?? "?")
            .font(small ? .system(size: 10, weight: .bold) : .caption.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(.white)
            .padding(.horizontal, small ? 6 : 9)
            .padding(.vertical, small ? 2 : 4)
            .background(TypeColor.color(typeId).gradient, in: Capsule())
    }
}

struct CategoryBadge: View {
    let category: Int
    var body: some View {
        let (text, color): (String, Color) = {
            switch category {
            case 2: return (L("Phys.", "Phys."), Color(hex: 0xE5583A))
            case 3: return (L("Spez.", "Spec."), Color(hex: 0x4F78E0))
            default: return ("Status", Color(hex: 0x8E8E93))
            }
        }()
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }
}

struct ShinyBadge: View {
    var body: some View {
        Image(systemName: "sparkles")
            .font(.caption.weight(.bold))
            .foregroundStyle(.yellow.gradient)
            .shadow(color: .orange.opacity(0.5), radius: 2)
    }
}

/// Card background used across the app.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Card with a coloured edge on the left: a coloured card lies behind the grey one and shows
/// as a rounded crescent (follows the corners).
struct AccentCardBackground: ViewModifier {
    let colors: [Color]
    var width: CGFloat = 7

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        content
            .background(Color(.secondarySystemGroupedBackground), in: shape)
            .padding(.leading, width)
            .background(LinearGradient(colors: colors.count > 1 ? colors : colors + colors, startPoint: .top, endPoint: .bottom), in: shape)
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
    func accentCard(_ colors: [Color], width: CGFloat = 7) -> some View { modifier(AccentCardBackground(colors: colors, width: width)) }
}


// MARK: - Battle mechanic logos

enum Mechanic {
    case mega, gmax, tera, zMove

    var asset: String {
        switch self {
        case .mega: return "mechanic-mega"
        case .gmax: return "mechanic-gmax"
        case .tera: return "mechanic-tera"
        case .zMove: return "mechanic-z"
        }
    }

    /// The Z-Crystal is a coloured picture, the others are one-colour logos that follow the text colour.
    var isTemplate: Bool { self != .zMove }
}

struct MechanicLogo: View {
    let mechanic: Mechanic
    var size: CGFloat = 18

    var body: some View {
        Image(mechanic.asset)
            .renderingMode(mechanic.isTemplate ? .template : .original)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Logo of a game's battle mechanic, or a fitting symbol for games without one.
struct GameMechanicIcon: View {
    let game: Game
    var size: CGFloat = 18

    var body: some View {
        if let m = game.mechanicLogo {
            MechanicLogo(mechanic: m, size: size)
        } else {
            Image(systemName: game.mechanicIcon)
                .font(.system(size: size * 0.8, weight: .bold))
                .frame(width: size, height: size)
        }
    }
}

/// Small round badge with a mechanic logo, e.g. on team cards and in the Pokédex list.
struct MechanicBadge: View {
    let mechanic: Mechanic
    var size: CGFloat = 22

    var body: some View {
        MechanicLogo(mechanic: mechanic, size: size * 0.66)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: mechanic == .gmax ? [Color(hex: 0xE5007E), Color(hex: 0x9B1C8C)] : [.pink, .purple],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
    }
}


/// Trainer sprite (pixel art from Pokémon Showdown); a person symbol when there is none.
struct TrainerSprite: View {
    let avatar: String?

    var body: some View {
        if let avatar, let url = SpriteURLs.trainer(avatar) {
            RemoteImage(urls: [url], pixelated: true, placeholder: "person.fill")
        } else {
            Image(systemName: "person.fill").font(.title2).foregroundStyle(.tertiary)
        }
    }
}

/// One line of text that slowly scrolls back and forth when it doesn't fit (instead of "…").
struct MarqueeText: View {
    let text: String
    var font: Font = .caption
    var color: Color = .secondary

    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var shift = false

    private var overflow: CGFloat { max(textWidth - boxWidth, 0) }

    var body: some View {
        // invisible copy: gives the line its height, may be narrower than the text
        Text(text)
            .font(font)
            .lineLimit(1)
            .hidden()
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    let width = geo.size.width
                    Text(text)
                        .font(font)
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .fixedSize()
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
                        .offset(x: shift ? -overflow : 0)
                        .frame(width: width, alignment: .leading)
                        .onAppear { boxWidth = width }
                        .onChange(of: width) { _, w in boxWidth = w }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            // soft edges while it moves
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: overflow > 0 && shift ? 8 : 0)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: overflow > 0 && !shift ? 8 : 0)
                }
            }
            .task(id: overflow) {
                shift = false
                guard overflow > 1 else { return }
                let duration = Double(overflow) / 22 + 0.6
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1.6))
                    withAnimation(.easeInOut(duration: duration)) { shift = true }
                    try? await Task.sleep(for: .seconds(duration + 1.6))
                    withAnimation(.easeInOut(duration: duration)) { shift = false }
                    try? await Task.sleep(for: .seconds(duration))
                }
            }
    }
}
