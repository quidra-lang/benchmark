import java.util.*;
final class Database {
    record Clause(Terms.Term head, Terms.Term body, String file, int line) {
        Copied copy() {
            Map<Terms.Variable, Terms.Variable> variables = new IdentityHashMap<>();
            return new Copied(Terms.copy(head, variables), Terms.copy(body, variables));
        }
    }
    record Copied(Terms.Term head, Terms.Term body) {}
    final LinkedHashMap<Terms.Indicator, List<Clause>> predicates = new LinkedHashMap<>();
    void add(Clause clause) {
        predicates.computeIfAbsent(Terms.indicator(clause.head()), key -> new ArrayList<>())
            .add(clause);
    }
    List<Clause> candidates(Terms.Term goal) {
        Terms.Indicator key = Terms.indicator(goal);
        List<Clause> result = new ArrayList<>();
        for (Clause clause : predicates.get(key))
            if (key.arity() == 0 ||
                Terms.sameKind(Terms.args(goal).getFirst(), Terms.args(clause.head()).getFirst()))
                result.add(clause);
        return result;
    }
}
