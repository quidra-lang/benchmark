import java.util.*;
final class Unifier {
    sealed interface Type permits Variable, Construct {}
    static final class Variable implements Type {
        Type binding;
    }
    record Construct(String kind, List<Type> children) implements Type {
        Construct(String kind, Type... children) { this(kind, List.of(children)); }
    }
    record Scheme(Type value, Set<Variable> quantified) {
        Scheme(Type value) { this(value, Set.of()); }
        Scheme { quantified = Set.copyOf(quantified); }
    }
    static final Construct INT = new Construct("int"), BOOL = new Construct("bool"),
                           STRING = new Construct("string");
    static Type resolve(Type value) {
        List<Variable> path = new ArrayList<>();
        while (value instanceof Variable variable && variable.binding != null) {
            path.add(variable);
            value = variable.binding;
        }
        for (Variable variable : path)
            variable.binding = value;
        return value;
    }
    static boolean occurs(Variable variable, Type value) {
        value = resolve(value);
        if (value instanceof Variable other)
            return variable == other;
        for (Type child : ((Construct)value).children())
            if (occurs(variable, child))
                return true;
        return false;
    }
    static final class Failure extends RuntimeException {
        Type expected, found;
        boolean infinite, nested;
        Failure(Type expected, Type found, boolean infinite, boolean nested) {
            this.expected = expected;
            this.found = found;
            this.infinite = infinite;
            this.nested = nested;
        }
    }
    static void unify(Type expected, Type found) { unify(expected, found, false); }
    static void unify(Type expected, Type found, boolean nested) {
        expected = resolve(expected);
        found = resolve(found);
        if (expected == found)
            return;
        if (expected instanceof Variable variable) {
            if (occurs(variable, found))
                throw new Failure(expected, found, true, nested);
            variable.binding = found;
            return;
        }
        if (found instanceof Variable variable) {
            if (occurs(variable, expected))
                throw new Failure(expected, found, true, nested);
            variable.binding = expected;
            return;
        }
        Construct first = (Construct)expected, second = (Construct)found;
        if (!first.kind().equals(second.kind()))
            throw new Failure(expected, found, false, nested);
        for (int i = 0; i < first.children().size(); i++)
            unify(first.children().get(i), second.children().get(i), true);
    }
    static Set<Variable> free(Type value) {
        value = resolve(value);
        if (value instanceof Variable variable)
            return new HashSet<>(Set.of(variable));
        Set<Variable> result = new HashSet<>();
        for (Type child : ((Construct)value).children())
            result.addAll(free(child));
        return result;
    }
    static Scheme generalize(Type value, Map<String, Scheme> environment) {
        Set<Variable> available = free(value);
        for (Scheme scheme : environment.values()) {
            Set<Variable> variables = free(scheme.value());
            variables.removeAll(scheme.quantified());
            available.removeAll(variables);
        }
        return new Scheme(value, available);
    }
    static Type instantiate(Scheme scheme) {
        return copy(scheme.value(), scheme.quantified(), new IdentityHashMap<>());
    }
    static Type copy(Type value, Set<Variable> quantified, Map<Variable, Variable> replacements) {
        value = resolve(value);
        if (value instanceof Variable variable)
            return quantified.contains(variable)
                ? replacements.computeIfAbsent(variable, ignored -> new Variable())
                : variable;
        Construct construct = (Construct)value;
        List<Type> children = new ArrayList<>();
        for (Type child : construct.children())
            children.add(copy(child, quantified, replacements));
        return new Construct(construct.kind(), children);
    }
}
