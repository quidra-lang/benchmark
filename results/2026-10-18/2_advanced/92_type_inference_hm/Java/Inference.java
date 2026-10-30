import java.util.*;
final class Inference {
    static final class Error extends RuntimeException {
        String kind, name;
        Lexer.Position position;
        Unifier.Type expected, found;
        Unifier.Failure failure;
        Set<String> candidates;
        Error(String kind, Lexer.Position position) {
            this.kind = kind;
            this.position = position;
        }
        Error named(String name) {
            this.name = name;
            return this;
        }
    }
    record OperatorTypes(Unifier.Type first, Unifier.Type second, Unifier.Type result) {}
    static OperatorTypes operatorTypes(String operator) {
        if (Set.of("+", "-", "*", "/", "mod").contains(operator))
            return new OperatorTypes(Unifier.INT, Unifier.INT, Unifier.INT);
        if (operator.equals("^"))
            return new OperatorTypes(Unifier.STRING, Unifier.STRING, Unifier.STRING);
        if (Set.of("&&", "||").contains(operator))
            return new OperatorTypes(Unifier.BOOL, Unifier.BOOL, Unifier.BOOL);
        Unifier.Variable variable = new Unifier.Variable();
        if (operator.equals("::")) {
            Unifier.Type list = new Unifier.Construct("list", variable);
            return new OperatorTypes(variable, list, list);
        }
        return new OperatorTypes(variable, variable, Unifier.BOOL);
    }
    List<Parser.Binding> localBindings = new ArrayList<>();
    Map<Parser.Expr, Unifier.Type> inferred = new IdentityHashMap<>();
    void check(Unifier.Type expected, Unifier.Type found, Lexer.Position position) {
        try {
            Unifier.unify(expected, found);
        } catch (Unifier.Failure failure) {
            Error error = new Error("check", position);
            error.expected = expected;
            error.found = found;
            error.failure = failure;
            throw error;
        }
    }
    Unifier.Type expression(Parser.Expr expression, Map<String, Unifier.Scheme> environment) {
        Unifier.Type result;
        switch (expression) {
        case Parser.Literal literal -> result = literalType(literal.kind());
        case Parser.Name name -> {
            Unifier.Scheme scheme = environment.get(name.token().spelling());
            if (scheme == null) {
                Error error = new Error("unbound", name.position()).named(name.token().spelling());
                error.candidates = new TreeSet<>(environment.keySet());
                throw error;
            }
            result = Unifier.instantiate(scheme);
        }
        case Parser.Fun function -> {
            Unifier.Variable argument = new Unifier.Variable();
            Map<String, Unifier.Scheme> inner = new HashMap<>(environment);
            if (!function.parameter().spelling().equals("_"))
                inner.put(function.parameter().spelling(), new Unifier.Scheme(argument));
            result =
                new Unifier.Construct("function", argument, expression(function.body(), inner));
        }
        case Parser.Apply application -> {
            Unifier.Type function =
                             Unifier.resolve(expression(application.function(), environment)),
                         argument;
            if (function instanceof Unifier.Variable variable) {
                argument = new Unifier.Variable();
                result = new Unifier.Variable();
                variable.binding = new Unifier.Construct("function", argument, result);
            } else if (function instanceof Unifier.Construct construct &&
                       construct.kind().equals("function")) {
                argument = construct.children().get(0);
                result = construct.children().get(1);
            } else {
                Error error = new Error("not_function", application.function().position());
                error.found = function;
                throw error;
            }
            check(argument, expression(application.argument(), environment),
                  application.argument().position());
        }
        case Parser.Binary binary -> {
            OperatorTypes operator = operatorTypes(binary.operator().spelling());
            check(operator.first(), expression(binary.left(), environment),
                  binary.left().position());
            check(operator.second(), expression(binary.right(), environment),
                  binary.right().position());
            result = operator.result();
        }
        case Parser.Negate negate -> {
            check(Unifier.INT, expression(negate.operand(), environment),
                  negate.operand().position());
            result = Unifier.INT;
        }
        case Parser.Conditional conditional -> {
            check(Unifier.BOOL, expression(conditional.condition(), environment),
                  conditional.condition().position());
            result = expression(conditional.yes(), environment);
            Unifier.Type found = expression(conditional.no(), environment);
            check(result, found, conditional.no().position());
        }
        case Parser.Pair pair -> {
            Unifier.Type first = expression(pair.first(), environment),
                         second = expression(pair.second(), environment);
            result = new Unifier.Construct("pair", first, second);
        }
        case Parser.ListExpr list -> {
            Unifier.Variable element = new Unifier.Variable();
            for (Parser.Expr child : list.elements())
                check(element, expression(child, environment), child.position());
            result = new Unifier.Construct("list", element);
        }
        case Parser.Match match -> {
            Unifier.Type matched = expression(match.matched(), environment);
            result = new Unifier.Variable();
            for (Parser.Arm arm : match.arms()) {
                Map<String, Unifier.Type> bindings = new HashMap<>();
                Unifier.Type pattern = pattern(arm.pattern(), bindings);
                check(matched, pattern, arm.pattern().position());
                Map<String, Unifier.Scheme> inner = new HashMap<>(environment);
                for (var entry : bindings.entrySet())
                    inner.put(entry.getKey(), new Unifier.Scheme(entry.getValue()));
                check(result, expression(arm.expression(), inner), arm.expression().position());
            }
        }
        case Parser.Let let -> {
            Map<String, Unifier.Scheme> inner = group(let.group(), environment, true);
            result = expression(let.body(), inner);
        }
        }
        inferred.put(expression, result);
        return result;
    }
    static Unifier.Type literalType(String kind) {
        return switch (kind) {
            case "integer" -> Unifier.INT;
            case "boolean" -> Unifier.BOOL;
            default -> Unifier.STRING;
        };
    }
    Unifier.Type pattern(Parser.Pattern pattern, Map<String, Unifier.Type> bindings) {
        if (pattern instanceof Parser.Wildcard)
            return new Unifier.Variable();
        if (pattern instanceof Parser.PatternName name) {
            String value = name.token().spelling();
            if (bindings.containsKey(value))
                throw new Error("duplicate_pattern", name.position()).named(value);
            Unifier.Type result = new Unifier.Variable();
            bindings.put(value, result);
            return result;
        }
        if (pattern instanceof Parser.PatternLiteral literal)
            return literalType(literal.kind());
        if (pattern instanceof Parser.PatternPair pair) {
            Unifier.Type first = pattern(pair.first(), bindings),
                         second = pattern(pair.second(), bindings);
            return new Unifier.Construct("pair", first, second);
        }
        Unifier.Type element = new Unifier.Variable(), sequence =
                                                           new Unifier.Construct("list", element);
        if (pattern instanceof Parser.Cons cons) {
            check(element, pattern(cons.first(), bindings), cons.first().position());
            check(sequence, pattern(cons.rest(), bindings), cons.rest().position());
        } else
            for (Parser.Pattern child : ((Parser.PatternList)pattern).elements())
                check(element, pattern(child, bindings), child.position());
        return sequence;
    }
    Map<String, Unifier.Scheme> group(Parser.Group group, Map<String, Unifier.Scheme> environment,
                                      boolean local) {
        Set<String> names = new HashSet<>();
        for (Parser.Binding binding : group.bindings()) {
            if (!names.add(binding.name()))
                throw new Error("duplicate_let", binding.position()).named(binding.name());
            if (group.recPosition() != null && !(binding.expression instanceof Parser.Fun))
                throw new Error("recursive_function", binding.position()).named(binding.name());
        }
        List<Unifier.Type> types = new ArrayList<>();
        if (group.recPosition() == null)
            for (Parser.Binding binding : group.bindings())
                types.add(expression(binding.expression, environment));
        else {
            Map<String, Unifier.Scheme> recursive = new HashMap<>(environment);
            for (Parser.Binding binding : group.bindings()) {
                Unifier.Type variable = new Unifier.Variable();
                types.add(variable);
                recursive.put(binding.name(), new Unifier.Scheme(variable));
            }
            for (int i = 0; i < group.bindings().size(); i++) {
                Parser.Binding binding = group.bindings().get(i);
                check(types.get(i), expression(binding.expression, recursive), binding.position());
            }
        }
        Map<String, Unifier.Scheme> result = new HashMap<>(environment);
        for (int i = 0; i < types.size(); i++) {
            Parser.Binding binding = group.bindings().get(i);
            binding.scheme = Unifier.generalize(types.get(i), environment);
            result.put(binding.name(), binding.scheme);
        }
        if (local)
            localBindings.addAll(group.bindings());
        return result;
    }
}
