import Foundation
import Security
import FoundationModels

// MARK: - Result

/// AI game plan of a team (stored with the team). Every section is a list of short bullet points.
nonisolated struct GamePlan: Codable, Equatable {
    nonisolated struct Role: Codable, Equatable, Identifiable {
        var pokemon: String
        var points: [String]
        var id: String { pokemon }

        init(pokemon: String, points: [String]) {
            self.pokemon = pokemon
            self.points = points
        }

        enum CodingKeys: String, CodingKey { case pokemon, points, role }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            pokemon = try c.decode(String.self, forKey: .pokemon).replacingOccurrences(of: "*", with: "")
            points = GamePlan.bullets(c, .points) ?? GamePlan.bullets(c, .role) ?? []
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(pokemon, forKey: .pokemon)
            try c.encode(points, forKey: .points)
        }
    }

    var summary: [String]
    var lead: [String]
    var winCondition: [String]
    var threats: [String]
    var roles: [Role]
    /// "apple" or a Claude model id
    var engine: String = "apple"
    var createdAt: Date = Date()
    /// team composition the plan was made for
    var signature: String = ""

    init(summary: [String], lead: [String], winCondition: [String], threats: [String], roles: [Role]) {
        self.summary = summary
        self.lead = lead
        self.winCondition = winCondition
        self.threats = threats
        self.roles = roles
    }

    enum CodingKeys: String, CodingKey { case summary, lead, winCondition, threats, roles, engine, createdAt, signature }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = GamePlan.bullets(c, .summary) ?? []
        lead = GamePlan.bullets(c, .lead) ?? []
        winCondition = GamePlan.bullets(c, .winCondition) ?? []
        threats = GamePlan.bullets(c, .threats) ?? []
        roles = (try? c.decode([Role].self, forKey: .roles)) ?? []
        engine = (try? c.decode(String.self, forKey: .engine)) ?? "apple"
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        signature = (try? c.decode(String.self, forKey: .signature)) ?? ""
    }

    /// A list of bullets – or one older plain text, split into sentences.
    static func bullets<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> [String]? {
        if let list = try? c.decode([String].self, forKey: key) { return clean(list) }
        if let text = try? c.decode(String.self, forKey: key) { return clean(sentences(text)) }
        return nil
    }

    static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sub, _, _, _ in
            if let sub { result.append(sub) }
        }
        return result.isEmpty ? [text] : result
    }

    static func clean(_ list: [String]) -> [String] {
        list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-•*·").union(.whitespaces)) }
            .filter { !$0.isEmpty }
    }
}

extension Team {
    var gamePlan: GamePlan? {
        get { gamePlanData.flatMap { try? JSONDecoder().decode(GamePlan.self, from: $0) } }
        set { gamePlanData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// Changes whenever Pokémon, moves, items, abilities, natures or the format change.
    var planSignature: String {
        let parts = sortedMembers.map { m in
            "\(m.battleForm(in: game)?.id ?? m.pokemonId):\(m.moveIds.map(String.init).joined(separator: ",")):\(m.itemId ?? 0):\(m.abilityId ?? 0):\(m.natureId ?? 0):\(m.teraTypeId ?? 0):\(m.level)"
        }
        return game.rawValue + "|" + battleFormat.rawValue + "|" + parts.joined(separator: ";")
    }
}

// MARK: - Settings

enum ClaudeModel: String, CaseIterable, Identifiable {
    case haiku = "claude-haiku-5-5"
    case sonnet = "claude-sonnet-5-5"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .haiku: return "Claude Haiku"
        case .sonnet: return "Claude Sonnet"
        }
    }
    var hint: String {
        switch self {
        case .haiku: return L("sehr günstig", "very cheap")
        case .sonnet: return L("beste Pläne", "best plans")
        }
    }
}

/// The Claude API key, kept in the iPhone's keychain (never in the app's files).
enum APIKeyStore {
    private static let service = "app.lukas.teamscan.claude"

    static var key: String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let s = String(data: data, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    static func save(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(base as CFDictionary)
        guard !trimmed.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(trimmed.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

// MARK: - Planner

enum GamePlanner {
    enum Engine: Equatable {
        case claude(ClaudeModel)
        case apple
        case none(String)

        var title: String {
            switch self {
            case .claude(let m): return m.title
            case .apple: return "Apple Intelligence"
            case .none: return ""
            }
        }
    }

    enum PlanError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            if case .message(let m) = self { return m }
            return nil
        }
    }

    /// Claude when a key is entered, otherwise Apple Intelligence (if the iPhone has it).
    static var engine: Engine {
        if APIKeyStore.key != nil {
            let raw = UserDefaults.standard.string(forKey: "claudeModel") ?? ClaudeModel.sonnet.rawValue
            return .claude(ClaudeModel(rawValue: raw) ?? .sonnet)
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .apple
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .none(L("Dieses iPhone unterstützt Apple Intelligence nicht. Trag in den Einstellungen einen Claude-Schlüssel ein, um Spielpläne zu erstellen.",
                               "This iPhone doesn't support Apple Intelligence. Enter a Claude key in Settings to create game plans."))
            case .appleIntelligenceNotEnabled:
                return .none(L("Apple Intelligence ist ausgeschaltet (Einstellungen → Apple Intelligence & Siri) – oder trag einen Claude-Schlüssel ein.",
                               "Apple Intelligence is turned off (Settings → Apple Intelligence & Siri) – or enter a Claude key."))
            case .modelNotReady:
                return .none(L("Das Apple-Modell wird gerade noch geladen. Versuch es später nochmal.",
                               "The Apple model is still downloading. Try again later."))
            @unknown default:
                return .none(L("Apple Intelligence ist gerade nicht verfügbar.", "Apple Intelligence is not available right now."))
            }
        }
    }

    @MainActor
    static func makePlan(for team: Team) async throws -> GamePlan {
        let facts = TeamFacts.text(for: team)
        let doubles = team.battleFormat == .doubles
        var plan: GamePlan
        switch engine {
        case .claude(let model):
            plan = try await claude(facts: facts, model: model, doubles: doubles)
            plan.engine = model.rawValue
        case .apple:
            plan = try await apple(facts: facts, doubles: doubles)
            plan.engine = "apple"
        case .none(let message):
            throw PlanError.message(message)
        }
        plan.createdAt = Date()
        plan.signature = team.planSignature
        return plan
    }

    private static var languageName: String { Lang.current == .de ? "German" : "English" }

    private static func instructions(doubles: Bool) -> String {
        let format = doubles
            ? """
              This is a DOUBLE BATTLE team: two Pokémon on each side at the same time. Name the lead PAIR, how the two support each other               (e.g. Protect, Fake Out, Tailwind, Trick Room, redirection, spread moves that hit both foes, partners that are immune to a spread move),               and which pair to bring in later.
              """
            : """
              This is a SINGLE BATTLE team: one Pokémon on each side. Name the single lead, when to switch, and the order in which to bring the others.
              """
        return """
        You are an experienced Pokémon coach. Write a practical, detailed game plan for the player's team in \(languageName).
        \(format)
        Use ONLY the facts given about the team (Pokémon, types, moves, items, abilities, stats, weaknesses).
        Do not invent moves, items or abilities the team doesn't have. Refer to Pokémon by the names given.
        Write SHORT BULLET POINTS, not paragraphs: 3–5 bullets per section, each bullet at most 15 words, one fact or action per bullet.
        Be concrete: which Pokémon, which move, in which situation, when to switch.
        Put Pokémon names and move names in **bold** (Markdown).
        """
    }

    // MARK: Apple Intelligence (on device)

    @Generable
    nonisolated struct AppleDraft {
        @Guide(description: "2–3 short bullet points: style of the team, its strengths, how it wins. Max 15 words each.")
        var summary: [String]
        @Guide(description: "3–4 short bullet points: who leads (in doubles: the lead pair), first moves, what to do if the lead is countered. Max 15 words each.")
        var lead: [String]
        @Guide(description: "3–4 short bullet points: which Pokémon and moves win, what must be removed first, when to set up. Max 15 words each.")
        var winCondition: [String]
        @Guide(description: "3–5 short bullet points: biggest threats and how to answer each, including which team member to switch in. Max 15 words each.")
        var threats: [String]
        @Guide(description: "One entry per team member, in the given order.")
        var roles: [AppleRole]
    }

    @Generable
    nonisolated struct AppleRole {
        @Guide(description: "Name of the team member exactly as given in the facts.")
        var pokemon: String
        @Guide(description: "2–3 short bullet points: its job, its key moves, when to bring it in. Max 12 words each.")
        var points: [String]
    }

    private static func apple(facts: String, doubles: Bool) async throws -> GamePlan {
        let session = LanguageModelSession(instructions: instructions(doubles: doubles))
        let response = try await session.respond(to: "Team facts:\n\(facts)\n\nWrite the game plan.", generating: AppleDraft.self)
        let d = response.content
        return GamePlan(summary: GamePlan.clean(d.summary), lead: GamePlan.clean(d.lead), winCondition: GamePlan.clean(d.winCondition),
                        threats: GamePlan.clean(d.threats), roles: d.roles.map { GamePlan.Role(pokemon: $0.pokemon.replacingOccurrences(of: "*", with: ""), points: GamePlan.clean($0.points)) })
    }

    // MARK: Claude API



    private static func claude(facts: String, model: ClaudeModel, doubles: Bool) async throws -> GamePlan {
        guard let key = APIKeyStore.key else { throw PlanError.message(L("Kein Claude-Schlüssel eingetragen.", "No Claude key entered.")) }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let system = instructions(doubles: doubles) + """

        Answer with ONLY a JSON object, no other text, in exactly this shape:
        {"summary": ["...", "..."], "lead": ["...", "..."], "winCondition": ["...", "..."], "threats": ["...", "..."], "roles": [{"pokemon": "...", "points": ["...", "..."]}]}
        Every list item is one short bullet point (max 15 words).
        "roles" has one entry per team member in the given order.
        """
        let body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 2500,
            "system": system,
            "messages": [["role": "user", "content": "Team facts:\n\(facts)\n\nWrite the game plan."]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }?["message"] as? String
            switch status {
            case 401: throw PlanError.message(L("Der Claude-Schlüssel ist ungültig.", "The Claude key is invalid."))
            case 402, 403: throw PlanError.message(L("Kein Guthaben oder kein Zugriff in der Claude Console.", "No credit or no access in the Claude Console."))
            case 429: throw PlanError.message(L("Zu viele Anfragen – kurz warten.", "Too many requests – wait a moment."))
            default: throw PlanError.message(L("Claude-Fehler \(status)", "Claude error \(status)") + (detail.map { ": \($0)" } ?? ""))
            }
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.compactMap({ $0["text"] as? String }).first else {
            throw PlanError.message(L("Unerwartete Antwort von Claude.", "Unexpected answer from Claude."))
        }
        // the JSON object inside the text (in case Claude adds a code fence)
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
              let parsed = try? JSONDecoder().decode(GamePlan.self, from: Data(text[start...end].utf8)) else {
            throw PlanError.message(L("Claude hat keinen lesbaren Plan geliefert – bitte nochmal versuchen.", "Claude returned no readable plan – please try again."))
        }
        return parsed
    }
}

// MARK: - Facts for the AI

/// Everything the app knows about the team, written as plain text – the AI must only use these facts.
enum TeamFacts {
    @MainActor
    static func text(for team: Team) -> String {
        let game = team.game
        let dex = Dex.shared
        let members = team.sortedMembers
        let analysis = TeamAnalysis(members: members, game: game, format: game.isChampions ? team.format : nil)
        var lines: [String] = []
        lines.append("Game: \(game.title) (Generation \(game.gen)). Battle mechanic: \(game.mechanic).")
        let formatName = team.battleFormat == .doubles ? "Double battles" : "Single battles"
        lines.append("Format: \(formatName)" + (game.isChampions ? ", all Pokémon at level 50." : "."))
        lines.append("")
        lines.append("Team (\(members.count) Pokémon):")
        for (i, m) in members.enumerated() {
            guard let p = m.battleForm(in: game) ?? m.species else { continue }
            let types = m.types(in: game).compactMap { dex.type($0)?.name }.joined(separator: "/")
            var head = "\(i + 1). \(m.displayName)"
            if !m.nickname.isEmpty, let s = m.species { head += " (\(s.name))" }
            if p.id != m.pokemonId { head += " – battle form: \(p.name)" }
            lines.append(head)
            lines.append("   Types: \(types). Level \(game.fixedLevel ?? m.level).")
            let s = p.s
            var stats = "   Base stats: HP \(s[0]), Atk \(s[1]), Def \(s[2]), SpA \(s[3]), SpD \(s[4]), Spe \(s[5])."
            if game.hasEVs {
                let lv = game.fixedLevel ?? m.level
                stats += " Real Speed: \(m.stat(5, base: s[5], level: lv, game: game))."
            }
            lines.append(stats)
            var extra: [String] = []
            if game.hasAbilities, let a = m.ability { extra.append("Ability: \(a.name)" + (Wiki.shared.abilityText(a.id).map { " (\($0))" } ?? "")) }
            if game.hasHeldItems, let it = m.item { extra.append("Item: \(it.name)") }
            if game.hasNatures, let n = m.nature { extra.append("Nature: \(n.name)") }
            if game.hasTera, let t = m.teraTypeId, let tn = dex.type(t)?.name { extra.append("Tera Type: \(tn)") }
            if m.gigantamax && game.hasDynamax { extra.append("Gigantamax") }
            if !extra.isEmpty { lines.append("   " + extra.joined(separator: ". ") + ".") }
            let moves = m.moves.map { mv -> String in
                let cat = mv.c == 1 ? "status" : (mv.c == 2 ? "physical" : "special")
                let power = mv.p > 0 ? ", power \(mv.p)" : ""
                return "\(mv.name) (\(dex.type(mv.t)?.name ?? "?"), \(cat)\(power)\(mv.pr > 0 ? ", priority +\(mv.pr)" : ""))"
            }
            lines.append("   Moves: " + (moves.isEmpty ? "none entered" : moves.joined(separator: "; ")) + ".")
        }
        lines.append("")
        let weak = analysis.defense.filter { $0.weak >= 2 && $0.weak > $0.resist + $0.immune }.map { "\($0.type.name) (\($0.weak) weak)" }
        if !weak.isEmpty { lines.append("Shared weaknesses: " + weak.joined(separator: ", ") + ".") }
        let resisted = analysis.defense.filter { $0.resist + $0.immune >= 3 }.map(\.type.name)
        if !resisted.isEmpty { lines.append("Well resisted: " + resisted.joined(separator: ", ") + ".") }
        if analysis.hasMoves {
            let gaps = analysis.offense.filter { $0.best <= 1 }.map(\.type.name)
            if !gaps.isEmpty { lines.append("No super effective move against: " + gaps.joined(separator: ", ") + ".") }
        }
        let order = members.compactMap { m -> (String, Int)? in
            guard let p = m.battleForm(in: game) ?? m.species else { return nil }
            let speed = game.hasEVs ? m.stat(5, base: p.s[5], level: game.fixedLevel ?? m.level, game: game) : p.s[5]
            return (m.displayName, speed)
        }.sorted { $0.1 > $1.1 }
        lines.append("Speed order: " + order.map { "\($0.0) \($0.1)" }.joined(separator: " > ") + ".")
        let notes = analysis.tips.filter { $0.level != .good }.prefix(6).map { "\($0.title): \($0.detail)" }
        if !notes.isEmpty { lines.append("App notes: " + notes.joined(separator: " | ")) }
        return lines.joined(separator: "\n")
    }
}
