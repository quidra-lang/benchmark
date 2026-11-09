sealed record Clause(Term Head, Term? Body, string File, int Line);
sealed class Predicate(Indicator indicator) {
    public Indicator Indicator = indicator;
    public List<Clause> Clauses = new();
}
sealed class Database {
    public List<Predicate> Predicates = new();
    public int? Find(Indicator key) {
        int index = Predicates.FindIndex(predicate => predicate.Indicator == key);
        return index < 0 ? null : index;
    }
    public List<int> Candidates(int index, Term goal, Store store) => Enumerable.Range(0, Predicates[index].Clauses.Count).Where(i => goal.Arguments.Count == 0 || Terms.SameKind(goal.Arguments[0], Predicates[index].Clauses[i].Head.Arguments[0], store)).ToList();
    public (Term Head, Term? Body) Copy(int predicate, int clause, Store store) {
        Clause source = Predicates[predicate].Clauses[clause];
        List<Term> terms = new() {
            source.Head
        };
        if (source.Body != null) terms.Add(source.Body);
        List<Term> copies = store.CopyMany(terms);
        return (copies[0], copies.Count == 2 ? copies[1] : null);
    }
}
