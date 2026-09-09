public struct DiceRoll: Codable, Equatable, Sendable {
    public let die1: Int
    public let die2: Int
    public var total: Int { die1 + die2 }
    public var isDouble: Bool { die1 == die2 }

    public init(die1: Int, die2: Int) {
        self.die1 = die1
        self.die2 = die2
    }
}

public protocol DiceRoller {
    mutating func roll() -> DiceRoll
}

/// Uses `Int.random(in:)`, seeded from the system RNG. Non-deterministic —
/// this is what the shipping game uses.
public struct SystemDiceRoller: DiceRoller {
    public init() {}

    public func roll() -> DiceRoll {
        DiceRoll(die1: .random(in: 1...6), die2: .random(in: 1...6))
    }
}

/// Replays a fixed sequence of rolls, looping if it runs out. Intended for
/// deterministic unit tests, not gameplay.
public struct ScriptedDiceRoller: DiceRoller {
    private let rolls: [DiceRoll]
    private var index = 0

    public init(rolls: [DiceRoll]) {
        precondition(!rolls.isEmpty, "ScriptedDiceRoller needs at least one roll")
        self.rolls = rolls
    }

    public mutating func roll() -> DiceRoll {
        defer { index = (index + 1) % rolls.count }
        return rolls[index]
    }
}
