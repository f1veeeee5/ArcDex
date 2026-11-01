import Foundation
import Security
import FoundationModels

// MARK: - Result

/// AI game plan of a team (stored with the team), always in the same fixed structure.
nonisolated struct GamePlan: Codable, Equatable {
    /// One line of a section: a team member and what it does.
    nonisolated struct Entry: Codable, Equatable, Identifiable {
        var pokemon: String
        /// for answers: the threat it answers
        var against: String?
        var text: String
        var id: String { pokemon + (against ?? "") + text }

        init(pokemon: String, against: String? = nil, text: String) {
            self.pokemon = pokemon.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespaces)
            self.against = against.map { $0.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespaces) }
                .flatMap { $0.isEmpty ? nil : $0 }
            self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var summary: [String]
    var lead: [Entry]
    var winConditions: [Entry]
    var answers: [Entry]
    var roles: [Entry]
    /// "apple" or a Claude model id
    var engine: String = "apple"
    var createdAt: Date = Date()
    /// team composition the plan was made for
    var signature: String = ""

    init(summary: [String], lead: [Entry], winConditions: [Entry], answers: [Entry], roles: [Entry]) {
        self.summary = summary
        self.lead = lead
        self.winConditions = winConditions
        self.answers = answers
        self.roles = roles
    }

    enum CodingKeys: String, CodingKey { case summary, lead, winConditions, answers, roles, engine, createdAt, signature }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = (try? c.decode([String].self, forKey: .summary)) ?? (try? c.decode(String.self, forKey: .summary)).map { [$0] } ?? []
        lead = (try? c.decode([Entry].self, forKey: .lead)) ?? []
        winConditions = (try? c.decode([Entry].self, forKey: .winConditions)) ?? []
        answers = (try? c.decode([Entry].self, forKey: .answers)) ?? []
        roles = (try? c.decode([Entry].self, forKey: .roles)) ?? []
        engine = (try? c.decode(String.self, forKey: .engine)) ?? "apple"
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        signature = (try? c.decode(String.self, forKey: .signature)) ?? ""
    }

    /// Plans of older app versions (other structure) can't be shown – they are simply created again.
    var isEmpty: Bool { lead.isEmpty && winConditions.isEmpty && answers.isEmpty && roles.isEmpty }
}

extension Team {
    var gamePlan: GamePlan? {
        get { gamePlanData.flatMap { try? JSONDecoder().decode(GamePlan.self, from: $0) }.flatMap { $0.isEmpty ? nil : $0 } }
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
        let names = team.sortedMembers.map(\.displayName)
        var plan: GamePlan
        switch engine {
        case .claude(let model):
            plan = try await claude(facts: facts, names: names, model: model, doubles: doubles)
            plan.engine = model.rawValue
        case .apple:
            plan = try await apple(facts: facts, names: names, doubles: doubles)
            plan.engine = "apple"
        case .none(let message):
            throw PlanError.message(message)
        }
        plan.lead = Array(plan.lead.prefix(doubles ? 2 : 1))
        plan.createdAt = Date()
        plan.signature = team.planSignature
        return plan
    }

    private static var languageName: String { Lang.current == .de ? "German" : "English" }

    private static func instructions(doubles: Bool, names: [String]) -> String {
        let format = doubles
            ? "This is a DOUBLE BATTLE team (two Pokémon per side). The lead is a PAIR of exactly 2 team members; mention how they support each other (Protect, Fake Out, Tailwind, Trick Room, redirection, spread moves)."
            : "This is a SINGLE BATTLE team (one Pokémon per side). The lead is exactly 1 team member; mention when to switch."
        return """
        You are an experienced Pokémon coach. Fill in a game plan for the player's team in \(languageName).
        \(format)
        The team members are exactly: \(names.joined(separator: ", ")). Use only these names for "pokemon".
        Use ONLY the facts given (types, moves, items, abilities, stats, weaknesses). Never invent moves, items or abilities.
        Fixed structure:
        - summary: 2 short bullet points about the team's style and strengths.
        - lead: \(doubles ? "exactly 2 entries" : "exactly 1 entry") – why this Pokémon leads and its job in the first turns (with moves).
        - winConditions: 1–3 entries – how this Pokémon wins: which moves, which setup, what must be removed first.
        - answers: 2–4 entries – "against" is the opposing threat (a type, a Pokémon kind or a strategy like Trick Room), "pokemon" is the OWN team member that answers it (never the threat), "text" says how.
        - roles: exactly \(names.count) entries, one for EVERY team member in this order: \(names.joined(separator: ", ")).
        Every "text" is 1–2 short sentences (max 30 words). Put move names in **bold**.
        """
    }

    // MARK: Apple Intelligence (on device)

    @Generable
    nonisolated struct AppleDraft {
        @Guide(description: "2 short bullet points about the team's style and strengths.")
        var summary: [String]
        @Guide(description: "The lead: 1 entry in singles, 2 entries in doubles.")
        var lead: [AppleEntry]
        @Guide(description: "1 to 3 win conditions.")
        var winConditions: [AppleEntry]
        @Guide(description: "2 to 4 answers to threats.")
        var answers: [AppleAnswer]
        @Guide(description: "One entry for EVERY team member, in the given order.")
        var roles: [AppleEntry]
    }

    @Generable
    nonisolated struct AppleEntry {
        @Guide(description: "Name of the team member exactly as listed.")
        var pokemon: String
        @Guide(description: "1–2 short sentences: why and how, with move names.")
        var text: String
    }

    @Generable
    nonisolated struct AppleAnswer {
        @Guide(description: "The threat: an opposing type (e.g. Ground), a kind of Pokémon or a strategy (e.g. Trick Room).")
        var against: String
        @Guide(description: "The OWN team member that answers the threat, exactly as listed – never the threat itself.")
        var pokemon: String
        @Guide(description: "1–2 short sentences: how it answers the threat.")
        var text: String
    }

    private static func apple(facts: String, names: [String], doubles: Bool) async throws -> GamePlan {
        let session = LanguageModelSession(instructions: instructions(doubles: doubles, names: names))
        let response = try await session.respond(to: "Team facts:\n\(facts)\n\nFill in the game plan.", generating: AppleDraft.self)
        let d = response.content
        var plan = GamePlan(summary: d.summary,
                            lead: d.lead.map { .init(pokemon: $0.pokemon, text: $0.text) },
                            winConditions: d.winConditions.map { .init(pokemon: $0.pokemon, text: $0.text) },
                            answers: d.answers.map { .init(pokemon: $0.pokemon, against: $0.against, text: $0.text) },
                            roles: d.roles.map { .init(pokemon: $0.pokemon, text: $0.text) })
        // the small model sometimes skips team members – ask for each missing role separately
        for name in missingRoles(plan, names: names) {
            if let text = try? await session.respond(to: "In 1–2 short sentences: what is the role of \(name) in this team? Mention its key moves.").content {
                plan.roles.append(.init(pokemon: name, text: text))
            }
        }
        plan.roles = ordered(plan.roles, names: names)
        return plan
    }

    private static func missingRoles(_ plan: GamePlan, names: [String]) -> [String] {
        names.filter { name in !plan.roles.contains { $0.pokemon.localizedCaseInsensitiveCompare(name) == .orderedSame } }
    }

    /// Roles in team order, duplicates removed.
    private static func ordered(_ roles: [GamePlan.Entry], names: [String]) -> [GamePlan.Entry] {
        var result: [GamePlan.Entry] = []
        for name in names {
            if let r = roles.first(where: { $0.pokemon.localizedCaseInsensitiveCompare(name) == .orderedSame }) { result.append(r) }
        }
        return result + roles.filter { r in !names.contains { r.pokemon.localizedCaseInsensitiveCompare($0) == .orderedSame } }
    }

    // MARK: Claude API

    private static func claude(facts: String, names: [String], model: ClaudeModel, doubles: Bool) async throws -> GamePlan {
        guard let key = APIKeyStore.key else { throw PlanError.message(L("Kein Claude-Schlüssel eingetragen.", "No Claude key entered.")) }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let system = instructions(doubles: doubles, names: names) + """

        Answer with ONLY a JSON object, no other text, in exactly this shape:
        {"summary": ["..."], "lead": [{"pokemon": "...", "text": "..."}], "winConditions": [{"pokemon": "...", "text": "..."}],
         "answers": [{"pokemon": "...", "against": "...", "text": "..."}], "roles": [{"pokemon": "...", "text": "..."}]}
        """
        let body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 3000,
            "system": system,
            "messages": [["role": "user", "content": "Team facts:\n\(facts)\n\nFill in the game plan."]],
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
              var parsed = try? JSONDecoder().decode(GamePlan.self, from: Data(text[start...end].utf8)), !parsed.isEmpty else {
            throw PlanError.message(L("Claude hat keinen lesbaren Plan geliefert – bitte nochmal versuchen.", "Claude returned no readable plan – please try again."))
        }
        parsed.roles = ordered(parsed.roles.map { .init(pokemon: $0.pokemon, text: $0.text) }, names: names)
        parsed.lead = parsed.lead.map { .init(pokemon: $0.pokemon, text: $0.text) }
        parsed.winConditions = parsed.winConditions.map { .init(pokemon: $0.pokemon, text: $0.text) }
        parsed.answers = parsed.answers.map { .init(pokemon: $0.pokemon, against: $0.against, text: $0.text) }
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
