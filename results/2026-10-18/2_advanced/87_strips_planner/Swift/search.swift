struct SearchResult {
    var status: String, plan: [Int] = [], expanded = 0, generated = 0
    static func failure(_ reason: String) -> Self {
        Self(status: reason)
    }
}
struct SearchNode {
    let state: State, g: Int, depth: Int, parent: Int?, action: Int?
}
struct SearchKey: Comparable {
    let f: Int, h: Int, serial: Int
    static func < (a: Self, b: Self) -> Bool {
        (a.f, a.h, a.serial) < (b.f, b.h, b.serial)
    }
}
struct OpenHeap {
    var values: [SearchKey] = []
    mutating func push(_ key: SearchKey) {
        values.append(key)
        var i = values.count - 1
        while i > 0 {
            let parent = (i - 1) / 2;
            if !(values[i] < values[parent]) {
                break
            };
            values.swapAt(i, parent);
            i = parent
        }
    }
    mutating func pop() -> SearchKey? {
        if values.isEmpty {
            return nil
        }
        let first = values[0], last = values.removeLast()
        if !values.isEmpty {
            values[0] = last
            var i = 0
            while i * 2 + 1 < values.count {
                var child = i * 2 + 1
                if child + 1 < values.count && values[child + 1] < values[child] {
                    child += 1
                }
                if !(values[child] < values[i]) {
                    break
                }
                values.swapAt(i, child);
                i = child
            }
        }
        return first
    }
}
enum Search {
    static func applicable(_ action: Action, _ state: State) -> Bool {
        action.pre.isSubset(of: state) && action.neg.isDisjoint(with: state)
    }
    static func apply(_ action: Action, _ state: State) -> State {
        state.subtracting(action.del).union(action.add)
    }
    static func run(_ grounding: Grounding, _ start: State, _ algorithm: String, _ heuristic: String, _ budget: Int, _ weight: Int) -> SearchResult {
        if algorithm == "ehc" {
            return ehc(grounding, start, heuristic, budget)
        }
        var result = SearchResult.failure("exhausted")
        let initialH = Heuristics.value(grounding, start, heuristic)
        if initialH >= Heuristics.infinity {
            result.status = "dead end";
            return result
        }
        var nodes = [SearchNode(state: start, g: 0, depth: 0, parent: nil, action: nil)], open = OpenHeap(), table = [start: 0]
        func key(_ cost: Int, _ depth: Int, _ h: Int, _ serial: Int) -> SearchKey {
            let f: Int
            switch algorithm {
                case "bfs": f = depth
                case "ucs": f = cost
                case "gbfs": f = h
                case "astar": f = cost + h
                default: f = cost + weight * h
            }
            return SearchKey(f: f, h: h, serial: serial)
        }
        open.push(key(0, 0, initialH, 0))
        while let entry = open.pop() {
            let index = entry.serial, node = nodes[index], state = node.state
            if ["ucs", "astar", "wastar"].contains(algorithm) && node.g > table[state]! {
                continue
            }
            if grounding.goals.isSubset(of: state) {
                result.status = "solved"
                var current = index
                while let parent = nodes[current].parent {
                    result.plan.append(nodes[current].action!);
                    current = parent
                }
                result.plan.reverse()
                return result
            }
            if result.expanded == budget {
                result.status = "budget";
                return result
            }
            result.expanded += 1
            for (a, action) in grounding.actions.enumerated() where applicable(action, state) {
                result.generated += 1
                let next = apply(action, state), cost = node.g + action.cost
                if let old = table[next], algorithm == "bfs" || algorithm == "gbfs" || old <= cost {
                    continue
                }
                table[next] = cost
                let h = Heuristics.value(grounding, next, heuristic)
                if h >= Heuristics.infinity {
                    continue
                }
                let serial = nodes.count
                nodes.append(SearchNode(state: next, g: cost, depth: node.depth + 1, parent: index, action: a))
                open.push(key(cost, node.depth + 1, h, serial))
            }
        }
        return result
    }
    static func ehc(_ grounding: Grounding, _ start: State, _ heuristic: String, _ budget: Int) -> SearchResult {
        var result = SearchResult.failure("stuck"), current = start, hc = Heuristics.value(grounding, start, heuristic)
        if hc >= Heuristics.infinity {
            result.status = "dead end";
            return result
        }
        while true {
            if grounding.goals.isSubset(of: current) {
                result.status = "solved";
                return result
            }
            var queue: [(State, [Int])] = [(current, [])], head = 0, visited: Set<State> = [current], improvement: (State, Int, [Int])?
            while head < queue.count {
                let (state, path) = queue[head];
                head += 1
                if result.expanded == budget {
                    result.status = "budget";
                    return result
                }
                result.expanded += 1
                for action in Heuristics.relaxed(grounding, state).2 {
                    result.generated += 1
                    let next = apply(grounding.actions[action], state)
                    if !visited.insert(next).inserted {
                        continue
                    }
                    let h = Heuristics.value(grounding, next, heuristic)
                    if h >= Heuristics.infinity {
                        continue
                    }
                    let nextPath = path + [action]
                    if h < hc {
                        improvement = (next, h, nextPath);
                        break
                    }
                    queue.append((next, nextPath))
                }
                if improvement != nil {
                    break
                }
            }
            guard let (next, h, path) = improvement else {
                return result
            }
            current = next;
            hc = h;
            result.plan += path
        }
    }
}
