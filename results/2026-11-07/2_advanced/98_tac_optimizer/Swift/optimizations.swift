enum FoldResult {
    case unchanged, deleted, replacement(Instruction)
}
enum Optimizations {
    static func fold(_ instruction: Instruction) -> FoldResult {
        guard ["bin", "if"].contains(instruction.kind) else {
            return .unchanged
        };
        let a = instruction.a!, b = instruction.b!
        if let x = a.constant, let y = b.constant {
            if ["/", "%"].contains(instruction.operation) && y == 0 {
                return .unchanged
            };
            let value = TacParser.operation(instruction.operation, x, y)
            if instruction.kind == "if" {
                if value == 0 {
                    return .deleted
                };
                var jump = Instruction("goto");
                jump.target = instruction.target;
                return .replacement(jump)
            }
            return (-2147483648...2147483647).contains(value) ? .replacement(.copy(instruction.destination!, .constant(value))) : .unchanged
        }
        if instruction.kind != "bin" {
            return .unchanged
        };
        let value: Operand?
        if instruction.operation == "+" && a.constant == 0 {
            value = b
        }
        else if ["+", "-"].contains(instruction.operation) && b.constant == 0 {
            value = a
        }
        else if instruction.operation == "*" && a.constant == 1 {
            value = b
        }
        else if ["*", "/"].contains(instruction.operation) && b.constant == 1 {
            value = a
        }
        else if instruction.operation == "*" && (a.constant == 0 || b.constant == 0) {
            value = .constant(0)
        }
        else {
            value = nil
        }
        return value.map {
            .replacement(.copy(instruction.destination!, $0))
        } ?? .unchanged
    }
    static func rewrite(_ function: inout Function, _ replacements: [Int: [Instruction]]) {
        var code: [CodeLine] = [], number = 0
        for line in function.code {
            switch line {
                case .label: code.append(line);
                case .instruction: if let replacement = replacements[number] {
                    code += replacement.map(CodeLine.instruction)
                } else {
                    code.append(line)
                };
                number += 1
            }
        };
        function.code = code
    }
    static func temporary(_ function: inout Function) -> String {
        function.temporary += 1;
        return "_t\(function.temporary)"
    }
    static func cseRewrite(_ instruction: Instruction, _ temporary: String, _ source: Bool) -> [Instruction] {
        let copy = Instruction.copy(instruction.destination!, .variable(temporary));
        if !source {
            return [copy]
        };
        var calculation = instruction;
        calculation.destination = temporary;
        return [calculation, copy]
    }
    static func hoist(_ function: inout Function, _ graph: Graph, _ loop: NaturalLoop, _ moved: [Int]) -> String {
        let h = loop.header, outside = graph.blocks[h].predecessors.filter {
            !loop.blocks.contains($0)
        }, preheader = h != 0 && outside.count == 1 && graph.blocks[outside[0]].successors == [h] ? outside[0] : nil
        let moving = Set(moved), instructions = graph.instructions;
        var insertion: [CodeLine] = [];
        let position: Int, target: String
        if let preheader {
            let last = graph.blocks[preheader].last;
            position = graph.positions[last] + (["goto", "if"].contains(instructions[last].kind) ? 0 : 1);
            target = "B\(preheader + 1)"
        }
        else {
            function.preheader += 1;
            let label = "_p\(function.preheader)";
            target = "new " + label;
            insertion.append(.label(label));
            var first = graph.positions[graph.blocks[h].first]
            while first > 0 {
                if case .label = function.code[first - 1] {
                    first -= 1
                } else {
                    break
                }
            };
            position = first
            for p in outside {
                let index = graph.blocks[p].last;
                if ["goto", "if"].contains(instructions[index].kind) && graph.blocks[h].labels.contains(instructions[index].target), case .instruction(var instruction) = function.code[graph.positions[index]] {
                    instruction.target = label;
                    function.code[graph.positions[index]] = .instruction(instruction)
                }
            }
        }
        insertion += moved.map {
            .instruction(instructions[$0])
        };
        var code: [CodeLine] = [], number = 0
        for (i, line) in function.code.enumerated() {
            if i == position {
                code += insertion
            };
            switch line {
                case .label: code.append(line);
                case .instruction: if !moving.contains(number) {
                    code.append(line)
                };
                number += 1
            }
        };
        if position == function.code.count {
            code += insertion
        };
        function.code = code;
        return target
    }
    static func unreachable(_ function: inout Function, _ graph: Graph) -> [String] {
        var records = graph.blocks.indices.filter {
            !graph.reachable.contains($0)
        }.map {
            "remove block B\($0 + 1)"
        }, code: [CodeLine] = [], labels: [CodeLine] = [], number = 0
        for line in function.code {
            switch line {
                case .label: labels.append(line);
                case .instruction: if graph.reachable.contains(graph.owners[number]) {
                    code += labels;
                    code.append(line)
                };
                labels = [];
                number += 1
            }
        }
        var deleted: Set<Int> = [];
        number = 0
        for (i, line) in code.enumerated() {
            if case .instruction(let instruction) = line {
                number += 1
                if ["goto", "if"].contains(instruction.kind) {
                    var j = i + 1;
                    while j < code.count {
                        guard case .label(let label) = code[j] else {
                            break
                        };
                        if label == instruction.target {
                            deleted.insert(i);
                            records.append("remove jump #\(number)");
                            break
                        };
                        j += 1
                    }
                }
            }
        }
        code = code.enumerated().filter {
            !deleted.contains($0.offset)
        }.map(\.element)
        let targets = Set(code.compactMap {
            line -> String? in if case .instruction(let instruction) = line, ["goto", "if"].contains(instruction.kind) {
                return instruction.target
            };
            return nil
        })
        function.code = code.filter {
            line in if case .label(let label) = line, !targets.contains(label) {
                records.append("remove label " + label);
                return false
            };
            return true
        };
        return records
    }
}
