struct EpisodeStep {
    let state: Int
    let action: Int
    let reward: Int
}

func discountedReturn(_ rewards: [Int], _ gamma: Int) -> Int {
    var value = 0
    for reward in rewards.reversed() { value = 10000 * reward + floorDivide(gamma * value, 100) }
    return value
}

final class ReturnAverages {
    var sums: [[Int]]
    var counts: [[Int]]

    init(_ count: Int) {
        let zeros = [[Int]](repeating: [Int](repeating: 0, count: 4), count: count)
        sums = zeros
        counts = zeros
    }

    func update(_ values: inout [[Int]], _ history: [EpisodeStep], _ gamma: Int) {
        var seen: Set<StateAction> = []
        let firstVisits = history.map { step in
            seen.insert(StateAction(state: step.state, action: step.action)).inserted
        }
        var value = 0
        for i in history.indices.reversed() {
            let step = history[i]
            value = 10000 * step.reward + floorDivide(gamma * value, 100)
            if firstVisits[i] {
                sums[step.state][step.action] += value
                counts[step.state][step.action] += 1
                values[step.state][step.action] = floorDivide(sums[step.state][step.action], counts[step.state][step.action])
            }
        }
    }
}
