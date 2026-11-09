enum Heuristics {
    static let infinity = 1_000_000_000_000
    static func aggregate(_ values: [Int], _ maximum: Bool) -> Int {
        if values.contains(where: {
            $0 >= infinity
        }) {
            return infinity
        }
        return maximum ? values.max() ?? 0 : values.reduce(0, +)
    }
    static func costs(_ grounding: Grounding, _ state: State, _ maximum: Bool) -> [Int] {
        var costs = Array(repeating: infinity, count: grounding.facts.count)
        for fact in state {
            costs[fact] = 0
        }
        while true {
            var changed = false
            for action in grounding.actions {
                let previous = aggregate(action.pre.sorted().map {
                    costs[$0]
                }, maximum)
                if previous >= infinity {
                    continue
                }
                let value = previous + action.cost
                for fact in action.add where value < costs[fact] {
                    costs[fact] = value;
                    changed = true
                }
            }
            if !changed {
                return costs
            }
        }
    }
    static func relaxed(_ grounding: Grounding, _ state: State) -> (Int, [Int], [Int]) {
        let costs = self.costs(grounding, state, false)
        if grounding.goals.contains(where: {
            costs[$0] >= infinity
        }) {
            return (infinity, [], [])
        }
        func achiever(_ fact: Int) -> Int {
            grounding.actions.indices.filter {
                grounding.actions[$0].add.contains(fact) && grounding.actions[$0].pre.allSatisfy {
                    costs[$0] < infinity
                }
            }.min {
                let a = grounding.actions[$0], b = grounding.actions[$1]
                let x = a.cost + a.pre.reduce(0) {
                    $0 + costs[$1]
                }, y = b.cost + b.pre.reduce(0) {
                    $0 + costs[$1]
                }
                return x == y ? $0 < $1 : x < y
            }!
        }
        var chosen: State = [], pending = grounding.goals.subtracting(state).sorted()
        while let fact = pending.popLast() {
            let action = achiever(fact);
            if chosen.insert(action).inserted {
                pending += grounding.actions[action].pre.subtracting(state).sorted()
            }
        }
        let plan = chosen.sorted(), helpful = plan.filter {
            Search.applicable(grounding.actions[$0], state)
        }
        return (plan.reduce(0) {
            $0 + grounding.actions[$1].cost
        }, plan, helpful)
    }
    static func landmarks(_ grounding: Grounding, _ state: State) -> State? {
        var factLevel = Array(repeating: Int.max, count: grounding.facts.count), actionLevel = Array(repeating: Int.max, count: grounding.actions.count)
        for fact in state {
            factLevel[fact] = 0
        }
        var k = 0
        while true {
            var added = false
            for (i, action) in grounding.actions.enumerated() where actionLevel[i] == Int.max && action.pre.allSatisfy({
                factLevel[$0] <= k
            }) {
                actionLevel[i] = k
                for fact in action.add where factLevel[fact] == Int.max {
                    factLevel[fact] = k + 1;
                    added = true
                }
            }
            if !added {
                break
            }
            k += 1
        }
        if grounding.goals.contains(where: {
            factLevel[$0] == Int.max
        }) {
            return nil
        }
        var landmarks = grounding.goals.subtracting(state)
        while true {
            let before = landmarks.count
            for fact in landmarks.sorted() {
                let achievers = grounding.actions.indices.filter {
                    actionLevel[$0] != Int.max && actionLevel[$0] + 1 == factLevel[fact] && grounding.actions[$0].add.contains(fact)
                }
                var candidates = grounding.actions[achievers[0]].pre
                for i in achievers.dropFirst() {
                    candidates.formIntersection(grounding.actions[i].pre)
                }
                for candidate in candidates.subtracting(state).sorted() where !landmarks.contains(candidate) {
                    var reachable = state
                    while true {
                        let old = reachable.count
                        for action in grounding.actions where !action.add.contains(candidate) && action.pre.isSubset(of: reachable) {
                            reachable.formUnion(action.add)
                        }
                        if old == reachable.count {
                            break
                        }
                    }
                    if !grounding.goals.isSubset(of: reachable) {
                        landmarks.insert(candidate)
                    }
                }
            }
            if before == landmarks.count {
                return landmarks
            }
        }
    }
    static func value(_ grounding: Grounding, _ state: State, _ name: String) -> Int {
        switch name {
            case "none": return 0
            case "goalcount": return grounding.goals.subtracting(state).count
            case "hmax", "hadd": let maximum = name == "hmax", costs = self.costs(grounding, state, maximum);
            return aggregate(grounding.goals.sorted().map {
                costs[$0]
            }, maximum)
            case "ff": return relaxed(grounding, state).0
            default: return landmarks(grounding, state)?.count ?? infinity
        }
    }
    static func values(_ grounding: Grounding, _ state: State) -> [Int] {
        ["goalcount", "hmax", "hadd", "ff", "lmcount"].map {
            value(grounding, state, $0)
        }
    }
}
