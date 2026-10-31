sealed class Trail {
    readonly List<int> bindings = new();
    public int Mark => bindings.Count;
    public void Undo(int mark, Store store) {
        while (bindings.Count > mark) {
            int index = bindings.Count - 1;
            store.Bindings[bindings[index]] = null;
            bindings.RemoveAt(index);
        }
    }
    public bool Unify(Term a, Term b, Store store) {
        Stack<(Term A, Term B)> pending = new();
        pending.Push((a, b));
        while (pending.Count > 0) {
            var (first, second) = pending.Pop();
            Term x = store.Dereference(first), y = store.Dereference(second);
            if (x is VariableTerm xv) {
                if (y is VariableTerm yv && xv.Id == yv.Id) continue;
                store.Bindings[xv.Id] = y;
                bindings.Add(xv.Id);
                continue;
            }
            if (y is VariableTerm variable) {
                store.Bindings[variable.Id] = x;
                bindings.Add(variable.Id);
                continue;
            }
            if (x is IntegerTerm xi && y is IntegerTerm yi && xi.Value == yi.Value) continue;
            if (x is AtomTerm xa && y is AtomTerm ya && xa.Name == ya.Name) continue;
            if (x is CompoundTerm xc && y is CompoundTerm yc && xc.Name == yc.Name && xc.Args.Count == yc.Args.Count) {
                for (int i = xc.Args.Count - 1; i >= 0; i--) pending.Push((xc.Args[i], yc.Args[i]));
            } else return false;
        }
        return true;
    }
    public static bool Identical(Term a, Term b, Store store) {
        Stack<(Term A, Term B)> pending = new();
        pending.Push((a, b));
        while (pending.Count > 0) {
            var (first, second) = pending.Pop();
            Term x = store.Dereference(first), y = store.Dereference(second);
            if (x is VariableTerm xv && y is VariableTerm yv && xv.Id == yv.Id) continue;
            if (x is IntegerTerm xi && y is IntegerTerm yi && xi.Value == yi.Value) continue;
            if (x is AtomTerm xa && y is AtomTerm ya && xa.Name == ya.Name) continue;
            if (x is CompoundTerm xc && y is CompoundTerm yc && xc.Name == yc.Name && xc.Args.Count == yc.Args.Count) {
                for (int i = xc.Args.Count - 1; i >= 0; i--) pending.Push((xc.Args[i], yc.Args[i]));
            } else return false;
        }
        return true;
    }
}
