typealias State = Set<Int>
struct Action {
    let source: Int, name: String, args: [String], cost: Int
    var pre: State, neg: State, add: State, del: State
    var text: String {
        Atom(name, args).text
    }
}
struct Grounding {
    let facts: [Atom], actions: [Action], initial: State, goals: State, unreachable: [Atom]
    let stats: [[Int]], fluent: Set<String>, staticCount: Int
}
struct GroundCandidate {
    let source: Int, args: [String]
    var pre: Set<Atom> = [], neg: Set<Atom> = [], add: Set<Atom> = [], del: Set<Atom> = []
}
enum Grounder {
    static func subtype(_ domain: Domain, _ type: String, _ expected: String) -> Bool {
        var current = type
        while true {
            if current == expected {
                return true
            };
            guard let parent = domain.parents[current] else {
                return false
            };
            current = parent
        }
    }
    static func fluents(_ domain: Domain) -> Set<String> {
        Set(domain.actions.flatMap {
            $0.effects.map {
                $0.atom.predicate
            }
        })
    }
    static func ground(_ domain: Domain, _ problem: Problem) -> Grounding {
        let fluent = fluents(domain), initial = Set(problem.initial)
        var stats = Array(repeating: [0, 0, 0], count: domain.actions.count), candidates: [GroundCandidate] = []
        for (source, action) in domain.actions.enumerated() {
            let choices = action.parameters.map {
                parameter in problem.objects.filter {
                    subtype(domain, $0.1, parameter.1)
                }.map {
                    $0.0
                }
            }
            var all: [[String]] = [], current: [String] = []
            func combinations(_ i: Int) {
                if i == choices.count {
                    all.append(current);
                    return
                }
                for object in choices[i] {
                    current.append(object);
                    combinations(i + 1);
                    current.removeLast()
                }
            }
            combinations(0)
            stats[source][0] = all.count
            for args in all {
                let values = Dictionary(uniqueKeysWithValues: zip(action.parameters.map {
                    $0.0
                }, args))
                var candidate = GroundCandidate(source: source, args: args), valid = true
                for literal in action.pre {
                    let atom = literal.atom.replace(values)
                    if atom.predicate == "=" || !fluent.contains(atom.predicate) {
                        let truth = atom.predicate == "=" ? atom.terms[0] == atom.terms[1] : initial.contains(atom)
                        if truth == literal.negative {
                            valid = false;
                            break
                        }
                    } else if literal.negative {
                        candidate.neg.insert(atom)
                    }
                    else {
                        candidate.pre.insert(atom)
                    }
                }
                if !valid {
                    continue
                }
                for literal in action.effects {
                    let atom = literal.atom.replace(values)
                    if literal.negative {
                        candidate.del.insert(atom)
                    } else {
                        candidate.add.insert(atom)
                    }
                }
                candidate.del.subtract(candidate.add)
                stats[source][1] += 1
                candidates.append(candidate)
            }
        }
        var reachable = Set(initial.filter {
            fluent.contains($0.predicate)
        }), kept: Set<Int> = []
        while true {
            let before = kept.count
            for (i, candidate) in candidates.enumerated() where candidate.pre.isSubset(of: reachable) {
                kept.insert(i);
                reachable.formUnion(candidate.add)
            }
            if kept.count == before {
                break
            }
        }
        let predicates = Dictionary(uniqueKeysWithValues: domain.predicates.enumerated().map {
            ($0.element.name, $0.offset)
        })
        let objects = Dictionary(uniqueKeysWithValues: problem.objects.enumerated().map {
            ($0.element.0, $0.offset)
        })
        let facts = reachable.sorted {
            let a = predicates[$0.predicate]!, b = predicates[$1.predicate]!
            return a == b ? $0.terms.map {
                objects[$0]!
            }.lexicographicallyPrecedes($1.terms.map {
                objects[$0]!
            }) : a < b
        }
        let numbering = Dictionary(uniqueKeysWithValues: facts.enumerated().map {
            ($0.element, $0.offset)
        })
        func numbers(_ atoms: Set<Atom>) -> State {
            Set(atoms.compactMap {
                numbering[$0]
            })
        }
        var actions: [Action] = []
        for i in kept.sorted() {
            let candidate = candidates[i], action = domain.actions[candidate.source]
            stats[candidate.source][2] += 1
            actions.append(Action(source: candidate.source, name: action.name, args: candidate.args, cost: action.cost, pre: numbers(candidate.pre), neg: numbers(candidate.neg), add: numbers(candidate.add), del: numbers(candidate.del)))
        }
        var goals: State = [], unreachable: [Atom] = []
        for atom in problem.goals {
            if let i = numbering[atom] {
                goals.insert(i)
            }
            else if fluent.contains(atom.predicate) || !initial.contains(atom) {
                unreachable.append(atom)
            }
        }
        return Grounding(facts: facts, actions: actions, initial: numbers(initial), goals: goals, unreachable: unreachable, stats: stats, fluent: fluent, staticCount: problem.initial.filter {
            !fluent.contains($0.predicate)
        }.count)
    }
}
