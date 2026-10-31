import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
public final class Main {
    static final Set<String> SPECIAL =
        Set.of("FILENAME", "FNR", "FS", "NF", "NR", "OFS", "ORS", "SUBSEP");
    record Binding(Parser.Function scope, String name) {}
    record StaticError(Lexer.Position pos, int priority, String message) {}
    static final class StaticIssue extends RuntimeException {
        final Lexer.Position pos;
        StaticIssue(Lexer.Position pos, String message) {
            super(message);
            this.pos = pos;
        }
    }
    static List<Parser.Node> children(Parser.Node node) {
        List<Parser.Node> result = new ArrayList<>();
        switch (node) {
        case Parser.Function f -> {
            result.addAll(f.parameters);
            result.add(f.body);
        }
        case Parser.Rule r -> {
            result.addAll(r.patterns);
            result.add(r.action);
        }
        case Parser.ArrayAccess a -> result.addAll(a.indexes());
        case Parser.Field f -> result.add(f.index());
        case Parser.Paren p -> result.add(p.expression());
        case Parser.Assignment a -> {
            result.add(a.location());
            result.add(a.value());
        }
        case Parser.Increment i -> result.add(i.location());
        case Parser.Conditional c -> {
            result.add(c.condition());
            result.add(c.first());
            result.add(c.second());
        }
        case Parser.Unary u -> result.add(u.operand());
        case Parser.Membership m -> {
            result.addAll(m.indexes());
            result.add(m.array());
        }
        case Parser.Binary b -> {
            result.add(b.left());
            result.add(b.right());
        }
        case Parser.Call c -> result.addAll(c.arguments());
        case Parser.Builtin b -> result.addAll(b.arguments());
        case Parser.Getline g -> {
            result.add(g.target());
            result.add(g.filename());
        }
        case Parser.Block b -> result.addAll(b.statements());
        case Parser.ExpressionStatement e -> result.add(e.expression());
        case Parser.Output o -> {
            result.addAll(o.arguments());
            result.add(o.filename());
        }
        case Parser.If i -> {
            result.add(i.condition());
            result.add(i.first());
            result.add(i.second());
        }
        case Parser.While w -> {
            result.add(w.condition());
            result.add(w.body());
        }
        case Parser.DoWhile d -> {
            result.add(d.body());
            result.add(d.condition());
        }
        case Parser.For f -> {
            result.add(f.initial());
            result.add(f.condition());
            result.add(f.update());
            result.add(f.body());
        }
        case Parser.ForIn f -> {
            result.add(f.variable());
            result.add(f.array());
            result.add(f.body());
        }
        case Parser.Delete d -> {
            result.add(d.array());
            if (d.indexes() != null)
                result.addAll(d.indexes());
        }
        case Parser.TransferStatement t -> result.add(t.value());
        default -> {
        }
        }
        result.removeIf(Objects::isNull);
        return result;
    }
    static final class Analysis {
        final List<Parser.Item> items;
        final List<Parser.Function> functions = new ArrayList<>();
        final List<Parser.Rule> rules = new ArrayList<>();
        final Map<String, Parser.Function> functionTable = new HashMap<>();
        final Set<String> globals = new TreeSet<>(SPECIAL);
        final Set<Binding> bindings = new HashSet<>(), arrays = new HashSet<>();
        final Map<Parser.Node, Binding> resolved = new IdentityHashMap<>();
        final Map<Parser.Call, Parser.Function> targets = new IdentityHashMap<>();
        final Set<Integer> statementLines = new TreeSet<>();
        final List<Parser.Node> nodes = new ArrayList<>();
        final List<StaticError> errors = new ArrayList<>();
        Analysis(List<Parser.Item> items) {
            this.items = items;
            for (String name : SPECIAL)
                bindings.add(new Binding(null, name));
            for (Parser.Item item : items) {
                if (item instanceof Parser.Function f)
                    functions.add(f);
                else
                    rules.add((Parser.Rule)item);
            }
        }
        void error(Lexer.Position pos, int priority, String message) {
            errors.add(new StaticError(pos, priority, message));
        }
        void resolve(Parser.Node node, String name, Parser.Function function) {
            boolean local = function != null && function.parameterNames.contains(name);
            Binding binding = new Binding(local ? function : null, name);
            resolved.put(node, binding);
            bindings.add(binding);
            if (!local)
                globals.add(name);
            if (functionTable.containsKey(name))
                error(node.pos(), 2, "function " + name + " used as variable");
        }
        void collect(Parser.Node node, Parser.Function function) {
            nodes.add(node);
            if (node instanceof Parser.Stmt && !(node instanceof Parser.Block) &&
                !(node instanceof Parser.Empty))
                statementLines.add(node.pos().line());
            if (node instanceof Parser.Variable v)
                resolve(v, v.name(), function);
            else if (node instanceof Parser.ArrayAccess a)
                resolve(a, a.name(), function);
            else if (node instanceof Parser.Call call) {
                Parser.Function target = functionTable.get(call.name());
                if (target == null)
                    error(call.pos(), 3, "undefined function " + call.name());
                else {
                    targets.put(call, target);
                    if (call.arguments().size() > target.parameters.size())
                        error(call.pos(), 4, "too many arguments to " + call.name());
                }
            }
            for (Parser.Node child : children(node))
                collect(child, function);
        }
        Binding root(Map<Binding, Binding> parents, Binding binding) {
            Binding parent = parents.get(binding);
            if (!parent.equals(binding)) {
                parent = root(parents, parent);
                parents.put(binding, parent);
            }
            return parent;
        }
        Analysis prepare() {
            for (Parser.Function function : functions) {
                if (functionTable.putIfAbsent(function.name, function) != null)
                    error(function.namePos, 0, "function " + function.name + " redefined");
                for (Parser.Variable parameter : function.parameters)
                    if (!function.parameterNames.add(parameter.name()))
                        error(parameter.pos(), 1, "duplicate parameter " + parameter.name());
            }
            for (Parser.Item item : items)
                collect(item, item instanceof Parser.Function f ? f : null);
            if (!errors.isEmpty()) {
                errors.sort(Comparator.comparing(StaticError::pos)
                                .thenComparingInt(StaticError::priority)
                                .thenComparing(StaticError::message));
                StaticError first = errors.getFirst();
                throw new StaticIssue(first.pos(), first.message());
            }
            Map<Binding, Binding> parents = new HashMap<>();
            for (Binding binding : bindings)
                parents.put(binding, binding);
            for (Parser.Node node : nodes) {
                if (node instanceof Parser.ArrayAccess)
                    arrays.add(resolved.get(node));
                else if (node instanceof Parser.Membership m)
                    arrays.add(resolved.get(m.array()));
                else if (node instanceof Parser.Delete d)
                    arrays.add(resolved.get(d.array()));
                else if (node instanceof Parser.ForIn f)
                    arrays.add(resolved.get(f.array()));
                else if (node instanceof Parser.Builtin b && b.name().equals("split"))
                    arrays.add(resolved.get(b.arguments().get(1)));
                else if (node instanceof Parser.Call call) {
                    Parser.Function target = targets.get(call);
                    for (int i = 0; i < call.arguments().size(); i++)
                        if (call.arguments().get(i) instanceof Parser.Variable variable)
                            parents.put(root(parents, resolved.get(variable)),
                                        root(parents, resolved.get(target.parameters.get(i))));
                }
            }
            Set<Binding> arrayRoots = new HashSet<>();
            for (Binding binding : arrays)
                arrayRoots.add(root(parents, binding));
            arrays.clear();
            for (Binding binding : bindings)
                if (arrayRoots.contains(root(parents, binding)))
                    arrays.add(binding);
            return this;
        }
    }
    static ValuesFields.Value number(int value) { return ValuesFields.number(value); }
    static ValuesFields.Value string(String text) { return ValuesFields.string(text); }
    static int numeric(ValuesFields.Value value) { return ValuesFields.numeric(value); }
    static String text(ValuesFields.Value value) { return ValuesFields.text(value); }
    static boolean truth(ValuesFields.Value value) { return ValuesFields.truth(value); }
    static ValuesFields.Value arithmetic(String operator, ValuesFields.Value first,
                                         ValuesFields.Value second, Lexer.Position pos) {
        int a = numeric(first), b = numeric(second);
        return number(switch (operator) {
            case "/", "%" -> {
                if (b == 0)
                    throw new Builtins.RuntimeIssue(pos, "division by zero");
                yield operator.equals("/") ? a / b : a % b;
            }
            case "^" -> {
                if (b < 0)
                    throw new Builtins.RuntimeIssue(pos, "negative exponent");
                int result = 1, base = a, power = b;
                while (power > 0) {
                    if ((power & 1) != 0)
                        result *= base;
                    power >>= 1;
                    if (power > 0)
                        base *= base;
                }
                yield result;
            }
            case "+" -> a + b;
            case "-" -> a - b;
            default -> a *b;
        });
    }
    enum Flow { NEXT, BREAK, CONTINUE, EXIT, RETURN }
    static final class Transfer extends RuntimeException {
        final Flow flow;
        final ValuesFields.Value value;
        Transfer(Flow flow) { this(flow, ValuesFields.UNINITIALIZED); }
        Transfer(Flow flow, ValuesFields.Value value) {
            this.flow = flow;
            this.value = value;
        }
    }
    static final class Cell {
        ValuesFields.Value scalar = ValuesFields.UNINITIALIZED;
        final Map<String, ValuesFields.Value> array;
        Cell(boolean array) { this.array = array ? new HashMap<>() : null; }
        Cell(ValuesFields.Value value) {
            scalar = value;
            array = null;
        }
    }
    sealed interface Location permits VariableLocation, ArrayLocation, FieldLocation {}
    record VariableLocation(Binding binding) implements Location {}
    record ArrayLocation(Map<String, ValuesFields.Value> array, String key) implements Location {}
    record FieldLocation(int index) implements Location {}
    static final class Engine {
        final Analysis analysis;
        final Streams.Arguments arguments;
        final Set<String> globalNames;
        final Map<String, Cell> globals = new HashMap<>();
        final Deque<Map<String, Cell>> locals = new ArrayDeque<>();
        final ValuesFields.Record record;
        final Streams streams = new Streams();
        final TreeMap<Integer, Integer> lines = new TreeMap<>();
        String phase = "BEGIN";
        int exitStatus, operandIndex, inputIndex;
        Streams.Operand current;
        List<String> inputLines = List.of();
        Builtins.RuntimeIssue error;
        Engine(Analysis analysis, Streams.Arguments arguments) {
            this.analysis = analysis;
            this.arguments = arguments;
            globalNames = new TreeSet<>(analysis.globals);
            for (String name : globalNames)
                globals.put(name, new Cell(analysis.arrays.contains(new Binding(null, name))));
            for (String name : List.of("NR", "FNR", "NF"))
                globals.put(name, new Cell(number(0)));
            globals.put("FILENAME", new Cell(string("")));
            globals.put("FS", new Cell(string(" ")));
            globals.put("OFS", new Cell(string(" ")));
            globals.put("ORS", new Cell(string("\n")));
            globals.put("SUBSEP", new Cell(string(String.valueOf((char)28))));
            record
            = new ValuesFields.Record(this::global);
            for (int line : analysis.statementLines)
                lines.put(line, 0);
        }
        Cell cell(Binding binding) {
            return binding.scope() == null ? globals.get(binding.name())
                                           : locals.peek().get(binding.name());
        }
        ValuesFields.Value variable(Binding binding) {
            return binding.scope() == null && binding.name().equals("NF")
                ? number(record.fields.size())
                : cell(binding).scalar;
        }
        ValuesFields.Value global(String name) { return variable(new Binding(null, name)); }
        Map<String, ValuesFields.Value> array(Parser.Node node) {
            return cell(analysis.resolved.get(node)).array;
        }
        void assignInput(String name, String text) {
            globalNames.add(name);
            globals.put(name, new Cell(ValuesFields.input(text)));
        }
        String subscript(List<Parser.Expr> expressions) throws IOException {
            List<String> values = new ArrayList<>();
            for (Parser.Expr expression : expressions)
                values.add(text(evaluate(expression)));
            return String.join(text(global("SUBSEP")), values);
        }
        Location location(Parser.Expr node) throws IOException {
            if (node instanceof Parser.Variable)
                return new VariableLocation(analysis.resolved.get(node));
            if (node instanceof Parser.ArrayAccess access) {
                String key = subscript(access.indexes());
                return new ArrayLocation(array(access), key);
            }
            Parser.Field field = (Parser.Field)node;
            int index = numeric(evaluate(field.index()));
            if (index < 0)
                throw new Builtins.RuntimeIssue(field.pos(), "negative field index");
            return new FieldLocation(index);
        }
        ValuesFields.Value read(Location location) {
            return switch (location) {
                case VariableLocation v -> variable(v.binding());
                case FieldLocation f -> record.read(f.index()) ;
                case ArrayLocation a ->
                    a.array().computeIfAbsent(a.key(), key -> ValuesFields.UNINITIALIZED);
            };
        }
        void store(Location location, ValuesFields.Value value, Lexer.Position pos) {
            switch (location) {
            case FieldLocation f -> record.write(f.index(), value) ;
            case ArrayLocation a -> a.array().put(a.key(), value);
            case VariableLocation v -> {
                Binding binding = v.binding();
                if (binding.scope() == null && binding.name().equals("NF")) {
                    int size = numeric(value);
                    if (size < 0)
                        throw new Builtins.RuntimeIssue(pos, "negative NF");
                    record.resize(size)
                    ;
                } else
                    cell(binding).scalar = value;
            }
            }
        }
        ValuesFields.Value evaluate(Parser.Expr expression) throws IOException {
            return switch (expression) {
                case Parser.Literal literal -> literal.value();
                case Parser.Variable v -> read(location(v));
                case Parser.ArrayAccess a -> read(location(a));
                case Parser.Field f -> read(location(f));
                case Parser.Paren p -> evaluate(p.expression());
                case Parser.Assignment a -> {
                    Location location = location(a.location());
                    ValuesFields.Value value = evaluate(a.value());
                    if (!a.operator().equals("="))
                        value = arithmetic(a.operator().substring(0, 1), read(location), value,
                                           a.pos());
                    store(location, value, a.pos());
                    yield read(location);
                }
                case Parser.Increment i -> {
                    Location location = location(i.location());
                    int old = numeric(read(location)), value = old + i.delta();
                    store(location, number(value), i.pos());
                    yield number(i.prefix() ? value : old);
                }
                case Parser.Conditional c ->
                    evaluate(truth(evaluate(c.condition())) ? c.first() : c.second());
                case Parser.Unary u -> {
                    ValuesFields.Value value = evaluate(u.operand());
                    yield number(u.operator().equals("!")   ? (truth(value) ? 0 : 1)
                                 : u.operator().equals("-") ? -numeric(value)
                                                            : numeric(value));
                }
                case Parser.Membership m -> {
                    String key = subscript(m.indexes());
                    yield number(array(m.array()).containsKey(key) ? 1 : 0);
                }
                case Parser.Binary binary -> binary(binary);
                case Parser.Call call -> call(call);
                case Parser.Builtin builtin -> builtin(builtin);
                case Parser.Getline getline -> getline(getline);
            };
        }
        ValuesFields.Value binary(Parser.Binary binary) throws IOException {
            ValuesFields.Value first = evaluate(binary.left());
            String operator = binary.operator();
            if (operator.equals("||") && truth(first))
                return number(1);
            if (operator.equals("&&") && !truth(first))
                return number(0);
            ValuesFields.Value second = evaluate(binary.right());
            if (operator.equals("&&") || operator.equals("||"))
                return number(truth(second) ? 1 : 0);
            if (operator.equals("concat"))
                return string(text(first) + text(second));
            if (Parser.COMPARISONS.contains(operator)) {
                int order = ValuesFields.compare(first, second);
                return number((switch (operator) {
                    case "<" -> order < 0;
                    case "<=" -> order <= 0;
                    case "==" -> order == 0;
                    case "!=" -> order != 0;
                    case ">=" -> order >= 0;
                    default -> order > 0;
                })
                                  ? 1
                                  : 0);
            }
            return arithmetic(operator, first, second, binary.pos());
        }
        ValuesFields.Value call(Parser.Call call) throws IOException {
            Parser.Function function = analysis.targets.get(call);
            Map<String, Cell> local = new HashMap<>();
            for (int i = 0; i < function.parameters.size(); i++) {
                Parser.Variable parameter = function.parameters.get(i);
                boolean isArray = analysis.arrays.contains(analysis.resolved.get(parameter));
                Cell value;
                if (i < call.arguments().size()) {
                    Parser.Expr argument = call.arguments().get(i);
                    if (isArray)
                        value = cell(analysis.resolved.get(argument));
                    else
                        value = new Cell(evaluate(argument));
                } else
                    value = new Cell(isArray);
                local.put(parameter.name(), value);
            }
            function.calls++;
            function.active++;
            function.depth = Math.max(function.depth, function.active);
            locals.push(local);
            try {
                statement(function.body);
            } catch (Transfer transfer) {
                if (transfer.flow == Flow.RETURN)
                    return transfer.value;
                throw transfer;
            } finally {
                locals.pop();
                function.active--;
            }
            return ValuesFields.UNINITIALIZED;
        }
        ValuesFields.Value builtin(Parser.Builtin builtin) throws IOException {
            List<Parser.Expr> args = builtin.arguments();
            String name = builtin.name();
            if (name.equals("length")) {
                if (args.isEmpty())
                    return number(text(record.zero).length());
                Parser.Expr argument = args.getFirst();
                if (argument instanceof Parser.Variable &&
                    analysis.arrays.contains(analysis.resolved.get(argument)))
                    return number(array(argument).size());
                return number(text(evaluate(argument)).length());
            }
            if (name.equals("split")) {
                String text = text(evaluate(args.getFirst()));
                String separator =
                    args.size() == 3 ? text(evaluate(args.get(2))) : text(global("FS"));
                Map<String, ValuesFields.Value> array = array(args.get(1));
                array.clear();
                List<String> pieces = ValuesFields.split(text, separator);
                for (int i = 0; i < pieces.size(); i++)
                    array.put(Integer.toString(i + 1), ValuesFields.input(pieces.get(i)));
                return number(pieces.size());
            }
            if (name.equals("close"))
                return number(streams.close(text(evaluate(args.getFirst()))));
            List<ValuesFields.Value> values = new ArrayList<>();
            for (Parser.Expr argument : args)
                values.add(evaluate(argument));
            return Builtins.invoke(name, values, builtin.pos());
        }
        ValuesFields.Value getline(Parser.Getline getline) throws IOException {
            Streams.Read result;
            if (getline.filename() != null)
                result = streams.getline(text(evaluate(getline.filename())));
            else if (phase.equals("END"))
                return number(0);
            else {
                String line = nextRecord();
                result = new Streams.Read(line == null ? 0 : 1, line);
            }
            if (result.status() == 1) {
                if (getline.target() == null)
                    record.set(result.line())
                ;
                else {
                    Location location = location(getline.target());
                    store(location, ValuesFields.input(result.line()), getline.pos());
                }
            }
            return number(result.status());
        }
        void output(Parser.Output output) throws IOException {
            List<ValuesFields.Value> values = new ArrayList<>();
            for (Parser.Expr expression : output.arguments())
                values.add(evaluate(expression));
            String content;
            if (output.formatted())
                content = Builtins.format(values, output.pos());
            else {
                if (values.isEmpty())
                    values.add(record.zero);
                StringJoiner joined = new StringJoiner(text(global("OFS")));
                for (ValuesFields.Value value : values)
                    joined.add(text(value));
                content = joined + text(global("ORS"));
            }
            String filename = output.filename() == null ? null : text(evaluate(output.filename()));
            streams.write(content, filename, output.redirect(), output.redirectPos());
        }
        boolean loopBody(Parser.Stmt body) throws IOException {
            try {
                statement(body);
            } catch (Transfer transfer) {
                if (transfer.flow == Flow.BREAK)
                    return false;
                if (transfer.flow != Flow.CONTINUE)
                    throw transfer;
            }
            return true;
        }
        void statement(Parser.Stmt statement) throws IOException {
            if (statement instanceof Parser.Block block) {
                for (Parser.Stmt child : block.statements())
                    statement(child);
                return;
            }
            if (statement instanceof Parser.Empty)
                return;
            lines.merge(statement.pos().line(), 1, Integer::sum);
            switch (statement) {
            case Parser.ExpressionStatement expression -> evaluate(expression.expression());
            case Parser.Output output -> output(output);
            case Parser.If branch -> {
                Parser.Stmt selected =
                    truth(evaluate(branch.condition())) ? branch.first() : branch.second();
                if (selected != null)
                    statement(selected);
            }
            case Parser.While loop -> {
                while (truth(evaluate(loop.condition())))
                    if (!loopBody(loop.body()))
                        break;
            }
            case Parser.DoWhile loop -> {
                do {
                    if (!loopBody(loop.body()))
                        break;
                } while (truth(evaluate(loop.condition())));
            }
            case Parser.For loop -> {
                if (loop.initial() != null)
                    evaluate(loop.initial());
                while (loop.condition() == null || truth(evaluate(loop.condition()))) {
                    if (!loopBody(loop.body()))
                        break;
                    if (loop.update() != null)
                        evaluate(loop.update());
                }
            }
            case Parser.ForIn loop -> {
                List<String> keys = new ArrayList<>(array(loop.array()).keySet());
                keys.sort(ValuesFields.KEY_ORDER);
                for (String key : keys) {
                    store(new VariableLocation(analysis.resolved.get(loop.variable())),
                          ValuesFields.input(key), loop.variable().pos());
                    if (!loopBody(loop.body()))
                        break;
                }
            }
            case Parser.Delete delete -> {
                Map<String, ValuesFields.Value> array = array(delete.array());
                if (delete.indexes() == null)
                    array.clear();
                else
                    array.remove(subscript(delete.indexes()));
            }
            case Parser.TransferStatement transfer -> {
                switch (transfer.kind()) {
                case "next" -> {
                    if (phase.equals("BEGIN") || phase.equals("END"))
                        throw new Builtins.RuntimeIssue(transfer.pos(),
                                                        "next used in BEGIN or END");
                    throw new Transfer(Flow.NEXT);
                }
                case "exit" -> {
                    if (transfer.value() != null)
                        exitStatus = numeric(evaluate(transfer.value()));
                    throw new Transfer(Flow.EXIT);
                }
                case "return" ->
                    throw new Transfer(Flow.RETURN, transfer.value() == null
                                                        ? ValuesFields.UNINITIALIZED
                                                        : evaluate(transfer.value()));
                case "break" -> throw new Transfer(Flow.BREAK);
                default -> throw new Transfer(Flow.CONTINUE);
                }
            }
            default -> throw new AssertionError();
            }
        }
        String nextRecord() throws IOException {
            while (true) {
                if (inputIndex < inputLines.size()) {
                    String line = inputLines.get(inputIndex++);
                    current.records++;
                    globals.get("NR").scalar = number(numeric(global("NR")) + 1);
                    globals.get("FNR").scalar = number(numeric(global("FNR")) + 1);
                    return line;
                }
                if (operandIndex == arguments.operands().size())
                    return null;
                Streams.Operand operand = arguments.operands().get(operandIndex++);
                if (!operand.file)
                    assignInput(operand.name, operand.value);
                else {
                    current = operand;
                    inputLines = Streams.records(operand.name);
                    inputIndex = 0;
                    globals.get("FILENAME").scalar = string(operand.name);
                    globals.get("FNR").scalar = number(0);
                }
            }
        }
        void actions(String phase) throws IOException {
            this.phase = phase;
            for (Parser.Rule rule : analysis.rules)
                if (rule.flavor.equals(phase)) {
                    rule.count++;
                    statement(rule.action);
                }
        }
        boolean matches(Parser.Rule rule) throws IOException {
            if (rule.flavor.equals("all"))
                return true;
            if (rule.flavor.equals("pattern"))
                return truth(evaluate(rule.patterns.getFirst()));
            if (!rule.inside && truth(evaluate(rule.patterns.getFirst())))
                rule.inside = true;
            if (!rule.inside)
                return false;
            if (truth(evaluate(rule.patterns.get(1))))
                rule.inside = false;
            return true;
        }
        void records() throws IOException {
            if (analysis.rules.stream().noneMatch(rule -> !rule.flavor.equals("BEGIN")))
                return;
            phase = "records";
            String line;
            while ((line = nextRecord()) != null) {
                record.set(line)
                ;
                try {
                    for (Parser.Rule rule : analysis.rules)
                        if (!rule.flavor.equals("BEGIN") && !rule.flavor.equals("END") &&
                            matches(rule)) {
                            rule.count++;
                            if (rule.action == null)
                                streams.write(text(record.zero) + text(global("ORS")), null, null,
                                              null);
                            else
                                statement(rule.action);
                        }
                } catch (Transfer transfer) {
                    if (transfer.flow != Flow.NEXT)
                        throw transfer;
                }
            }
        }
        void execute() throws IOException {
            try {
                for (Streams.Option option : arguments.options())
                    assignInput(option.name(), option.value());
                try {
                    actions("BEGIN");
                    records();
                } catch (Transfer transfer) {
                    if (transfer.flow != Flow.EXIT)
                        throw transfer;
                }
                try {
                    actions("END");
                } catch (Transfer transfer) {
                    if (transfer.flow != Flow.EXIT)
                        throw transfer;
                }
            } catch (Builtins.RuntimeIssue issue) {
                error = issue;
            }
        }
        List<String> statistics() {
            List<String> result = new ArrayList<>();
            result.add(error == null
                           ? "status: exit " + exitStatus
                           : "status: runtime error at " + error.pos + ": " + error.getMessage());
            result.add("[inputs]");
            for (Streams.Operand operand : arguments.operands())
                if (operand.file)
                    result.add(operand.name + " records=" + operand.records);
            result.add("[getline]");
            for (var entry : streams.inputs.entrySet())
                result.add(
                    entry.getKey() + " " +
                    (entry.getValue().everOpened ? "reads=" + entry.getValue().reads : "missing"));
            result.add("[rules]");
            for (Parser.Rule rule : analysis.rules)
                result.add(rule.pos + " " + rule.flavor + " count=" + rule.count);
            result.add("[functions]");
            for (Parser.Function function : analysis.functions)
                result.add(function.name + " calls=" + function.calls + " depth=" + function.depth);
            result.add("[outputs]");
            result.add("stdout.txt writes=" + streams.stdout.writes +
                       " bytes=" + streams.stdout.content.length());
            for (var entry : streams.outputs.entrySet())
                result.add(entry.getKey() + " writes=" + entry.getValue().writes +
                           " bytes=" + entry.getValue().content.length());
            result.add("[lines]");
            for (var entry : lines.entrySet())
                result.add(entry.getKey() + " count=" + entry.getValue());
            result.add("[globals]");
            for (String name : globalNames) {
                Binding binding = new Binding(null, name);
                result.add(name + " = " +
                           (analysis.arrays.contains(binding)
                                ? "array (" + globals.get(name).array.size() + ")"
                                : ValuesFields.describe(variable(binding))));
            }
            return result;
        }
    }
    public static void main(String[] args) throws IOException {
        Streams.Arguments arguments =
            Streams.parse(Files.readString(Path.of("input/args.txt"), StandardCharsets.US_ASCII));
        String source = Files.readString(Path.of("input/program.awk"), StandardCharsets.US_ASCII);
        Streams streams;
        List<String> statistics;
        try {
            Analysis analysis = new Analysis(new Parser(Lexer.tokenize(source)).parse()).prepare();
            Engine engine = new Engine(analysis, arguments);
            engine.execute();
            streams = engine.streams;
            statistics = engine.statistics();
        } catch (Lexer.SyntaxIssue issue) {
            streams = new Streams();
            statistics = List.of("status: syntax error at " + issue.pos);
        } catch (StaticIssue issue) {
            streams = new Streams();
            statistics = List.of("status: error at " + issue.pos + ": " + issue.getMessage());
        }
        streams.save();
        Files.writeString(Path.of("output/stats.txt"), String.join("\n", statistics) + "\n",
                          StandardCharsets.US_ASCII);
    }
}
