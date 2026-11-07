import java.util.*;
final class Evaluator {
    sealed interface Value permits IntegerValue, BooleanValue, StringValue, PairValue, ListValue,
        Closure, Builtin {}
    record IntegerValue(int value) implements Value {}
    record BooleanValue(boolean value) implements Value {}
    record StringValue(String value) implements Value {}
    record PairValue(Value first, Value second) implements Value {}
    record ListValue(List<Value> elements) implements Value {
        ListValue { elements = List.copyOf(elements); }
    }
    static final class Closure implements Value {
        String parameter;
        Parser.Expr body;
        Map<String, Value> environment;
        Closure(String parameter, Parser.Expr body, Map<String, Value> environment) {
            this.parameter = parameter;
            this.body = body;
            this.environment = environment;
        }
    }
    @FunctionalInterface
    interface Behavior {
        Value apply(Value value, Lexer.Position position);
    }
    record Builtin(Behavior behavior) implements Value {}
    static final class RuntimeFailure extends RuntimeException {
        Lexer.Position position;
        RuntimeFailure(Lexer.Position position, String message) {
            super(message);
            this.position = position;
        }
    }
    static IntegerValue checked(long value, Lexer.Position position) {
        if (value < Integer.MIN_VALUE || value > Integer.MAX_VALUE)
            throw new RuntimeFailure(position, "integer overflow");
        return new IntegerValue((int)value);
    }
    static Value literal(String kind, String value) {
        return switch (kind) {
            case "integer" -> new IntegerValue(Integer.parseInt(value));
            case "boolean" -> new BooleanValue(Boolean.parseBoolean(value));
            default -> new StringValue(value);
        };
    }
    static int compare(Value first, Value second, Lexer.Position position) {
        if (first instanceof Closure || first instanceof Builtin)
            throw new RuntimeFailure(position, "functional value compared");
        if (first instanceof IntegerValue a)
            return Integer.compare(a.value(), ((IntegerValue)second).value());
        if (first instanceof BooleanValue a)
            return Boolean.compare(a.value(), ((BooleanValue)second).value());
        if (first instanceof StringValue a)
            return a.value().compareTo(((StringValue)second).value());
        if (first instanceof PairValue a) {
            PairValue b = (PairValue)second;
            int order = compare(a.first(), b.first(), position);
            return order == 0 ? compare(a.second(), b.second(), position) : order;
        }
        List<Value> a = ((ListValue)first).elements(), b = ((ListValue)second).elements();
        for (int i = 0; i < Math.min(a.size(), b.size()); i++) {
            int order = compare(a.get(i), b.get(i), position);
            if (order != 0)
                return order;
        }
        return Integer.compare(a.size(), b.size());
    }
    static Value binary(String operator, Value first, Value second, Lexer.Position position) {
        if (Set.of("+", "-", "*", "/", "mod").contains(operator)) {
            long a = ((IntegerValue)first).value(), b = ((IntegerValue)second).value();
            if ((operator.equals("/") || operator.equals("mod")) && b == 0)
                throw new RuntimeFailure(position, "division by zero");
            return checked(switch (operator) {
                case "+" -> a + b;
                case "-" -> a - b;
                case "*" -> a *b;
                case "/" -> a / b;
                default -> a % b;
            }, position);
        }
        if (operator.equals("^"))
            return new StringValue(((StringValue)first).value() + ((StringValue)second).value());
        if (operator.equals("::")) {
            List<Value> values = new ArrayList<>();
            values.add(first);
            values.addAll(((ListValue)second).elements());
            return new ListValue(values);
        }
        int order = compare(first, second, position);
        return new BooleanValue(switch (operator) {
            case "=" -> order == 0;
            case "<>" -> order != 0;
            case "<" -> order < 0;
            case ">" -> order > 0;
            case "<=" -> order <= 0;
            default -> order >= 0;
        });
    }
    static boolean matches(Parser.Pattern pattern, Value value, Map<String, Value> bindings) {
        if (pattern instanceof Parser.Wildcard)
            return true;
        if (pattern instanceof Parser.PatternName name) {
            bindings.put(name.token().spelling(), value);
            return true;
        }
        if (pattern instanceof Parser.PatternLiteral constant)
            return literal(constant.kind(), constant.value()).equals(value);
        if (pattern instanceof Parser.Cons cons) {
            List<Value> list = ((ListValue)value).elements();
            return !list.isEmpty() && matches(cons.first(), list.getFirst(), bindings) &&
                matches(cons.rest(), new ListValue(list.subList(1, list.size())), bindings);
        }
        if (pattern instanceof Parser.PatternList list) {
            List<Value> values = ((ListValue)value).elements();
            if (values.size() != list.elements().size())
                return false;
            for (int i = 0; i < values.size(); i++)
                if (!matches(list.elements().get(i), values.get(i), bindings))
                    return false;
            return true;
        }
        Parser.PatternPair pair = (Parser.PatternPair)pattern;
        PairValue values = (PairValue)value;
        return matches(pair.first(), values.first(), bindings) &&
            matches(pair.second(), values.second(), bindings);
    }
    int calls;
    Value expression(Parser.Expr expression, Map<String, Value> environment) {
        return switch (expression) {
            case Parser.Literal literal -> literal(literal.kind(), literal.value());
            case Parser.Name name -> environment.get(name.token().spelling());
            case Parser.Fun function ->
                new Closure(function.parameter().spelling(), function.body(),
                            new HashMap<>(environment));
            case Parser.Apply application -> {
                Value function = expression(application.function(), environment),
                      argument = expression(application.argument(), environment);
                calls++;
                if (function instanceof Builtin builtin)
                    yield builtin.behavior().apply(argument, application.position());
                Closure closure = (Closure)function;
                Map<String, Value> inner = new HashMap<>(closure.environment);
                if (!closure.parameter.equals("_"))
                    inner.put(closure.parameter, argument);
                yield expression(closure.body, inner);
            }
            case Parser.Binary binary -> {
                Value first = expression(binary.left(), environment);
                String operator = binary.operator().spelling();
                if (operator.equals("&&"))
                    yield((BooleanValue)first).value() ? expression(binary.right(), environment)
                                                       : new BooleanValue(false);
                if (operator.equals("||"))
                    yield((BooleanValue)first).value() ? new BooleanValue(true)
                                                       : expression(binary.right(), environment);
                Value second = expression(binary.right(), environment);
                yield binary(operator, first, second, binary.operator().position());
            }
            case Parser.Negate negate ->
                checked(-(long)((IntegerValue)expression(negate.operand(), environment)).value(),
                        negate.operator().position());
            case Parser.Conditional conditional ->
                expression(((BooleanValue)expression(conditional.condition(), environment)).value()
                               ? conditional.yes()
                               : conditional.no(),
                           environment);
            case Parser.Pair pair -> {
                Value first = expression(pair.first(), environment),
                      second = expression(pair.second(), environment);
                yield new PairValue(first, second);
            }
            case Parser.ListExpr list -> {
                List<Value> values = new ArrayList<>();
                for (Parser.Expr child : list.elements())
                    values.add(expression(child, environment));
                yield new ListValue(values);
            }
            case Parser.Match match -> {
                Value value = expression(match.matched(), environment);
                Value result = null;
                for (Parser.Arm arm : match.arms()) {
                    Map<String, Value> bindings = new HashMap<>();
                    if (matches(arm.pattern(), value, bindings)) {
                        Map<String, Value> inner = new HashMap<>(environment);
                        inner.putAll(bindings);
                        result = expression(arm.expression(), inner);
                        break;
                    }
                }
                if (result == null)
                    throw new RuntimeFailure(match.position(), "match failure");
                yield result;
            }
            case Parser.Let let -> expression(let.body(), group(let.group(), environment));
        };
    }
    Map<String, Value> group(Parser.Group group, Map<String, Value> environment) {
        Map<String, Value> result = new HashMap<>(environment);
        if (group.recPosition() != null)
            for (Parser.Binding binding : group.bindings()) {
                Parser.Fun function = (Parser.Fun)binding.expression;
                result.put(binding.name(),
                           new Closure(function.parameter().spelling(), function.body(), result));
            }
        else {
            List<Value> values = new ArrayList<>();
            for (Parser.Binding binding : group.bindings())
                values.add(expression(binding.expression, environment));
            for (int i = 0; i < values.size(); i++)
                result.put(group.bindings().get(i).name(), values.get(i));
        }
        return result;
    }
}
