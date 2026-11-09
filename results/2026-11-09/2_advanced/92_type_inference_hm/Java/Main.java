import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
public final class Main {
    static String quoted(String value) {
        return "\"" +
            value.replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
                .replace("\t", "\\t") +
            "\"";
    }
    static String printValue(Evaluator.Value value) {
        return switch (value) {
            case Evaluator.IntegerValue integer -> Integer.toString(integer.value());
            case Evaluator.BooleanValue bool -> Boolean.toString(bool.value());
            case Evaluator.StringValue string -> quoted(string.value());
            case Evaluator.PairValue pair ->
                "(" + printValue(pair.first()) + ", " + printValue(pair.second()) + ")";
            case Evaluator.ListValue list -> {
                StringJoiner result = new StringJoiner("; ");
                for (Evaluator.Value child : list.elements())
                    result.add(printValue(child));
                yield "[" + result + "]";
            }
            default -> "<fun>";
        };
    }
    static final class TypePrinter {
        Map<Unifier.Variable, String> names = new IdentityHashMap<>();
        Set<Unifier.Variable> quantified;
        TypePrinter() {}
        TypePrinter(Set<Unifier.Variable> quantified) { this.quantified = quantified; }
        String print(Unifier.Type type) {
            type = Unifier.resolve(type);
            if (type instanceof Unifier.Variable variable) {
                if (!names.containsKey(variable)) {
                    int index = names.size();
                    String prefix =
                        quantified != null && !quantified.contains(variable) ? "'_" : "'";
                    names.put(variable, prefix + (char)('a' + index % 26) +
                                            (index >= 26 ? Integer.toString(index / 26) : ""));
                }
                return names.get(variable);
            }
            Unifier.Construct construct = (Unifier.Construct)type;
            String kind = construct.kind();
            if (Set.of("int", "bool", "string").contains(kind))
                return kind;
            Unifier.Type first = Unifier.resolve(construct.children().get(0));
            String left = print(first),
                   firstKind = first instanceof Unifier.Construct child ? child.kind() : "variable";
            if (kind.equals("list"))
                return (Set.of("pair", "function").contains(firstKind) ? "(" + left + ")" : left) +
                    " list";
            Unifier.Type second = Unifier.resolve(construct.children().get(1));
            String right = print(second), secondKind = second instanceof Unifier.Construct child
                                                           ? child.kind()
                                                           : "variable";
            if (kind.equals("pair")) {
                if (Set.of("pair", "function").contains(firstKind))
                    left = "(" + left + ")";
                if (Set.of("pair", "function").contains(secondKind))
                    right = "(" + right + ")";
                return left + " * " + right;
            }
            return (firstKind.equals("function") ? "(" + left + ")" : left) + " -> " + right;
        }
    }
    static String declaredKind(Parser.TypeExpr type) {
        return type instanceof Parser.TypeConstructor constructor ? constructor.kind() : "atom";
    }
    static String formatDeclared(Parser.TypeExpr type) {
        if (type instanceof Parser.TypeName name)
            return name.name();
        if (type instanceof Parser.TypeVariableName variable)
            return variable.spelling();
        Parser.TypeConstructor constructor = (Parser.TypeConstructor)type;
        Parser.TypeExpr first = constructor.children().get(0);
        String left = formatDeclared(first);
        if (constructor.kind().equals("list"))
            return (Set.of("pair", "function").contains(declaredKind(first)) ? "(" + left + ")"
                                                                             : left) +
                " list";
        Parser.TypeExpr second = constructor.children().get(1);
        String right = formatDeclared(second);
        if (constructor.kind().equals("pair")) {
            if (Set.of("pair", "function").contains(declaredKind(first)))
                left = "(" + left + ")";
            if (Set.of("pair", "function").contains(declaredKind(second)))
                right = "(" + right + ")";
            return left + " * " + right;
        }
        return (declaredKind(first).equals("function") ? "(" + left + ")" : left) + " -> " + right;
    }
    static Unifier.Type signatureType(Parser.TypeExpr type,
                                      Map<String, Unifier.Variable> variables) {
        if (type instanceof Parser.TypeVariableName variable)
            return variables.computeIfAbsent(variable.spelling(),
                                             ignored -> new Unifier.Variable());
        if (type instanceof Parser.TypeName name)
            return new Unifier.Construct(name.name());
        Parser.TypeConstructor constructor = (Parser.TypeConstructor)type;
        List<Unifier.Type> children = new ArrayList<>();
        for (Parser.TypeExpr child : constructor.children())
            children.add(signatureType(child, variables));
        return new Unifier.Construct(constructor.kind(), children);
    }
    static boolean identical(Unifier.Type first, Unifier.Type second) {
        first = Unifier.resolve(first);
        second = Unifier.resolve(second);
        if (first instanceof Unifier.Variable || second instanceof Unifier.Variable)
            return first == second;
        Unifier.Construct a = (Unifier.Construct)first, b = (Unifier.Construct)second;
        if (!a.kind().equals(b.kind()))
            return false;
        for (int i = 0; i < a.children().size(); i++)
            if (!identical(a.children().get(i), b.children().get(i)))
                return false;
        return true;
    }
    static boolean signatureMatches(Unifier.Type inferred, Unifier.Type declared,
                                    Map<Unifier.Variable, Unifier.Type> assignments) {
        inferred = Unifier.resolve(inferred);
        declared = Unifier.resolve(declared);
        if (inferred instanceof Unifier.Variable variable) {
            if (assignments.containsKey(variable))
                return identical(assignments.get(variable), declared);
            assignments.put(variable, declared);
            return true;
        }
        if (declared instanceof Unifier.Variable)
            return false;
        Unifier.Construct a = (Unifier.Construct)inferred, b = (Unifier.Construct)declared;
        if (!a.kind().equals(b.kind()))
            return false;
        for (int i = 0; i < a.children().size(); i++)
            if (!signatureMatches(a.children().get(i), b.children().get(i), assignments))
                return false;
        return true;
    }
    static void checkSignatures(Parser.Group group, List<Parser.Signature> signatures) {
        for (int i = 0; i < group.bindings().size(); i++) {
            Parser.Signature signature = signatures.get(i);
            if (signature == null)
                continue;
            Parser.Binding binding = group.bindings().get(i);
            Unifier.Type declared = signatureType(signature.declared(), new HashMap<>()),
                         inferred = binding.scheme.value();
            if (!signatureMatches(inferred, declared, new IdentityHashMap<>())) {
                Inference.Error error =
                    new Inference.Error("signature", binding.position()).named(binding.name());
                error.expected = inferred;
                error.found = declared;
                throw error;
            }
            binding.scheme = new Unifier.Scheme(declared, Unifier.free(declared));
        }
    }
    static int editDistance(String a, String b) {
        int[] previous = new int[b.length() + 1];
        for (int i = 0; i < previous.length; i++)
            previous[i] = i;
        for (int i = 1; i <= a.length(); i++) {
            int[] current = new int[b.length() + 1];
            current[0] = i;
            for (int j = 1; j <= b.length(); j++)
                current[j] =
                    Math.min(Math.min(current[j - 1] + 1, previous[j] + 1),
                             previous[j - 1] + (a.charAt(i - 1) == b.charAt(j - 1) ? 0 : 1));
            previous = current;
        }
        return previous[b.length()];
    }
    static String candidate(String name, Set<String> candidates) {
        String chosen = null;
        int best = 3;
        for (String candidate : new TreeSet<>(candidates)) {
            int distance = editDistance(name, candidate);
            if (distance <= 2 && distance < name.length() && distance < best) {
                best = distance;
                chosen = candidate;
            }
        }
        return chosen;
    }
    static String typeError(Inference.Error error) {
        TypePrinter printer = new TypePrinter();
        if (error.kind.equals("unbound")) {
            String candidate = candidate(error.name, error.candidates);
            return "unbound variable '" + error.name + "'" +
                (candidate == null ? "" : " (did you mean '" + candidate + "'?)");
        }
        if (error.kind.equals("not_function"))
            return "expected a function but found " + printer.print(error.found);
        if (error.kind.equals("check")) {
            String message = "expected " + printer.print(error.expected) + " but found " +
                             printer.print(error.found);
            Unifier.Failure failure = error.failure;
            if (failure.infinite) {
                Unifier.Type variable = failure.expected, value = failure.found;
                if (!(variable instanceof Unifier.Variable)) {
                    variable = failure.found;
                    value = failure.expected;
                }
                message += " (infinite type " + printer.print(variable) + " = " +
                           printer.print(value) + ")";
            } else if (failure.nested)
                message += " (" + printer.print(failure.expected) + " vs " +
                           printer.print(failure.found) + ")";
            return message;
        }
        return switch (error.kind) {
            case "duplicate_pattern" ->
                "variable '" + error.name + "' is bound twice in this pattern";
            case "duplicate_let" -> "variable '" + error.name + "' is bound twice in this let";
            case "recursive_function" -> "'" + error.name + "' in let rec must be a function";
            default ->
                "'" + error.name + "' has type " + printer.print(error.expected) +
                    " but its signature is " + printer.print(error.found);
        };
    }
    record Environments(Map<String, Unifier.Scheme> types, Map<String, Evaluator.Value> values) {}
    static Environments builtins() {
        Map<String, Unifier.Scheme> types = new HashMap<>();
        for (String name : List.of("fst", "snd")) {
            Unifier.Variable a = new Unifier.Variable(), b = new Unifier.Variable();
            types.put(name, new Unifier.Scheme(new Unifier.Construct(
                                                   "function", new Unifier.Construct("pair", a, b),
                                                   name.equals("fst") ? a : b),
                                               Set.of(a, b)));
        }
        types.put("not", new Unifier.Scheme(
                             new Unifier.Construct("function", Unifier.BOOL, Unifier.BOOL)));
        types.put("string_of_int", new Unifier.Scheme(new Unifier.Construct("function", Unifier.INT,
                                                                            Unifier.STRING)));
        Unifier.Variable result = new Unifier.Variable();
        types.put("failwith",
                  new Unifier.Scheme(new Unifier.Construct("function", Unifier.STRING, result),
                                     Set.of(result)));
        Map<String, Evaluator.Value> values = new HashMap<>();
        values.put("fst", new Evaluator.Builtin(
                              (value, position) -> ((Evaluator.PairValue)value).first()));
        values.put("snd", new Evaluator.Builtin(
                              (value, position) -> ((Evaluator.PairValue)value).second()));
        values.put("not", new Evaluator.Builtin((value, position)
                                                    -> new Evaluator.BooleanValue(
                                                        !((Evaluator.BooleanValue)value).value())));
        values.put("string_of_int",
                   new Evaluator.Builtin((value, position)
                                             -> new Evaluator.StringValue(Integer.toString(
                                                 ((Evaluator.IntegerValue)value).value()))));
        values.put("failwith", new Evaluator.Builtin((value, position) -> {
            throw new Evaluator.RuntimeFailure(position, "failure " + printValue(value));
        }));
        return new Environments(types, values);
    }
    record Leading(List<String> parameters, Parser.Expr body) {}
    static Leading leading(Parser.Expr expression) {
        List<String> parameters = new ArrayList<>();
        while (expression instanceof Parser.Fun function) {
            parameters.add(function.parameter().spelling());
            expression = function.body();
        }
        return new Leading(parameters, expression);
    }
    static String formatBinding(Parser.Binding binding) {
        Leading leading = leading(binding.expression);
        StringJoiner parts = new StringJoiner(" ");
        parts.add(binding.name());
        for (String parameter : leading.parameters())
            parts.add(parameter);
        parts.add("=");
        parts.add(formatExpression(leading.body(), 0));
        return parts.toString();
    }
    static String formatGroup(Parser.Group group) {
        StringJoiner bindings = new StringJoiner(" and ");
        for (Parser.Binding binding : group.bindings())
            bindings.add(formatBinding(binding));
        return (group.recPosition() == null ? "let " : "let rec ") + bindings;
    }
    static boolean endsWithMatch(Parser.Expr expression) {
        return switch (expression) {
            case Parser.Match ignored -> true;
            case Parser.Let let -> endsWithMatch(let.body());
            case Parser.Fun function -> endsWithMatch(function.body());
            case Parser.Conditional conditional -> endsWithMatch(conditional.no());
            default -> false;
        };
    }
    static String printLiteral(String kind, String value) {
        return kind.equals("string") ? quoted(value) : value;
    }
    static String formatPattern(Parser.Pattern pattern) {
        return switch (pattern) {
            case Parser.Wildcard ignored -> "_";
            case Parser.PatternName name -> name.token().spelling();
            case Parser.PatternLiteral literal -> printLiteral(literal.kind(), literal.value());
            case Parser.PatternPair pair ->
                "(" + formatPattern(pair.first()) + ", " + formatPattern(pair.second()) + ")";
            case Parser.PatternList list -> {
                StringJoiner elements = new StringJoiner("; ");
                for (Parser.Pattern child : list.elements())
                    elements.add(formatPattern(child));
                yield "[" + elements + "]";
            }
            case Parser.Cons cons -> {
                String first = formatPattern(cons.first());
                yield(cons.first() instanceof Parser.Cons ? "(" + first + ")" : first) +
                    " :: " + formatPattern(cons.rest());
            }
        };
    }
    static int strength(Parser.Expr expression) {
        if (expression instanceof Parser.Let || expression instanceof Parser.Fun ||
            expression instanceof Parser.Conditional || expression instanceof Parser.Match)
            return 0;
        if (expression instanceof Parser.Binary binary)
            return Parser.OPERATORS.get(binary.operator().spelling()).precedence();
        if (expression instanceof Parser.Negate)
            return 7;
        return expression instanceof Parser.Apply ? 8 : 9;
    }
    static String formatExpression(Parser.Expr expression, int minimum) {
        String text = switch (expression) {
            case Parser.Literal literal -> printLiteral(literal.kind(), literal.value());
            case Parser.Name name -> name.token().spelling();
            case Parser.Fun function -> {
                Leading leading = leading(function);
                yield "fun " + String.join(" ", leading.parameters()) + " -> " +
                    formatExpression(leading.body(), 0);
            }
            case Parser.Apply application ->
                formatExpression(application.function(), 8) + " " +
                    formatExpression(application.argument(), 9);
            case Parser.Binary binary -> {
                Parser.Operator operator = Parser.OPERATORS.get(binary.operator().spelling());
                yield formatExpression(binary.left(),
                                       operator.precedence() + (operator.right() ? 1 : 0)) +
                    " " + binary.operator().spelling() + " " +
                    formatExpression(binary.right(),
                                     operator.precedence() + (operator.right() ? 0 : 1));
            }
            case Parser.Negate negate -> "-" + formatExpression(negate.operand(), 7);
            case Parser.Conditional conditional ->
                "if " + formatExpression(conditional.condition(), 0) + " then " +
                    formatExpression(conditional.yes(), 0) + " else " +
                    formatExpression(conditional.no(), 0);
            case Parser.Pair pair ->
                "(" + formatExpression(pair.first(), 0) + ", " +
                    formatExpression(pair.second(), 0) + ")";
            case Parser.ListExpr list -> {
                StringJoiner elements = new StringJoiner("; ");
                for (Parser.Expr child : list.elements())
                    elements.add(formatExpression(child, 0));
                yield "[" + elements + "]";
            }
            case Parser.Let let ->
                formatGroup(let.group()) + " in " + formatExpression(let.body(), 0);
            case Parser.Match match -> {
                StringJoiner arms = new StringJoiner(" | ");
                for (int i = 0; i < match.arms().size(); i++) {
                    Parser.Arm arm = match.arms().get(i);
                    String body = formatExpression(arm.expression(), 0);
                    if (i + 1 < match.arms().size() && endsWithMatch(arm.expression()))
                        body = "(" + body + ")";
                    arms.add(formatPattern(arm.pattern()) + " -> " + body);
                }
                yield "match " + formatExpression(match.matched(), 0) + " with " + arms;
            }
        };
        return strength(expression) < minimum ? "(" + text + ")" : text;
    }
    static String formatItem(Parser.Item item) {
        return switch (item) {
            case Parser.Signature signature ->
                "val " + signature.name().spelling() + " : " +
                    formatDeclared(signature.declared()) + ";;";
            case Parser.Declaration declaration -> formatGroup(declaration.group()) + ";;";
            case Parser.ExpressionItem expression ->
                formatExpression(expression.expression(), 0) + ";;";
        };
    }
    record CoverageType(String kind, List<CoverageType> children) {}
    record Constructor(String kind, String value) {}
    record CoveragePattern(Constructor constructor, List<CoveragePattern> arguments) {}
    static final CoveragePattern ANY = new CoveragePattern(new Constructor("*", ""), List.of());
    static final Constructor NIL = new Constructor("nil", ""), CONS = new Constructor("cons", ""),
                             PAIR = new Constructor("pair", "");
    static CoverageType coverageType(Unifier.Type type) {
        type = Unifier.resolve(type);
        if (type instanceof Unifier.Variable)
            return new CoverageType("opaque", List.of());
        Unifier.Construct constructor = (Unifier.Construct)type;
        if (constructor.kind().equals("function"))
            return new CoverageType("opaque", List.of());
        List<CoverageType> children = new ArrayList<>();
        for (Unifier.Type child : constructor.children())
            children.add(coverageType(child));
        return new CoverageType(constructor.kind(), List.copyOf(children));
    }
    static CoveragePattern coveragePattern(Parser.Pattern pattern) {
        if (pattern instanceof Parser.Wildcard || pattern instanceof Parser.PatternName)
            return ANY;
        if (pattern instanceof Parser.PatternLiteral literal)
            return new CoveragePattern(new Constructor(literal.kind(), literal.value()), List.of());
        if (pattern instanceof Parser.PatternList list) {
            CoveragePattern result = new CoveragePattern(NIL, List.of());
            for (int i = list.elements().size() - 1; i >= 0; i--)
                result = new CoveragePattern(
                    CONS, List.of(coveragePattern(list.elements().get(i)), result));
            return result;
        }
        if (pattern instanceof Parser.Cons cons)
            return new CoveragePattern(
                CONS, List.of(coveragePattern(cons.first()), coveragePattern(cons.rest())));
        Parser.PatternPair pair = (Parser.PatternPair)pattern;
        return new CoveragePattern(
            PAIR, List.of(coveragePattern(pair.first()), coveragePattern(pair.second())));
    }
    static List<Constructor> constructors(CoverageType type) {
        return switch (type.kind()) {
            case "bool" ->
                List.of(new Constructor("boolean", "false"), new Constructor("boolean", "true"));
            case "list" -> List.of(NIL, CONS);
            case "pair" -> List.of(PAIR);
            default -> List.of();
        };
    }
    static List<CoverageType> constructorArguments(Constructor constructor, CoverageType type) {
        if (constructor.equals(PAIR))
            return type.children();
        if (constructor.equals(CONS))
            return List.of(type.children().getFirst(), type);
        return List.of();
    }
    static <T> List<T> prepend(List<T> first, List<T> rest) {
        List<T> result = new ArrayList<>(first);
        result.addAll(rest);
        return List.copyOf(result);
    }
    static List<List<CoveragePattern>> specialize(List<List<CoveragePattern>> matrix,
                                                  Constructor constructor, int arity) {
        List<List<CoveragePattern>> rows = new ArrayList<>();
        for (List<CoveragePattern> row : matrix) {
            CoveragePattern first = row.getFirst();
            if (first.equals(ANY))
                rows.add(prepend(Collections.nCopies(arity, ANY), row.subList(1, row.size())));
            else if (first.constructor().equals(constructor))
                rows.add(prepend(first.arguments(), row.subList(1, row.size())));
        }
        return List.copyOf(rows);
    }
    record UsefulKey(List<List<CoveragePattern>> matrix, List<CoveragePattern> query,
                     List<CoverageType> types) {}
    static boolean useful(List<List<CoveragePattern>> matrix, List<CoveragePattern> query,
                          List<CoverageType> types, Map<UsefulKey, Boolean> cache) {
        UsefulKey key = new UsefulKey(matrix, query, types);
        Boolean previous = cache.get(key);
        if (previous != null)
            return previous;
        boolean result;
        if (query.isEmpty())
            result = matrix.isEmpty();
        else if (matrix.isEmpty())
            result = true;
        else {
            CoveragePattern first = query.getFirst();
            List<CoveragePattern> remaining = query.subList(1, query.size());
            List<CoverageType> remainingTypes = types.subList(1, types.size());
            if (!first.equals(ANY)) {
                List<CoverageType> arguments =
                    constructorArguments(first.constructor(), types.getFirst());
                result = useful(specialize(matrix, first.constructor(), first.arguments().size()),
                                prepend(first.arguments(), remaining),
                                prepend(arguments, remainingTypes), cache);
            } else {
                List<Constructor> possible = constructors(types.getFirst());
                Set<Constructor> present = new HashSet<>();
                for (List<CoveragePattern> row : matrix)
                    if (!row.getFirst().equals(ANY))
                        present.add(row.getFirst().constructor());
                if (!possible.isEmpty() && present.containsAll(possible)) {
                    result = false;
                    for (Constructor constructor : possible) {
                        List<CoverageType> arguments =
                            constructorArguments(constructor, types.getFirst());
                        if (useful(specialize(matrix, constructor, arguments.size()),
                                   prepend(Collections.nCopies(arguments.size(), ANY), remaining),
                                   prepend(arguments, remainingTypes), cache)) {
                            result = true;
                            break;
                        }
                    }
                } else {
                    List<List<CoveragePattern>> defaults = new ArrayList<>();
                    for (List<CoveragePattern> row : matrix)
                        if (row.getFirst().equals(ANY))
                            defaults.add(List.copyOf(row.subList(1, row.size())));
                    result = useful(List.copyOf(defaults), remaining, remainingTypes, cache);
                }
            }
        }
        cache.put(key, result);
        return result;
    }
    static List<Parser.Expr> children(Parser.Expr expression) {
        return switch (expression) {
            case Parser.Fun function -> List.of(function.body());
            case Parser.Apply application ->
                List.of(application.function(), application.argument());
            case Parser.Binary binary -> List.of(binary.left(), binary.right());
            case Parser.Negate negate -> List.of(negate.operand());
            case Parser.Conditional conditional ->
                List.of(conditional.condition(), conditional.yes(), conditional.no());
            case Parser.Pair pair -> List.of(pair.first(), pair.second());
            case Parser.ListExpr list -> list.elements();
            case Parser.Let let -> {
                List<Parser.Expr> children = new ArrayList<>();
                for (Parser.Binding binding : let.group().bindings())
                    children.add(binding.expression);
                children.add(let.body());
                yield children;
            }
            case Parser.Match match -> {
                List<Parser.Expr> children = new ArrayList<>();
                children.add(match.matched());
                for (Parser.Arm arm : match.arms())
                    children.add(arm.expression());
                yield children;
            }
            default -> List.of();
        };
    }
    static final class Symbol {
        String name;
        Lexer.Position position;
        boolean topLevel, used;
        Symbol(String name, Lexer.Position position, boolean topLevel) {
            this.name = name;
            this.position = position;
            this.topLevel = topLevel;
        }
    }
    record GroupSymbols(Parser.Group group, Set<Symbol> targets) {}
    record Warning(Lexer.Position position, int priority, String message) {}
    static final class StaticChecks {
        List<Symbol> symbols = new ArrayList<>();
        Map<Parser.Expr, Symbol> references = new IdentityHashMap<>();
        List<GroupSymbols> groups = new ArrayList<>();
        List<Warning> warnings = new ArrayList<>();
        Map<Parser.Expr, Unifier.Type> inferred;
        StaticChecks(Map<Parser.Expr, Unifier.Type> inferred) { this.inferred = inferred; }
        Symbol symbol(String name, Lexer.Position position, boolean topLevel) {
            Symbol symbol = new Symbol(name, position, topLevel);
            symbols.add(symbol);
            return symbol;
        }
        void bindPattern(Parser.Pattern pattern, Map<String, Symbol> environment) {
            switch (pattern) {
            case Parser.PatternName name ->
                environment.put(name.token().spelling(),
                                symbol(name.token().spelling(), name.position(), false));
            case Parser.PatternPair pair -> {
                bindPattern(pair.first(), environment);
                bindPattern(pair.second(), environment);
            }
            case Parser.PatternList list -> {
                for (Parser.Pattern child : list.elements())
                    bindPattern(child, environment);
            }
            case Parser.Cons cons -> {
                bindPattern(cons.first(), environment);
                bindPattern(cons.rest(), environment);
            }
            default -> {
            }
            }
        }
        Map<String, Symbol> group(Parser.Group group, Map<String, Symbol> environment,
                                  boolean topLevel) {
            List<Symbol> bound = new ArrayList<>();
            for (Parser.Binding binding : group.bindings())
                bound.add(symbol(binding.name(), binding.position(), topLevel));
            groups.add(new GroupSymbols(group, new HashSet<>(bound)));
            Map<String, Symbol> inner = new HashMap<>(environment);
            for (Symbol symbol : bound)
                inner.put(symbol.name, symbol);
            Map<String, Symbol> right = group.recPosition() == null ? environment : inner;
            for (Parser.Binding binding : group.bindings())
                expression(binding.expression, right);
            return inner;
        }
        void matchWarnings(Parser.Match match) {
            Map<UsefulKey, Boolean> cache = new HashMap<>();
            List<List<CoveragePattern>> matrix = List.of();
            List<CoverageType> types = List.of(coverageType(inferred.get(match.matched())));
            for (int i = 0; i < match.arms().size(); i++) {
                Parser.Pattern pattern = match.arms().get(i).pattern();
                List<CoveragePattern> query = List.of(coveragePattern(pattern));
                if (i > 0 && !useful(matrix, query, types, cache))
                    warnings.add(new Warning(pattern.position(), 2, "this match case is unused"));
                List<List<CoveragePattern>> expanded = new ArrayList<>(matrix);
                expanded.add(query);
                matrix = List.copyOf(expanded);
            }
            if (useful(matrix, List.of(ANY), types, cache))
                warnings.add(new Warning(match.position(), 1, "this match is not exhaustive"));
        }
        void expression(Parser.Expr expression, Map<String, Symbol> environment) {
            if (expression instanceof Parser.Name name) {
                Symbol symbol = environment.get(name.token().spelling());
                references.put(expression, symbol);
                if (symbol != null)
                    symbol.used = true;
                return;
            }
            if (expression instanceof Parser.Fun function) {
                Map<String, Symbol> inner = new HashMap<>(environment);
                String parameter = function.parameter().spelling();
                if (!parameter.equals("_"))
                    inner.put(parameter, symbol(parameter, function.parameter().position(), false));
                expression(function.body(), inner);
                return;
            }
            if (expression instanceof Parser.Let let) {
                expression(let.body(), group(let.group(), environment, false));
                return;
            }
            if (expression instanceof Parser.Match match) {
                expression(match.matched(), environment);
                matchWarnings(match);
                for (Parser.Arm arm : match.arms()) {
                    Map<String, Symbol> inner = new HashMap<>(environment);
                    bindPattern(arm.pattern(), inner);
                    expression(arm.expression(), inner);
                }
                return;
            }
            for (Parser.Expr child : children(expression))
                expression(child, environment);
        }
        boolean hasReference(Parser.Expr expression, Set<Symbol> targets) {
            if (targets.contains(references.get(expression)))
                return true;
            for (Parser.Expr child : children(expression))
                if (hasReference(child, targets))
                    return true;
            return false;
        }
        void tailCalls(Parser.Expr expression, boolean tail, Set<Symbol> targets,
                       List<Boolean> calls) {
            if (expression instanceof Parser.Name) {
                if (targets.contains(references.get(expression)))
                    calls.add(false);
                return;
            }
            if (expression instanceof Parser.Apply) {
                List<Parser.Expr> arguments = new ArrayList<>();
                Parser.Expr function = expression;
                while (function instanceof Parser.Apply application) {
                    arguments.add(application.argument());
                    function = application.function();
                }
                if (function instanceof Parser.Name && targets.contains(references.get(function)))
                    calls.add(tail);
                else
                    tailCalls(function, false, targets, calls);
                for (int i = arguments.size() - 1; i >= 0; i--)
                    tailCalls(arguments.get(i), false, targets, calls);
                return;
            }
            if (expression instanceof Parser.Conditional conditional) {
                tailCalls(conditional.condition(), false, targets, calls);
                tailCalls(conditional.yes(), tail, targets, calls);
                tailCalls(conditional.no(), tail, targets, calls);
                return;
            }
            if (expression instanceof Parser.Match match) {
                tailCalls(match.matched(), false, targets, calls);
                for (Parser.Arm arm : match.arms())
                    tailCalls(arm.expression(), tail, targets, calls);
                return;
            }
            if (expression instanceof Parser.Let let) {
                for (Parser.Binding binding : let.group().bindings())
                    tailCalls(binding.expression, false, targets, calls);
                tailCalls(let.body(), tail, targets, calls);
                return;
            }
            if (expression instanceof Parser.Binary binary &&
                Set.of("&&", "||").contains(binary.operator().spelling())) {
                tailCalls(binary.left(), false, targets, calls);
                tailCalls(binary.right(), tail, targets, calls);
                return;
            }
            for (Parser.Expr child : children(expression))
                tailCalls(child, false, targets, calls);
        }
        List<Warning> item(Parser.Item item, Set<String> environmentNames) {
            Map<String, Symbol> environment = new HashMap<>();
            for (String name : environmentNames)
                environment.put(name, null);
            if (item instanceof Parser.Declaration declaration)
                group(declaration.group(), environment, true);
            else
                expression(((Parser.ExpressionItem)item).expression(), environment);
            for (GroupSymbols entry : groups) {
                Parser.Group group = entry.group();
                if (group.recPosition() == null)
                    continue;
                boolean referenced = false;
                for (Parser.Binding binding : group.bindings())
                    if (hasReference(binding.expression, entry.targets()))
                        referenced = true;
                if (!referenced)
                    warnings.add(new Warning(group.recPosition(), 3, "unused rec flag"));
                for (Parser.Binding binding : group.bindings()) {
                    List<Boolean> calls = new ArrayList<>();
                    tailCalls(leading(binding.expression).body(), true, entry.targets(), calls);
                    binding.classification = calls.isEmpty() ? ""
                                             : calls.stream().allMatch(Boolean::booleanValue)
                                                 ? "tail recursive"
                                                 : "recursive";
                }
            }
            for (Symbol symbol : symbols)
                if (!symbol.topLevel && !symbol.used && !symbol.name.startsWith("_"))
                    warnings.add(
                        new Warning(symbol.position, 4, "unused variable '" + symbol.name + "'"));
            warnings.sort(
                Comparator.comparing(Warning::position).thenComparingInt(Warning::priority));
            return warnings;
        }
    }
    static String classification(Parser.Binding binding) {
        return binding.classification.isEmpty() ? "" : " (" + binding.classification + ")";
    }
    static String syntaxError(Lexer.Token token) {
        return token.kind().equals("invalid") ? token.value()
        : token.kind().equals("EOF")          ? "unexpected end of file"
                                              : "unexpected '" + token.spelling() + "'";
    }
    static final class Counts {
        int items, bindings, syntax, type, runtime, warnings, calls;
        public String toString() {
            return "items=" + items + " bindings=" + bindings + " syntax=" + syntax +
                " type=" + type + " runtime=" + runtime + " warnings=" + warnings +
                " calls=" + calls;
        }
    }
    static final class Reports {
        Map<String, List<String>> sources = new LinkedHashMap<>();
        Map<String, Counts> statistics = new LinkedHashMap<>();
        List<String> lines = new ArrayList<>();
        String currentFile;
        Reports(Map<String, String> sources) {
            for (var entry : sources.entrySet()) {
                this.sources.put(
                    entry.getKey(),
                    entry.getValue().isEmpty()
                        ? List.of()
                        : Arrays.asList(entry.getValue()
                                            .substring(0, entry.getValue().length() - 1)
                                            .split("\n", -1)));
                statistics.put(entry.getKey(), new Counts());
            }
        }
        void report(String kind, Lexer.Position position, String message) {
            Counts counts = statistics.get(currentFile);
            switch (kind) {
            case "syntax error" -> counts.syntax++;
            case "type error" -> counts.type++;
            case "runtime error" -> counts.runtime++;
            case "warning" -> counts.warnings++;
            }
            lines.add(position.file() + ":" + position.line() + ":" + position.column() + ": " +
                      kind + ": " + message);
            List<String> source = sources.get(position.file());
            if (position.line() <= source.size()) {
                lines.add("    " + source.get(position.line() - 1));
                lines.add(" ".repeat(position.column() + 3) + "^");
            }
        }
        void finish() {
            lines.add("== summary ==");
            for (var entry : statistics.entrySet())
                lines.add(entry.getKey() + ": " + entry.getValue());
        }
    }
    static final class MiniMl {
        Map<String, String> sources;
        Map<String, Unifier.Scheme> typeEnvironment;
        Map<String, Evaluator.Value> valueEnvironment;
        Reports reports;
        List<String> types = new ArrayList<>(), values = new ArrayList<>(),
                     formatted = new ArrayList<>();
        MiniMl(Map<String, String> sources) {
            this.sources = sources;
            Environments builtins = builtins();
            typeEnvironment = builtins.types();
            valueEnvironment = builtins.values();
            reports = new Reports(sources);
        }
        void unusedSignature(Parser.Signature signature) {
            reports.report("warning", signature.name().position(),
                           "signature for '" + signature.name().spelling() + "' is never used");
        }
        void writeTypes(Parser.Item item, Unifier.Type inferred, List<Parser.Binding> local) {
            if (item instanceof Parser.Declaration declaration)
                for (Parser.Binding binding : declaration.group().bindings())
                    types.add(binding.name() + " : " +
                              new TypePrinter().print(binding.scheme.value()) +
                              classification(binding));
            else
                types.add("- : " + new TypePrinter().print(inferred));
            List<Parser.Binding> ordered = new ArrayList<>(local);
            ordered.sort(Comparator.comparing(Parser.Binding::position));
            for (Parser.Binding binding : ordered) {
                Lexer.Position position = binding.position();
                types.add(
                    "  " + binding.name() + " (" + position.line() + ":" + position.column() +
                    ") : " +
                    new TypePrinter(binding.scheme.quantified()).print(binding.scheme.value()) +
                    classification(binding));
            }
        }
        void processItem(Parser.Item item, Map<String, Parser.Signature> pending,
                         Evaluator evaluator, Counts counts) {
            formatted.add(formatItem(item));
            if (item instanceof Parser.Signature signature) {
                String name = signature.name().spelling();
                Parser.Signature previous = pending.put(name, signature);
                if (previous != null)
                    unusedSignature(previous);
                return;
            }
            List<Parser.Signature> signatures = new ArrayList<>();
            if (item instanceof Parser.Declaration declaration)
                for (Parser.Binding binding : declaration.group().bindings())
                    signatures.add(pending.remove(binding.name()));
            Inference inference = new Inference();
            Unifier.Type inferred = null;
            try {
                if (item instanceof Parser.Declaration declaration) {
                    inference.group(declaration.group(), typeEnvironment, false);
                    checkSignatures(declaration.group(), signatures);
                } else
                    inferred = inference.expression(((Parser.ExpressionItem)item).expression(),
                                                    typeEnvironment);
            } catch (Inference.Error error) {
                reports.report("type error", error.position, typeError(error));
                return;
            }
            List<Warning> warnings =
                new StaticChecks(inference.inferred).item(item, typeEnvironment.keySet());
            writeTypes(item, inferred, inference.localBindings);
            for (Warning warning : warnings)
                reports.report("warning", warning.position(), warning.message());
            Map<String, Evaluator.Value> environment = null;
            Evaluator.Value value = null;
            try {
                if (item instanceof Parser.Declaration declaration)
                    environment = evaluator.group(declaration.group(), valueEnvironment);
                else
                    value = evaluator.expression(((Parser.ExpressionItem)item).expression(),
                                                 valueEnvironment);
            } catch (Evaluator.RuntimeFailure error) {
                reports.report("runtime error", error.position, error.getMessage());
                return;
            }
            if (item instanceof Parser.Declaration declaration) {
                Map<String, Unifier.Scheme> newTypes = new HashMap<>(typeEnvironment);
                for (Parser.Binding binding : declaration.group().bindings()) {
                    values.add(binding.name() + " = " +
                               printValue(environment.get(binding.name())));
                    newTypes.put(binding.name(), binding.scheme);
                }
                typeEnvironment = newTypes;
                valueEnvironment = environment;
                counts.bindings += declaration.group().bindings().size();
            } else
                values.add("- = " + printValue(value));
        }
        void processFile(String file) {
            reports.currentFile = file;
            Counts counts = reports.statistics.get(file);
            types.add("== " + file + " ==");
            values.add("== " + file + " ==");
            formatted.add("(* " + file + " *)");
            Map<String, Parser.Signature> pending = new HashMap<>();
            Evaluator evaluator = new Evaluator();
            Parser parser = new Parser(Lexer.tokenize(sources.get(file), file));
            while (!parser.peek().kind().equals("EOF")) {
                counts.items++;
                Parser.Item item;
                try {
                    item = parser.item();
                } catch (Parser.SyntaxFailure failure) {
                    reports.report("syntax error", failure.token.position(),
                                   syntaxError(failure.token));
                    parser.recover();
                    continue;
                }
                processItem(item, pending, evaluator, counts);
            }
            List<Parser.Signature> unused = new ArrayList<>(pending.values());
            unused.sort(Comparator.comparing(signature -> signature.name().position()));
            for (Parser.Signature signature : unused)
                unusedSignature(signature);
            counts.calls = evaluator.calls;
        }
        void run() throws Exception {
            for (String file : sources.keySet())
                processFile(file);
            reports.finish();
            Files.createDirectories(Path.of("output"));
            write("types.txt", types);
            write("values.txt", values);
            write("errors.txt", reports.lines);
            write("formatted.ml", formatted);
        }
    }
    static void write(String file, List<String> lines) throws Exception {
        Files.writeString(Path.of("output", file), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    public static void main(String[] args) throws Exception {
        Map<String, String> sources = new LinkedHashMap<>();
        for (String file : List.of("prelude.ml", "program.ml"))
            sources.put(file, Files.readString(Path.of("input", file), StandardCharsets.US_ASCII));
        new MiniMl(sources).run();
    }
}
