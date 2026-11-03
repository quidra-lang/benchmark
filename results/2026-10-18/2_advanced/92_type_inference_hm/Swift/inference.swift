enum TypeErrorKind {
    case message(String), function(MLType), check(MLType, MLType, UnifyFailure)
}
struct TypeError: Error {
    let position: Position, kind: TypeErrorKind
}
struct Local {
    let name: String, position: Position, scheme: Scheme
}
final class Inference {
    let unifier = Unifier();
    var locals: [Local] = [], matches: [Position: (MLType, [Pattern])] = [:]
    func clear() {
        locals = [];
        matches = [:]
    }
    func message(_ position: Position, _ message: String) -> TypeError {
        TypeError(position: position, kind: .message(message))
    }
    func check(_ expected: MLType, _ found: MLType, _ position: Position) throws {
        do {
            try unifier.unify(expected, found)
        } catch let failure as UnifyFailure {
            throw TypeError(position: position, kind: .check(expected, found, failure))
        }
    }
    func group(_ group: Group, _ environment: TypeEnvironment, _ local: Bool) throws -> (TypeEnvironment, [Scheme]) {
        var names: Set<String> = []
        for binding in group.bindings {
            if !names.insert(binding.name).inserted {
                throw message(binding.position, "variable '\(binding.name)' is bound twice in this let")
            }
            if group.recursive != nil {
                guard case .fun = binding.expression.kind else {
                    throw message(binding.position, "'\(binding.name)' in let rec must be a function")
                }
            }
        }
        var recursive = environment, types: [MLType] = []
        if group.recursive != nil {
            for binding in group.bindings {
                let type = unifier.fresh();
                recursive[binding.name] = .mono(type);
                types.append(type)
            }
            for (i, binding) in group.bindings.enumerated() {
                let found = try expression(binding.expression, recursive);
                try check(types[i], found, binding.position)
            }
        } else {
            for binding in group.bindings {
                types.append(try expression(binding.expression, environment))
            }
        }
        let schemes = types.map {
            unifier.generalize($0, environment)
        };
        var result = environment
        for (binding, scheme) in zip(group.bindings, schemes) {
            result[binding.name] = scheme;
            if local {
                locals.append(Local(name: binding.name, position: binding.position, scheme: scheme))
            }
        };
        return (result, schemes)
    }
    func expression(_ expression: Expr, _ environment: TypeEnvironment) throws -> MLType {
        switch expression.kind {
            case .integer: return .integer
            case .boolean: return .boolean
            case .string: return .string
            case .name(let name):
            if let scheme = environment[name] {
                return unifier.instantiate(scheme)
            }
            let candidate = environment.keys.map {
                (editDistance(name, $0), $0)
            }.filter {
                $0.0 <= 2 && $0.0 < name.count
            }.min {
                $0 < $1
            }
            throw message(expression.position, "unbound variable '\(name)'" + (candidate.map {
                " (did you mean '\($0.1)'?)"
            } ?? ""))
            case .fun(let parameter, let body):
            let argument = unifier.fresh();
            var inner = environment;
            if let name = parameter.name {
                inner[name] = .mono(argument)
            };
            let result = try self.expression(body, inner);
            return .function(argument, result)
            case .apply(let function, let argument):
            let functionType = try self.expression(function, environment), expected: MLType, result: MLType
            switch unifier.resolve(functionType) {
                case .variable(let i): expected = unifier.fresh();
                result = unifier.fresh();
                unifier.bind(i, .function(expected, result))
                case .function(let a, let b): expected = a;
                result = b
                case let type: throw TypeError(position: function.position, kind: .function(type))
            }
            let found = try self.expression(argument, environment);
            try check(expected, found, argument.position);
            return result
            case .binary(let op, _, let left, let right):
            let a: MLType, b: MLType, result: MLType
            switch op {
                case "+", "-", "*", "/", "mod": a = .integer;
                b = .integer;
                result = .integer
                case "^": a = .string;
                b = .string;
                result = .string
                case "&&", "||": a = .boolean;
                b = .boolean;
                result = .boolean
                case "::": a = unifier.fresh();
                b = .list(a);
                result = .list(a)
                default: a = unifier.fresh();
                b = a;
                result = .boolean
            }
            let first = try self.expression(left, environment);
            try check(a, first, left.position);
            let second = try self.expression(right, environment);
            try check(b, second, right.position);
            return result
            case .negate(_, let value): let found = try self.expression(value, environment);
            try check(.integer, found, value.position);
            return .integer
            case .conditional(let condition, let yes, let no):
            let found = try self.expression(condition, environment);
            try check(.boolean, found, condition.position);
            let a = try self.expression(yes, environment), b = try self.expression(no, environment);
            try check(a, b, no.position);
            return a
            case .pair(let a, let b): let first = try self.expression(a, environment), second = try self.expression(b, environment);
            return .pair(first, second)
            case .list(let elements): let type = unifier.fresh();
            for value in elements {
                let found = try self.expression(value, environment);
                try check(type, found, value.position)
            };
            return .list(type)
            case .match(let value, let arms):
            let type = try self.expression(value, environment), result = unifier.fresh()
            for (pattern, body) in arms {
                var bindings: [String: MLType] = [:];
                let found = try self.pattern(pattern, &bindings);
                try check(type, found, pattern.position)
                var inner = environment;
                for (name, type) in bindings {
                    inner[name] = .mono(type)
                };
                let bodyType = try self.expression(body, inner);
                try check(result, bodyType, body.position)
            }
            matches[expression.position] = (type, arms.map {
                $0.0
            });
            return result
            case .letIn(let group, let body): let (inner, _) = try self.group(group, environment, true);
            return try self.expression(body, inner)
        }
    }
    func pattern(_ pattern: Pattern, _ bindings: inout [String: MLType]) throws -> MLType {
        switch pattern.kind {
            case .wildcard: return unifier.fresh()
            case .name(let name): if bindings[name] != nil {
                throw message(pattern.position, "variable '\(name)' is bound twice in this pattern")
            };
            let type = unifier.fresh();
            bindings[name] = type;
            return type
            case .integer: return .integer
            case .boolean: return .boolean
            case .string: return .string
            case .nilList: return .list(unifier.fresh())
            case .cons(let a, let b): let type = unifier.fresh(), head = try self.pattern(a, &bindings);
            try check(type, head, a.position);
            let tail = try self.pattern(b, &bindings), list = MLType.list(type);
            try check(list, tail, b.position);
            return list
            case .list(let elements): let type = unifier.fresh();
            for value in elements {
                let found = try self.pattern(value, &bindings);
                try check(type, found, value.position)
            };
            return .list(type)
            case .pair(let a, let b): let first = try self.pattern(a, &bindings), second = try self.pattern(b, &bindings);
            return .pair(first, second)
        }
    }
}
