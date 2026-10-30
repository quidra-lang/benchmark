import java.util.*;
final class Terms {
    sealed interface Term permits IntegerTerm, Atom, Variable, Compound {}
    record IntegerTerm(int value) implements Term {}
    record Atom(String name) implements Term {}
    static final class Variable implements Term {
        Term binding;
    }
    record Compound(String name, List<Term> args) implements Term {
        Compound(String name, Term... args) { this(name, List.of(args)); }
    }
    record Indicator(String name, int arity) {}
    record ListParts(List<Term> elements, Term tail) {}
    static final Atom NIL = new Atom("[]"), INSTANTIATION = new Atom("instantiation_error");
    static Term atom(String name) { return new Atom(name); }
    static Term integer(int value) { return new IntegerTerm(value); }
    static Term compound(String name, Term... args) { return new Compound(name, args); }
    static Term dereference(Term term) {
        while (term instanceof Variable variable && variable.binding != null)
            term = variable.binding;
        return term;
    }
    static boolean atomIs(Term term, String name) {
        return dereference(term) instanceof Atom atom && atom.name().equals(name);
    }
    static Indicator indicator(Term term) {
        term = dereference(term);
        return term instanceof Compound compound
            ? new Indicator(compound.name(), compound.args().size())
            : new Indicator(((Atom)term).name(), 0);
    }
    static Term indicatorTerm(Indicator key) {
        return compound("/", atom(key.name()), integer(key.arity()));
    }
    static List<Term> args(Term term) {
        return term instanceof Compound compound ? compound.args() : List.of();
    }
    static Term list(List<? extends Term> elements, Term tail) {
        for (int i = elements.size() - 1; i >= 0; i--)
            tail = compound(".", elements.get(i), tail);
        return tail;
    }
    static Term list(List<? extends Term> elements) { return list(elements, NIL); }
    static ListParts listParts(Term term) {
        List<Term> elements = new ArrayList<>();
        term = dereference(term);
        while (term instanceof Compound compound && compound.name().equals(".") &&
               compound.args().size() == 2) {
            elements.add(compound.args().get(0));
            term = dereference(compound.args().get(1));
        }
        return new ListParts(elements, term);
    }
    static Term copy(Term term, Map<Variable, Variable> variables) {
        if (term == null)
            return null;
        term = dereference(term);
        if (term instanceof Variable variable)
            return variables.computeIfAbsent(variable, key -> new Variable());
        if (term instanceof Compound compound) {
            List<Term> arguments = new ArrayList<>();
            for (Term argument : compound.args())
                arguments.add(copy(argument, variables));
            return new Compound(compound.name(), arguments);
        }
        return term;
    }
    static Term copy(Term term) { return copy(term, new IdentityHashMap<>()); }
    static List<Variable> variables(Term... terms) {
        List<Variable> result = new ArrayList<>();
        Deque<Term> pending = new ArrayDeque<>();
        for (int i = terms.length - 1; i >= 0; i--)
            if (terms[i] != null)
                pending.push(terms[i]);
        while (!pending.isEmpty()) {
            Term term = dereference(pending.pop());
            if (term instanceof Variable variable)
                result.add(variable);
            else if (term instanceof Compound compound)
                for (int i = compound.args().size() - 1; i >= 0; i--)
                    pending.push(compound.args().get(i));
        }
        return result;
    }
    static boolean sameKind(Term first, Term second) {
        first = dereference(first);
        second = dereference(second);
        if (first instanceof Variable || second instanceof Variable)
            return true;
        if (first instanceof Compound a && second instanceof Compound b)
            return a.name().equals(b.name()) && a.args().size() == b.args().size();
        return first.equals(second);
    }
    static Term typeError(String kind, Term term) {
        return compound("type_error", atom(kind), term);
    }
    static Term domainError(String kind, Term term) {
        return compound("domain_error", atom(kind), term);
    }
    static final class Fault extends RuntimeException {
        final Term term;
        Fault(Term term) { this.term = term; }
    }
    static final class Ball extends RuntimeException {
        final Term term;
        Ball(Term term) { this.term = term; }
    }
}
