readonly record struct Indicator(string Name, int Arity);
abstract record Term {
    public Indicator? Indicator => this switch {
        AtomTerm atom => new(atom.Name, 0), CompoundTerm compound => new(compound.Name, compound.Args.Count), _ => null
    };
    public List<Term> Arguments => this is CompoundTerm compound ? compound.Args : new();
    public int? VariableId => this is VariableTerm variable ? variable.Id : null;
    public bool Nil => this is AtomTerm atom && atom.Name == "[]";
}
sealed record IntegerTerm(long Value) : Term;
sealed record AtomTerm(string Name) : Term;
sealed record VariableTerm(int Id) : Term;
sealed record CompoundTerm(string Name, List<Term> Args) : Term;
sealed class Store {
    public List<Term?> Bindings = new();
    public Store Clone() => new() {
        Bindings = this.Bindings.ToList()
    };
    public Term Fresh() {
        Term result = new VariableTerm(Bindings.Count);
        Bindings.Add(null);
        return result;
    }
    public Term Dereference(Term term) {
        Term result = term;
        while (result is VariableTerm variable && Bindings[variable.Id] is Term binding) result = binding;
        return result;
    }
    public Term Copy(Term term) => Copy(term, new());
    public List<Term> CopyMany(List<Term> terms) {
        Dictionary<int, Term> names = new();
        return terms.Select(term => Copy(term, names)).ToList();
    }
    Term Copy(Term term, Dictionary<int, Term> names) {
        Term value = Dereference(term);
        if (value is VariableTerm variable) {
            if (!names.ContainsKey(variable.Id)) names[variable.Id] = Fresh();
            return names[variable.Id];
        }
        return value is CompoundTerm compound ? new CompoundTerm(compound.Name, compound.Args.Select(argument => Copy(argument, names)).ToList()) : value;
    }
    public (List<Term> Elements, Term Tail) Parts(Term term) {
        List<Term> elements = new();
        Term tail = Dereference(term);
        while (tail is CompoundTerm compound && compound.Name == "." && compound.Args.Count == 2) {
            elements.Add(compound.Args[0]);
            tail = Dereference(compound.Args[1]);
        } return (elements, tail);
    }
    public List<int> Variables(List<Term> terms) {
        Stack<Term> pending = new(terms.AsEnumerable().Reverse());
        List<int> result = new();
        while (pending.Count > 0) {
            Term term = Dereference(pending.Pop());
            if (term is VariableTerm variable) result.Add(variable.Id);
            else if (term is CompoundTerm compound) for (int i = compound.Args.Count - 1; i >= 0; i--) pending.Push(compound.Args[i]);
        } return result;
    }
}
static class Terms {
    public static Term List(IEnumerable<Term> elements, Term? tail = null) {
        Term result = tail ?? new AtomTerm("[]");
        foreach (Term element in elements.Reverse()) result = new CompoundTerm(".", new() {
            element, result
        });
        return result;
    }
    public static Term IndicatorTerm(Indicator key) => new CompoundTerm("/", new() {
        new AtomTerm(key.Name), new IntegerTerm(key.Arity)
    });
    public static Term TypeError(string kind, Term term) => new CompoundTerm("type_error", new() {
        new AtomTerm(kind), term
    });
    public static Term DomainError(string kind, Term term) => new CompoundTerm("domain_error", new() {
        new AtomTerm(kind), term
    });
    public static Term ErrorBall(Term error, Indicator key) => new CompoundTerm("error", new() {
        error, IndicatorTerm(key)
    });
    public static bool SameKind(Term a, Term b, Store store) {
        Term x = store.Dereference(a), y = store.Dereference(b);
        if (x is VariableTerm || y is VariableTerm) return true;
        return (x, y) switch {
            (IntegerTerm first, IntegerTerm second) => first.Value == second.Value, (AtomTerm first, AtomTerm second) => first.Name == second.Name, (CompoundTerm first, CompoundTerm second) => first.Name == second.Name && first.Args.Count == second.Args.Count, _ => false
        };
    }
}
sealed class PrologError(Term term) : Exception {
    public Term Term {
        get;
    } = term;
}
