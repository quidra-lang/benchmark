enum BreakingMethod: String {
    case kp, greedy
}

struct Breaking {
    let positions: [Int]
    let cost: Int
}

func lineClass(_ slack: Int, last: Bool) -> Int {
    if last { return 1 }
    if slack <= 1 { return 0 }
    if slack <= 3 { return 1 }
    if slack <= 6 { return 2 }
    return 3
}

func lineCost(_ metrics: TextMetrics, _ start: Int, _ end: Int, _ previousClass: Int,
              _ parameters: [String: Int]) -> Int {
    let slack = metrics.slack(start, end)
    let last = end == metrics.end
    let currentClass = lineClass(slack, last: last)
    var cost = parameters["line_penalty"]!
    if slack < 0 { cost += parameters["overfull_penalty"]! }
    else if !last { cost += slack * slack }
    if metrics.breaks[end].midword {
        cost += parameters["hyphen_penalty"]!
        if metrics.breaks[start].midword { cost += parameters["double_hyphen_demerit"]! }
    }
    if last && metrics.breaks[start].midword { cost += parameters["final_hyphen_demerit"]! }
    if abs(currentClass - previousClass) >= 2 { cost += parameters["fitness_demerit"]! }
    return cost
}

func breakingCost(_ metrics: TextMetrics, _ positions: [Int], _ parameters: [String: Int]) -> Int {
    var cost = 0
    var start = 0
    var previousClass = 1
    for end in positions {
        cost += lineCost(metrics, start, end, previousClass, parameters)
        previousClass = lineClass(metrics.slack(start, end), last: end == metrics.end)
        start = end
    }
    return cost
}

private struct OptimalState {
    let cost: Int
    let previousPosition: Int
    let previousClass: Int
}

func knuthPlass(_ metrics: TextMetrics, _ parameters: [String: Int]) -> Breaking {
    var states = Array(repeating: Array<OptimalState?>(repeating: nil, count: 4), count: metrics.end + 1)
    states[0][1] = OptimalState(cost: 0, previousPosition: 0, previousClass: 1)
    for end in 1...metrics.end {
        for start in stride(from: end - 1, through: 0, by: -1) {
            let slack = metrics.slack(start, end)
            if slack < 0 && end != start + 1 { break }
            let currentClass = lineClass(slack, last: end == metrics.end)
            for previousClass in 0..<4 {
                guard let previous = states[start][previousClass] else { continue }
                let cost = previous.cost + lineCost(metrics, start, end, previousClass, parameters)
                let candidate = OptimalState(cost: cost, previousPosition: start, previousClass: previousClass)
                if let best = states[end][currentClass] {
                    if cost > best.cost { continue }
                    if cost == best.cost && (start > best.previousPosition
                        || (start == best.previousPosition && previousClass >= best.previousClass)) { continue }
                }
                states[end][currentClass] = candidate
            }
        }
    }
    let cost = states[metrics.end][1]!.cost
    var positions: [Int] = []
    var end = metrics.end
    var currentClass = 1
    while end > 0 {
        positions.append(end)
        let previous = states[end][currentClass]!
        end = previous.previousPosition
        currentClass = previous.previousClass
    }
    return Breaking(positions: Array(positions.reversed()), cost: cost)
}

func greedyBreaking(_ metrics: TextMetrics, _ parameters: [String: Int]) -> Breaking {
    var positions: [Int] = []
    var start = 0
    while start < metrics.end {
        var chosen = start + 1
        if metrics.slack(start, chosen) >= 0 {
            var end = chosen + 1
            while end <= metrics.end && metrics.slack(start, end) >= 0 {
                chosen = end
                end += 1
            }
        }
        positions.append(chosen)
        start = chosen
    }
    return Breaking(positions: positions, cost: breakingCost(metrics, positions, parameters))
}

func breakText(_ metrics: TextMetrics, _ method: BreakingMethod, _ parameters: [String: Int]) -> Breaking {
    method == .kp ? knuthPlass(metrics, parameters) : greedyBreaking(metrics, parameters)
}
