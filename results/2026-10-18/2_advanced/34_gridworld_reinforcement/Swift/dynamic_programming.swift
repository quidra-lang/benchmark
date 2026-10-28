func floorDivide(_ numerator: Int, _ denominator: Int) -> Int {
    numerator / denominator - (numerator % denominator < 0 ? 1 : 0)
}

func firstMaximum(_ values: [Int]) -> Int {
    var best = 0
    for i in 1..<values.count {
        if values[i] > values[best] { best = i }
    }
    return best
}

func bellman(_ environment: Environment, _ values: [Int], _ gamma: Int, _ state: Int, _ action: Int) -> Int {
    var total = 0
    for transition in environment.transitions[state][action] {
        let cell = transition.cell
        let future = environment.world.stateIndex[cell].map { floorDivide(gamma * values[$0], 100) } ?? 0
        total += transition.numerator * (10000 * environment.reward(cell) + future)
    }
    return floorDivide(total, environment.slipTotal)
}

func actionValues(_ environment: Environment, _ values: [Int], _ gamma: Int, _ state: Int) -> [Int] {
    (0..<4).map { bellman(environment, values, gamma, state, $0) }
}

func greedyPolicy(_ environment: Environment, _ values: [Int], _ gamma: Int) -> [Int] {
    values.indices.map { firstMaximum(actionValues(environment, values, gamma, $0)) }
}

struct ValueIteration {
    let values: [Int]
    let changes: [Int]
}

func valueIteration(_ environment: Environment, _ gamma: Int, _ theta: Int) -> ValueIteration {
    var values = [Int](repeating: 0, count: environment.world.states.count)
    var changes: [Int] = []
    while true {
        let updated = values.indices.map { actionValues(environment, values, gamma, $0).max()! }
        let change = values.indices.map { abs(updated[$0] - values[$0]) }.max()!
        changes.append(change)
        values = updated
        if change <= theta { return ValueIteration(values: values, changes: changes) }
    }
}

func inPlaceValueIteration(_ environment: Environment, _ gamma: Int, _ theta: Int) -> Int {
    var values = [Int](repeating: 0, count: environment.world.states.count)
    var sweeps = 0
    while true {
        sweeps += 1
        var delta = 0
        for state in values.indices {
            let value = actionValues(environment, values, gamma, state).max()!
            delta = max(delta, abs(value - values[state]))
            values[state] = value
        }
        if delta <= theta { return sweeps }
    }
}

func evaluatePolicy(
    _ environment: Environment, _ policy: [Int], _ initial: [Int], _ gamma: Int, _ theta: Int
) -> ([Int], Int) {
    var values = initial
    var sweeps = 0
    while true {
        sweeps += 1
        var delta = 0
        for state in policy.indices {
            let value = bellman(environment, values, gamma, state, policy[state])
            delta = max(delta, abs(value - values[state]))
            values[state] = value
        }
        if delta <= theta { return (values, sweeps) }
    }
}

struct PolicyRound {
    let sweeps: Int
    let changed: Int
    let startValue: Int
}

struct PolicyIteration {
    let policy: [Int]
    let values: [Int]
    let rounds: [PolicyRound]
}

func policyIteration(_ environment: Environment, _ gamma: Int, _ theta: Int) -> PolicyIteration {
    var policy = [Int](repeating: 0, count: environment.world.states.count)
    var values = policy
    var rounds: [PolicyRound] = []
    while true {
        let (evaluated, sweeps) = evaluatePolicy(environment, policy, values, gamma, theta)
        values = evaluated
        let improved = greedyPolicy(environment, values, gamma)
        let changed = policy.indices.filter { improved[$0] != policy[$0] }.count
        rounds.append(PolicyRound(sweeps: sweeps, changed: changed, startValue: values[environment.world.startState]))
        policy = improved
        if changed == 0 { return PolicyIteration(policy: policy, values: values, rounds: rounds) }
    }
}
