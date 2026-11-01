import Foundation
import Security
import FoundationModels

// MARK: - Result

/// AI game plan of a team (stored with the team).
nonisolated struct GamePlan: Codable, Equatable {
    struct Role: Codable, Equatable, Identifiable {
        var pokemon: String
        var role: String
        var id: String { pokemon }
    }

    var summary: String
    var lead: String
    var winCondition: String
    var threats: String
    var roles: [Role]
    /// "apple" or a Claude model id
    var engine: String = "apple"
    var createdAt: Date = Date()
    /// team composition the plan was made for
    var signature: String = ""
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
        return game.rawValue + "|" + formatRaw + "|" + parts.joined(separator: ";")
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
        var plan: GamePlan
        switch engine {
        case .claude(let model):
            plan = try await claude(facts: facts, model: model)
            plan.engine = model.rawValue
        case .apple:
            plan = try await apple(facts: facts)
            plan.engine = "apple"
        case .none(let message):
            throw PlanError.message(message)
        }
        plan.createdAt = Date()
        plan.signature = team.planSignature
        return plan
    }

    private static var languageName: String { Lang.current == .de ? "German" : "English" }

    private static var instructions: String {
        """
        You are an experienced Pokémon coach. Write a short, practical game plan for the player's team in \(languageName).
        Use ONLY the facts given about the team (Pokémon, types, moves, items, abilities, stats, weaknesses).
        Do not invent moves, items or abilities the team doesn't have. Refer to Pokémon by the names given.
        Keep every text short: 1–3 sentences. Be concrete (which Pokémon, which move, when to switch).
        """
    }

    // MARK: Apple Intelligence (on device)

    @Generable
    nonisolated struct AppleDraft {
        @Guide(description: "One or two sentences: the overall style of the team and how it wins.")
        var summary: String
        @Guide(description: "Which Pokémon should go first (lead) and why, with the moves to use first.")
        var lead: String
        @Guide(description: "The main win condition: which Pokémon and which moves finish the battle, and when to set it up.")
        var winCondition: String
        @Guide(description: "The biggest threats or weaknesses of the team and how to play around them (which Pokémon to switch in).")
        var threats: String
        @Guide(description: "One entry per team member, in the given order.")
        var roles: [AppleRole]
    }

    @Generable
    nonisolated struct AppleRole {
        @Guide(description: "Name of the team member exactly as given in the facts.")
        var pokemon: String
        @Guide(description: "Its job in the team in one or two sentences.")
        var role: String
    }

    private static func apple(facts: String) async throws -> GamePlan {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: "Team facts:\n\(facts)\n\nWrite the game plan.", generating: AppleDraft.self)
        let d = response.content
        return GamePlan(summary: d.summary, lead: d.lead, winCondition: d.winCondition, threats: d.threats,
                        roles: d.roles.map { GamePlan.Role(pokemon: $0.pokemon, role: $0.role) })
    }

    // MARK: Claude API

    private struct ClaudeJSON: Decodable {
        let summary: String
        let lead: String
        let winCondition: String
        let threats: String
        let roles: [GamePlan.Role]
    }

    private static func claude(facts: String, model: ClaudeModel) async throws -> GamePlan {
        guard let key = APIKeyStore.key else { throw PlanError.message(L("Kein Claude-Schlüssel eingetragen.", "No Claude key entered.")) }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let system = instructions + """

        Answer with ONLY a JSON object, no other text, in exactly this shape:
        {"summary": "...", "lead": "...", "winCondition": "...", "threats": "...", "roles": [{"pokemon": "...", "role": "..."}]}
        "roles" has one entry per team member in the given order.
        """
        let body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 1500,
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
              let parsed = try? JSONDecoder().decode(ClaudeJSON.self, from: Data(text[start...end].utf8)) else {
            throw PlanError.message(L("Claude hat keinen lesbaren Plan geliefert – bitte nochmal versuchen.", "Claude returned no readable plan – please try again."))
        }
        return GamePlan(summary: parsed.summary, lead: parsed.lead, winCondition: parsed.winCondition,
                        threats: parsed.threats, roles: parsed.roles)
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
        if game.isChampions { lines.append("Format: \(team.format == .doubles ? "Doubles" : "Singles"), all Pokémon at level 50.") }
        else { lines.append("Format: in-game / singles.") }
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
