indirect enum Value {
    case integer(Int), boolean(Bool), string(String), pair(Value, Value), list([Value]), closure(Closure), builtin(String)
}
typealias ValueEnvironment = [String: Value]
final class EnvironmentBox {
    var values: ValueEnvironment;
    init(_ values: ValueEnvironment) {
        self.values = values
    }
}
struct Closure {
    let parameter: Parameter, body: Expr, environment: EnvironmentBox
}
struct RuntimeError: Error {
    let position: Position, message: String
}
func checkedInteger(_ value: Int, _ position: Position) throws -> Value {
    guard (-2147483648...2147483647).contains(value) else {
        throw RuntimeError(position: position, message: "integer overflow")
    };
    return .integer(value)
}
func compareValues(_ a: Value, _ b: Value, _ position: Position) throws -> Int {
    switch (a, b) {
        case (.integer(let a), .integer(let b)): return a < b ? -1 : a > b ? 1 : 0
        case (.boolean(let a), .boolean(let b)): return a == b ? 0 : a ? 1 : -1
        case (.string(let a), .string(let b)): return a < b ? -1 : a > b ? 1 : 0
        case (.pair(let a, let b), .pair(let c, let d)): let first = try compareValues(a, c, position);
        return first == 0 ? try compareValues(b, d, position) : first
        case (.list(let a), .list(let b)):
        for (a, b) in zip(a, b) {
            let order = try compareValues(a, b, position);
            if order != 0 {
                return order
            }
        };
        return a.count < b.count ? -1 : a.count > b.count ? 1 : 0
        default: throw RuntimeError(position: position, message: "functional value compared")
    }
}
func matchPattern(_ pattern: Pattern, _ value: Value, _ bindings: inout ValueEnvironment) -> Bool {
    switch (pattern.kind, value) {
        case (.wildcard, _): return true
        case (.name(let name), _): bindings[name] = value;
        return true
        case (.integer(let a), .integer(let b)): return a == b
        case (.boolean(let a), .boolean(let b)): return a == b
        case (.string(let a), .string(let b)): return a == b
        case (.nilList, .list(let values)): return values.isEmpty
        case (.cons(let a, let b), .list(let values)): return !values.isEmpty && matchPattern(a, values[0], &bindings) && matchPattern(b, .list(Array(values.dropFirst())), &bindings)
        case (.list(let patterns), .list(let values)):
        if patterns.count != values.count {
            return false
        };
        for (p, v) in zip(patterns, values) {
            if !matchPattern(p, v, &bindings) {
                return false
            }
        };
        return true
        case (.pair(let a, let b), .pair(let c, let d)): return matchPattern(a, c, &bindings) && matchPattern(b, d, &bindings)
        default: return false
    }
}
final class Evaluator {
    var calls = 0
    func group(_ group: Group, _ environment: ValueEnvironment) throws -> (ValueEnvironment, [Value]) {
        var values: [Value] = []
        if group.recursive != nil {
            let shared = EnvironmentBox(environment)
            for binding in group.bindings {
                if case .fun(let parameter, let body) = binding.expression.kind {
                    values.append(.closure(Closure(parameter: parameter, body: body, environment: shared)))
                }
            }
            for (binding, value) in zip(group.bindings, values) {
                shared.values[binding.name] = value
            };
            return (shared.values, values)
        }
        for binding in group.bindings {
            values.append(try expression(binding.expression, environment))
        }
        var result = environment;
        for (binding, value) in zip(group.bindings, values) {
            result[binding.name] = value
        };
        return (result, values)
    }
    func apply(_ function: Value, _ argument: Value, _ position: Position) throws -> Value {
        calls += 1
        switch function {
            case .closure(let closure): var environment = closure.environment.values;
            if let name = closure.parameter.name {
                environment[name] = argument
            };
            return try expression(closure.body, environment)
            case .builtin(let name): return try applyBuiltin(name, argument, position)
            default: preconditionFailure()
        }
    }
    func expression(_ expression: Expr, _ environment: ValueEnvironment) throws -> Value {
        switch expression.kind {
            case .integer(let value): return .integer(value)
            case .boolean(let value): return .boolean(value)
            case .string(let value): return .string(value)
            case .name(let name): return environment[name]!
            case .fun(let parameter, let body): return .closure(Closure(parameter: parameter, body: body, environment: EnvironmentBox(environment)))
            case .apply(let function, let argument): let f = try self.expression(function, environment), a = try self.expression(argument, environment);
            return try apply(f, a, expression.position)
            case .negate(let position, let value): guard case .integer(let number) = try self.expression(value, environment) else {
                preconditionFailure()
            };
            return try checkedInteger(-number, position)
            case .binary(let op, let position, let a, let b):
            let left = try self.expression(a, environment)
            if op == "&&", case .boolean(let flag) = left {
                return flag ? try self.expression(b, environment) : .boolean(false)
            }
            if op == "||", case .boolean(let flag) = left {
                return flag ? .boolean(true) : try self.expression(b, environment)
            }
            let right = try self.expression(b, environment)
            switch op {
                case "+", "-", "*", "/", "mod":
                guard case .integer(let a) = left, case .integer(let b) = right else {
                    preconditionFailure()
                }
                if (op == "/" || op == "mod") && b == 0 {
                    throw RuntimeError(position: position, message: "division by zero")
                }
                let value: Int;
                switch op {
                    case "+": value = a + b;
                    case "-": value = a - b;
                    case "*": value = a * b;
                    case "/": value = a / b;
                    default: value = a - b * (a / b)
                };
                return try checkedInteger(value, position)
                case "^": guard case .string(let a) = left, case .string(let b) = right else {
                    preconditionFailure()
                };
                return .string(a + b)
                case "::": guard case .list(let values) = right else {
                    preconditionFailure()
                };
                return .list([left] + values)
                default: let order = try compareValues(left, right, position);
                let value: Bool;
                switch op {
                    case "=": value = order == 0;
                    case "<>": value = order != 0;
                    case "<": value = order < 0;
                    case ">": value = order > 0;
                    case "<=": value = order <= 0;
                    default: value = order >= 0
                };
                return .boolean(value)
            }
            case .conditional(let condition, let yes, let no): guard case .boolean(let flag) = try self.expression(condition, environment) else {
                preconditionFailure()
            };
            return try self.expression(flag ? yes : no, environment)
            case .pair(let a, let b): let first = try self.expression(a, environment), second = try self.expression(b, environment);
            return .pair(first, second)
            case .list(let elements): var values: [Value] = [];
            for element in elements {
                values.append(try self.expression(element, environment))
            };
            return .list(values)
            case .match(let value, let arms):
            let matched = try self.expression(value, environment)
            for (pattern, body) in arms {
                var bindings: ValueEnvironment = [:];
                if matchPattern(pattern, matched, &bindings) {
                    return try self.expression(body, environment.merging(bindings) {
                        _, new in new
                    })
                }
            }
            throw RuntimeError(position: expression.position, message: "match failure")
            case .letIn(let group, let body): let (inner, _) = try self.group(group, environment);
            return try self.expression(body, inner)
        }
    }
}
