import Foundation
struct NameKey: Hashable {
    let scope: Int?, name: String
}
struct CallSite {
    let name: String, arguments: [Expr], scope: Int?, position: Position
}
struct StaticError: Error {
    let position: Position, message: String
}
final class Preparation {
    let program: Program
    var globals = Set(["FILENAME", "FNR", "FS", "NF", "NR", "OFS", "ORS", "SUBSEP"]), arrays: Set<NameKey> = [], uses: [(NameKey, Position)] = [], calls: [CallSite] = [], lines: [Int: Int] = [:], functions: [String: Int] = [:]
    init(_ program: Program) {
        self.program = program
    }
    func key(_ scope: Int?, _ name: String) -> NameKey {
        NameKey(scope: scope.flatMap {
            program.functions[$0].parameters.contains {
                $0.0 == name
            } ? $0 : nil
        }, name: name)
    }
    func name(_ scope: Int?, _ name: String, _ position: Position, _ array: Bool) {
        let key = self.key(scope, name);
        if key.scope == nil {
            globals.insert(name)
        };
        if array {
            arrays.insert(key)
        };
        uses.append((key, position))
    }
    func expression(_ expression: Expr, _ scope: Int?) {
        switch expression.kind {
            case .name(let name): self.name(scope, name, expression.position, false)
            case .index(let name, let indices): self.name(scope, name, expression.position, true);
            for index in indices {
                self.expression(index, scope)
            }
            case .field(let body), .parentheses(let body), .unary(_, let body), .increment(_, _, let body): self.expression(body, scope)
            case .binary(_, let a, let b), .assignment(_, let a, let b): self.expression(a, scope);
            self.expression(b, scope)
            case .conditional(let a, let b, let c): self.expression(a, scope);
            self.expression(b, scope);
            self.expression(c, scope)
            case .member(let indices, let name, let position): for index in indices {
                self.expression(index, scope)
            };
            self.name(scope, name, position, true)
            case .call(let name, let builtin, let arguments):
            if !builtin {
                calls.append(CallSite(name: name, arguments: arguments, scope: scope, position: expression.position))
            };
            for argument in arguments {
                self.expression(argument, scope)
            }
            if builtin && name == "split", case .name(let name) = arguments[1].kind {
                arrays.insert(key(scope, name))
            }
            case .getline(let target, let file): if let target {
                self.expression(target, scope)
            };
            if let file {
                self.expression(file, scope)
            }
            default: break
        }
    }
    func statement(_ statement: Stmt, _ scope: Int?) {
        switch statement.kind {
            case .block, .empty: break;
            default: lines[statement.position.line] = 0
        }
        switch statement.kind {
            case .block(let statements): for statement in statements {
                self.statement(statement, scope)
            }
            case .expression(let expression): self.expression(expression, scope)
            case .conditional(let condition, let yes, let no): expression(condition, scope);
            self.statement(yes, scope);
            if let no {
                self.statement(no, scope)
            }
            case .whileLoop(let condition, let body): expression(condition, scope);
            self.statement(body, scope)
            case .doLoop(let body, let condition): self.statement(body, scope);
            expression(condition, scope)
            case .forLoop(let initial, let condition, let update, let body): for expression in [initial, condition, update].compactMap({
                $0
            }) {
                self.expression(expression, scope)
            };
            self.statement(body, scope)
            case .forIn(let variable, let vp, let array, let ap, let body): name(scope, variable, vp, false);
            name(scope, array, ap, true);
            self.statement(body, scope)
            case .output(_, let arguments, let redirect): for argument in arguments {
                expression(argument, scope)
            };
            if let redirect {
                expression(redirect.expression, scope)
            }
            case .delete(let name, let position, let indices): self.name(scope, name, position, true);
            for index in indices ?? [] {
                expression(index, scope)
            }
            case .exit(let value), .returnValue(let value): if let value {
                expression(value, scope)
            }
            default: break
        }
    }
    func analyze() throws {
        var errors: [(Position, Int, String)] = []
        for (i, function) in program.functions.enumerated() {
            if functions[function.name] != nil {
                errors.append((function.position, 0, "function \(function.name) redefined"))
            } else {
                functions[function.name] = i
            }
            var parameters: Set<String> = []
            for (name, position) in function.parameters {
                if !parameters.insert(name).inserted {
                    errors.append((position, 1, "duplicate parameter \(name)"))
                };
                uses.append((NameKey(scope: i, name: name), position))
            };
            statement(function.body, i)
        }
        for rule in program.rules {
            if let start = rule.start {
                expression(start, nil)
            };
            if let end = rule.end {
                expression(end, nil)
            };
            if let action = rule.action {
                statement(action, nil)
            }
        }
        for (key, position) in uses where functions[key.name] != nil {
            errors.append((position, 2, "function \(key.name) used as variable"))
        }
        var links: [(NameKey, NameKey)] = []
        for call in calls {
            if let callee = functions[call.name] {
                let parameters = program.functions[callee].parameters
                if call.arguments.count > parameters.count {
                    errors.append((call.position, 4, "too many arguments to \(call.name)"))
                }
                for (argument, parameter) in zip(call.arguments, parameters) {
                    if case .name(let name) = argument.kind {
                        links.append((key(call.scope, name), NameKey(scope: callee, name: parameter.0)))
                    }
                }
            } else {
                errors.append((call.position, 3, "undefined function \(call.name)"))
            }
        }
        if let error = errors.min(by: {
            ($0.0, $0.1) < ($1.0, $1.1)
        }) {
            throw StaticError(position: error.0, message: error.2)
        }
        while true {
            var changed = false;
            for (a, b) in links where arrays.contains(a) || arrays.contains(b) {
                if arrays.insert(a).inserted {
                    changed = true
                };
                if arrays.insert(b).inserted {
                    changed = true
                }
            };
            if !changed {
                break
            }
        }
    }
}
final class AwkArray {
    var elements: [String: Value] = [:]
}
enum Cell {
    case scalar(Value), array(AwkArray)
}
enum Location {
    case variable(Int?, String), element(AwkArray, String), field(Int)
}
enum Flow: Error {
    case next, exit, returnValue(Value), breakLoop, continueLoop
}
struct MainInput {
    let file: Int, lines: [String];
    var position: Int
}
final class Runtime {
    let program: Program, preparation: Preparation, fields = Fields(), streams = Streams()
    var globals: [String: Cell] = [:], locals: [[String: Cell]] = [], arguments: Arguments, operand = 0, current: MainInput?, phase = "BEGIN", status = 0, rules: [Int], ranges: [Bool], calls: [Int], active: [Int], depths: [Int]
    init(_ program: Program, _ preparation: Preparation, _ arguments: Arguments) {
        self.program = program;
        self.preparation = preparation;
        self.arguments = arguments
        rules = Array(repeating: 0, count: program.rules.count);
        ranges = Array(repeating: false, count: program.rules.count);
        calls = Array(repeating: 0, count: program.functions.count);
        active = calls;
        depths = calls
        for name in preparation.globals {
            globals[name] = preparation.arrays.contains(NameKey(scope: nil, name: name)) ? .array(AwkArray()) : .scalar(.uninitialized)
        }
        for (name, value) in [("FS", Value.string(" ")), ("OFS", .string(" ")), ("ORS", .string("\n")), ("SUBSEP", .string("\u{1c}")), ("NR", .number(0)), ("FNR", .number(0)), ("FILENAME", .string(""))] {
            globals[name] = .scalar(value)
        }
    }
    func frame(_ name: String) -> Int? {
        locals.last?[name] != nil ? locals.count - 1 : nil
    }
    func cell(_ frame: Int?, _ name: String) -> Cell? {
        frame.map {
            locals[$0][name]
        } ?? globals[name]
    }
    func array(_ name: String) -> AwkArray {
        guard case .array(let array)? = cell(frame(name), name) else {
            preconditionFailure()
        };
        return array
    }
    func value(_ frame: Int?, _ name: String) -> Value {
        if frame == nil && name == "NF" {
            return .number(fields.values.count)
        };
        if case .scalar(let value)? = cell(frame, name) {
            return value
        };
        return .uninitialized
    }
    func global(_ name: String) -> Value {
        value(nil, name)
    }
    func key(_ expressions: [Expr]) throws -> String {
        var keys: [String] = [];
        for expression in expressions {
            keys.append(try self.expression(expression).text)
        };
        return keys.joined(separator: global("SUBSEP").text)
    }
    func location(_ expression: Expr) throws -> Location {
        switch expression.kind {
            case .name(let name): return .variable(frame(name), name)
            case .index(let name, let indices): let key = try self.key(indices);
            return .element(array(name), key)
            case .field(let index): let number = try self.expression(index).number;
            if number < 0 {
                throw RuntimeError(position: expression.position, message: "negative field index")
            };
            return .field(number)
            default: preconditionFailure()
        }
    }
    func read(_ location: Location) -> Value {
        switch location {
            case .variable(let frame, let name): return value(frame, name);
            case .element(let array, let key): if array.elements[key] == nil {
                array.elements[key] = .uninitialized
            };
            return array.elements[key]!;
            case .field(let index): return fields.get(index)
        }
    }
    @discardableResult func store(_ location: Location, _ value: Value, _ position: Position) throws -> Value {
        switch location {
            case .variable(let frame, let name):
            if frame == nil && name == "NF" {
                let n = value.number;
                if n < 0 {
                    throw RuntimeError(position: position, message: "negative NF")
                };
                fields.nf(n, global("OFS").text)
            }
            else if let frame {
                locals[frame][name] = .scalar(value)
            } else {
                preparation.globals.insert(name);
                globals[name] = .scalar(value)
            }
            case .element(let array, let key): array.elements[key] = value
            case .field(let index): fields.assign(index, value, global("FS").text, global("OFS").text)
        };
        return read(location)
    }
    func arithmetic(_ op: String, _ a: Int, _ b: Int, _ position: Position) throws -> Value {
        if ["/", "%"].contains(op) && b == 0 {
            throw RuntimeError(position: position, message: "division by zero")
        }
        if op == "^" && b < 0 {
            throw RuntimeError(position: position, message: "negative exponent")
        }
        let value: Int
        switch op {
            case "+": value = a + b;
            case "-": value = a - b;
            case "*": value = a * b;
            case "/": value = a / b;
            case "%": value = a % b
            default: var result = 1, base = a, exponent = b;
            while exponent > 0 {
                if exponent % 2 == 1 {
                    result *= base
                };
                exponent /= 2;
                if exponent > 0 {
                    base *= base
                }
            };
            value = result
        };
        return .number(value)
    }
    func expression(_ expression: Expr) throws -> Value {
        let position = expression.position
        switch expression.kind {
            case .number(let n): return .number(n)
            case .string(let s): return .string(s)
            case .name, .index, .field: return read(try location(expression))
            case .parentheses(let body): return try self.expression(body)
            case .unary(let op, let body): let value = try self.expression(body);
            return .number(op == "-" ? -value.number : op == "+" ? value.number : value.truth ? 0 : 1)
            case .binary(let op, let left, let right):
            let a = try self.expression(left);
            if op == "||" && a.truth {
                return .number(1)
            };
            if op == "&&" && !a.truth {
                return .number(0)
            };
            let b = try self.expression(right)
            if op == "||" || op == "&&" {
                return .number(b.truth ? 1 : 0)
            };
            if op == "concat" {
                return .string(a.text + b.text)
            }
            if ["<", "<=", "==", "!=", ">=", ">"].contains(op) {
                let order = a.compare(b), result: Bool;
                switch op {
                    case "<": result = order < 0;
                    case "<=": result = order <= 0;
                    case "==": result = order == 0;
                    case "!=": result = order != 0;
                    case ">=": result = order >= 0;
                    default: result = order > 0
                };
                return .number(result ? 1 : 0)
            }
            return try arithmetic(op, a.number, b.number, position)
            case .assignment(let op, let target, let right):
            let location = try self.location(target), b = try self.expression(right), value: Value
            if op == "=" {
                value = b
            } else {
                let a = read(location);
                value = try arithmetic(String(op.prefix(1)), a.number, b.number, position)
            };
            return try store(location, value, position)
            case .increment(let delta, let prefix, let target): let location = try self.location(target), value = read(location).number;
            try store(location, .number(value + delta), position);
            return .number(prefix ? value + delta : value)
            case .conditional(let condition, let yes, let no): let value = try self.expression(condition);
            return try self.expression(value.truth ? yes : no)
            case .member(let indices, let name, _): let key = try self.key(indices);
            return .number(array(name).elements[key] != nil ? 1 : 0)
            case .call(let name, let builtin, let arguments): return builtin ? try self.builtin(name, arguments, position) : try call(name, arguments)
            case .getline(let target, let file):
            let status: Int, line: String?
            if let file {
                let name = try self.expression(file).text;
                (status, line) = streams.getline(name)
            }
            else if phase == "END" {
                status = 0;
                line = nil
            }
            else {
                line = nextRecord();
                status = line == nil ? 0 : 1
            }
            if let line {
                if let target {
                    let location = try self.location(target);
                    try store(location, .input(line), position)
                } else {
                    fields.set(line, global("FS").text)
                }
            };
            return .number(status)
        }
    }
    func builtin(_ name: String, _ arguments: [Expr], _ position: Position) throws -> Value {
        if name == "length" {
            if arguments.isEmpty {
                return .number(fields.record.text.count)
            }
            if case .name(let name) = arguments[0].kind, case .array(let array)? = cell(frame(name), name) {
                return .number(array.elements.count)
            };
            return .number(try expression(arguments[0]).text.count)
        }
        if name == "split" {
            let text = try expression(arguments[0]).text, separator = arguments.count == 3 ? try expression(arguments[2]).text : global("FS").text
            guard case .name(let name) = arguments[1].kind else {
                preconditionFailure()
            };
            let array = self.array(name), pieces = splitText(text, separator);
            array.elements = [:];
            for (i, piece) in pieces.enumerated() {
                array.elements[String(i + 1)] = .input(piece)
            };
            return .number(pieces.count)
        }
        var values: [Value] = [];
        for argument in arguments {
            values.append(try expression(argument))
        }
        if name == "close" {
            return .number(streams.close(values[0].text))
        };
        return try Builtins.scalar(name, values, position)
    }
    func call(_ name: String, _ arguments: [Expr]) throws -> Value {
        let index = preparation.functions[name]!, function = program.functions[index];
        var local: [String: Cell] = [:]
        for (i, parameter) in function.parameters.enumerated() {
            if preparation.arrays.contains(NameKey(scope: index, name: parameter.0)) {
                if i < arguments.count {
                    guard case .name(let name) = arguments[i].kind else {
                        preconditionFailure()
                    };
                    local[parameter.0] = .array(array(name))
                } else {
                    local[parameter.0] = .array(AwkArray())
                }
            } else {
                local[parameter.0] = .scalar(i < arguments.count ? try expression(arguments[i]) : .uninitialized)
            }
        }
        calls[index] += 1;
        active[index] += 1;
        depths[index] = max(depths[index], active[index]);
        locals.append(local)
        defer {
            locals.removeLast();
            active[index] -= 1
        }
        do {
            try statement(function.body);
            return .uninitialized
        } catch Flow.returnValue(let value) {
            return value
        }
    }
    func output(_ printf: Bool, _ arguments: [Expr], _ redirect: Redirect?, _ position: Position) throws {
        var values: [Value] = [];
        for argument in arguments {
            values.append(try expression(argument))
        }
        let text: String
        if printf {
            text = try Builtins.format(values, position)
        }
        else {
            if values.isEmpty {
                values = [fields.record]
            };
            text = values.map(\.text).joined(separator: global("OFS").text) + global("ORS").text
        }
        if let redirect {
            let name = try expression(redirect.expression).text
            if !validFile(name) || ["stdout.txt", "stats.txt"].contains(name) {
                throw RuntimeError(position: redirect.position, message: "invalid output file name")
            };
            streams.output(name, redirect.append, text)
        } else {
            streams.output(nil, false, text)
        }
    }
    func loopBody(_ body: Stmt) throws -> Bool {
        do {
            try statement(body);
            return true
        } catch Flow.continueLoop {
            return true
        } catch Flow.breakLoop {
            return false
        }
    }
    func statement(_ statement: Stmt) throws {
        let position = statement.position
        switch statement.kind {
            case .block, .empty: break;
            default: preparation.lines[position.line, default: 0] += 1
        }
        switch statement.kind {
            case .block(let statements): for statement in statements {
                try self.statement(statement)
            }
            case .empty: break
            case .expression(let expression): _ = try self.expression(expression)
            case .conditional(let condition, let yes, let no): if try expression(condition).truth {
                try self.statement(yes)
            } else if let no {
                try self.statement(no)
            }
            case .whileLoop(let condition, let body): while try expression(condition).truth {
                if try !loopBody(body) {
                    break
                }
            }
            case .doLoop(let body, let condition): while true {
                if try !loopBody(body) {
                    break
                };
                if try !expression(condition).truth {
                    break
                }
            }
            case .forLoop(let initial, let condition, let update, let body):
            if let initial {
                _ = try expression(initial)
            }
            while true {
                if let condition, try !expression(condition).truth {
                    break
                };
                if try !loopBody(body) {
                    break
                };
                if let update {
                    _ = try expression(update)
                }
            }
            case .forIn(let variable, let vp, let array, _, let body):
            let keys = self.array(array).elements.keys.sorted(by: keyLess)
            for key in keys {
                try store(.variable(frame(variable), variable), .input(key), vp);
                if try !loopBody(body) {
                    break
                }
            }
            case .output(let printf, let arguments, let redirect): try output(printf, arguments, redirect, position)
            case .delete(let name, _, let indices): let key = try indices.map(self.key), array = self.array(name);
            if let key {
                array.elements.removeValue(forKey: key)
            } else {
                array.elements = [:]
            }
            case .next: if phase == "BEGIN" || phase == "END" {
                throw RuntimeError(position: position, message: "next used in BEGIN or END")
            };
            throw Flow.next
            case .breakLoop: throw Flow.breakLoop
            case .continueLoop: throw Flow.continueLoop
            case .exit(let value): if let value {
                status = try expression(value).number
            };
            throw Flow.exit
            case .returnValue(let value): throw Flow.returnValue(try value.map(expression) ?? .uninitialized)
        }
    }
    func nextRecord() -> String? {
        while true {
            if var input = current, input.position < input.lines.count {
                let line = input.lines[input.position];
                input.position += 1;
                current = input;
                arguments.files[input.file].1 += 1
                let nr = global("NR").number + 1, fnr = global("FNR").number + 1;
                globals["NR"] = .scalar(.number(nr));
                globals["FNR"] = .scalar(.number(fnr));
                return line
            }
            if operand == arguments.operands.count {
                return nil
            };
            let next = arguments.operands[operand];
            operand += 1
            switch next {
                case .assignment(let name, let value): preparation.globals.insert(name);
                globals[name] = .scalar(.input(value))
                case .file(let name, let index): globals["FILENAME"] = .scalar(.string(name));
                globals["FNR"] = .scalar(.number(0));
                current = MainInput(file: index, lines: readFile(name)!, position: 0)
            }
        }
    }
    func testRule(_ rule: Rule, _ index: Int) throws -> Bool {
        if rule.kind == "all" {
            return true
        }
        if rule.kind == "range" {
            if !ranges[index] {
                if try expression(rule.start!).truth {
                    ranges[index] = true
                }
            }
            let matched = ranges[index];
            if matched {
                if try expression(rule.end!).truth {
                    ranges[index] = false
                }
            };
            return matched
        };
        return try expression(rule.start!).truth
    }
    func execute() throws {
        for (name, value) in arguments.options {
            preparation.globals.insert(name);
            globals[name] = .scalar(.input(value))
        }
        var exiting = false
        for (i, rule) in program.rules.enumerated() where rule.kind == "BEGIN" {
            rules[i] += 1
            do {
                try statement(rule.action!)
            } catch Flow.exit {
                exiting = true;
                break
            }
        }
        phase = "rules"
        if !exiting && program.rules.contains(where: {
            $0.kind != "BEGIN"
        }) {
            records: while let record = nextRecord() {
                fields.set(record, global("FS").text)
                for (i, rule) in program.rules.enumerated() where !["BEGIN", "END"].contains(rule.kind) {
                    do {
                        if try testRule(rule, i) {
                            rules[i] += 1
                            if let action = rule.action {
                                try statement(action)
                            } else {
                                streams.output(nil, false, fields.record.text + global("ORS").text)
                            }
                        }
                    } catch Flow.next {
                        continue records
                    } catch Flow.exit {
                        break records
                    }
                }
            }
        }
        phase = "END"
        for (i, rule) in program.rules.enumerated() where rule.kind == "END" {
            rules[i] += 1;
            do {
                try statement(rule.action!)
            } catch Flow.exit {
                break
            }
        }
    }
    func report(_ status: String) {
        streams.save();
        var lines = [status, "[inputs]"]
        for (name, count) in arguments.files {
            lines.append("\(name) records=\(count)")
        };
        lines.append("[getline]")
        for input in streams.inputs {
            lines.append(input.opened ? "\(input.name) reads=\(input.reads)" : "\(input.name) missing")
        };
        lines.append("[rules]")
        for (i, rule) in program.rules.enumerated() {
            lines.append("\(rule.position) \(rule.kind) count=\(rules[i])")
        };
        lines.append("[functions]")
        for (i, function) in program.functions.enumerated() {
            lines.append("\(function.name) calls=\(calls[i]) depth=\(depths[i])")
        };
        lines += ["[outputs]", "stdout.txt writes=\(streams.writes) bytes=\(streams.stdout.utf8.count)"]
        for output in streams.outputs {
            lines.append("\(output.name) writes=\(output.writes) bytes=\(output.text.utf8.count)")
        };
        lines.append("[lines]")
        for line in preparation.lines.keys.sorted() {
            lines.append("\(line) count=\(preparation.lines[line]!)")
        };
        lines.append("[globals]")
        for name in preparation.globals.sorted() {
            let value: String;
            if case .array(let array)? = globals[name] {
                value = "array (\(array.elements.count))"
            } else {
                value = global(name).display
            };
            lines.append("\(name) = \(value)")
        };
        saveStats(lines)
    }
}
func saveStats(_ lines: [String]) {
    try! FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try! (lines.joined(separator: "\n") + "\n").write(toFile: "output/stats.txt", atomically: true, encoding: .utf8)
}
func failure(_ status: String) {
    try! FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try! "".write(toFile: "output/stdout.txt", atomically: true, encoding: .utf8);
    saveStats([status])
}
func run() {
    let source = try! String(contentsOfFile: "input/program.awk", encoding: .ascii), program: Program
    do {
        program = try Parser(Lexer.lex(source)).program()
    } catch let position as Position {
        failure("status: syntax error at \(position)");
        return
    } catch {
        preconditionFailure()
    }
    let preparation = Preparation(program)
    do {
        try preparation.analyze()
    } catch let error as StaticError {
        failure("status: error at \(error.position): \(error.message)");
        return
    } catch {
        preconditionFailure()
    }
    let args = arguments(try! String(contentsOfFile: "input/args.txt", encoding: .ascii)), runtime = Runtime(program, preparation, args), status: String
    do {
        try runtime.execute();
        status = "status: exit \(runtime.status)"
    } catch let error as RuntimeError {
        status = "status: runtime error at \(error.position): \(error.message)"
    } catch {
        status = "status: exit \(runtime.status)"
    }
    runtime.report(status)
}
run()
