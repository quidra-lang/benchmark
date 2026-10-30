import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
public final class Main {
    static final List<String> RULES =
        List.of("const-jump", "not-compare", "not-jump", "invert-branch", "thread", "jump-next",
                "unreachable");
    record Warning(Lexer.Position position, String message) {}
    record
        Linked(List<Codegen.Instruction> code, List<String> owners, Map<Integer, String> starts) {}
    static final class Program {
        String name;
        List<Lexer.SourceLine> lines = new ArrayList<>();
        Map<Integer, String> source = new HashMap<>();
        List<Integer> inputs = new ArrayList<>();
        Lexer.CompileError error;
        List<Warning> warnings = new ArrayList<>();
        int folds, globalSize;
        int[] peephole = new int[7];
        Semantic analysis;
        List<Parser.VariableDecl> globals = new ArrayList<>();
        List<Codegen.Unit> units;
        Linked before, after;
        Vm.Execution execution, comparison;
        Program(String name) { this.name = name; }
        void compile() {
            for (Lexer.SourceLine line : lines)
                source.put(line.number(), line.text());
            List<Parser.Declaration> declarations;
            try {
                List<Lexer.Token> tokens = Lexer.tokenize(lines);
                declarations = new Parser(tokens).parse();
                analysis = new Semantic(declarations, tokens.getLast().position()).analyze();
            } catch (Lexer.CompileError error) {
                this.error = error;
                return;
            }
            Set<Parser.Function> reachable = collectWarnings(this);
            List<Parser.Function> functions = new ArrayList<>();
            for (Parser.Declaration declaration : declarations)
                if (declaration instanceof Parser.VariableDecl variable)
                    globals.add(variable);
            for (Parser.Function function : analysis.functions)
                if (reachable.contains(function))
                    functions.add(function);
            Folder folder = new Folder();
            for (Parser.VariableDecl variable : globals)
                if (variable.initializer != null)
                    variable.initializer = folder.expression(variable.initializer);
            for (Parser.Function function : functions)
                function.body = (Parser.Block)folder.statement(function.body);
            folds = folder.count;
            Codegen.Generated generated =
                Codegen.generate(globals, functions, (Parser.Function)analysis.globals.get("main"));
            units = generated.units();
            globalSize = generated.globalSize();
            Map<String, Parser.Function> table = new HashMap<>();
            for (Parser.Function function : functions)
                table.put(function.name, function);
            for (Codegen.Unit unit : units) {
                Optimized optimized = optimize(unit.before);
                unit.after = optimized.code();
                for (int i = 0; i < 7; i++)
                    peephole[i] += optimized.counts()[i];
                analyzeFlow(unit, table);
                unit.recursive = unit.function != null && recursive(unit.function);
            }
            before = link(units, false);
            after = link(units, true);
            execution =
                new Vm.Execution(after.code(), after.owners(), after.starts(), globalSize, inputs)
                    .run();
            comparison =
                new Vm
                    .Execution(before.code(), before.owners(), before.starts(), globalSize, inputs)
                    .run();
        }
    }
    static Set<Parser.Function> collectWarnings(Program program) {
        Semantic analysis = program.analysis;
        for (Parser.VariableDecl variable : analysis.variables)
            if (variable.reads == 0)
                program.warnings.add(new Warning(
                    variable.namePosition,
                    "unused " +
                        (variable.storage == Parser.Storage.PARAMETER ? "parameter" : "variable") +
                        " '" + variable.name + "'"));
        for (Parser.Function function : analysis.functions) {
            Deque<Parser.Statement> pending = new ArrayDeque<>();
            pending.push(function.body);
            while (!pending.isEmpty()) {
                Parser.Statement statement = pending.pop();
                if (statement instanceof Parser.Block block)
                    for (int i = 0; i + 1 < block.statements.size(); i++)
                        if (!Semantic.canComplete(block.statements.get(i))) {
                            program.warnings.add(new Warning(block.statements.get(i + 1).position(),
                                                             "unreachable statement"));
                            break;
                        }
                for (Parser.Statement child : Parser.statementChildren(statement))
                    pending.push(child);
            }
        }
        Set<Parser.Function> reachable = new HashSet<>();
        Deque<Parser.Function> pending = new ArrayDeque<>();
        pending.push((Parser.Function)analysis.globals.get("main"));
        while (!pending.isEmpty()) {
            Parser.Function function = pending.pop();
            if (reachable.add(function))
                for (Parser.Function called : function.calls)
                    pending.push(called);
        }
        for (Parser.Function function : analysis.functions)
            if (!reachable.contains(function))
                program.warnings.add(new Warning(
                    function.namePosition, "function '" + function.name + "' is never called"));
        program.warnings.sort(Comparator.comparing(Warning::position));
        return reachable;
    }
    static boolean recursive(Parser.Function function) {
        Set<Parser.Function> visited = new HashSet<>();
        Deque<Parser.Function> pending = new ArrayDeque<>(function.calls);
        while (!pending.isEmpty()) {
            Parser.Function current = pending.pop();
            if (current == function)
                return true;
            if (visited.add(current))
                pending.addAll(current.calls);
        }
        return false;
    }
    static boolean literal(Parser.Expr expression, Parser.Type type, int value) {
        return expression instanceof Parser.Literal literal && literal.type == type &&
            literal.value == value;
    }
    static final class Folder {
        int count;
        Parser.Expr literal(Parser.Expr expression, int value) {
            count++;
            return new Parser.Literal(value, expression.type, expression.position);
        }
        Parser.Expr identity(Parser.Expr expression) {
            count++;
            return expression;
        }
        Parser.Expr expression(Parser.Expr expression) {
            if (expression instanceof Parser.Unary unary) {
                unary.operand = expression(unary.operand);
                if (unary.operand instanceof Parser.Literal literal)
                    try {
                        return literal(unary,
                                       Vm.calculate(unary.operator.equals("-") ? Codegen.Op.NEG
                                                                               : Codegen.Op.NOT,
                                                    literal.value, 0));
                    } catch (Vm.RuntimeFault ignored) {
                    }
            } else if (expression instanceof Parser.Binary binary) {
                binary.left = expression(binary.left);
                binary.right = expression(binary.right);
                Parser.Expr left = binary.left, right = binary.right;
                String operator = binary.operator;
                if (left instanceof Parser.Literal a && right instanceof Parser.Literal b)
                    try {
                        int value =
                            operator.equals("&&") ? (a.value != 0 && b.value != 0 ? 1 : 0)
                            : operator.equals("||")
                                ? (a.value != 0 || b.value != 0 ? 1 : 0)
                                : Vm.calculate(Codegen.BINARY.get(operator), a.value, b.value);
                        return literal(binary, value);
                    } catch (Vm.RuntimeFault ignored) {
                    }
                if (operator.equals("&&") && Main.literal(left, Parser.Type.BOOL, 0))
                    return literal(binary, 0);
                if (operator.equals("||") && Main.literal(left, Parser.Type.BOOL, 1))
                    return literal(binary, 1);
                if (operator.equals("&&") && Main.literal(left, Parser.Type.BOOL, 1) ||
                    operator.equals("||") && Main.literal(left, Parser.Type.BOOL, 0) ||
                    operator.equals("+") && Main.literal(left, Parser.Type.INT, 0) ||
                    operator.equals("*") && Main.literal(left, Parser.Type.INT, 1))
                    return identity(right);
                if (Set.of("+", "-").contains(operator) &&
                        Main.literal(right, Parser.Type.INT, 0) ||
                    Set.of("*", "/").contains(operator) &&
                        Main.literal(right, Parser.Type.INT, 1) ||
                    operator.equals("&&") && Main.literal(right, Parser.Type.BOOL, 1) ||
                    operator.equals("||") && Main.literal(right, Parser.Type.BOOL, 0))
                    return identity(left);
            } else if (expression instanceof Parser.ArrayElement array)
                array.index = expression(array.index);
            else if (expression instanceof Parser.Call call) {
                List<Parser.Expr> arguments = new ArrayList<>();
                for (Parser.Expr argument : call.arguments)
                    arguments.add(expression(argument));
                call.arguments = arguments;
            }
            return expression;
        }
        Parser.Statement statement(Parser.Statement statement) {
            switch (statement) {
            case Parser.VariableDecl variable -> {
                if (variable.initializer != null)
                    variable.initializer = expression(variable.initializer);
            }
            case Parser.Assignment assignment -> {
                if (assignment.index != null)
                    assignment.index = expression(assignment.index);
                assignment.value = expression(assignment.value);
            }
            case Parser.CallStatement call -> call.expression = expression(call.expression);
            case Parser.Print print -> {
                List<Parser.Expr> arguments = new ArrayList<>();
                for (Parser.Expr argument : print.arguments)
                    arguments.add(expression(argument));
                print.arguments = arguments;
            }
            case Parser.Return returned -> {
                if (returned.value != null)
                    returned.value = expression(returned.value);
            }
            case Parser.Block block -> {
                List<Parser.Statement> statements = new ArrayList<>();
                for (Parser.Statement child : block.statements)
                    statements.add(statement(child));
                block.statements = statements;
            }
            case Parser.If conditional -> {
                conditional.condition = expression(conditional.condition);
                if (conditional.condition instanceof Parser.Literal literal) {
                    Parser.Statement selected =
                        literal.value != 0 ? conditional.thenStatement : conditional.otherwise;
                    Parser.Statement replacement = selected == null
                                                       ? new Parser.Empty(conditional.position)
                                                       : statement(selected);
                    count++;
                    return replacement;
                }
                conditional.thenStatement = statement(conditional.thenStatement);
                if (conditional.otherwise != null)
                    conditional.otherwise = statement(conditional.otherwise);
            }
            case Parser.While loop -> {
                loop.condition = expression(loop.condition);
                if (Main.literal(loop.condition, Parser.Type.BOOL, 0)) {
                    count++;
                    return new Parser.Empty(loop.position);
                }
                loop.body = statement(loop.body);
            }
            case Parser.For loop -> {
                if (loop.initial != null)
                    loop.initial = statement(loop.initial);
                if (loop.condition != null)
                    loop.condition = expression(loop.condition);
                if (loop.update != null)
                    loop.update = statement(loop.update);
                loop.body = statement(loop.body);
            }
            default -> {
            }
            }
            return statement;
        }
    }
    static boolean jumpsOn(Codegen.Op op, int value) {
        return (value == 0) == (op == Codegen.Op.JUMPF);
    }
    static void deleteInstruction(List<Codegen.Instruction> code, int position) {
        code.remove(position);
        for (int i = 0; i < code.size(); i++) {
            Codegen.Instruction instruction = code.get(i);
            if (Codegen.JUMPS.contains(instruction.op()) && instruction.first() > position)
                code.set(i, instruction.target(instruction.first() - 1));
        }
    }
    static int rewrite(List<Codegen.Instruction> code, int index, Set<Integer> targets) {
        Codegen.Instruction first = code.get(index),
                            second = index + 1 < code.size() ? code.get(index + 1) : null;
        boolean free = second != null && !targets.contains(index + 1);
        if (free && first.op() == Codegen.Op.PUSH && Codegen.CONDITIONAL.contains(second.op())) {
            if (jumpsOn(second.op(), first.first())) {
                code.set(index, new Codegen.Instruction(Codegen.Op.JUMP, second.first(),
                                                        second.position()));
                deleteInstruction(code, index + 1);
            } else {
                deleteInstruction(code, index + 1);
                deleteInstruction(code, index);
            }
            return 1;
        }
        Codegen.Op negated = Codegen.negated(first.op());
        if (free && negated != null && second.op() == Codegen.Op.NOT) {
            code.set(index, first.operation(negated));
            deleteInstruction(code, index + 1);
            return 2;
        }
        if (free && first.op() == Codegen.Op.NOT && Codegen.CONDITIONAL.contains(second.op())) {
            code.set(index, new Codegen.Instruction(Codegen.inverse(second.op()), second.first(),
                                                    second.position()));
            deleteInstruction(code, index + 1);
            return 3;
        }
        if (free && Codegen.CONDITIONAL.contains(first.op()) && first.first() == index + 2 &&
            second.op() == Codegen.Op.JUMP) {
            code.set(index, new Codegen.Instruction(Codegen.inverse(first.op()), second.first(),
                                                    first.position()));
            deleteInstruction(code, index + 1);
            return 4;
        }
        if (Codegen.JUMPS.contains(first.op())) {
            int target = first.first();
            Integer replacement = null;
            if (target < code.size()) {
                Codegen.Instruction destination = code.get(target);
                if (destination.op() == Codegen.Op.JUMP)
                    replacement = destination.first();
                else if (destination.op() == Codegen.Op.PUSH && target + 1 < code.size()) {
                    Codegen.Instruction following = code.get(target + 1);
                    if (Codegen.CONDITIONAL.contains(following.op()))
                        replacement = jumpsOn(following.op(), destination.first())
                                          ? following.first()
                                          : target + 2;
                }
                if (replacement != null && replacement != target) {
                    code.set(index, first.target(replacement));
                    return 5;
                }
            }
            if (target == index + 1) {
                if (first.op() == Codegen.Op.JUMP)
                    deleteInstruction(code, index);
                else
                    code.set(index, new Codegen.Instruction(Codegen.Op.POP, first.position()));
                return 6;
            }
        }
        if (free && Codegen.TRANSFERS.contains(first.op())) {
            deleteInstruction(code, index + 1);
            return 7;
        }
        return 0;
    }
    record Optimized(List<Codegen.Instruction> code, int[] counts) {}
    static Optimized optimize(List<Codegen.Instruction> original) {
        List<Codegen.Instruction> code = new ArrayList<>(original);
        int[] counts = new int[7];
        while (true) {
            Set<Integer> targets = new HashSet<>();
            for (Codegen.Instruction instruction : code)
                if (Codegen.JUMPS.contains(instruction.op()))
                    targets.add(instruction.first());
            boolean changed = false;
            for (int i = 0; i < code.size(); i++) {
                int rule = rewrite(code, i, targets);
                if (rule != 0) {
                    counts[rule - 1]++;
                    changed = true;
                    break;
                }
            }
            if (!changed)
                return new Optimized(code, counts);
        }
    }
    static List<Integer> successors(List<Codegen.Instruction> code, int index) {
        Codegen.Instruction instruction = code.get(index);
        List<Integer> result = new ArrayList<>();
        if (!Codegen.TRANSFERS.contains(instruction.op()) && index + 1 < code.size())
            result.add(index + 1);
        if (Codegen.JUMPS.contains(instruction.op()) && instruction.first() < code.size() &&
            !result.contains(instruction.first()))
            result.add(instruction.first());
        return result;
    }
    static int stackEffect(Codegen.Instruction instruction,
                           Map<String, Parser.Function> functions) {
        return switch (instruction.op()) {
            case PUSH, LOADG, LOADL, READ -> 1;
            case POP, STOREG, STOREL, JUMPF, JUMPT, RETV, ADD, SUB, MUL, DIV, MOD, LT, LE, GT, GE,
                EQ, NE ->
                -1;
            case STOREA -> -2;
            case CALL ->
                -instruction.second() +
                    (functions.get(instruction.callee()).type == Parser.Type.VOID ? 0 : 1);
            case PRINT -> -instruction.first();
            default -> 0;
        };
    }
    static void analyzeFlow(Codegen.Unit unit, Map<String, Parser.Function> functions) {
        List<Codegen.Instruction> code = unit.after;
        Set<Integer> leaders = new TreeSet<>();
        leaders.add(0);
        for (int i = 0; i < code.size(); i++) {
            Codegen.Instruction instruction = code.get(i);
            if (Codegen.JUMPS.contains(instruction.op()) && instruction.first() < code.size())
                leaders.add(instruction.first());
            if ((Codegen.JUMPS.contains(instruction.op()) ||
                 Codegen.TRANSFERS.contains(instruction.op())) &&
                i + 1 < code.size())
                leaders.add(i + 1);
        }
        List<Integer> starts = new ArrayList<>(leaders);
        Map<Integer, Integer> numbers = new HashMap<>();
        for (int i = 0; i < starts.size(); i++)
            numbers.put(starts.get(i), i);
        for (int i = 0; i < starts.size(); i++) {
            int start = starts.get(i), end = i + 1 < starts.size() ? starts.get(i + 1) - 1
                                                                   : code.size() - 1;
            List<Integer> following = new ArrayList<>();
            for (int target : successors(code, end))
                following.add(numbers.get(target));
            unit.blocks.add(new Codegen.Block(start, end, following));
        }
        Map<Integer, Integer> depths = new HashMap<>();
        depths.put(0, 0);
        Deque<Integer> pending = new ArrayDeque<>();
        pending.push(0);
        while (!pending.isEmpty()) {
            int index = pending.pop(),
                after = depths.get(index) + stackEffect(code.get(index), functions);
            unit.depth = Math.max(unit.depth, after);
            for (int target : successors(code, index))
                if (!depths.containsKey(target)) {
                    depths.put(target, after);
                    pending.push(target);
                }
        }
    }
    static Linked link(List<Codegen.Unit> units, boolean after) {
        Map<String, Integer> addresses = new HashMap<>();
        int offset = 0;
        for (Codegen.Unit unit : units) {
            addresses.put(unit.name, offset);
            if (after)
                unit.afterStart = offset;
            else
                unit.beforeStart = offset;
            offset += (after ? unit.after : unit.before).size();
        }
        List<Codegen.Instruction> code = new ArrayList<>();
        List<String> owners = new ArrayList<>();
        Map<Integer, String> starts = new HashMap<>();
        for (Codegen.Unit unit : units) {
            int start = addresses.get(unit.name);
            starts.put(start, unit.name);
            for (Codegen.Instruction instruction : after ? unit.after : unit.before) {
                if (Codegen.JUMPS.contains(instruction.op()))
                    instruction = instruction.target(start + instruction.first());
                else if (instruction.op() == Codegen.Op.CALL)
                    instruction = instruction.target(addresses.get(instruction.callee()));
                code.add(instruction);
                owners.add(unit.name);
            }
        }
        return new Linked(code, owners, starts);
    }
    static String spelling(Codegen.Instruction instruction) {
        String result = instruction.op().name();
        return switch (instruction.op()) {
            case PUSH, LOADG, STOREG, LOADL, STOREL, JUMP, JUMPF, JUMPT, ENTER, PRINT ->
                result + " " + instruction.first();
            case LOADA, STOREA, CALL ->
                result + " " + instruction.first() + " " + instruction.second();
            default -> result;
        };
    }
    static List<String> listing(Program program) {
        List<String> lines = new ArrayList<>();
        if (program.globals.isEmpty())
            lines.add("globals: none");
        else {
            lines.add("globals:");
            for (Parser.VariableDecl variable : program.globals)
                lines.add("  " + variable.address + " " + variable.name + " " +
                          (variable.size == null ? variable.type : "int[" + variable.size + "]"));
        }
        lines.add("functions:");
        for (Codegen.Unit unit : program.units) {
            String signature = "", callees = "main";
            if (unit.function != null) {
                StringJoiner parameters = new StringJoiner(",");
                for (Parser.VariableDecl parameter : unit.function.parameters)
                    parameters.add(parameter.type.toString());
                signature = " " + unit.function.type + "(" + parameters + ")";
                List<String> calls = new ArrayList<>();
                for (Parser.Function function : unit.function.calls)
                    calls.add(function.name);
                calls.sort(String::compareTo);
                callees = calls.isEmpty() ? "-" : String.join(",", calls);
            }
            lines.add("  " + unit.name + signature + " address=" + unit.beforeStart + "->" +
                      unit.afterStart + " size=" + unit.before.size() + "->" + unit.after.size() +
                      " slots=" + unit.slots.size() + " stack=" + unit.depth +
                      " blocks=" + unit.blocks.size() + " calls=" + callees +
                      (unit.recursive ? " recursive" : ""));
            for (int i = 0; i < unit.slots.size(); i++) {
                Parser.VariableDecl slot = unit.slots.get(i);
                lines.add("    slot " + i + " " + slot.name + " " + slot.type);
            }
        }
        lines.add("references:");
        List<Parser.Declaration> declarations = new ArrayList<>(program.globals);
        declarations.addAll(program.analysis.functions);
        for (Parser.Declaration declaration : declarations) {
            Set<Integer> used = new TreeSet<>();
            for (Lexer.Position position : declaration.references)
                used.add(position.line());
            StringJoiner text = new StringJoiner(" ");
            for (int line : used)
                text.add(Integer.toString(line));
            lines.add("  " + declaration.name + " defined " + declaration.namePosition.line() +
                      " used " + (used.isEmpty() ? "-" : text));
        }
        for (boolean after : List.of(false, true)) {
            Linked linked = after ? program.after : program.before;
            lines.add((after ? "after" : "before") + " peephole: " + linked.code().size() +
                      " instructions");
            for (Codegen.Unit unit : program.units) {
                lines.add(unit.name + ":");
                int start = after ? unit.afterStart : unit.beforeStart,
                    size = (after ? unit.after : unit.before).size();
                for (int address = start; address < start + size; address++)
                    lines.add(String.format(Locale.ROOT, "%5d  ", address) +
                              spelling(linked.code().get(address)));
            }
        }
        lines.add("control flow:");
        for (Codegen.Unit unit : program.units) {
            lines.add("  " + unit.name);
            for (int i = 0; i < unit.blocks.size(); i++) {
                Codegen.Block block = unit.blocks.get(i);
                String line = "    B" + i + " " + (unit.afterStart + block.start()) + "-" +
                              (unit.afterStart + block.end());
                if (!block.following().isEmpty()) {
                    StringJoiner following = new StringJoiner(" ");
                    for (int target : block.following())
                        following.add("B" + target);
                    line += " -> " + following;
                }
                lines.add(line);
            }
        }
        return lines;
    }
    static List<String> positionDisplay(Program program, Lexer.Position position) {
        return List.of("  " + program.source.get(position.line()),
                       " ".repeat(position.column() + 1) + "^");
    }
    static List<String> diagnostics(Program program) {
        List<String> lines = new ArrayList<>();
        if (program.error != null) {
            lines.add(program.error.kind + " error " + program.error.position + ": " +
                      program.error.getMessage());
            lines.addAll(positionDisplay(program, program.error.position));
            lines.add("status: compile error");
            return lines;
        }
        for (Warning warning : program.warnings)
            lines.add("warning " + warning.position() + ": " + warning.message());
        Vm.Execution execution = program.execution;
        if (execution.error == null) {
            lines.add("status: ok");
            return lines;
        }
        Codegen.Instruction instruction = program.after.code().get(execution.errorPc);
        lines.add("runtime error " + instruction.position() + ": " + execution.error + " in " +
                  program.after.owners().get(execution.errorPc));
        lines.addAll(positionDisplay(program, instruction.position()));
        int callers = execution.frames.size() - 1;
        for (int i = 0; i < Math.min(callers, 5); i++) {
            Vm.Frame frame = execution.frames.get(execution.frames.size() - 1 - i);
            int address = frame.returnAddress() - 1;
            lines.add("  called from " + program.after.owners().get(address) + " at " +
                      program.after.code().get(address).position());
        }
        if (callers > 5)
            lines.add("  ... " + (callers - 5) + " more");
        lines.add("status: runtime error");
        return lines;
    }
    static <K> List<Map.Entry<K, Integer>> descending(Map<K, Integer> counts, Comparator<K> ties) {
        List<Map.Entry<K, Integer>> entries = new ArrayList<>(counts.entrySet());
        entries.sort((a, b) -> {
            int order = Integer.compare(b.getValue(), a.getValue());
            return order == 0 ? ties.compare(a.getKey(), b.getKey()) : order;
        });
        return entries;
    }
    static List<String> statistics(Program program) {
        Vm.Execution execution = program.execution, comparison = program.comparison;
        boolean same = execution.output.equals(comparison.output) &&
                       Objects.equals(execution.error, comparison.error);
        List<String> lines = new ArrayList<>();
        lines.add("code: " + program.before.code().size() + " -> " + program.after.code().size());
        lines.add("folds: " + program.folds);
        lines.add("peephole: " + Arrays.stream(program.peephole).sum());
        for (int i = 0; i < 7; i++)
            lines.add("  " + RULES.get(i) + " " + program.peephole[i]);
        lines.add("executed: " + execution.executed);
        lines.add("executed before peephole: " + comparison.executed);
        lines.add("behaviour: " + (same ? "same" : "different"));
        lines.add("max call depth: " + execution.maxDepth);
        lines.add("max stack: " + execution.maxStack);
        Map<String, Integer> opcodes = new HashMap<>(), functions = new HashMap<>();
        Map<Integer, Integer> sourceLines = new TreeMap<>(), hotspots = new HashMap<>();
        for (int address = 0; address < program.after.code().size(); address++) {
            Codegen.Instruction instruction = program.after.code().get(address);
            int count = execution.counts[address];
            opcodes.merge(instruction.op().name(), count, Integer::sum);
            functions.merge(program.after.owners().get(address), count, Integer::sum);
            sourceLines.merge(instruction.position().line(), count, Integer::sum);
            if (count > 0)
                hotspots.put(address, count);
        }
        lines.add("opcodes:");
        for (var entry : descending(opcodes, Comparator.naturalOrder()))
            if (entry.getValue() > 0)
                lines.add("  " + entry.getKey() + " " + entry.getValue());
        lines.add("functions:");
        List<String> names = new ArrayList<>();
        for (Codegen.Unit unit : program.units)
            if (unit.function != null)
                names.add(unit.name);
        names.sort(Comparator.<String>comparingInt(name -> functions.getOrDefault(name, 0))
                       .reversed()
                       .thenComparing(Comparator.naturalOrder()));
        for (String name : names)
            lines.add("  " + name + " calls=" + execution.calls.getOrDefault(name, 0) +
                      " executed=" + functions.getOrDefault(name, 0));
        lines.add("calls:");
        Comparator<Vm.CallPair> pairs =
            Comparator.comparing(Vm.CallPair::caller).thenComparing(Vm.CallPair::callee);
        for (var entry : descending(execution.pairs, pairs))
            lines.add("  " + entry.getKey().caller() + " -> " + entry.getKey().callee() + " " +
                      entry.getValue());
        lines.add("hot lines:");
        List<Map.Entry<Integer, Integer>> executedLines = new ArrayList<>();
        for (var entry : descending(sourceLines, Comparator.naturalOrder()))
            if (entry.getValue() > 0)
                executedLines.add(entry);
        for (int i = 0; i < Math.min(5, executedLines.size()); i++) {
            var entry = executedLines.get(i);
            lines.add("  line " + entry.getKey() + ": " + entry.getValue());
        }
        lines.add("coverage: " + executedLines.size() + " of " + sourceLines.size() + " lines");
        StringJoiner unexecuted = new StringJoiner(" ");
        int missing = 0;
        for (var entry : sourceLines.entrySet())
            if (entry.getValue() == 0) {
                unexecuted.add(entry.getKey().toString());
                missing++;
            }
        lines.add("not executed: " + (missing == 0 ? "none" : unexecuted));
        lines.add("hot spots:");
        List<Map.Entry<Integer, Integer>> hot = descending(hotspots, Comparator.naturalOrder());
        for (int i = 0; i < Math.min(5, hot.size()); i++) {
            var entry = hot.get(i);
            lines.add("  pc=" + entry.getKey() + " count=" + entry.getValue() + " " +
                      spelling(program.after.code().get(entry.getKey())));
        }
        return lines;
    }
    static List<String> summary(List<Program> programs) {
        int compiled = 0, runtimeErrors = 0, folds = 0, executed = 0;
        int[] peephole = new int[7];
        Map<String, Integer> errors = new HashMap<>();
        List<List<String>> rows = new ArrayList<>();
        rows.add(List.of("program", "status", "code", "executed", "output"));
        for (Program program : programs) {
            if (program.error != null) {
                errors.merge(program.error.kind, 1, Integer::sum);
                rows.add(List.of(program.name, program.error.kind + " error", "-", "-", "-"));
                continue;
            }
            compiled++;
            if (program.execution.error != null)
                runtimeErrors++;
            folds += program.folds;
            executed += program.execution.executed;
            for (int i = 0; i < 7; i++)
                peephole[i] += program.peephole[i];
            rows.add(List.of(program.name, program.execution.error == null ? "ok" : "runtime error",
                             Integer.toString(program.after.code().size()),
                             Integer.toString(program.execution.executed),
                             Integer.toString(program.execution.output.size())));
        }
        List<String> lines = new ArrayList<>();
        lines.add("== summary ==");
        lines.add("programs: " + programs.size());
        lines.add("compiled: " + compiled);
        lines.add("compile errors: lexical " + errors.getOrDefault("lexical", 0) + " syntax " +
                  errors.getOrDefault("syntax", 0) + " semantic " +
                  errors.getOrDefault("semantic", 0));
        lines.add("runtime errors: " + runtimeErrors);
        lines.add("folds: " + folds);
        lines.add("peephole: " + Arrays.stream(peephole).sum());
        for (int i = 0; i < 7; i++)
            lines.add("  " + RULES.get(i) + " " + peephole[i]);
        lines.add("executed: " + executed);
        int[] widths = new int[5];
        for (List<String> row : rows)
            for (int i = 0; i < 5; i++)
                widths[i] = Math.max(widths[i], row.get(i).length());
        for (List<String> row : rows) {
            StringJoiner line = new StringJoiner("  ");
            for (int i = 0; i < 5; i++) {
                String value = row.get(i), spaces = " ".repeat(widths[i] - value.length());
                line.add(i < 2 ? value + spaces : spaces + value);
            }
            lines.add("  " + line);
        }
        return lines;
    }
    static List<Program> readPrograms() throws Exception {
        List<Program> programs = new ArrayList<>();
        Map<String, Program> names = new HashMap<>();
        List<String> source =
            Files.readAllLines(Path.of("input", "program.src"), StandardCharsets.US_ASCII);
        for (int i = 0; i < source.size(); i++) {
            String line = source.get(i);
            if (line.startsWith("#program ")) {
                Program program = new Program(line.substring(9));
                programs.add(program);
                names.put(program.name, program);
            } else
                programs.getLast().lines.add(new Lexer.SourceLine(i + 1, line));
        }
        Program current = null;
        for (String line :
             Files.readAllLines(Path.of("input", "input.txt"), StandardCharsets.US_ASCII))
            if (line.startsWith("#input "))
                current = names.get(line.substring(7));
            else
                for (String value : line.split(" "))
                    current.inputs.add(Integer.parseInt(value));
        return programs;
    }
    static void write(String name, List<String> lines) throws Exception {
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    public static void main(String[] args) throws Exception {
        List<Program> programs = readPrograms();
        List<String> listing = new ArrayList<>(), output = new ArrayList<>(),
                     diagnostics = new ArrayList<>(), stats = new ArrayList<>();
        for (Program program : programs) {
            program.compile();
            String heading = "== program " + program.name + " ==";
            for (List<String> lines : List.of(listing, output, diagnostics, stats))
                lines.add(heading);
            diagnostics.addAll(diagnostics(program));
            if (program.error != null) {
                listing.add("not compiled");
                stats.add("not compiled");
            } else {
                listing.addAll(listing(program));
                output.addAll(program.execution.output);
                stats.addAll(statistics(program));
            }
        }
        stats.addAll(summary(programs));
        Files.createDirectories(Path.of("output"));
        write("listing.txt", listing);
        write("output.txt", output);
        write("diagnostics.txt", diagnostics);
        write("stats.txt", stats);
    }
}
