struct Pair: Hashable {
    let a: Int, b: Int
    init(_ a: Int, _ b: Int) {
        self.a = min(a, b);
        self.b = max(a, b)
    }
}
typealias Mutex = Set<Pair>
struct GraphElement {
    let action: Int?, pre: State, add: State, del: State
}
struct GraphLevel {
    let elements: [GraphElement], mutex: Mutex
}
struct MemoKey: Hashable {
    let level: Int, goals: [Int]
}
final class Extractor {
    var levels: [GraphLevel] = [], memo: Set<MemoKey> = []
    var searched = 0, hits = 0, tried = 0
    func extract(_ level: Int, _ goals: [Int]) -> [[Int]]? {
        if level == 0 {
            return []
        }
        let key = MemoKey(level: level, goals: goals)
        if memo.contains(key) {
            hits += 1;
            return nil
        }
        searched += 1
        let result = assign(level, goals, 0, [])
        if result == nil {
            memo.insert(key)
        }
        return result
    }
    func assign(_ j: Int, _ goals: [Int], _ position: Int, _ chosen: [Int]) -> [[Int]]? {
        let level = levels[j - 1]
        var k = position
        while k < goals.count && chosen.contains(where: {
            level.elements[$0].add.contains(goals[k])
        }) {
            k += 1
        }
        if k == goals.count {
            let previous = Set(chosen.flatMap {
                level.elements[$0].pre
            }).sorted()
            guard var plan = extract(j - 1, previous) else {
                return nil
            }
            plan.append(chosen.compactMap {
                level.elements[$0].action
            }.sorted())
            return plan
        }
        let goal = goals[k]
        let achievers = level.elements.indices.filter {
            level.elements[$0].add.contains(goal)
        }.sorted {
            let a = level.elements[$0].action, b = level.elements[$1].action
            if (a == nil) != (b == nil) {
                return a == nil
            }
            return (a ?? 0) < (b ?? 0)
        }
        for x in achievers where chosen.allSatisfy({
            x == $0 || !level.mutex.contains(Pair(x, $0))
        }) {
            tried += 1
            if let plan = assign(j, goals, k + 1, chosen + [x]) {
                return plan
            }
        }
        return nil
    }
}
struct GraphResult {
    let search: SearchResult, layers: [[Int]], records: [String], hits: Int
}
enum GraphPlan {
    static func compatible(_ pre: State, _ mutex: Mutex) -> Bool {
        pre.allSatisfy {
            p in pre.allSatisfy {
                q in p == q || !mutex.contains(Pair(p, q))
            }
        }
    }
    static func run(_ actions: [Action], _ initial: State, _ goals: State, _ limit: Int) -> GraphResult {
        let extractor = Extractor()
        var facts = initial, mutex: Mutex = [], previous: (Int, Int)?, records: [String] = [], answer: [[Int]] = [], status = "level limit"
        for i in 0...limit {
            records.append("fact level \(i): facts=\(facts.count) mutexes=\(mutex.count)")
            let extract = goals.isSubset(of: facts) && compatible(goals, mutex)
            if extract {
                let before = extractor.searched, hits = extractor.hits, result = extractor.extract(i, goals.sorted())
                records.append("extract level \(i): \(result == nil ? "fail" : "success") searched=\(extractor.searched - before) memo_hits=\(extractor.hits - hits)")
                if let result {
                    answer = result;
                    status = "solved";
                    break
                }
            } else if let previous, previous.0 == facts.count && previous.1 == mutex.count {
                status = "unreachable";
                break
            }
            if i == limit {
                break
            }
            previous = (facts.count, mutex.count)
            var elements = actions.enumerated().filter {
                $0.element.pre.isSubset(of: facts) && compatible($0.element.pre, mutex)
            }.map {
                GraphElement(action: $0.offset, pre: $0.element.pre, add: $0.element.add, del: $0.element.del)
            }
            let real = elements.count
            for fact in facts.sorted() {
                elements.append(GraphElement(action: nil, pre: [fact], add: [fact], del: []))
            }
            var actionMutex: Mutex = []
            for x in elements.indices {
                for y in (x + 1)..<elements.count {
                    let a = elements[x], b = elements[y]
                    let interference = !a.del.isDisjoint(with: b.pre) || !a.del.isDisjoint(with: b.add) || !b.del.isDisjoint(with: a.pre) || !b.del.isDisjoint(with: a.add)
                    let competing = a.pre.contains {
                        p in b.pre.contains {
                            q in p != q && mutex.contains(Pair(p, q))
                        }
                    }
                    if interference || competing {
                        actionMutex.insert(Pair(x, y))
                    }
                }
            }
            records.append("action level \(i): actions=\(real) noops=\(facts.count) mutexes=\(actionMutex.count)")
            let next = Set(elements.flatMap(\.add)), values = next.sorted()
            var nextMutex: Mutex = []
            for x in values.indices {
                for y in (x + 1)..<values.count {
                    let p = values[x], q = values[y]
                    let impossible = elements.indices.filter {
                        elements[$0].add.contains(p)
                    }.allSatisfy {
                        a in elements.indices.filter {
                            elements[$0].add.contains(q)
                        }.allSatisfy {
                            b in a != b && actionMutex.contains(Pair(a, b))
                        }
                    }
                    if impossible {
                        nextMutex.insert(Pair(p, q))
                    }
                }
            }
            extractor.levels.append(GraphLevel(elements: elements, mutex: actionMutex))
            facts = next;
            mutex = nextMutex
        }
        return GraphResult(search: SearchResult(status: status, plan: answer.flatMap {
            $0
        }, expanded: extractor.searched, generated: extractor.tried), layers: answer, records: records, hits: extractor.hits)
    }
}
