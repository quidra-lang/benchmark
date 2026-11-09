struct DefinitionKey: Hashable {
    let variable: String, number: Int
}
struct CopyKey: Hashable {
    let destination: String, source: String
}
struct FlowSets<Element: Hashable> {
    var input: [Set<Element>], output: [Set<Element>], iterations = 0
}
enum Transfer {
    static func definitions(_ set: Set<DefinitionKey>, _ instruction: Instruction, _ number: Int) -> Set<DefinitionKey> {
        guard let x = instruction.destination else {
            return set
        };
        return Set(set.filter {
            $0.variable != x
        }).union([DefinitionKey(variable: x, number: number)])
    }
    static func live(_ set: Set<String>, _ instruction: Instruction) -> Set<String> {
        var result = set;
        if let x = instruction.destination {
            result.remove(x)
        };
        result.formUnion(instruction.used);
        return result
    }
    static func expressions(_ original: Set<TacExpression>, _ instruction: Instruction) -> Set<TacExpression> {
        var set = original;
        if let expression = instruction.expression {
            set.insert(expression)
        }
        if instruction.kind == "store" {
            set = Set(set.filter {
                $0.kind != "load" || $0.operation != instruction.array
            })
        }
        if instruction.kind == "call" {
            set = Set(set.filter {
                $0.kind != "load"
            })
        }
        if let x = instruction.destination {
            set = Set(set.filter {
                !$0.uses(x)
            })
        };
        return set
    }
    static func copies(_ original: Set<CopyKey>, _ instruction: Instruction) -> Set<CopyKey> {
        var set = original
        if let x = instruction.destination {
            set = Set(set.filter {
                $0.destination != x && $0.source != x
            });
            if instruction.kind == "copy", let y = instruction.a?.variable, y != x {
                set.insert(CopyKey(destination: x, source: y))
            }
        };
        return set
    }
}
final class Analysis {
    var definitions: FlowSets<DefinitionKey>, live: FlowSets<String>, expressions: FlowSets<TacExpression>, copies: FlowSets<CopyKey>
    var beforeDefinitions: [Set<DefinitionKey>], beforeExpressions: [Set<TacExpression>], beforeCopies: [Set<CopyKey>], beforeLive: [Set<String>], afterLive: [Set<String>]
    init(_ function: Function, _ graph: Graph) {
        let count = graph.blocks.count, n = graph.instructions.count, reachableInstructions = graph.instructions.indices.filter {
            graph.reachable.contains(graph.owners[$0])
        }, universe = Set(reachableInstructions.compactMap {
            graph.instructions[$0].expression
        })
        let copyUniverse = Set(reachableInstructions.compactMap {
            i -> CopyKey? in let instruction = graph.instructions[i];
            if instruction.kind == "copy", let x = instruction.destination, let y = instruction.a?.variable, x != y {
                return CopyKey(destination: x, source: y)
            };
            return nil
        })
        definitions = FlowSets(input: Array(repeating: [], count: count), output: Array(repeating: [], count: count));
        live = FlowSets(input: Array(repeating: [], count: count), output: Array(repeating: [], count: count))
        expressions = FlowSets(input: Array(repeating: [], count: count), output: Array(repeating: universe, count: count));
        copies = FlowSets(input: Array(repeating: [], count: count), output: Array(repeating: copyUniverse, count: count))
        beforeDefinitions = Array(repeating: [], count: n);
        beforeExpressions = Array(repeating: [], count: n);
        beforeCopies = Array(repeating: [], count: n);
        beforeLive = Array(repeating: [], count: n);
        afterLive = Array(repeating: [], count: n)
        while true {
            definitions.iterations += 1;
            var changed = false
            for b in graph.order {
                var set: Set<DefinitionKey> = b == 0 ? Set(function.parameters.map {
                    DefinitionKey(variable: $0, number: 0)
                }) : []
                for p in graph.blocks[b].predecessors where graph.reachable.contains(p) {
                    set.formUnion(definitions.output[p])
                };
                definitions.input[b] = set
                for i in graph.blocks[b].first...graph.blocks[b].last {
                    set = Transfer.definitions(set, graph.instructions[i], i + 1)
                };
                if definitions.output[b] != set {
                    changed = true
                };
                definitions.output[b] = set
            };
            if !changed {
                break
            }
        }
        while true {
            live.iterations += 1;
            var changed = false
            for b in graph.postorder {
                var set: Set<String> = [];
                for s in graph.blocks[b].successors {
                    set.formUnion(live.input[s])
                };
                live.output[b] = set
                for i in (graph.blocks[b].first...graph.blocks[b].last).reversed() {
                    set = Transfer.live(set, graph.instructions[i])
                };
                if set != live.input[b] {
                    changed = true
                };
                live.input[b] = set
            };
            if !changed {
                break
            }
        }
        expressions = Self.available(expressions, graph, universe, Transfer.expressions)
        copies = Self.available(copies, graph, copyUniverse, Transfer.copies)
        for b in graph.reachable {
            var d = definitions.input[b], e = expressions.input[b], c = copies.input[b]
            for i in graph.blocks[b].first...graph.blocks[b].last {
                beforeDefinitions[i] = d;
                beforeExpressions[i] = e;
                beforeCopies[i] = c;
                d = Transfer.definitions(d, graph.instructions[i], i + 1);
                e = Transfer.expressions(e, graph.instructions[i]);
                c = Transfer.copies(c, graph.instructions[i])
            }
            var l = live.output[b]
            for i in (graph.blocks[b].first...graph.blocks[b].last).reversed() {
                afterLive[i] = l;
                l = Transfer.live(l, graph.instructions[i]);
                beforeLive[i] = l
            }
        }
    }
    static func available<T: Hashable>(_ original: FlowSets<T>, _ graph: Graph, _ universe: Set<T>, _ transfer: (Set<T>, Instruction) -> Set<T>) -> FlowSets<T> {
        var result = original
        while true {
            result.iterations += 1;
            var changed = false
            for b in graph.order {
                var set: Set<T> = b == 0 ? [] : universe
                if b != 0 {
                    for p in graph.blocks[b].predecessors where graph.reachable.contains(p) {
                        set.formIntersection(result.output[p])
                    }
                };
                result.input[b] = set
                for i in graph.blocks[b].first...graph.blocks[b].last {
                    set = transfer(set, graph.instructions[i])
                };
                if set != result.output[b] {
                    changed = true
                };
                result.output[b] = set
            };
            if !changed {
                return result
            }
        }
    }
}
