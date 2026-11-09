import Foundation

let actionLetters = Array("NESW")

struct World {
    let rows: Int
    let cols: Int
    let kinds: [Character]
    let wind: [Int]
    let terminalRewards: [Int]
    let states: [Int]
    let terminals: [Int]
    let stateIndex: [Int?]
    let terminalIndex: [Int?]
    let start: Int
    var startState: Int { stateIndex[start]! }

    init(_ rows: Int, _ cols: Int, _ kinds: [Character], _ wind: [Int], _ rewards: [Int]) {
        var states: [Int] = []
        var terminals: [Int] = []
        var stateIndex = [Int?](repeating: nil, count: kinds.count)
        var terminalIndex = stateIndex
        for (cell, kind) in kinds.enumerated() {
            if kind == "G" || kind == "P" {
                terminalIndex[cell] = terminals.count
                terminals.append(cell)
            } else if kind != "#" {
                stateIndex[cell] = states.count
                states.append(cell)
            }
        }
        self.rows = rows
        self.cols = cols
        self.kinds = kinds
        self.wind = wind
        terminalRewards = rewards
        self.states = states
        self.terminals = terminals
        self.stateIndex = stateIndex
        self.terminalIndex = terminalIndex
        start = kinds.firstIndex(of: "S")!
    }

    func isTerminal(_ cell: Int) -> Bool { terminalIndex[cell] != nil }
    func terminalName(_ cell: Int) -> String { kinds[cell] == "G" ? "goal" : "pit" }

    func move(_ cell: Int, _ direction: Int) -> Int {
        let rowSteps = [-1, 0, 1, 0]
        let colSteps = [0, 1, 0, -1]
        var target = cell + rowSteps[direction] * cols + colSteps[direction]
        if kinds[target] == "#" { target = cell }
        if isTerminal(target) { return target }
        for _ in 0..<wind[cell % cols] {
            let above = target - cols
            if kinds[above] == "#" { break }
            target = above
            if isTerminal(target) { break }
        }
        return target
    }
}

func readWorld(_ path: String) throws -> World {
    let text = try String(contentsOfFile: path, encoding: .ascii)
    let lines = text.split(separator: "\n").map(String.init)
    let rows = Int(lines[0].split(separator: " ")[1])!
    let cols = Int(lines[1].split(separator: " ")[1])!
    let kinds = Array(lines[2..<(2 + rows)].joined())
    let wind = lines[2 + rows].split(separator: " ")[1].map { Int(String($0))! }
    let rewards = lines[3 + rows].split(separator: " ").dropFirst().map { Int($0)! }
    return World(rows, cols, kinds, wind, rewards)
}

final class RandomGenerator {
    var value: Int
    init(_ seed: Int) { value = seed }

    func draw() -> Int {
        value = 48271 * value % 2147483647
        return value
    }
}

struct Transition {
    let cell: Int
    let numerator: Int
}

struct Environment {
    let world: World
    let stepReward: Int
    let slipTotal: Int
    let floorSlip: Int
    let iceSlip: Int
    let moves: [[Int]]
    let transitions: [[[Transition]]]

    init(_ world: World, _ stepReward: Int, _ total: Int, _ floorSlip: Int, _ iceSlip: Int) {
        let moves = world.states.map { cell in (0..<4).map { world.move(cell, $0) } }
        let transitions = world.states.indices.map { state in
            (0..<4).map { action in
                let slip = world.kinds[world.states[state]] == "~" ? iceSlip : floorSlip
                let outcomes = [(action, total - 2 * slip), ((action + 1) % 4, slip), ((action + 3) % 4, slip)]
                return outcomes.filter { $0.1 > 0 }.map {
                    Transition(cell: moves[state][$0.0], numerator: $0.1)
                }
            }
        }
        self.world = world
        self.stepReward = stepReward
        slipTotal = total
        self.floorSlip = floorSlip
        self.iceSlip = iceSlip
        self.moves = moves
        self.transitions = transitions
    }

    func slip(_ state: Int) -> Int { world.kinds[world.states[state]] == "~" ? iceSlip : floorSlip }

    func reward(_ cell: Int) -> Int {
        world.terminalIndex[cell].map { world.terminalRewards[$0] } ?? stepReward
    }

    func step(_ generator: RandomGenerator, _ state: Int, _ action: Int) -> (Int, Int) {
        let draw = generator.draw() % slipTotal
        let p = slip(state)
        let direction: Int
        if draw < slipTotal - 2 * p {
            direction = action
        } else if draw < slipTotal - p {
            direction = (action + 1) % 4
        } else {
            direction = (action + 3) % 4
        }
        let cell = moves[state][direction]
        return (cell, reward(cell))
    }
}
