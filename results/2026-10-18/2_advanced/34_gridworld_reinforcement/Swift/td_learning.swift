func choose(_ generator: RandomGenerator, _ values: [Int], _ epsilon: Int) -> Int {
    generator.draw() % 1000 < epsilon ? generator.draw() % 4 : firstMaximum(values)
}

func tdTarget(_ reward: Int, _ terminal: Bool, _ nextValue: Int, _ gamma: Int) -> Int {
    terminal ? 10000 * reward : 10000 * reward + floorDivide(gamma * nextValue, 100)
}

func expectedValue(_ values: [Int], _ epsilon: Int) -> Int {
    floorDivide(epsilon * values.reduce(0, +) + 4 * (1000 - epsilon) * values.max()!, 4000)
}

func tdUpdate(_ values: inout [[Int]], _ state: Int, _ action: Int, _ target: Int, _ alpha: Int) {
    let current = values[state][action]
    values[state][action] = current + floorDivide(alpha * (target - current), 100)
}

struct StateAction: Hashable {
    let state: Int
    let action: Int
}

struct ModelOutcome {
    let reward: Int
    let nextState: Int?
}

final class DynaModel {
    var outcomes: [[ModelOutcome?]]
    var pairs: [StateAction] = []

    init(_ count: Int) { outcomes = [[ModelOutcome?]](repeating: [ModelOutcome?](repeating: nil, count: 4), count: count) }

    func record(_ state: Int, _ action: Int, _ reward: Int, _ next: Int?) {
        if outcomes[state][action] == nil { pairs.append(StateAction(state: state, action: action)) }
        outcomes[state][action] = ModelOutcome(reward: reward, nextState: next)
    }

    func plan(_ generator: RandomGenerator, _ values: inout [[Int]], _ gamma: Int, _ alpha: Int, _ count: Int) {
        for _ in 0..<count {
            let pair = pairs[generator.draw() % pairs.count]
            let outcome = outcomes[pair.state][pair.action]!
            let nextValue = outcome.nextState.map { values[$0].max()! } ?? 0
            let target = tdTarget(outcome.reward, outcome.nextState == nil, nextValue, gamma)
            tdUpdate(&values, pair.state, pair.action, target, alpha)
        }
    }
}
