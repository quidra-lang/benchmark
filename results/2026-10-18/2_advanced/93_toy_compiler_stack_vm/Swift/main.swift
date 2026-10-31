import Foundation
func reachableFrom(_ root: Int, _ calls: [Int: Set<Int>]) -> Set<Int> {
    var seen: Set<Int> = [], pending = [root]
    while let id = pending.popLast() {
        if seen.insert(id).inserted {
            pending += (calls[id] ?? []).sorted()
        }
    };
    return seen
}
func warningLines(_ program: Program, _ semantic: Semantic, _ reachable: Set<Int>) -> [String] {
    var warnings: [(Position, String)] = []
    for symbol in semantic.symbols {
        if symbol.variable != nil && symbol.reads == 0 {
            warnings.append((symbol.name.position, "unused \(symbol.parameter ? "parameter" : "variable") '\(symbol.name.text)'"))
        }
        if let function = symbol.function, !reachable.contains(function.id) {
            warnings.append((symbol.name.position, "function '\(symbol.name.text)' is never called"))
        }
    }
    func walk(_ statement: Stmt) {
        switch statement.kind {
            case .block(let values, _):
            if let i = values.indices.first(where: {
                !canComplete(values[$0])
            }), i + 1 < values.count {
                warnings.append((values[i + 1].position, "unreachable statement"))
            };
            for value in values {
                walk(value)
            }
            case .conditional(_, let yes, let no): walk(yes);
            if let no {
                walk(no)
            }
            case .whileLoop(_, let body): walk(body)
            case .forLoop(let initial, _, let update, let body): if let initial {
                walk(initial)
            };
            if let update {
                walk(update)
            };
            walk(body)
            default: break
        }
    }
    for declaration in program.declarations {
        if case .function(let function) = declaration {
            walk(function.body)
        }
    }
    return warnings.sorted {
        $0.0 < $1.0
    }.map {
        "warning \($0.0): \($0.1)"
    }
}
final class Folder {
    var count = 0
    func literal(_ expression: Expr) -> Int? {
        switch expression.kind {
            case .integer(let v): return v;
            case .boolean(let v): return v ? 1 : 0;
            default: return nil
        }
    }
    func boolean(_ expression: Expr, _ value: Bool) -> Bool {
        if case .boolean(let v) = expression.kind {
            return v == value
        };
        return false
    }
    func integer(_ expression: Expr, _ value: Int) -> Bool {
        if case .integer(let v) = expression.kind {
            return v == value
        };
        return false
    }
    func made(_ old: Expr, _ value: Int, _ type: ToyType) -> Expr {
        let expression = Expr(old.position, type == .bool ? .boolean(value != 0) : .integer(value));
        expression.type = type;
        count += 1;
        return expression
    }
    func expression(_ original: Expr) -> Expr {
        switch original.kind {
            case .element(let name, let index): original.kind = .element(name, expression(index))
            case .call(let name, let arguments): original.kind = .call(name, arguments.map(expression))
            case .unary(let op, let value):
            let value = expression(value);
            original.kind = .unary(op, value)
            if let v = literal(value) {
                let result = op == "!" ? (v == 0 ? 1 : 0) : -v;
                if (-2147483648...2147483647).contains(result) {
                    return made(original, result, original.type!)
                }
            }
            case .binary(let op, let left, let right):
            let a = expression(left), b = expression(right);
            original.kind = .binary(op, a, b)
            if let x = literal(a), let y = literal(b) {
                var value: Int?
                switch op {
                    case "+": value = x + y;
                    case "-": value = x - y;
                    case "*": value = x * y;
                    case "/": if y != 0 {
                        value = x / y
                    };
                    case "%": if y != 0 {
                        value = x - y * (x / y)
                    };
                    case "<": value = x < y ? 1 : 0;
                    case "<=": value = x <= y ? 1 : 0;
                    case ">": value = x > y ? 1 : 0;
                    case ">=": value = x >= y ? 1 : 0;
                    case "==": value = x == y ? 1 : 0;
                    case "!=": value = x != y ? 1 : 0;
                    case "&&": value = x != 0 && y != 0 ? 1 : 0;
                    case "||": value = x != 0 || y != 0 ? 1 : 0;
                    default: break
                }
                if let value, (-2147483648...2147483647).contains(value) {
                    return made(original, value, original.type!)
                }
            }
            if op == "&&" && boolean(a, false) {
                return made(original, 0, .bool)
            }
            if op == "||" && boolean(a, true) {
                return made(original, 1, .bool)
            }
            if op == "&&" && boolean(a, true) || op == "||" && boolean(a, false) || op == "+" && integer(a, 0) || op == "*" && integer(a, 1) {
                count += 1;
                return b
            }
            if ["+", "-"].contains(op) && integer(b, 0) || ["*", "/"].contains(op) && integer(b, 1) || op == "&&" && boolean(b, true) || op == "||" && boolean(b, false) {
                count += 1;
                return a
            }
            default: break
        };
        return original
    }
    func statement(_ original: Stmt) -> Stmt {
        switch original.kind {
            case .block(let values, let close): original.kind = .block(values.map(statement), close)
            case .declaration(let variable): variable.initializer = variable.initializer.map(expression)
            case .assignment(let name, let index, let value): original.kind = .assignment(name, index.map(expression), expression(value))
            case .call(let value): original.kind = .call(expression(value))
            case .print(let values): original.kind = .print(values.map(expression))
            case .returnValue(let value): original.kind = .returnValue(value.map(expression))
            case .conditional(let condition, let yes, let no):
            let condition = expression(condition)
            if case .boolean(let value) = condition.kind {
                count += 1;
                return value ? statement(yes) : no.map(statement) ?? Stmt(original.position, .empty)
            }
            original.kind = .conditional(condition, statement(yes), no.map(statement))
            case .whileLoop(let condition, let body):
            let condition = expression(condition);
            if boolean(condition, false) {
                count += 1;
                return Stmt(original.position, .empty)
            };
            original.kind = .whileLoop(condition, statement(body))
            case .forLoop(let initial, let condition, let update, let body): original.kind = .forLoop(initial.map(statement), condition.map(expression), update.map(statement), statement(body))
            default: break
        };
        return original
    }
    func program(_ program: Program, _ reachable: Set<Int>) {
        for declaration in program.declarations {
            switch declaration {
                case .variable(let variable): variable.initializer = variable.initializer.map(expression);
                case .function(let function) where reachable.contains(function.id): if case .block(let values, let close) = function.body.kind {
                    function.body.kind = .block(values.map(statement), close)
                };
                default: break
            }
        }
    }
}
let ruleNames = ["const-jump", "not-compare", "not-jump", "invert-branch", "thread", "jump-next", "unreachable"]
func isJump(_ op: String) -> Bool {
    ["JUMP", "JUMPF", "JUMPT"].contains(op)
}
func conditional(_ op: String) -> Bool {
    op == "JUMPF" || op == "JUMPT"
}
func transfer(_ op: String) -> Bool {
    ["JUMP", "RET", "RETV", "HALT"].contains(op)
}
func jumps(_ op: String, _ value: Int) -> Bool {
    op == "JUMPF" ? value == 0 : value != 0
}
func inverse(_ op: String) -> String {
    op == "JUMPF" ? "JUMPT" : "JUMPF"
}
func peephole(_ original: [Instruction]) -> ([Instruction], [Int]) {
    var code = original, counts = Array(repeating: 0, count: 7)
    func delete(_ index: Int) {
        code.remove(at: index);
        for k in code.indices where isJump(code[k].op) && code[k].operands[0] > index {
            code[k].operands[0] -= 1
        }
    }
    while true {
        let targets = Set(code.filter {
            isJump($0.op)
        }.map {
            $0.operands[0]
        });
        var changed = false
        for i in code.indices {
            let a = code[i], b: Instruction? = i + 1 < code.count ? code[i + 1] : nil, free = b != nil && !targets.contains(i + 1)
            if let b, free && a.op == "PUSH" && conditional(b.op) {
                if jumps(b.op, a.operands[0]) {
                    code[i] = Instruction("JUMP", b.operands, b.position);
                    delete(i + 1)
                } else {
                    delete(i + 1);
                    delete(i)
                };
                counts[0] += 1
            } else if let b, free && b.op == "NOT", let negated = ["LT": "GE", "LE": "GT", "GT": "LE", "GE": "LT", "EQ": "NE", "NE": "EQ"][a.op] {
                code[i].op = negated;
                delete(i + 1);
                counts[1] += 1
            }
            else if let b, free && a.op == "NOT" && conditional(b.op) {
                code[i] = Instruction(inverse(b.op), b.operands, b.position);
                delete(i + 1);
                counts[2] += 1
            }
            else if let b, free && conditional(a.op) && a.operands[0] == i + 2 && b.op == "JUMP" {
                code[i] = Instruction(inverse(a.op), b.operands, a.position);
                delete(i + 1);
                counts[3] += 1
            }
            else {
                var target: Int?
                if isJump(a.op) && a.operands[0] < code.count {
                    let t = a.operands[0], at = code[t]
                    if at.op == "JUMP" {
                        target = at.operands[0]
                    }
                    else if at.op == "PUSH" && t + 1 < code.count && conditional(code[t + 1].op) {
                        target = jumps(code[t + 1].op, at.operands[0]) ? code[t + 1].operands[0] : t + 2
                    }
                }
                if let target, target != a.operands[0] {
                    code[i].operands[0] = target;
                    counts[4] += 1
                }
                else if isJump(a.op) && a.operands[0] == i + 1 {
                    if a.op == "JUMP" {
                        delete(i)
                    } else {
                        code[i] = Instruction("POP", [], a.position)
                    };
                    counts[5] += 1
                }
                else if free && transfer(a.op) {
                    delete(i + 1);
                    counts[6] += 1
                }
                else {
                    continue
                }
            };
            changed = true;
            break
        };
        if !changed {
            return (code, counts)
        }
    }
}
func successors(_ code: [Instruction], _ index: Int) -> [Int] {
    let instruction = code[index];
    var result: [Int] = []
    if !transfer(instruction.op) && index + 1 < code.count {
        result.append(index + 1)
    }
    if isJump(instruction.op), instruction.operands[0] < code.count, !result.contains(instruction.operands[0]) {
        result.append(instruction.operands[0])
    };
    return result
}
struct BasicBlock {
    let first: Int, last: Int, successors: [Int]
}
func blocks(_ code: [Instruction]) -> [BasicBlock] {
    var leaders: Set<Int> = [0]
    for (i, instruction) in code.enumerated() {
        if isJump(instruction.op) && instruction.operands[0] < code.count {
            leaders.insert(instruction.operands[0])
        }
        if (isJump(instruction.op) || transfer(instruction.op)) && i + 1 < code.count {
            leaders.insert(i + 1)
        }
    }
    let sorted = leaders.sorted(), index = Dictionary(uniqueKeysWithValues: sorted.enumerated().map {
        ($0.element, $0.offset)
    })
    return sorted.enumerated().map {
        k, first in let last = k + 1 < sorted.count ? sorted[k + 1] - 1 : code.count - 1;
        return BasicBlock(first: first, last: last, successors: successors(code, last).map {
            index[$0]!
        })
    }
}
func stackDepth(_ code: [Instruction], _ semantic: Semantic) -> Int {
    func effect(_ instruction: Instruction) -> Int {
        switch instruction.op {
            case "PUSH", "LOADG", "LOADL", "READ": return 1
            case "POP", "STOREG", "STOREL", "JUMPF", "JUMPT", "RETV", "ADD", "SUB", "MUL", "DIV", "MOD", "LT", "LE", "GT", "GE", "EQ", "NE": return -1
            case "STOREA": return -2
            case "CALL": return -instruction.operands[1] + (semantic.symbols[instruction.callee!].type == .void ? 0 : 1)
            case "PRINT": return -instruction.operands[0]
            default: return 0
        }
    }
    var depth: [Int: Int] = [0: 0], pending = [0], maximum = 0
    while let i = pending.popLast() {
        let nextDepth = depth[i]! + effect(code[i]);
        maximum = max(maximum, nextDepth)
        for j in successors(code, i) where depth[j] == nil {
            depth[j] = nextDepth;
            pending.append(j)
        }
    };
    return maximum
}
struct FlatCode {
    let instructions: [Instruction], owners: [Int], starts: [Int]
}
func flatten(_ units: [Unit]) -> FlatCode {
    var starts: [Int] = [], address = 0, functionStarts: [Int: Int] = [:]
    for unit in units {
        starts.append(address);
        if let function = unit.function {
            functionStarts[function.id] = address
        };
        address += unit.code.count
    }
    var instructions: [Instruction] = [], owners: [Int] = []
    for (i, unit) in units.enumerated() {
        for var instruction in unit.code {
            if isJump(instruction.op) {
                instruction.operands[0] += starts[i]
            }
            if instruction.op == "CALL" {
                instruction.operands[0] = functionStarts[instruction.callee!]!
            }
            instructions.append(instruction);
            owners.append(i)
        }
    };
    return FlatCode(instructions: instructions, owners: owners, starts: starts)
}
func spelling(_ instruction: Instruction) -> String {
    instruction.op + instruction.operands.map {
        " " + String($0)
    }.joined()
}
func pad(_ text: String, _ width: Int, _ left: Bool = false) -> String {
    let spaces = String(repeating: " ", count: max(0, width - text.count));
    return left ? text + spaces : spaces + text
}
func listingLines(_ program: Program, _ semantic: Semantic, _ before: [Unit], _ after: [Unit], _ old: FlatCode, _ new: FlatCode) -> [String] {
    let globals: [Variable] = program.declarations.compactMap {
        if case .variable(let variable) = $0 {
            return variable
        };
        return nil
    }
    var lines = globals.isEmpty ? ["globals: none"] : ["globals:"]
    for variable in globals {
        lines.append("  \(variable.address) \(variable.name.text) " + (variable.size.map {
            "int[\($0)]"
        } ?? variable.type.rawValue))
    }
    lines.append("functions:")
    for (i, unit) in after.enumerated() {
        let signature = unit.function.map {
            " " + $0.type.rawValue + "(" + $0.parameters.map {
                $0.type.rawValue
            }.joined(separator: ",") + ")"
        } ?? ""
        let callees = unit.function.map {
            (semantic.calls[$0.id] ?? []).map {
                semantic.symbols[$0].name.text
            }.sorted()
        } ?? ["main"]
        let recursive = unit.function.map {
            function in (semantic.calls[function.id] ?? []).contains {
                reachableFrom($0, semantic.calls).contains(function.id)
            }
        } ?? false
        lines.append("  \(unit.name)\(signature) address=\(old.starts[i])->\(new.starts[i]) size=\(before[i].code.count)->\(unit.code.count) slots=\(unit.slots.count) stack=\(stackDepth(unit.code, semantic)) blocks=\(blocks(unit.code).count) calls=\(callees.isEmpty ? "-" : callees.joined(separator: ","))" + (recursive ? " recursive" : ""))
        for (slot, variable) in unit.slots.enumerated() {
            lines.append("    slot \(slot) \(variable.name.text) \(variable.type.rawValue)")
        }
    }
    lines.append("references:")
    let referents = globals.map(\.id) + program.declarations.compactMap {
        if case .function(let function) = $0 {
            return function.id
        };
        return nil
    }
    for id in referents {
        let symbol = semantic.symbols[id], uses = Set(symbol.references.map(\.line)).sorted().map(String.init);
        lines.append("  \(symbol.name.text) defined \(symbol.name.position.line) used \(uses.isEmpty ? "-" : uses.joined(separator: " "))")
    }
    for (heading, units, flat) in [("before", before, old), ("after", after, new)] {
        lines.append("\(heading) peephole: \(flat.instructions.count) instructions")
        for (i, unit) in units.enumerated() {
            lines.append(unit.name + ":");
            for j in unit.code.indices {
                let pc = flat.starts[i] + j;
                lines.append(pad(String(pc), 5) + "  " + spelling(flat.instructions[pc]))
            }
        }
    }
    lines.append("control flow:")
    for (i, unit) in after.enumerated() {
        lines.append("  " + unit.name)
        for (k, block) in blocks(unit.code).enumerated() {
            lines.append("    B\(k) \(new.starts[i] + block.first)-\(new.starts[i] + block.last)" + (block.successors.isEmpty ? "" : " -> " + block.successors.map {
                "B\($0)"
            }.joined(separator: " ")))
        }
    };
    return lines
}
func statsLines(_ beforeCount: Int, _ after: [Unit], _ code: FlatCode, _ main: VMResult, _ comparison: VMResult, _ folds: Int, _ rules: [Int]) -> [String] {
    var lines = ["code: \(beforeCount) -> \(code.instructions.count)", "folds: \(folds)", "peephole: \(rules.reduce(0, +))"]
    for i in ruleNames.indices {
        lines.append("  \(ruleNames[i]) \(rules[i])")
    }
    lines += ["executed: \(main.executed)", "executed before peephole: \(comparison.executed)", "behaviour: \(main.output == comparison.output && main.message == comparison.message ? "same" : "different")", "max call depth: \(main.maxDepth)", "max stack: \(main.maxStack)", "opcodes:"]
    var opcodes: [String: Int] = [:], unitCounts = Array(repeating: 0, count: after.count), lineCounts: [Int: Int] = [:]
    for (pc, instruction) in code.instructions.enumerated() {
        let count = main.counts[pc];
        opcodes[instruction.op, default: 0] += count;
        unitCounts[code.owners[pc]] += count;
        lineCounts[instruction.position.line, default: 0] += count
    }
    for (op, count) in opcodes.filter({
        $0.value > 0
    }).sorted(by: {
        $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
    }) {
        lines.append("  \(op) \(count)")
    }
    lines.append("functions:")
    for i in after.indices.dropFirst().sorted(by: {
        unitCounts[$0] == unitCounts[$1] ? after[$0].name < after[$1].name : unitCounts[$0] > unitCounts[$1]
    }) {
        lines.append("  \(after[i].name) calls=\(main.calls[i]) executed=\(unitCounts[i])")
    }
    lines.append("calls:")
    for (edge, count) in main.edges.sorted(by: {
        a, b in a.value == b.value ? (after[a.key.caller].name, after[a.key.callee].name) < (after[b.key.caller].name, after[b.key.callee].name) : a.value > b.value
    }) {
        lines.append("  \(after[edge.caller].name) -> \(after[edge.callee].name) \(count)")
    }
    lines.append("hot lines:")
    for (line, count) in lineCounts.filter({
        $0.value > 0
    }).sorted(by: {
        $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
    }).prefix(5) {
        lines.append("  line \(line): \(count)")
    }
    let missing = lineCounts.filter {
        $0.value == 0
    }.keys.sorted().map(String.init)
    lines += ["coverage: \(lineCounts.values.filter { $0 > 0 }.count) of \(lineCounts.count) lines", "not executed: \(missing.isEmpty ? "none" : missing.joined(separator: " "))", "hot spots:"]
    for pc in code.instructions.indices.filter({
        main.counts[$0] > 0
    }).sorted(by: {
        main.counts[$0] == main.counts[$1] ? $0 < $1 : main.counts[$0] > main.counts[$1]
    }).prefix(5) {
        lines.append("  pc=\(pc) count=\(main.counts[pc]) \(spelling(code.instructions[pc]))")
    };
    return lines
}
struct SourceProgram {
    let name: String;
    var lines: [(Int, String)]
}
func readPrograms() -> ([SourceProgram], [String]) {
    let lines = Array(try! String(contentsOfFile: "input/program.src", encoding: .ascii).components(separatedBy: "\n").dropLast());
    var result: [SourceProgram] = []
    for (i, line) in lines.enumerated() {
        if line.hasPrefix("#program ") {
            result.append(SourceProgram(name: String(line.dropFirst(9)), lines: []))
        } else {
            result[result.count - 1].lines.append((i + 1, line))
        }
    };
    return (result, lines)
}
func readInput() -> [String: [Int]] {
    var result: [String: [Int]] = [:], name = ""
    for line in try! String(contentsOfFile: "input/input.txt", encoding: .ascii).split(separator: "\n") {
        if line.hasPrefix("#input ") {
            name = String(line.dropFirst(7));
            result[name] = []
        } else {
            result[name, default: []] += line.split(separator: " ").map {
                Int($0)!
            }
        }
    };
    return result
}
func display(_ position: Position, _ sources: [String]) -> [String] {
    ["  " + sources[position.line - 1], String(repeating: " ", count: position.column + 1) + "^"]
}
func write(_ name: String, _ lines: [String]) {
    try! FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try! (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: true, encoding: .utf8)
}
let (programs, sourceLines) = readPrograms(), inputs = readInput()
var listing: [String] = [], output: [String] = [], diagnostics: [String] = [], stats: [String] = [], rows = [["program", "status", "code", "executed", "output"]]
var compiled = 0, compileErrors = ["lexical": 0, "syntax": 0, "semantic": 0], runtimeErrors = 0, foldTotal = 0, ruleTotals = Array(repeating: 0, count: 7), executedTotal = 0
for source in programs {
    let heading = "== program \(source.name) ==";
    listing.append(heading);
    output.append(heading);
    diagnostics.append(heading);
    stats.append(heading)
    let program: Program, semantic = Semantic()
    do {
        program = try Parser(Lexer.lex(source.lines)).program();
        try semantic.analyze(program)
    }
    catch let error as CompileError {
        listing.append("not compiled");
        stats.append("not compiled");
        diagnostics.append("\(error.kind) error \(error.position): \(error.message)");
        diagnostics += display(error.position, sourceLines);
        diagnostics.append("status: compile error")
        compileErrors[error.kind, default: 0] += 1;
        rows.append([source.name, error.kind + " error", "-", "-", "-"]);
        continue
    } catch {
        preconditionFailure()
    }
    compiled += 1
    let reachable = reachableFrom(semantic.globals["main"]!, semantic.calls);
    diagnostics += warningLines(program, semantic, reachable)
    let folder = Folder();
    folder.program(program, reachable);
    foldTotal += folder.count
    let (before, area) = Codegen(semantic).generate(program, reachable);
    var after = before, rules = Array(repeating: 0, count: 7)
    for i in after.indices {
        let (code, counts) = peephole(after[i].code);
        after[i].code = code;
        for k in rules.indices {
            rules[k] += counts[k]
        }
    }
    for k in rules.indices {
        ruleTotals[k] += rules[k]
    }
    let old = flatten(before), new = flatten(after), input = inputs[source.name] ?? []
    let main = VM.run(new.instructions, new.owners, new.starts, area, input), comparison = VM.run(old.instructions, old.owners, old.starts, area, input)
    executedTotal += main.executed;
    listing += listingLines(program, semantic, before, after, old, new);
    output += main.output
    if let pc = main.errorPC {
        runtimeErrors += 1;
        let instruction = new.instructions[pc]
        diagnostics.append("runtime error \(instruction.position): \(main.message!) in \(after[new.owners[pc]].name)");
        diagnostics += display(instruction.position, sourceLines)
        for caller in main.callers.prefix(5) {
            diagnostics.append("  called from \(after[new.owners[caller]].name) at \(new.instructions[caller].position)")
        }
        if main.callers.count > 5 {
            diagnostics.append("  ... \(main.callers.count - 5) more")
        }
    }
    let status = main.message == nil ? "ok" : "runtime error";
    diagnostics.append("status: " + status)
    stats += statsLines(old.instructions.count, after, new, main, comparison, folder.count, rules);
    rows.append([source.name, status, String(new.instructions.count), String(main.executed), String(main.output.count)])
}
stats += ["== summary ==", "programs: \(programs.count)", "compiled: \(compiled)", "compile errors: lexical \(compileErrors["lexical"]!) syntax \(compileErrors["syntax"]!) semantic \(compileErrors["semantic"]!)", "runtime errors: \(runtimeErrors)", "folds: \(foldTotal)", "peephole: \(ruleTotals.reduce(0, +))"]
for i in ruleNames.indices {
    stats.append("  \(ruleNames[i]) \(ruleTotals[i])")
};
stats.append("executed: \(executedTotal)")
let widths = (0..<5).map {
    k in rows.map {
        $0[k].count
    }.max()!
}
for row in rows {
    stats.append("  " + row.enumerated().map {
        pad($0.element, widths[$0.offset], $0.offset < 2)
    }.joined(separator: "  "))
}
write("listing.txt", listing);
write("output.txt", output);
write("diagnostics.txt", diagnostics);
write("stats.txt", stats)
