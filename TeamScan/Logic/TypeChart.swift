import Foundation

/// Type ids as used by PokéAPI.
enum T {
    static let normal = 1, fighting = 2, flying = 3, poison = 4, ground = 5, rock = 6, bug = 7, ghost = 8, steel = 9
    static let fire = 10, water = 11, grass = 12, electric = 13, psychic = 14, ice = 15, dragon = 16, dark = 17, fairy = 18
    static let stellar = 19
}

enum TypeChart {
    /// attacker -> defender -> multiplier (only entries that are not 1×). Valid from Gen 6 on.
    static let table: [Int: [Int: Double]] = {
        func row(se: [Int] = [], nve: [Int] = [], immune: [Int] = []) -> [Int: Double] {
            var r: [Int: Double] = [:]
            se.forEach { r[$0] = 2 }
            nve.forEach { r[$0] = 0.5 }
            immune.forEach { r[$0] = 0 }
            return r
        }
        return [
            T.normal: row(nve: [T.rock, T.steel], immune: [T.ghost]),
            T.fighting: row(se: [T.normal, T.rock, T.steel, T.ice, T.dark], nve: [T.flying, T.poison, T.bug, T.psychic, T.fairy], immune: [T.ghost]),
            T.flying: row(se: [T.fighting, T.bug, T.grass], nve: [T.rock, T.steel, T.electric]),
            T.poison: row(se: [T.grass, T.fairy], nve: [T.poison, T.ground, T.rock, T.ghost], immune: [T.steel]),
            T.ground: row(se: [T.poison, T.rock, T.steel, T.fire, T.electric], nve: [T.bug, T.grass], immune: [T.flying]),
            T.rock: row(se: [T.flying, T.bug, T.fire, T.ice], nve: [T.fighting, T.ground, T.steel]),
            T.bug: row(se: [T.grass, T.psychic, T.dark], nve: [T.fighting, T.flying, T.poison, T.ghost, T.steel, T.fire, T.fairy]),
            T.ghost: row(se: [T.ghost, T.psychic], nve: [T.dark], immune: [T.normal]),
            T.steel: row(se: [T.rock, T.ice, T.fairy], nve: [T.steel, T.fire, T.water, T.electric]),
            T.fire: row(se: [T.bug, T.steel, T.grass, T.ice], nve: [T.rock, T.fire, T.water, T.dragon]),
            T.water: row(se: [T.ground, T.rock, T.fire], nve: [T.water, T.grass, T.dragon]),
            T.grass: row(se: [T.ground, T.rock, T.water], nve: [T.flying, T.poison, T.bug, T.steel, T.fire, T.grass, T.dragon]),
            T.electric: row(se: [T.flying, T.water], nve: [T.grass, T.electric, T.dragon], immune: [T.ground]),
            T.psychic: row(se: [T.fighting, T.poison], nve: [T.steel, T.psychic], immune: [T.dark]),
            T.ice: row(se: [T.flying, T.ground, T.grass, T.dragon], nve: [T.steel, T.fire, T.water, T.ice]),
            T.dragon: row(se: [T.dragon], nve: [T.steel], immune: [T.fairy]),
            T.dark: row(se: [T.ghost, T.psychic], nve: [T.fighting, T.dark, T.fairy]),
            T.fairy: row(se: [T.fighting, T.dragon, T.dark], nve: [T.poison, T.steel, T.fire]),
        ]
    }()

    static func multiplier(attack: Int, defense: [Int]) -> Double {
        defense.reduce(1.0) { $0 * (table[attack]?[$1] ?? 1) }
    }

    /// Defensive multiplier incl. common immunity / resistance abilities.
    static func multiplier(attack: Int, defense: [Int], abilityKey: String?) -> Double {
        var m = multiplier(attack: attack, defense: defense)
        guard let key = abilityKey else { return m }
        switch key {
        case "levitate", "earth-eater": if attack == T.ground { m = 0 }
        case "flash-fire", "well-baked-body": if attack == T.fire { m = 0 }
        case "water-absorb", "storm-drain", "dry-skin": if attack == T.water { m = 0 }
        case "volt-absorb", "lightning-rod", "motor-drive": if attack == T.electric { m = 0 }
        case "sap-sipper": if attack == T.grass { m = 0 }
        case "thick-fat": if attack == T.fire || attack == T.ice { m *= 0.5 }
        case "heatproof", "water-bubble": if attack == T.fire { m *= 0.5 }
        case "purifying-salt": if attack == T.ghost { m *= 0.5 }
        case "wonder-guard": if m <= 1 { m = 0 }
        default: break
        }
        return m
    }

    /// Types that resist or are immune to the given attacking type.
    static func resisters(of attack: Int) -> [Int] {
        (1...18).filter { multiplier(attack: attack, defense: [$0]) < 1 }
    }

    /// Types that hit the given defending type super effectively.
    static func counters(of defense: Int) -> [Int] {
        (1...18).filter { multiplier(attack: $0, defense: [defense]) > 1 }
    }
}
