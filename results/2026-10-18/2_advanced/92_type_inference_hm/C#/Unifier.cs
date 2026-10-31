using System;
using System.Collections.Generic;
using System.Linq;
abstract record MLType {
    public sealed record IntType : MLType;
    public sealed record BoolType : MLType;
    public sealed record StringType : MLType;
    public sealed record Variable(int Id) : MLType;
    public sealed record ListType(MLType Element) : MLType;
    public sealed record PairType(MLType First, MLType Second) : MLType;
    public sealed record Function(MLType Argument, MLType Result) : MLType;
    public static MLType Int {
        get;
    } = new IntType();
    public static MLType Bool {
        get;
    } = new BoolType();
    public static MLType String {
        get;
    } = new StringType();
}
sealed record Scheme(MLType Type, HashSet<int> Quantified) {
    public static Scheme Mono(MLType type) => new(type, new());
}
sealed class UnifyFailure(MLType expected, MLType found, bool occurs, bool nested) : Exception {
    public MLType Expected {
        get;
    } = expected;
    public MLType Found {
        get;
    } = found;
    public bool Occurs {
        get;
    } = occurs;
    public bool Nested {
        get;
    } = nested;
}
sealed class Unifier {
    readonly List<MLType?> bindings = new();
    public MLType.Variable Fresh() {
        int id = bindings.Count;
        bindings.Add(null);
        return new(id);
    }
    public MLType Resolve(MLType type) => type switch {
        MLType.Variable v => bindings[v.Id] is {
        } bound ? Resolve(bound) : type, MLType.ListType l => new MLType.ListType(Resolve(l.Element)), MLType.PairType p => new MLType.PairType(Resolve(p.First), Resolve(p.Second)), MLType.Function f => new MLType.Function(Resolve(f.Argument), Resolve(f.Result)), _ => type
    };
    public HashSet<int> Variables(MLType type) {
        switch (Resolve(type)) {
            case MLType.Variable v: return new() {
                v.Id
            };
            case MLType.ListType l: return Variables(l.Element);
            case MLType.PairType p: {
                HashSet<int> result = Variables(p.First);
                result.UnionWith(Variables(p.Second));
                return result;
            } case MLType.Function f: {
                HashSet<int> result = Variables(f.Argument);
                result.UnionWith(Variables(f.Result));
                return result;
            } default: return new();
        }
    }
    public void Bind(int id, MLType type) => bindings[id] = type;
    public void Unify(MLType expected, MLType found, bool nested = false) {
        MLType e = Resolve(expected), f = Resolve(found);
        if (e == f) return;
        if (e is MLType.Variable ev) {
            if (Variables(f).Contains(ev.Id)) throw new UnifyFailure(e, f, true, nested);
            Bind(ev.Id, f);
            return;
        }
        if (f is MLType.Variable fv) {
            if (Variables(e).Contains(fv.Id)) throw new UnifyFailure(e, f, true, nested);
            Bind(fv.Id, e);
            return;
        }
        switch (e, f) {
            case (MLType.ListType a, MLType.ListType b): Unify(a.Element, b.Element, true);
            break;
            case (MLType.PairType a, MLType.PairType b): Unify(a.First, b.First, true);
            Unify(a.Second, b.Second, true);
            break;
            case (MLType.Function a, MLType.Function b): Unify(a.Argument, b.Argument, true);
            Unify(a.Result, b.Result, true);
            break;
            default: throw new UnifyFailure(e, f, false, nested);
        }
    }
    public Scheme Generalize(MLType type, IReadOnlyDictionary<string, Scheme> environment) {
        HashSet<int> variables = Variables(type);
        foreach (Scheme scheme in environment.Values) {
            HashSet<int> free = Variables(scheme.Type);
            free.ExceptWith(scheme.Quantified);
            variables.ExceptWith(free);
        } return new(type, variables);
    }
    public MLType Instantiate(Scheme scheme) {
        Dictionary<int, MLType> replacements = scheme.Quantified.Order().ToDictionary(id => id, _ => (MLType)Fresh());
        MLType Replace(MLType type) => type switch {
            MLType.Variable v => replacements.GetValueOrDefault(v.Id, type), MLType.ListType l => new MLType.ListType(Replace(l.Element)), MLType.PairType p => new MLType.PairType(Replace(p.First), Replace(p.Second)), MLType.Function f => new MLType.Function(Replace(f.Argument), Replace(f.Result)), _ => type
        };
        return Replace(Resolve(scheme.Type));
    }
}
