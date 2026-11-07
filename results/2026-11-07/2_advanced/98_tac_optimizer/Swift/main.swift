import Foundation
let passNames = ["constprop", "copyprop", "cse", "dce", "licm", "unreachable"], kinds = ["copy", "bin", "load", "store", "goto", "if", "param", "call", "return", "read", "print"]
func list(_ values: [String]) -> String {
    values.isEmpty ? "-" : values.joined(separator: ",")
}
func blockList(_ values: [Int]) -> String {
    list(values.map {
        "B\($0 + 1)"
    })
}
func numbers(_ values: [Int]) -> String {
    list(values.map {
        "#\($0 + 1)"
    })
}
func constant(_ instructions: [Instruction], _ definitions: Set<DefinitionKey>, _ variable: String) -> Int? {
    let numbers = definitions.filter {
        $0.variable == variable
    }.map(\.number);
    if numbers.isEmpty || numbers.contains(0) {
        return nil
    };
    var value: Int?
    for number in numbers {
        let instruction = instructions[number - 1];
        guard instruction.kind == "copy", let current = instruction.a?.constant else {
            return nil
        };
        if let value, value != current {
            return nil
        };
        value = current
    };
    return value
}
func propagate(_ function: inout Function, _ graph: Graph, _ analysis: Analysis, _ constants: Bool) -> (Int, [String]) {
    let instructions = graph.instructions;
    var replacements: [Int: [Instruction]] = [:], records: [String] = []
    for (i, original) in instructions.enumerated() where graph.reachable.contains(graph.owners[i]) {
        var instruction = original
        for field in 0..<2 {
            guard let operand = field == 0 ? instruction.a : instruction.b, let variable = operand.variable else {
                continue
            };
            let replacement: Operand?
            if constants {
                replacement = constant(instructions, analysis.beforeDefinitions[i], variable).map(Operand.constant)
            }
            else {
                replacement = analysis.beforeCopies[i].first {
                    $0.destination == variable
                }.map {
                    .variable($0.source)
                }
            }
            if let replacement {
                records.append("#\(i + 1): \(variable) -> \(replacement.text)");
                if field == 0 {
                    instruction.a = replacement
                } else {
                    instruction.b = replacement
                }
            }
        }
        if constants {
            switch Optimizations.fold(instruction) {
                case .deleted: records.append("#\(i + 1): delete \(instruction.text)");
                replacements[i] = [];
                continue;
                case .replacement(let folded): records.append("#\(i + 1): fold \(folded.text)");
                replacements[i] = [folded];
                continue;
                default: break
            }
        };
        replacements[i] = [instruction]
    };
    Optimizations.rewrite(&function, replacements);
    return (records.count, records)
}
func cse(_ function: inout Function, _ graph: Graph, _ analysis: Analysis) -> (Int, [String]) {
    let instructions = graph.instructions;
    var groups: [TacExpression: [Int]] = [:]
    for (i, instruction) in instructions.enumerated() where graph.reachable.contains(graph.owners[i]) {
        if let expression = instruction.expression, analysis.beforeExpressions[i].contains(expression) {
            groups[expression, default: []].append(i)
        }
    }
    var replacements: [Int: [Instruction]] = [:], records: [String] = [], count = 0
    for (expression, candidates) in groups.sorted(by: {
        $0.value[0] < $1.value[0]
    }) {
        var sources: Set<Int> = []
        for candidate in candidates {
            let block = graph.owners[candidate], first = graph.blocks[block].first
            if let source = (first..<candidate).reversed().first(where: {
                instructions[$0].expression == expression
            }) {
                sources.insert(source);
                continue
            }
            var pending = graph.blocks[block].predecessors.filter {
                graph.reachable.contains($0)
            }, seen: Set<Int> = []
            while let block = pending.popLast() {
                if !seen.insert(block).inserted {
                    continue
                }
                if let source = (graph.blocks[block].first...graph.blocks[block].last).reversed().first(where: {
                    instructions[$0].expression == expression
                }) {
                    sources.insert(source)
                }
                else {
                    pending += graph.blocks[block].predecessors.filter {
                        graph.reachable.contains($0)
                    }
                }
            }
        }
        sources.subtract(candidates);
        let temporary = Optimizations.temporary(&function)
        for source in sources {
            replacements[source] = Optimizations.cseRewrite(instructions[source], temporary, true)
        }
        for candidate in candidates {
            replacements[candidate] = Optimizations.cseRewrite(instructions[candidate], temporary, false)
        }
        records.append("\(expression.text): \(temporary) sources=\(numbers(sources.sorted())) replaced=\(numbers(candidates))");
        count += candidates.count
    };
    Optimizations.rewrite(&function, replacements);
    return (count, records)
}
func dce(_ function: inout Function, _ graph: Graph, _ analysis: Analysis) -> (Int, [String]) {
    var replacements: [Int: [Instruction]] = [:], records: [Int: String] = [:]
    for b in graph.reachable.sorted() {
        var live = analysis.live.output[b]
        for i in (graph.blocks[b].first...graph.blocks[b].last).reversed() {
            var instruction = graph.instructions[i]
            let selfCopy = instruction.kind == "copy" && instruction.destination == instruction.a?.variable, dead = ["copy", "bin", "load"].contains(instruction.kind) && instruction.destination.map {
                !live.contains($0)
            } ?? false
            if selfCopy || dead {
                replacements[i] = [];
                records[i] = "#\(i + 1): delete \(instruction.text)";
                continue
            }
            if instruction.kind == "call", let x = instruction.destination, !live.contains(x) {
                records[i] = "#\(i + 1): unused result \(instruction.text)";
                instruction.destination = nil;
                replacements[i] = [instruction]
            };
            live = Transfer.live(live, instruction)
        }
    };
    Optimizations.rewrite(&function, replacements);
    let lines = records.keys.sorted().map {
        records[$0]!
    };
    return (lines.count, lines)
}
func licm(_ function: inout Function, _ graph: Graph, _ analysis: Analysis) -> (Int, [String]) {
    let instructions = graph.instructions
    for loop in graph.loops.sorted(by: {
        ($0.blocks.count, $0.header) < ($1.blocks.count, $1.header)
    }) {
        func inside(_ number: Int) -> Bool {
            number != 0 && loop.blocks.contains(graph.owners[number - 1])
        }
        let indices = instructions.indices.filter {
            loop.blocks.contains(graph.owners[$0])
        };
        var marked: Set<Int> = [], order: [Int] = []
        while true {
            var changed = false
            for i in indices {
                let instruction = instructions[i]
                if marked.contains(i) || !["copy", "bin", "load"].contains(instruction.kind) {
                    continue
                }
                if instruction.kind == "load" && indices.contains(where: {
                    instructions[$0].kind == "call" || instructions[$0].kind == "store" && instructions[$0].array == instruction.array
                }) {
                    continue
                }
                let invariant = instruction.used.allSatisfy {
                    variable in let definitions = analysis.beforeDefinitions[i].filter {
                        $0.variable == variable
                    }.map(\.number);
                    return definitions.allSatisfy {
                        !inside($0)
                    } || definitions.count == 1 && inside(definitions[0]) && marked.contains(definitions[0] - 1)
                }
                if invariant {
                    marked.insert(i);
                    order.append(i);
                    changed = true
                }
            };
            if !changed {
                break
            }
        }
        var moved: [Int] = [], movedSet: Set<Int> = []
        for i in order {
            let instruction = instructions[i], destination = instruction.destination!
            if indices.filter({
                instructions[$0].destination == destination
            }).count != 1 || analysis.live.input[loop.header].contains(destination) {
                continue
            }
            let block = graph.owners[i], dominatesExits = loop.exits.allSatisfy {
                graph.dominators[$0].contains(block)
            }
            let dangerous = instruction.kind == "load" || instruction.kind == "bin" && ["/", "%"].contains(instruction.operation) && (instruction.b?.constant.map {
                $0 == 0
            } ?? true)
            let safe = !dangerous && loop.outside.allSatisfy {
                !analysis.live.input[$0].contains(destination)
            }
            if !dominatesExits && !safe {
                continue
            }
            if !instruction.used.allSatisfy({
                variable in analysis.beforeDefinitions[i].filter {
                    $0.variable == variable && inside($0.number)
                }.allSatisfy {
                    movedSet.contains($0.number - 1)
                }
            }) {
                continue
            }
            moved.append(i);
            movedSet.insert(i)
        }
        if !moved.isEmpty {
            let target = Optimizations.hoist(&function, graph, loop, moved);
            return (moved.count, ["B\(loop.header + 1): hoist \(numbers(moved)) to \(target)"])
        }
    };
    return (0, [])
}
func pass(_ name: String, _ function: inout Function) -> (Int, [String]) {
    let graph = Graph(function), analysis = Analysis(function, graph)
    switch name {
        case "constprop": return propagate(&function, graph, analysis, true);
        case "copyprop": return propagate(&function, graph, analysis, false);
        case "cse": return cse(&function, graph, analysis);
        case "dce": return dce(&function, graph, analysis);
        case "licm": return licm(&function, graph, analysis);
        default: let records = Optimizations.unreachable(&function, graph);
        return (records.count, records)
    }
}
func reach(_ start: Int, _ edges: [[Int]]) -> Set<Int> {
    var pending = [start], seen: Set<Int> = [];
    while let i = pending.popLast() {
        if seen.insert(i).inserted {
            pending += edges[i]
        }
    };
    return seen
}
struct Calls {
    let edges: [[Int]], reachable: Set<Int>
}
func callGraph(_ program: Program) -> Calls {
    let indices = Dictionary(uniqueKeysWithValues: program.functions.enumerated().map {
        ($0.element.name, $0.offset)
    }), edges = program.functions.map {
        function in Set(function.instructions.filter {
            $0.kind == "call"
        }.map {
            indices[$0.function]!
        }).sorted()
    };
    return Calls(edges: edges, reachable: reach(indices["main"]!, edges))
}
func graphReport(_ program: Program, _ graph: Calls, _ label: String) -> [String] {
    var lines = ["== call graph (\(label)) =="]
    for (i, function) in program.functions.enumerated() {
        let recursive = graph.edges[i].contains {
            reach($0, graph.edges).contains(i)
        };
        lines.append("\(function.name) -> \(list(graph.edges[i].map { program.functions[$0].name }))" + (recursive ? " (recursive)" : ""))
    }
    lines.append("unreachable functions: " + list(program.functions.indices.filter {
        !graph.reachable.contains($0)
    }.map {
        program.functions[$0].name
    }));
    return lines
}
func definitionList(_ set: Set<DefinitionKey>) -> String {
    list(set.sorted {
        ($0.number, $0.variable) < ($1.number, $1.variable)
    }.map {
        "\($0.variable):\($0.number)"
    })
}
func analysisReport(_ function: Function, _ label: String) -> [String] {
    let graph = Graph(function), analysis = Analysis(function, graph);
    var lines = ["== \(function.name) (\(label)) ==", "code:"], number = 0
    for line in function.code {
        switch line {
            case .label(let label): lines.append(label + ":")
            case .instruction(let instruction):
            var text = "  #\(number + 1) \(instruction.text)"
            if graph.reachable.contains(graph.owners[number]) {
                var used: Set<String> = [], chains: [String] = []
                for variable in instruction.used where used.insert(variable).inserted {
                    let definitions = analysis.beforeDefinitions[number].filter {
                        $0.variable == variable
                    }.map(\.number).sorted();
                    chains.append(variable + ":" + list(definitions.map(String.init)))
                }
                if !chains.isEmpty {
                    text += " | " + chains.joined(separator: " ")
                }
            };
            lines.append(text);
            number += 1
        }
    }
    lines.append("blocks: \(graph.blocks.count)")
    for (b, block) in graph.blocks.enumerated() {
        lines.append("B\(b + 1) \(block.first + 1)-\(block.last + 1) labels=\(list(block.labels)) preds=\(blockList(block.predecessors)) succs=\(blockList(block.successors))")
    }
    lines += ["unreachable: " + blockList(graph.blocks.indices.filter {
        !graph.reachable.contains($0)
    }), "order: " + blockList(graph.order), "dominators:"]
    for b in graph.reachable.sorted() {
        lines.append("B\(b + 1) idom=\(graph.idom[b].map { "B\($0 + 1)" } ?? "-") dom=\(blockList(graph.dominators[b].sorted()))")
    };
    lines.append("dominator tree:")
    func tree(_ block: Int, _ depth: Int) {
        lines.append(String(repeating: " ", count: depth * 2) + "B\(block + 1)");
        for b in graph.blocks.indices where graph.idom[b] == block {
            tree(b, depth + 1)
        }
    };
    tree(0, 0)
    lines.append("loops: \(graph.loops.count)")
    for loop in graph.loops {
        lines.append("header=B\(loop.header + 1) latches=\(blockList(loop.latches)) depth=\(loop.depth) blocks=\(blockList(loop.blocks.sorted())) exits=\(blockList(loop.exits.sorted()))")
    }
    lines.append("reaching definitions: iterations=\(analysis.definitions.iterations)")
    for b in graph.reachable.sorted() {
        lines.append("B\(b + 1) in=\(definitionList(analysis.definitions.input[b])) out=\(definitionList(analysis.definitions.output[b]))")
    };
    lines.append("liveness: iterations=\(analysis.live.iterations)")
    for b in graph.reachable.sorted() {
        lines.append("B\(b + 1) in=\(list(analysis.live.input[b].sorted())) out=\(list(analysis.live.output[b].sorted()))")
    };
    lines.append("available expressions: iterations=\(analysis.expressions.iterations)")
    for b in graph.reachable.sorted() {
        lines.append("B\(b + 1) in=\(list(analysis.expressions.input[b].map(\.text).sorted())) out=\(list(analysis.expressions.output[b].map(\.text).sorted()))")
    };
    return lines
}
func allocate(_ function: Function, _ registers: Int, _ output: inout [String]) -> Function {
    let graph = Graph(function), analysis = Analysis(function, graph), allocation = Regalloc.allocate(function, graph, analysis, registers)
    func rewrite(_ name: String) -> String {
        allocation.registers[name].map {
            "R\($0)"
        } ?? name
    }
    func operand(_ value: Operand?) -> Operand? {
        value.map {
            if let name = $0.variable {
                return .variable(rewrite(name))
            };
            return $0
        }
    }
    var allocated = function, moves = 0;
    allocated.parameters = allocated.parameters.map(rewrite)
    allocated.code = allocated.code.compactMap {
        line in
        guard case .instruction(var instruction) = line else {
            return line
        };
        instruction.destination = instruction.destination.map(rewrite);
        instruction.a = operand(instruction.a);
        instruction.b = operand(instruction.b)
        if instruction.kind == "copy" && instruction.destination == instruction.a?.variable {
            moves += 1;
            return nil
        };
        return .instruction(instruction)
    }
    let spillUses = graph.instructions.reduce(0) {
        $0 + $1.used.filter {
            allocation.spills.contains($0)
        }.count
    }, spillDefinitions = function.parameters.filter {
        allocation.spills.contains($0)
    }.count + graph.instructions.filter {
        $0.destination.map {
            allocation.spills.contains($0)
        } ?? false
    }.count
    let pressure = graph.instructions.indices.filter {
        graph.reachable.contains(graph.owners[$0])
    }.map {
        max(analysis.beforeLive[$0].count, analysis.afterLive[$0].count)
    }.max() ?? 0
    output += ["== \(function.name) ==", "nodes=\(allocation.nodes.count) edges=\(allocation.neighbors.values.reduce(0) { $0 + $1.count } / 2) registers=\(registers)"]
    for node in allocation.nodes {
        let neighbors = allocation.neighbors[node]!;
        output.append("\(node) degree=\(neighbors.count) cost=\(allocation.costs[node]!) neighbors=\(list(neighbors.sorted()))")
    }
    output += ["simplify: " + list(allocation.order), "potential spills: " + list(allocation.potential.map {
        "\($0.0)(\(allocation.costs[$0.0]!)/\($0.1))"
    })]
    for node in allocation.nodes {
        output.append("\(node) -> \(allocation.registers[node].map { "R\($0)" } ?? "spill")")
    }
    output.append("summary: pressure=\(pressure) used=\(Set(allocation.registers.values).count) spilled=\(allocation.spills.count) moves=\(moves) spill_uses=\(spillUses) spill_defs=\(spillDefinitions)");
    output += allocated.text;
    return allocated
}
final class Execution {
    let program: Program, input: [Int];
    var arrays: [String: [Int]], position = 0, output: [Int] = [], steps: [String: Int] = [:], calls: [String: Int] = [:], counts = Dictionary(uniqueKeysWithValues: kinds.map {
        ($0, 0)
    })
    init(_ program: Program, _ input: [Int]) {
        self.program = program;
        self.input = input;
        arrays = Dictionary(uniqueKeysWithValues: program.arrays.map {
            ($0.0, Array(repeating: 0, count: $0.1))
        })
    }
    func call(_ name: String, _ arguments: [Int]) -> Int? {
        calls[name, default: 0] += 1;
        let function = program.functions.first {
            $0.name == name
        }!, instructions = function.instructions, labels = TacParser.labels(function)
        var values = Dictionary(uniqueKeysWithValues: zip(function.parameters, arguments)), pushed: [Int] = [], pc = 0
        func value(_ operand: Operand) -> Int {
            operand.constant ?? values[operand.variable!]!
        }
        while true {
            let instruction = instructions[pc];
            steps[name, default: 0] += 1;
            counts[instruction.kind, default: 0] += 1
            var next = pc + 1, result: Int?;
            let a = instruction.a.map(value), b = instruction.b.map(value)
            switch instruction.kind {
                case "copy": result = a
                case "bin": result = TacParser.operation(instruction.operation, a!, b!)
                case "load": result = arrays[instruction.array]![a!]
                case "store": arrays[instruction.array]![a!] = b!
                case "goto": next = labels[instruction.target]!
                case "if": if TacParser.operation(instruction.operation, a!, b!) != 0 {
                    next = labels[instruction.target]!
                }
                case "param": pushed.append(a!)
                case "call": let arguments = Array(pushed.suffix(instruction.count));
                pushed.removeLast(instruction.count);
                result = call(instruction.function, arguments)
                case "return": return a
                case "read": result = input[position];
                position += 1
                default: output.append(a!)
            }
            if let destination = instruction.destination, let result {
                values[destination] = result
            };
            pc = next
        }
    }
}
func kindCounts(_ program: Program) -> [String: Int] {
    var counts = Dictionary(uniqueKeysWithValues: kinds.map {
        ($0, 0)
    });
    for function in program.functions {
        for instruction in function.instructions {
            counts[instruction.kind, default: 0] += 1
        }
    };
    return counts
}
func write(_ name: String, _ lines: [String]) {
    try! FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try! (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: true, encoding: .utf8)
}
let original = TacParser.parse(try! String(contentsOfFile: "input/program.tac", encoding: .ascii)), settings = try! String(contentsOfFile: "input/params.txt", encoding: .ascii).split(separator: "\n").map {
    $0.split(separator: " ").map(String.init)
}
let registers = Int(settings[0][1])!, enabled = passNames.filter {
    settings[1].dropFirst().contains($0)
}, maxRounds = Int(settings[2][1])!
var optimized = original, passes: [String] = [], totals = Dictionary(uniqueKeysWithValues: enabled.map {
    ($0, 0)
})
for i in optimized.functions.indices {
    let before = optimized.functions[i].instructions.count;
    passes.append("== \(optimized.functions[i].name) ==");
    var performed = 0
    for round in 1...maxRounds {
        performed = round;
        var changes: [String] = [], records: [String] = [], changed = false
        for name in enabled {
            let (count, entries) = pass(name, &optimized.functions[i]);
            if count > 0 {
                changed = true
            };
            changes.append("\(name)=\(count)");
            totals[name, default: 0] += count;
            records += entries.map {
                "  \(name) \($0)"
            }
        }
        passes.append("round \(round): " + changes.joined(separator: " "));
        passes += records;
        if !changed {
            break
        }
    };
    passes.append("result: rounds=\(performed) instructions=\(before)->\(optimized.functions[i].instructions.count)")
}
let optimizedGraph = callGraph(optimized)
var analysisLines = graphReport(original, callGraph(original), "original")
for function in original.functions {
    analysisLines += analysisReport(function, "original")
};
analysisLines += graphReport(optimized, optimizedGraph, "optimized")
let removed = enabled.contains("unreachable") ? optimized.functions.indices.filter {
    !optimizedGraph.reachable.contains($0)
}.map {
    optimized.functions[$0].name
} : []
optimized.functions.removeAll {
    removed.contains($0.name)
}
for function in optimized.functions {
    analysisLines += analysisReport(function, "optimized")
}
passes += ["== program ==", "removed functions: " + list(removed), "== total ==", enabled.map {
    "\($0)=\(totals[$0]!)"
}.joined(separator: " ")]
var allocationLines: [String] = []
let allocated = Program(arrays: optimized.arrays, functions: optimized.functions.map {
    allocate($0, registers, &allocationLines)
})
let runs = try! String(contentsOfFile: "input/input.txt", encoding: .ascii).split(separator: "\n").dropFirst().map {
    $0.split(separator: " ").dropFirst().map {
        Int($0)!
    }
}, programs = [original, optimized, allocated], labels = ["original", "optimized", "allocated"]
var comparison: [String] = [], same = 0, totalSteps = [0, 0, 0], profileSteps = Array(repeating: [String: Int](), count: 3), profileCalls: [String: Int] = [:], dynamic = Array(repeating: Dictionary(uniqueKeysWithValues: kinds.map {
    ($0, 0)
}), count: 3)
for (i, input) in runs.enumerated() {
    comparison.append("run \(i + 1): inputs=\(input.count)");
    var outputs: [[Int]] = []
    for p in 0..<3 {
        let execution = Execution(programs[p], input);
        _ = execution.call("main", []);
        let steps = execution.steps.values.reduce(0, +), calls = execution.calls.values.reduce(0, +)
        comparison.append("  \(labels[p]): steps=\(steps) calls=\(calls) output=\(list(execution.output.map(String.init)))");
        outputs.append(execution.output);
        totalSteps[p] += steps
        for (name, count) in execution.steps {
            profileSteps[p][name, default: 0] += count
        };
        if p == 0 {
            for (name, count) in execution.calls {
                profileCalls[name, default: 0] += count
            }
        };
        for kind in kinds {
            dynamic[p][kind, default: 0] += execution.counts[kind]!
        }
    }
    let equal = outputs[0] == outputs[1] && outputs[0] == outputs[2];
    if equal {
        same += 1
    };
    comparison.append("  result: " + (equal ? "same" : "different"))
}
comparison.append("== profile ==")
for function in original.functions {
    let name = function.name;
    comparison.append("\(name): calls=\(profileCalls[name] ?? 0) original=\(profileSteps[0][name] ?? 0) optimized=\(profileSteps[1][name] ?? 0) allocated=\(profileSteps[2][name] ?? 0)")
}
let before = kindCounts(original), after = kindCounts(optimized)
comparison += ["== summary ==", "runs=\(runs.count) same=\(same) different=\(runs.count - same)", "instructions: original=\(before.values.reduce(0, +)) optimized=\(after.values.reduce(0, +))", "kinds: " + kinds.map {
    "\($0)=\(before[$0]!)->\(after[$0]!)"
}.joined(separator: " "), "steps: original=\(totalSteps[0]) optimized=\(totalSteps[1]) allocated=\(totalSteps[2])"]
for p in 0..<3 {
    comparison.append("dynamic \(labels[p]): " + kinds.map {
        "\($0)=\(dynamic[p][$0]!)"
    }.joined(separator: " "))
}
write("optimized.tac", optimized.text);
write("analysis.txt", analysisLines);
write("passes.txt", passes);
write("regalloc.txt", allocationLines);
write("comparison.txt", comparison)
