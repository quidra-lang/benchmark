import Foundation
func quote(_ value: String) -> String {
    var out = "\""
    for c in value {
        switch c {
            case "\\": out += "\\\\";
            case "\"": out += "\\\"";
            case "\n": out += "\\n";
            case "\t": out += "\\t";
            default: out.append(c)
        }
    };
    return out + "\""
}
func valueString(_ value: Value) -> String {
    switch value {
        case .integer(let v): return String(v);
        case .boolean(let v): return String(v);
        case .string(let v): return quote(v);
        case .pair(let a, let b): return "(\(valueString(a)), \(valueString(b)))";
        case .list(let values): return "[" + values.map(valueString).joined(separator: "; ") + "]";
        default: return "<fun>"
    }
}
func editDistance(_ a: String, _ b: String) -> Int {
    let aa = Array(a.utf8), bb = Array(b.utf8);
    var row = Array(0...bb.count)
    for (i, a) in aa.enumerated() {
        var next = [i + 1];
        for (j, b) in bb.enumerated() {
            next.append(min(next[j] + 1, row[j + 1] + 1, row[j] + (a == b ? 0 : 1)))
        };
        row = next
    };
    return row[bb.count]
}
final class TypePrinter {
    let unifier: Unifier, quantified: Set<Int>?;
    var names: [Int: String] = [:]
    init(_ unifier: Unifier, _ quantified: Set<Int>? = nil) {
        self.unifier = unifier;
        self.quantified = quantified
    }
    func write(_ type: MLType) -> String {
        switch unifier.resolve(type) {
            case .integer: return "int"
            case .boolean: return "bool"
            case .string: return "string"
            case .variable(let i):
            if let name = names[i] {
                return name
            };
            let k = names.count, weak = quantified.map {
                !$0.contains(i)
            } ?? false
            let name = "'" + (weak ? "_" : "") + String(UnicodeScalar(97 + k % 26)!) + (k >= 26 ? String(k / 26) : "");
            names[i] = name;
            return name
            case .list(let element): return wrap(element, pair: true) + " list"
            case .pair(let a, let b): return wrap(a, pair: true) + " * " + wrap(b, pair: true)
            case .function(let a, let b): return wrap(a, pair: false) + " -> " + write(b)
        }
    }
    func wrap(_ type: MLType, pair: Bool) -> String {
        let resolved = unifier.resolve(type), text = write(resolved)
        switch resolved {
            case .function: return "(" + text + ")";
            case .pair where pair: return "(" + text + ")";
            default: return text
        }
    }
}
func errorMessage(_ error: TypeError, _ unifier: Unifier) -> String {
    let printer = TypePrinter(unifier)
    switch error.kind {
        case .message(let message): return message
        case .function(let type): return "expected a function but found \(printer.write(type))"
        case .check(let expected, let found, let failure):
        var message = "expected \(printer.write(expected)) but found \(printer.write(found))"
        if failure.occurs {
            let variable: MLType, other: MLType;
            if case .variable = failure.expected {
                variable = failure.expected;
                other = failure.found
            } else {
                variable = failure.found;
                other = failure.expected
            };
            message += " (infinite type \(printer.write(variable)) = \(printer.write(other)))"
        }
        else if failure.nested {
            message += " (\(printer.write(failure.expected)) vs \(printer.write(failure.found)))"
        };
        return message
    }
}
func signatureType(_ expression: TypeExpression, _ unifier: Unifier, _ variables: inout [String: MLType]) -> MLType {
    switch expression {
        case .primitive(let name): return name == "int" ? .integer : name == "bool" ? .boolean : .string
        case .variable(let name): if let type = variables[name] {
            return type
        };
        let type = unifier.fresh();
        variables[name] = type;
        return type
        case .list(let type): return .list(signatureType(type, unifier, &variables))
        case .pair(let a, let b): let first = signatureType(a, unifier, &variables), second = signatureType(b, unifier, &variables);
        return .pair(first, second)
        case .function(let a, let b): let first = signatureType(a, unifier, &variables), second = signatureType(b, unifier, &variables);
        return .function(first, second)
    }
}
func signatureMatches(_ inferred: MLType, _ declared: MLType, _ unifier: Unifier, _ assigned: inout [Int: MLType]) -> Bool {
    let a = unifier.resolve(inferred), b = unifier.resolve(declared)
    switch (a, b) {
        case (.variable(let i), _): if let old = assigned[i] {
            return old == b
        };
        assigned[i] = b;
        return true
        case (.list(let a), .list(let b)): return signatureMatches(a, b, unifier, &assigned)
        case (.pair(let a, let b), .pair(let c, let d)), (.function(let a, let b), .function(let c, let d)): return signatureMatches(a, c, unifier, &assigned) && signatureMatches(b, d, unifier, &assigned)
        default: return a == b
    }
}
func typeSyntax(_ type: TypeExpression) -> String {
    func wrap(_ t: TypeExpression, _ pair: Bool) -> String {
        let text = typeSyntax(t);
        switch t {
            case .function: return "(" + text + ")";
            case .pair where pair: return "(" + text + ")";
            default: return text
        }
    }
    switch type {
        case .primitive(let name), .variable(let name): return name;
        case .list(let t): return wrap(t, true) + " list";
        case .pair(let a, let b): return wrap(a, true) + " * " + wrap(b, true);
        case .function(let a, let b): return wrap(a, false) + " -> " + typeSyntax(b)
    }
}
func patternString(_ pattern: Pattern) -> String {
    switch pattern.kind {
        case .wildcard: return "_"
        case .name(let name): return name
        case .integer(let value): return String(value)
        case .boolean(let value): return String(value)
        case .string(let value): return quote(value)
        case .nilList: return "[]"
        case .list(let values): return "[" + values.map(patternString).joined(separator: "; ") + "]"
        case .pair(let a, let b): return "(\(patternString(a)), \(patternString(b)))"
        case .cons(let a, let b): let head = patternString(a);
        if case .cons = a.kind {
            return "(\(head)) :: \(patternString(b))"
        };
        return "\(head) :: \(patternString(b))"
    }
}
func groupString(_ group: Group) -> String {
    let bindings = group.bindings.map {
        binding -> String in
        var body = binding.expression, names = [binding.name]
        while case .fun(let parameter, let next) = body.kind {
            names.append(parameter.name ?? "_");
            body = next
        };
        return names.joined(separator: " ") + " = " + expressionString(body, 0)
    };
    return "let " + (group.recursive != nil ? "rec " : "") + bindings.joined(separator: " and ")
}
func endsInMatch(_ expression: Expr) -> Bool {
    switch expression.kind {
        case .match: return true;
        case .letIn(_, let body), .fun(_, let body): return endsInMatch(body);
        case .conditional(_, _, let no): return endsInMatch(no);
        default: return false
    }
}
func expressionString(_ expression: Expr, _ required: Int) -> String {
    let strength: Int, text: String
    switch expression.kind {
        case .integer(let v): strength = 9;
        text = String(v)
        case .boolean(let v): strength = 9;
        text = String(v)
        case .string(let v): strength = 9;
        text = quote(v)
        case .name(let name): strength = 9;
        text = name
        case .fun:
        var body = expression, parameters: [String] = []
        while case .fun(let parameter, let next) = body.kind {
            parameters.append(parameter.name ?? "_");
            body = next
        };
        strength = 0;
        text = "fun " + parameters.joined(separator: " ") + " -> " + expressionString(body, 0)
        case .apply(let f, let a): strength = 8;
        text = expressionString(f, 8) + " " + expressionString(a, 9)
        case .binary(let op, _, let a, let b): let k = precedence(op), right = rightAssociative(op);
        strength = k;
        text = expressionString(a, k + (right ? 1 : 0)) + " " + op + " " + expressionString(b, k + (right ? 0 : 1))
        case .negate(_, let v): strength = 7;
        text = "-" + expressionString(v, 7)
        case .conditional(let c, let a, let b): strength = 0;
        text = "if \(expressionString(c, 0)) then \(expressionString(a, 0)) else \(expressionString(b, 0))"
        case .pair(let a, let b): strength = 9;
        text = "(\(expressionString(a, 0)), \(expressionString(b, 0)))"
        case .list(let values): strength = 9;
        text = "[" + values.map {
            expressionString($0, 0)
        }.joined(separator: "; ") + "]"
        case .letIn(let group, let body): strength = 0;
        text = groupString(group) + " in " + expressionString(body, 0)
        case .match(let value, let arms):
        let written = arms.enumerated().map {
            i, arm -> String in let body = expressionString(arm.1, 0);
            return patternString(arm.0) + " -> " + (i + 1 < arms.count && endsInMatch(arm.1) ? "(" + body + ")" : body)
        }
        strength = 0;
        text = "match " + expressionString(value, 0) + " with " + written.joined(separator: " | ")
    };
    return strength < required ? "(" + text + ")" : text
}
func itemString(_ item: Item) -> String {
    switch item {
        case .signature(let name, _, let type): return "val \(name) : \(typeSyntax(type));;";
        case .declaration(let group): return groupString(group) + ";;";
        case .expression(let expression): return expressionString(expression, 0) + ";;"
    }
}
indirect enum Cover {
    case wild, constructor(String, [Cover])
}
func cover(_ pattern: Pattern) -> Cover {
    func list(_ values: ArraySlice<Pattern>) -> Cover {
        guard let first = values.first else {
            return .constructor("nil", [])
        };
        return .constructor("cons", [cover(first), list(values.dropFirst())])
    }
    switch pattern.kind {
        case .wildcard, .name: return .wild
        case .integer(let value): return .constructor("i\(value)", [])
        case .string(let value): return .constructor("s" + quote(value), [])
        case .boolean(let value): return .constructor(String(value), [])
        case .nilList: return .constructor("nil", [])
        case .cons(let a, let b): return .constructor("cons", [cover(a), cover(b)])
        case .pair(let a, let b): return .constructor("pair", [cover(a), cover(b)])
        case .list(let values): return list(values[...])
    }
}
func constructorArguments(_ type: MLType, _ name: String) -> [MLType] {
    switch type {
        case .list(let element) where name == "cons": return [element, type];
        case .pair(let a, let b): return [a, b];
        default: return []
    }
}
func specialize(_ matrix: [[Cover]], _ name: String, _ arity: Int) -> [[Cover]] {
    var result: [[Cover]] = []
    for row in matrix {
        let prefix: [Cover]
        switch row[0] {
            case .wild: prefix = Array(repeating: .wild, count: arity);
            case .constructor(let constructor, let arguments) where constructor == name: prefix = arguments;
            default: continue
        }
        result.append(prefix + row.dropFirst())
    };
    return result
}
func useful(_ matrix: [[Cover]], _ vector: [Cover], _ types: [MLType]) -> Bool {
    if vector.isEmpty {
        return matrix.isEmpty
    }
    if case .constructor(let name, let arguments) = vector[0] {
        return useful(specialize(matrix, name, arguments.count), arguments + vector.dropFirst(), constructorArguments(types[0], name) + types.dropFirst())
    }
    let family: [String]
    switch types[0] {
        case .boolean: family = ["false", "true"];
        case .list: family = ["nil", "cons"];
        case .pair: family = ["pair"];
        default: family = []
    }
    let present = Set(matrix.compactMap {
        row -> String? in if case .constructor(let name, _) = row[0] {
            return name
        };
        return nil
    })
    if !family.isEmpty && family.allSatisfy(present.contains) {
        for name in family {
            let arguments = constructorArguments(types[0], name);
            if useful(specialize(matrix, name, arguments.count), Array(repeating: .wild, count: arguments.count) + vector.dropFirst(), arguments + types.dropFirst()) {
                return true
            }
        };
        return false
    }
    let defaults = matrix.compactMap {
        row -> [Cover]? in if case .wild = row[0] {
            return Array(row.dropFirst())
        };
        return nil
    }
    return useful(defaults, Array(vector.dropFirst()), Array(types.dropFirst()))
}
typealias Scope = [String: Position]
struct Reference {
    let target: Position, tail: Bool
}
func patternNames(_ pattern: Pattern) -> [(String, Position)] {
    switch pattern.kind {
        case .name(let name): return [(name, pattern.position)];
        case .cons(let a, let b), .pair(let a, let b): return patternNames(a) + patternNames(b);
        case .list(let values): return values.flatMap(patternNames);
        default: return []
    }
}
func pureReferences(_ expression: Expr, _ scope: Scope, _ tail: Bool) -> [Reference] {
    switch expression.kind {
        case .name(let name): return scope[name].map {
            [Reference(target: $0, tail: false)]
        } ?? []
        case .fun(let parameter, let body): var inner = scope;
        if let name = parameter.name {
            inner[name] = parameter.position
        };
        return pureReferences(body, inner, false)
        case .apply:
        var head = expression, arguments: [Expr] = []
        while case .apply(let function, let argument) = head.kind {
            arguments.append(argument);
            head = function
        };
        arguments.reverse()
        var references: [Reference]
        if case .name(let name) = head.kind {
            references = scope[name].map {
                [Reference(target: $0, tail: tail)]
            } ?? []
        } else {
            references = pureReferences(head, scope, false)
        }
        for argument in arguments {
            references += pureReferences(argument, scope, false)
        };
        return references
        case .binary(let op, _, let a, let b): return pureReferences(a, scope, false) + pureReferences(b, scope, tail && ["&&", "||"].contains(op))
        case .negate(_, let body): return pureReferences(body, scope, false)
        case .conditional(let c, let a, let b): return pureReferences(c, scope, false) + pureReferences(a, scope, tail) + pureReferences(b, scope, tail)
        case .pair(let a, let b): return pureReferences(a, scope, false) + pureReferences(b, scope, false)
        case .list(let values): return values.flatMap {
            pureReferences($0, scope, false)
        }
        case .match(let value, let arms):
        var references = pureReferences(value, scope, false)
        for (pattern, body) in arms {
            var inner = scope;
            for (name, position) in patternNames(pattern) {
                inner[name] = position
            };
            references += pureReferences(body, inner, tail)
        };
        return references
        case .letIn(let group, let body):
        var inner = scope;
        for binding in group.bindings {
            inner[binding.name] = binding.position
        }
        return group.bindings.flatMap {
            pureReferences($0.expression, group.recursive != nil ? inner : scope, false)
        } + pureReferences(body, inner, tail)
        default: return []
    }
}
final class Inspection {
    var warnings: [(Position, Int, String)] = [], classifications: [Position: String] = [:], candidates: [Position: String] = [:]
    func group(_ group: Group, _ scope: Scope, _ top: Bool, _ context: Inference) -> Scope {
        var inner = scope
        for binding in group.bindings {
            inner[binding.name] = binding.position;
            if !top {
                candidates[binding.position] = binding.name
            }
        }
        let rhs = group.recursive != nil ? inner : scope
        for binding in group.bindings {
            walk(binding.expression, rhs, context)
        }
        if let position = group.recursive {
            let names = Set(group.bindings.map(\.position)), references = group.bindings.flatMap {
                pureReferences($0.expression, inner, false)
            }
            if references.allSatisfy({
                !names.contains($0.target)
            }) {
                warnings.append((position, 3, "unused rec flag"))
            }
            for binding in group.bindings {
                var body = binding.expression, bodyScope = inner
                while case .fun(let parameter, let next) = body.kind {
                    if let name = parameter.name {
                        bodyScope[name] = parameter.position
                    };
                    body = next
                }
                let references = pureReferences(body, bodyScope, true).filter {
                    names.contains($0.target)
                }
                if !references.isEmpty {
                    classifications[binding.position] = references.allSatisfy(\.tail) ? "tail recursive" : "recursive"
                }
            }
        };
        return inner
    }
    func walk(_ expression: Expr, _ scope: Scope, _ context: Inference) {
        switch expression.kind {
            case .fun(let parameter, let body): var inner = scope;
            if let name = parameter.name {
                candidates[parameter.position] = name;
                inner[name] = parameter.position
            };
            walk(body, inner, context)
            case .apply(let a, let b), .pair(let a, let b), .binary(_, _, let a, let b): walk(a, scope, context);
            walk(b, scope, context)
            case .negate(_, let body): walk(body, scope, context)
            case .conditional(let c, let a, let b): walk(c, scope, context);
            walk(a, scope, context);
            walk(b, scope, context)
            case .list(let values): for value in values {
                walk(value, scope, context)
            }
            case .letIn(let group, let body): let inner = self.group(group, scope, false, context);
            walk(body, inner, context)
            case .match(let value, let arms):
            let (originalType, patterns) = context.matches[expression.position]!, type = context.unifier.resolve(originalType)
            var matrix: [[Cover]] = []
            for (i, pattern) in patterns.enumerated() {
                let candidate = cover(pattern);
                if i > 0 && !useful(matrix, [candidate], [type]) {
                    warnings.append((pattern.position, 2, "this match case is unused"))
                };
                matrix.append([candidate])
            }
            if useful(matrix, [.wild], [type]) {
                warnings.append((expression.position, 1, "this match is not exhaustive"))
            }
            walk(value, scope, context)
            for (pattern, body) in arms {
                var inner = scope;
                for (name, position) in patternNames(pattern) {
                    candidates[position] = name;
                    inner[name] = position
                };
                walk(body, inner, context)
            }
            default: break
        }
    }
    func finish(_ references: [Reference]) {
        let used = Set(references.map(\.target))
        for (position, name) in candidates where !name.hasPrefix("_") && !used.contains(position) {
            warnings.append((position, 4, "unused variable '\(name)'"))
        }
        warnings.sort {
            ($0.0, $0.1) < ($1.0, $1.1)
        }
    }
}
func inspect(_ item: Item, _ scope: Scope, _ context: Inference) -> Inspection {
    let inspection = Inspection(), references: [Reference]
    switch item {
        case .declaration(let group): let inner = inspection.group(group, scope, true, context);
        references = group.bindings.flatMap {
            pureReferences($0.expression, group.recursive != nil ? inner : scope, false)
        }
        case .expression(let expression): inspection.walk(expression, scope, context);
        references = pureReferences(expression, scope, false)
        default: references = []
    };
    inspection.finish(references);
    return inspection
}
func builtins(_ unifier: Unifier) -> (TypeEnvironment, ValueEnvironment) {
    var types: TypeEnvironment = [:]
    let a = unifier.fresh(), b = unifier.fresh(), fst = MLType.function(.pair(a, b), a)
    types["fst"] = Scheme(type: fst, quantified: unifier.variables(fst))
    let c = unifier.fresh(), d = unifier.fresh(), snd = MLType.function(.pair(c, d), d)
    types["snd"] = Scheme(type: snd, quantified: unifier.variables(snd));
    types["not"] = .mono(.function(.boolean, .boolean));
    types["string_of_int"] = .mono(.function(.integer, .string))
    let result = unifier.fresh(), fail = MLType.function(.string, result);
    types["failwith"] = Scheme(type: fail, quantified: unifier.variables(fail))
    return (types, Dictionary(uniqueKeysWithValues: ["fst", "snd", "not", "string_of_int", "failwith"].map {
        ($0, Value.builtin($0))
    }))
}
func applyBuiltin(_ name: String, _ argument: Value, _ position: Position) throws -> Value {
    switch (name, argument) {
        case ("fst", .pair(let a, _)): return a
        case ("snd", .pair(_, let b)): return b
        case ("not", .boolean(let value)): return .boolean(!value)
        case ("string_of_int", .integer(let value)): return .string(String(value))
        case ("failwith", .string(let value)): throw RuntimeError(position: position, message: "failure " + quote(value))
        default: preconditionFailure()
    }
}
struct Signature {
    let position: Position, type: TypeExpression
}
struct Diagnostic: Error {
    let position: Position, message: String
}
func report(_ position: Position, _ kind: String, _ message: String, _ sources: [[String]], _ output: inout [String]) {
    let name = ["prelude.ml", "program.ml"][position.file];
    output.append("\(name):\(position.line):\(position.column): \(kind): \(message)")
    if position.line <= sources[position.file].count {
        output.append("    " + sources[position.file][position.line - 1]);
        output.append(String(repeating: " ", count: position.column + 3) + "^")
    }
}
func write(_ name: String, _ lines: [String]) {
    try! FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try! (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: true, encoding: .utf8)
}
let fileNames = ["prelude.ml", "program.ml"], texts = fileNames.map {
    try! String(contentsOfFile: "input/" + $0, encoding: .ascii)
}
let sources = texts.map {
    Array($0.components(separatedBy: "\n").dropLast())
}, context = Inference(), evaluator = Evaluator()
var (typeEnvironment, valueEnvironment) = builtins(context.unifier)
var scope: Scope = [:], types: [String] = [], values: [String] = [], errors: [String] = [], formatted: [String] = [], statistics = Array(repeating: Array(repeating: 0, count: 7), count: 2)
for file in 0..<2 {
    types.append("== \(fileNames[file]) ==");
    values.append("== \(fileNames[file]) ==");
    formatted.append("(* \(fileNames[file]) *)")
    var pending: [String: Signature] = [:]
    let parser = Parser(Lexer.lex(texts[file], file));
    evaluator.calls = 0
    while parser.peek.kind != "eof" {
        statistics[file][0] += 1
        let item: Item
        do {
            item = try parser.item()
        }
        catch let token as Token {
            let message = token.kind == "invalid" ? token.value : token.kind == "eof" ? "unexpected end of file" : "unexpected '\(token.spelling)'"
            statistics[file][2] += 1;
            report(token.position, "syntax error", message, sources, &errors);
            parser.recover();
            continue
        } catch {
            preconditionFailure()
        }
        formatted.append(itemString(item))
        if case .signature(let name, let position, let type) = item {
            if let old = pending.updateValue(Signature(position: position, type: type), forKey: name) {
                statistics[file][5] += 1;
                report(old.position, "warning", "signature for '\(name)' is never used", sources, &errors)
            };
            continue
        }
        context.clear()
        let nextTypes: TypeEnvironment, schemes: [Scheme], expressionType: MLType?
        do {
            switch item {
                case .declaration(let group):
                let signatures = group.bindings.map {
                    pending.removeValue(forKey: $0.name)
                }
                var (next, inferred) = try context.group(group, typeEnvironment, false)
                for (i, signature) in signatures.enumerated() {
                    if let signature {
                        var variables: [String: MLType] = [:], assigned: [Int: MLType] = [:]
                        let declared = signatureType(signature.type, context.unifier, &variables)
                        if !signatureMatches(inferred[i].type, declared, context.unifier, &assigned) {
                            let printer = TypePrinter(context.unifier);
                            throw Diagnostic(position: group.bindings[i].position, message: "'\(group.bindings[i].name)' has type \(printer.write(inferred[i].type)) but its signature is \(printer.write(declared))")
                        }
                        inferred[i] = Scheme(type: declared, quantified: context.unifier.variables(declared));
                        next[group.bindings[i].name] = inferred[i]
                    }
                }
                nextTypes = next;
                schemes = inferred;
                expressionType = nil
                case .expression(let expression): let type = try context.expression(expression, typeEnvironment);
                nextTypes = typeEnvironment;
                schemes = [];
                expressionType = type
                default: preconditionFailure()
            }
        } catch let error as TypeError {
            statistics[file][3] += 1;
            report(error.position, "type error", errorMessage(error, context.unifier), sources, &errors);
            continue
        }
        catch let error as Diagnostic {
            statistics[file][3] += 1;
            report(error.position, "type error", error.message, sources, &errors);
            continue
        }
        catch {
            preconditionFailure()
        }
        let inspected = inspect(item, scope, context)
        func classification(_ position: Position) -> String {
            inspected.classifications[position].map {
                " (\($0))"
            } ?? ""
        }
        if case .declaration(let group) = item {
            for (binding, scheme) in zip(group.bindings, schemes) {
                types.append("\(binding.name) : \(TypePrinter(context.unifier).write(scheme.type))" + classification(binding.position))
            }
        } else {
            types.append("- : " + TypePrinter(context.unifier).write(expressionType!))
        }
        context.locals.sort {
            $0.position < $1.position
        }
        for local in context.locals {
            types.append("  \(local.name) (\(local.position.line):\(local.position.column)) : \(TypePrinter(context.unifier, local.scheme.quantified).write(local.scheme.type))" + classification(local.position))
        }
        for (position, _, message) in inspected.warnings {
            statistics[file][5] += 1;
            report(position, "warning", message, sources, &errors)
        }
        let nextValues: ValueEnvironment, evaluated: [Value]
        do {
            switch item {
                case .declaration(let group): (nextValues, evaluated) = try evaluator.group(group, valueEnvironment);
                case .expression(let expression): let value = try evaluator.expression(expression, valueEnvironment);
                nextValues = valueEnvironment;
                evaluated = [value];
                default: preconditionFailure()
            }
        } catch let error as RuntimeError {
            statistics[file][4] += 1;
            report(error.position, "runtime error", error.message, sources, &errors);
            continue
        }
        catch {
            preconditionFailure()
        }
        if case .declaration(let group) = item {
            for (binding, value) in zip(group.bindings, evaluated) {
                values.append("\(binding.name) = \(valueString(value))");
                scope[binding.name] = binding.position
            };
            statistics[file][1] += group.bindings.count
        } else {
            values.append("- = " + valueString(evaluated[0]))
        }
        typeEnvironment = nextTypes;
        valueEnvironment = nextValues
    }
    for (name, signature) in pending.sorted(by: {
        $0.value.position < $1.value.position
    }) {
        statistics[file][5] += 1;
        report(signature.position, "warning", "signature for '\(name)' is never used", sources, &errors)
    };
    statistics[file][6] = evaluator.calls
}
errors.append("== summary ==")
for file in 0..<2 {
    let s = statistics[file];
    errors.append("\(fileNames[file]): items=\(s[0]) bindings=\(s[1]) syntax=\(s[2]) type=\(s[3]) runtime=\(s[4]) warnings=\(s[5]) calls=\(s[6])")
}
write("types.txt", types);
write("values.txt", values);
write("errors.txt", errors);
write("formatted.ml", formatted)
