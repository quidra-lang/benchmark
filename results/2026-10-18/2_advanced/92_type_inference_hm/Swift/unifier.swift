indirect enum MLType: Equatable {
    case integer, boolean, string, variable(Int), list(MLType), pair(MLType, MLType), function(MLType, MLType)
}
struct Scheme {
    let type: MLType, quantified: Set<Int>;
    static func mono(_ type: MLType) -> Self {
        Self(type: type, quantified: [])
    }
}
typealias TypeEnvironment = [String: Scheme]
struct UnifyFailure: Error {
    let expected: MLType, found: MLType, occurs: Bool, nested: Bool
}
final class Unifier {
    var bindings: [MLType?] = []
    func fresh() -> MLType {
        let index = bindings.count;
        bindings.append(nil);
        return .variable(index)
    }
    func resolve(_ type: MLType) -> MLType {
        switch type {
            case .variable(let i): return bindings[i].map(resolve) ?? type
            case .list(let t): return .list(resolve(t))
            case .pair(let a, let b): return .pair(resolve(a), resolve(b))
            case .function(let a, let b): return .function(resolve(a), resolve(b))
            default: return type
        }
    }
    func variables(_ type: MLType) -> Set<Int> {
        switch resolve(type) {
            case .variable(let i): return [i];
            case .list(let t): return variables(t);
            case .pair(let a, let b), .function(let a, let b): return variables(a).union(variables(b));
            default: return []
        }
    }
    func bind(_ index: Int, _ type: MLType) {
        bindings[index] = type
    }
    func unify(_ expected: MLType, _ found: MLType, _ nested: Bool = false) throws {
        let e = resolve(expected), f = resolve(found)
        if e == f {
            return
        }
        if case .variable(let i) = e {
            if variables(f).contains(i) {
                throw UnifyFailure(expected: e, found: f, occurs: true, nested: nested)
            };
            bind(i, f);
            return
        }
        if case .variable(let i) = f {
            if variables(e).contains(i) {
                throw UnifyFailure(expected: e, found: f, occurs: true, nested: nested)
            };
            bind(i, e);
            return
        }
        switch (e, f) {
            case (.list(let a), .list(let b)): try unify(a, b, true)
            case (.pair(let a, let b), .pair(let c, let d)), (.function(let a, let b), .function(let c, let d)): try unify(a, c, true);
            try unify(b, d, true)
            default: throw UnifyFailure(expected: e, found: f, occurs: false, nested: nested)
        }
    }
    func generalize(_ type: MLType, _ environment: TypeEnvironment) -> Scheme {
        var vars = variables(type)
        for scheme in environment.values {
            vars.subtract(variables(scheme.type).subtracting(scheme.quantified))
        };
        return Scheme(type: type, quantified: vars)
    }
    func instantiate(_ scheme: Scheme) -> MLType {
        let replacements = Dictionary(uniqueKeysWithValues: scheme.quantified.sorted().map {
            ($0, fresh())
        })
        func replace(_ type: MLType) -> MLType {
            switch type {
                case .variable(let i): return replacements[i] ?? type;
                case .list(let t): return .list(replace(t));
                case .pair(let a, let b): return .pair(replace(a), replace(b));
                case .function(let a, let b): return .function(replace(a), replace(b));
                default: return type
            }
        };
        return replace(resolve(scheme.type))
    }
}
