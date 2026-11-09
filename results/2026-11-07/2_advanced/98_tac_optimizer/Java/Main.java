import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.function.Function;
public final class Main {
    static final List<String> PASS_ORDER = List.of("constprop", "copyprop", "cse", "dce", "licm",
                                                   "unreachable"),
                              VERSIONS = List.of("original", "optimized", "allocated");
    static String list(Collection<?> values) {
        return values.isEmpty() ? "-"
                                : String.join(",", values.stream().map(Object::toString).toList());
    }
    static String blocks(Collection<Integer> numbers) {
        return list(numbers.stream().map(number -> "B" + number).toList());
    }
    static String instructions(Collection<Integer> numbers) {
        return list(numbers.stream().map(number -> "#" + number).toList());
    }
    record Settings(int registers, List<String> enabled, int rounds) {}
    static Settings settings(String text) {
        List<String> lines = text.lines().toList();
        int registers = Integer.parseInt(lines.get(0).split(" ")[1]),
            rounds = Integer.parseInt(lines.get(2).split(" ")[1]);
        Set<String> enabled = new HashSet<>(Arrays.asList(lines.get(1).split(" ")));
        return new Settings(registers, PASS_ORDER.stream().filter(enabled::contains).toList(),
                            rounds);
    }
    static List<List<Integer>> runs(String text) {
        List<String> lines = text.lines().toList();
        List<List<Integer>> result = new ArrayList<>();
        for (int i = 1; i <= Integer.parseInt(lines.getFirst()); i++) {
            String[] words = lines.get(i).split(" +");
            List<Integer> values = new ArrayList<>();
            for (int j = 1; j <= Integer.parseInt(words[0]); j++)
                values.add(Integer.parseInt(words[j]));
            result.add(values);
        }
        return result;
    }
    static List<Integer> reachableInstructions(Cfg graph) {
        return graph.instructions.keySet()
            .stream()
            .filter(number -> graph.reachable.contains(graph.blockOf.get(number)))
            .toList();
    }
    static Set<Integer> reachingNumbers(Dataflow flow, int number, String variable) {
        Set<Integer> result = new TreeSet<>();
        for (Dataflow.Definition definition : flow.reachingBefore.get(number))
            if (definition.variable().equals(variable))
                result.add(definition.number());
        return result;
    }
    static Integer constantValue(Cfg graph, Set<Integer> definitions) {
        if (definitions.isEmpty() || definitions.contains(0))
            return null;
        Integer value = null;
        for (int number : definitions) {
            TacParser.Instruction instruction = graph.instructions.get(number);
            if (instruction.kind() != TacParser.Kind.COPY ||
                !(instruction.a() instanceof TacParser.Constant constant))
                return null;
            if (value != null && value != constant.value())
                return null;
            value = constant.value();
        }
        return value;
    }
    record PassResult(int count, List<String> records) {}
    static PassResult constantPropagation(TacParser.Function function, Cfg graph, Dataflow flow) {
        Map<Integer, List<TacParser.Line>> replacements = new HashMap<>();
        List<String> records = new ArrayList<>();
        for (int number : reachableInstructions(graph)) {
            TacParser.Instruction original = graph.instructions.get(number), instruction = original;
            for (int field : original.operandFields())
                if (original.operand(field) instanceof TacParser.Variable variable) {
                    Integer value =
                        constantValue(graph, reachingNumbers(flow, number, variable.name()));
                    if (value != null) {
                        instruction = instruction.withOperand(field, new TacParser.Constant(value));
                        records.add("#" + number + ": " + variable.name() + " -> " + value);
                    }
                }
            TacParser.Instruction result = Optimizations.fold(instruction);
            if (result == null) {
                records.add("#" + number + ": delete " + instruction);
                replacements.put(number, List.of());
            } else {
                if (result != instruction)
                    records.add("#" + number + ": fold " + result);
                replacements.put(number, List.of(result));
            }
        }
        Optimizations.rewrite(function, replacements);
        return new PassResult(records.size(), records);
    }
    static PassResult copyPropagation(TacParser.Function function, Cfg graph, Dataflow flow) {
        Map<Integer, List<TacParser.Line>> replacements = new HashMap<>();
        List<String> records = new ArrayList<>();
        for (int number : reachableInstructions(graph)) {
            TacParser.Instruction original = graph.instructions.get(number), instruction = original;
            Map<String, String> available = new HashMap<>();
            for (Dataflow.Copy copy : flow.copyBefore.get(number))
                available.put(copy.destination(), copy.source());
            for (int field : original.operandFields())
                if (original.operand(field) instanceof TacParser.Variable variable &&
                    available.containsKey(variable.name())) {
                    String replacement = available.get(variable.name());
                    instruction =
                        instruction.withOperand(field, new TacParser.Variable(replacement));
                    records.add("#" + number + ": " + variable.name() + " -> " + replacement);
                }
            replacements.put(number, List.of(instruction));
        }
        Optimizations.rewrite(function, replacements);
        return new PassResult(records.size(), records);
    }
    static Set<Integer> expressionSources(Cfg graph, TacParser.Expression expression,
                                          int candidate) {
        int blockNumber = graph.blockOf.get(candidate);
        List<Integer> numbers = graph.blocks.get(blockNumber).instructions;
        for (int i = numbers.size() - 1; i >= 0; i--) {
            int number = numbers.get(i);
            if (number < candidate &&
                expression.equals(graph.instructions.get(number).expression()))
                return Set.of(number);
        }
        Set<Integer> sources = new TreeSet<>(), examined = new HashSet<>();
        Deque<Integer> pending = new ArrayDeque<>(graph.reachablePredecessors.get(blockNumber));
        while (!pending.isEmpty()) {
            int number = pending.pop();
            if (!examined.add(number))
                continue;
            List<Integer> block = graph.blocks.get(number).instructions;
            boolean found = false;
            for (int i = block.size() - 1; i >= 0; i--) {
                int instruction = block.get(i);
                if (expression.equals(graph.instructions.get(instruction).expression())) {
                    sources.add(instruction);
                    found = true;
                    break;
                }
            }
            if (!found)
                pending.addAll(graph.reachablePredecessors.get(number));
        }
        return sources;
    }
    static PassResult commonSubexpressions(TacParser.Function function, Cfg graph, Dataflow flow) {
        Map<TacParser.Expression, List<Integer>> candidates = new LinkedHashMap<>();
        for (int number : reachableInstructions(graph)) {
            TacParser.Expression expression = graph.instructions.get(number).expression();
            if (expression != null && flow.expressionBefore.get(number).contains(expression))
                candidates.computeIfAbsent(expression, key -> new ArrayList<>()).add(number);
        }
        Map<Integer, List<TacParser.Line>> replacements = new HashMap<>();
        List<String> records = new ArrayList<>();
        int changes = 0;
        for (var entry : candidates.entrySet()) {
            TacParser.Expression expression = entry.getKey();
            List<Integer> numbers = entry.getValue();
            Set<Integer> sources = new TreeSet<>();
            for (int number : numbers)
                sources.addAll(expressionSources(graph, expression, number));
            sources.removeAll(numbers);
            Optimizations.CseEdits edits = Optimizations.cse(function, graph, sources, numbers);
            replacements.putAll(edits.replacements());
            records.add(expression + ": " + edits.temporary() +
                        " sources=" + instructions(sources) + " replaced=" + instructions(numbers));
            changes += numbers.size();
        }
        Optimizations.rewrite(function, replacements);
        return new PassResult(changes, records);
    }
    static PassResult deadCode(TacParser.Function function, Cfg graph, Dataflow flow) {
        Map<Integer, List<TacParser.Line>> replacements = new HashMap<>();
        TreeMap<Integer, String> records = new TreeMap<>();
        for (int block : graph.reachable) {
            Set<String> state = new HashSet<>(flow.live.outgoing().get(block));
            List<Integer> numbers = graph.blocks.get(block).instructions;
            for (int i = numbers.size() - 1; i >= 0; i--) {
                int number = numbers.get(i);
                TacParser.Instruction instruction = graph.instructions.get(number);
                String destination = instruction.destination();
                boolean selfCopy = instruction.kind() == TacParser.Kind.COPY &&
                                   instruction.a() instanceof TacParser.Variable variable &&
                                   variable.name().equals(destination);
                boolean dead = Set.of(TacParser.Kind.COPY, TacParser.Kind.BIN, TacParser.Kind.LOAD)
                                   .contains(instruction.kind()) &&
                               !state.contains(destination);
                if (selfCopy || dead) {
                    replacements.put(number, List.of());
                    records.put(number, "#" + number + ": delete " + instruction);
                    continue;
                }
                if (instruction.kind() == TacParser.Kind.CALL && destination != null &&
                    !state.contains(destination)) {
                    records.put(number, "#" + number + ": unused result " + instruction);
                    instruction = instruction.withDestination(null);
                    replacements.put(number, List.of(instruction));
                }
                state = Dataflow.liveTransfer(instruction, state);
            }
        }
        Optimizations.rewrite(function, replacements);
        return new PassResult(records.size(), new ArrayList<>(records.values()));
    }
    static Set<Integer> inside(Cfg graph, Cfg.Loop loop, Set<Integer> definitions) {
        Set<Integer> result = new HashSet<>();
        for (int number : definitions)
            if (number != 0 && loop.blocks.contains(graph.blockOf.get(number)))
                result.add(number);
        return result;
    }
    static List<Integer> markedInvariants(Cfg graph, Dataflow flow, Cfg.Loop loop,
                                          List<Integer> numbers) {
        Set<String> stores = new HashSet<>();
        boolean calls = false;
        for (int number : numbers) {
            TacParser.Instruction instruction = graph.instructions.get(number);
            if (instruction.kind() == TacParser.Kind.STORE)
                stores.add(instruction.name());
            if (instruction.kind() == TacParser.Kind.CALL)
                calls = true;
        }
        Set<Integer> marked = new HashSet<>();
        List<Integer> order = new ArrayList<>();
        while (true) {
            boolean changed = false;
            for (int number : numbers) {
                TacParser.Instruction instruction = graph.instructions.get(number);
                if (marked.contains(number) ||
                    !Set.of(TacParser.Kind.COPY, TacParser.Kind.BIN, TacParser.Kind.LOAD)
                         .contains(instruction.kind()))
                    continue;
                if (instruction.kind() == TacParser.Kind.LOAD &&
                    (calls || stores.contains(instruction.name())))
                    continue;
                boolean invariant = true;
                for (String variable : instruction.used()) {
                    Set<Integer> definitions = reachingNumbers(flow, number, variable),
                                 inside = inside(graph, loop, definitions);
                    if (!inside.isEmpty() &&
                        !(definitions.size() == 1 && marked.containsAll(inside))) {
                        invariant = false;
                        break;
                    }
                }
                if (invariant) {
                    marked.add(number);
                    order.add(number);
                    changed = true;
                }
            }
            if (!changed)
                return order;
        }
    }
    static List<Integer> movableInvariants(Cfg graph, Dataflow flow, Cfg.Loop loop,
                                           List<Integer> numbers, List<Integer> marked) {
        Map<String, Integer> definitions = new HashMap<>();
        for (int number : numbers) {
            String destination = graph.instructions.get(number).destination();
            if (destination != null)
                definitions.merge(destination, 1, Integer::sum);
        }
        Set<Integer> moved = new HashSet<>();
        List<Integer> order = new ArrayList<>();
        for (int number : marked) {
            TacParser.Instruction instruction = graph.instructions.get(number);
            String destination = instruction.destination();
            if (definitions.get(destination) != 1 ||
                flow.live.incoming().get(loop.header).contains(destination))
                continue;
            int block = graph.blockOf.get(number);
            boolean dominatesExits = true;
            for (int exit : loop.exits)
                if (!graph.dominators.get(exit).contains(block))
                    dominatesExits = false;
            boolean dangerous =
                instruction.kind() == TacParser.Kind.LOAD ||
                instruction.kind() == TacParser.Kind.BIN &&
                    (instruction.operation().equals("/") || instruction.operation().equals("%")) &&
                    (instruction.b() instanceof TacParser.Variable ||
                     Optimizations.constant(instruction.b(), 0));
            boolean deadOutside = true;
            for (int successor : loop.outside)
                if (flow.live.incoming().get(successor).contains(destination))
                    deadOutside = false;
            if (!dominatesExits && (dangerous || !deadOutside))
                continue;
            boolean ready = true;
            for (String variable : instruction.used())
                if (!moved.containsAll(
                        inside(graph, loop, reachingNumbers(flow, number, variable))))
                    ready = false;
            if (ready) {
                moved.add(number);
                order.add(number);
            }
        }
        return order;
    }
    static PassResult invariantMotion(TacParser.Function function, Cfg graph, Dataflow flow) {
        List<Cfg.Loop> loops = new ArrayList<>(graph.loops);
        loops.sort(Comparator.comparingInt((Cfg.Loop loop) -> loop.blocks.size())
                       .thenComparingInt(loop -> loop.header));
        for (Cfg.Loop loop : loops) {
            List<Integer> numbers = new ArrayList<>();
            for (int block : loop.blocks)
                numbers.addAll(graph.blocks.get(block).instructions);
            Collections.sort(numbers);
            List<Integer> moves = movableInvariants(graph, flow, loop, numbers,
                                                    markedInvariants(graph, flow, loop, numbers));
            if (!moves.isEmpty()) {
                String destination = Optimizations.hoist(function, graph, loop, moves);
                return new PassResult(moves.size(),
                                      List.of("B" + loop.header + ": hoist " + instructions(moves) +
                                              " to " + destination));
            }
        }
        return new PassResult(0, List.of());
    }
    static PassResult unreachable(TacParser.Function function, Cfg graph) {
        Optimizations.Removal removal = Optimizations.removeUnreachable(function, graph);
        List<String> records = new ArrayList<>();
        for (int block : removal.blocks())
            records.add("remove block B" + block);
        for (int number : removal.jumps())
            records.add("remove jump #" + number);
        for (String label : removal.labels())
            records.add("remove label " + label);
        return new PassResult(records.size(), records);
    }
    static List<String> optimize(TacParser.Function function, Settings settings,
                                 Map<String, Integer> totals) {
        int before = function.instructions().size(), round = 0;
        List<String> result = new ArrayList<>(List.of("== " + function.name + " =="));
        for (int r = 1; r <= settings.rounds(); r++) {
            round = r;
            List<String> counts = new ArrayList<>(), records = new ArrayList<>();
            boolean changed = false;
            for (String name : settings.enabled()) {
                Cfg graph = new Cfg(function);
                Dataflow flow = new Dataflow(graph);
                PassResult pass = switch (name) {
                    case "constprop" -> constantPropagation(function, graph, flow);
                    case "copyprop" -> copyPropagation(function, graph, flow);
                    case "cse" -> commonSubexpressions(function, graph, flow);
                    case "dce" -> deadCode(function, graph, flow);
                    case "licm" -> invariantMotion(function, graph, flow);
                    default -> unreachable(function, graph);
                };
                counts.add(name + "=" + pass.count());
                totals.merge(name, pass.count(), Integer::sum);
                changed |= pass.count() != 0;
                for (String record : pass.records())
                    records.add("  " + name + " " + record);
            }
            result.add("round " + round + ": " + String.join(" ", counts));
            result.addAll(records);
            if (!changed)
                break;
        }
        result.add("result: rounds=" + round + " instructions=" + before + "->" +
                   function.instructions().size());
        return result;
    }
    record
        CallGraph(Map<String, List<String>> callees, Set<String> reachable, Set<String> recursive) {
    }
    static Set<String> reach(Collection<String> starts, Map<String, List<String>> callees) {
        Set<String> result = new HashSet<>();
        Deque<String> pending = new ArrayDeque<>(starts);
        while (!pending.isEmpty()) {
            String name = pending.pop();
            if (result.add(name))
                pending.addAll(callees.get(name));
        }
        return result;
    }
    static CallGraph callGraph(TacParser.Program program) {
        List<String> names = program.functions().stream().map(function -> function.name).toList();
        Map<String, List<String>> callees = new HashMap<>();
        for (TacParser.Function function : program.functions()) {
            Set<String> called = new HashSet<>();
            for (TacParser.Instruction instruction : function.instructions())
                if (instruction.kind() == TacParser.Kind.CALL)
                    called.add(instruction.name());
            callees.put(function.name, names.stream().filter(called::contains).toList());
        }
        Set<String> recursive = new HashSet<>();
        for (String name : names)
            if (reach(callees.get(name), callees).contains(name))
                recursive.add(name);
        return new CallGraph(callees, reach(List.of("main"), callees), recursive);
    }
    static List<String> callGraphLines(TacParser.Program program, String heading, CallGraph graph) {
        List<String> result = new ArrayList<>(List.of("== call graph (" + heading + ") =="));
        for (TacParser.Function function : program.functions())
            result.add(function.name + " -> " + list(graph.callees().get(function.name)) +
                       (graph.recursive().contains(function.name) ? " (recursive)" : ""));
        result.add("unreachable functions: " +
                   list(program.functions()
                            .stream()
                            .map(function -> function.name)
                            .filter(name -> !graph.reachable().contains(name))
                            .toList()));
        return result;
    }
    static String definitions(Set<Dataflow.Definition> values) {
        return list(values.stream()
                        .sorted(Comparator.comparingInt(Dataflow.Definition::number)
                                    .thenComparing(Dataflow.Definition::variable))
                        .map(definition -> definition.variable() + ":" + definition.number())
                        .toList());
    }
    static <T> void analysisSets(List<String> lines, String title, Dataflow.Solution<T> solution,
                                 Cfg graph, Function<Set<T>, String> render) {
        lines.add(title + ": iterations=" + solution.iterations());
        for (int block : graph.reachable)
            lines.add("B" + block + " in=" + render.apply(solution.incoming().get(block)) +
                      " out=" + render.apply(solution.outgoing().get(block)));
    }
    static void tree(List<String> lines, Cfg graph, int number, int depth) {
        lines.add("  ".repeat(depth) + "B" + number);
        for (int child : graph.reachable)
            if (Objects.equals(graph.immediate.get(child), number))
                tree(lines, graph, child, depth + 1);
    }
    static List<String> analysis(TacParser.Function function, String heading) {
        Cfg graph = new Cfg(function);
        Dataflow flow = new Dataflow(graph);
        List<String> result =
            new ArrayList<>(List.of("== " + function.name + " (" + heading + ") ==", "code:"));
        int number = 0;
        for (TacParser.Line line : function.code) {
            if (line instanceof TacParser.Label label) {
                result.add(label.name() + ":");
                continue;
            }
            TacParser.Instruction instruction = (TacParser.Instruction)line;
            number++;
            String text = "  #" + number + " " + instruction;
            if (graph.reachable.contains(graph.blockOf.get(number))) {
                List<String> chains = new ArrayList<>();
                for (String variable : new LinkedHashSet<>(instruction.used()))
                    chains.add(variable + ":" + list(reachingNumbers(flow, number, variable)));
                if (!chains.isEmpty())
                    text += " | " + String.join(" ", chains);
            }
            result.add(text);
        }
        result.add("blocks: " + graph.blocks.size());
        for (Cfg.Block block : graph.blocks.values())
            result.add("B" + block.number + " " + block.instructions.getFirst() + "-" +
                       block.instructions.getLast() + " labels=" + list(block.labels) + " preds=" +
                       blocks(block.predecessors) + " succs=" + blocks(block.successors));
        Set<Integer> unreachable = new TreeSet<>(graph.blocks.keySet());
        unreachable.removeAll(graph.reachable);
        result.add("unreachable: " + blocks(unreachable));
        result.add("order: " + blocks(graph.reversePostorder));
        result.add("dominators:");
        for (int block : graph.reachable)
            result.add("B" + block +
                       " idom=" + (block == 1 ? "-" : "B" + graph.immediate.get(block)) +
                       " dom=" + blocks(new TreeSet<>(graph.dominators.get(block))));
        result.add("dominator tree:");
        tree(result, graph, 1, 0);
        result.add("loops: " + graph.loops.size());
        for (Cfg.Loop loop : graph.loops)
            result.add("header=B" + loop.header + " latches=" + blocks(loop.latches) +
                       " depth=" + loop.depth + " blocks=" + blocks(loop.blocks) +
                       " exits=" + blocks(loop.exits));
        analysisSets(result, "reaching definitions", flow.reaching, graph, Main::definitions);
        analysisSets(result, "liveness", flow.live, graph, values -> list(new TreeSet<>(values)));
        analysisSets(result, "available expressions", flow.expressions, graph,
                     values -> list(values.stream().map(Object::toString).sorted().toList()));
        return result;
    }
    record Rewritten(TacParser.Function function, int moves) {}
    static TacParser.Operand rename(TacParser.Operand operand, Map<String, Integer> colors) {
        return operand instanceof TacParser.Variable variable && colors.containsKey(variable.name())
            ? new TacParser.Variable("R" + colors.get(variable.name()))
            : operand;
    }
    static Rewritten registers(TacParser.Function function, Map<String, Integer> colors) {
        List<TacParser.Line> code = new ArrayList<>();
        int moves = 0;
        for (TacParser.Line line : function.code) {
            if (line instanceof TacParser.Label) {
                code.add(line);
                continue;
            }
            TacParser.Instruction instruction = (TacParser.Instruction)line;
            if (instruction.destination() != null && colors.containsKey(instruction.destination()))
                instruction =
                    instruction.withDestination("R" + colors.get(instruction.destination()));
            for (int field : instruction.operandFields())
                instruction =
                    instruction.withOperand(field, rename(instruction.operand(field), colors));
            if (instruction.kind() == TacParser.Kind.COPY &&
                instruction.a() instanceof TacParser.Variable variable &&
                variable.name().equals(instruction.destination()))
                moves++;
            else
                code.add(instruction);
        }
        List<String> parameters =
            function.parameters.stream()
                .map(name -> colors.containsKey(name) ? "R" + colors.get(name) : name)
                .toList();
        return new Rewritten(new TacParser.Function(function.name, parameters, code), moves);
    }
    record AllocationReport(TacParser.Function function, List<String> lines) {}
    static AllocationReport allocation(TacParser.Function function, int registers) {
        Cfg graph = new Cfg(function);
        Dataflow flow = new Dataflow(graph);
        Regalloc allocation = new Regalloc(function, graph, flow, registers);
        Rewritten rewritten = registers(function, allocation.colors);
        int edges = allocation.neighbors.values().stream().mapToInt(Set::size).sum() / 2;
        List<String> result = new ArrayList<>(List.of(
            "== " + function.name + " ==", "nodes=" + allocation.neighbors.size() +
                                               " edges=" + edges + " registers=" + registers));
        for (var entry : allocation.neighbors.entrySet())
            result.add(entry.getKey() + " degree=" + entry.getValue().size() +
                       " cost=" + allocation.costs.get(entry.getKey()) +
                       " neighbors=" + list(entry.getValue()));
        result.add("simplify: " + list(allocation.order));
        result.add(
            "potential spills: " +
            list(allocation.potential.stream()
                     .map(potential
                          -> potential.node() + "(" + allocation.costs.get(potential.node()) + "/" +
                                 potential.degree() + ")")
                     .toList()));
        for (String node : allocation.neighbors.keySet())
            result.add(node + " -> " +
                       (allocation.colors.containsKey(node) ? "R" + allocation.colors.get(node)
                                                            : "spill"));
        int pressure = 0;
        for (Set<String> state : flow.liveBefore.values())
            pressure = Math.max(pressure, state.size());
        for (Set<String> state : flow.liveAfter.values())
            pressure = Math.max(pressure, state.size());
        int spillUses = 0, spillDefinitions = 0;
        for (TacParser.Instruction instruction : function.instructions()) {
            for (String variable : instruction.used())
                if (allocation.spills.contains(variable))
                    spillUses++;
            if (allocation.spills.contains(instruction.destination()))
                spillDefinitions++;
        }
        for (String parameter : function.parameters)
            if (allocation.spills.contains(parameter))
                spillDefinitions++;
        result.add("summary: pressure=" + pressure +
                   " used=" + new HashSet<>(allocation.colors.values()).size() +
                   " spilled=" + allocation.spills.size() + " moves=" + rewritten.moves() +
                   " spill_uses=" + spillUses + " spill_defs=" + spillDefinitions);
        result.addAll(TacParser.functionLines(rewritten.function()));
        return new AllocationReport(rewritten.function(), result);
    }
    record Executable(List<String> parameters, List<TacParser.Instruction> instructions,
                      Map<String, Integer> labels) {}
    static final class Interpreter {
        final Map<String, Executable> functions = new HashMap<>();
        final Map<String, int[]> arrays = new HashMap<>();
        final List<Integer> inputs, output = new ArrayList<>();
        final Map<String, Integer> steps = new HashMap<>(), calls = new HashMap<>();
        final EnumMap<TacParser.Kind, Integer> kinds = new EnumMap<>(TacParser.Kind.class);
        int inputIndex;
        Interpreter(TacParser.Program program, List<Integer> inputs) {
            this.inputs = inputs;
            for (TacParser.Function function : program.functions()) {
                Map<String, Integer> labels = new HashMap<>();
                List<TacParser.Instruction> instructions = new ArrayList<>();
                for (TacParser.Line line : function.code)
                    if (line instanceof TacParser.Label label)
                        labels.put(label.name(), instructions.size());
                    else
                        instructions.add((TacParser.Instruction)line);
                functions.put(function.name,
                              new Executable(function.parameters, instructions, labels));
            }
            for (TacParser.Array array : program.arrays())
                arrays.put(array.name(), new int[array.size()]);
        }
        int value(TacParser.Operand operand, Map<String, Integer> variables) {
            return operand instanceof TacParser.Constant constant
                ? constant.value()
                : variables.get(((TacParser.Variable)operand).name());
        }
        Integer call(String name, List<Integer> arguments) {
            Executable function = functions.get(name);
            Map<String, Integer> variables = new HashMap<>();
            for (int i = 0; i < function.parameters().size(); i++)
                variables.put(function.parameters().get(i), arguments.get(i));
            List<Integer> pushed = new ArrayList<>();
            int position = 0;
            calls.merge(name, 1, Integer::sum);
            while (true) {
                TacParser.Instruction instruction = function.instructions().get(position++);
                steps.merge(name, 1, Integer::sum);
                kinds.merge(instruction.kind(), 1, Integer::sum);
                switch (instruction.kind()) {
                case COPY ->
                    variables.put(instruction.destination(), value(instruction.a(), variables));
                case BIN ->
                    variables.put(instruction.destination(),
                                  (int)TacParser.calculate(instruction.operation(),
                                                           value(instruction.a(), variables),
                                                           value(instruction.b(), variables)));
                case LOAD ->
                    variables.put(
                        instruction.destination(),
                        arrays.get(instruction.name())[value(instruction.a(), variables)]);
                case STORE ->
                    arrays.get(instruction.name())[value(instruction.a(), variables)] =
                        value(instruction.b(), variables);
                case GOTO -> position = function.labels().get(instruction.name());
                case IF -> {
                    if (TacParser.calculate(instruction.operation(),
                                            value(instruction.a(), variables),
                                            value(instruction.b(), variables)) != 0)
                        position = function.labels().get(instruction.name());
                }
                case PARAM -> pushed.add(value(instruction.a(), variables));
                case CALL -> {
                    int first = pushed.size() - instruction.count();
                    List<Integer> values = new ArrayList<>(pushed.subList(first, pushed.size()));
                    pushed.subList(first, pushed.size()).clear();
                    Integer returned = call(instruction.name(), values);
                    if (instruction.destination() != null)
                        variables.put(instruction.destination(), returned);
                }
                case RETURN -> {
                    return instruction.a() == null ? null : value(instruction.a(), variables);
                }
                case READ -> variables.put(instruction.destination(), inputs.get(inputIndex++));
                case PRINT -> output.add(value(instruction.a(), variables));
                }
            }
        }
    }
    static EnumMap<TacParser.Kind, Integer> staticKinds(TacParser.Program program) {
        EnumMap<TacParser.Kind, Integer> result = new EnumMap<>(TacParser.Kind.class);
        for (TacParser.Function function : program.functions())
            for (TacParser.Instruction instruction : function.instructions())
                result.merge(instruction.kind(), 1, Integer::sum);
        return result;
    }
    static int sum(Map<?, Integer> values) {
        return values.values().stream().mapToInt(Integer::intValue).sum();
    }
    static <K> void addCounts(Map<K, Integer> destination, Map<K, Integer> source) {
        for (var entry : source.entrySet())
            destination.merge(entry.getKey(), entry.getValue(), Integer::sum);
    }
    static List<String> comparison(TacParser.Program original, TacParser.Program optimized,
                                   TacParser.Program allocated, List<List<Integer>> runs) {
        List<TacParser.Program> programs = List.of(original, optimized, allocated);
        List<Map<String, Integer>> profiles = new ArrayList<>();
        List<EnumMap<TacParser.Kind, Integer>> dynamic = new ArrayList<>();
        for (int i = 0; i < 3; i++) {
            profiles.add(new HashMap<>());
            dynamic.add(new EnumMap<>(TacParser.Kind.class));
        }
        int[] totalSteps = new int[3];
        Map<String, Integer> originalCalls = new HashMap<>();
        List<String> result = new ArrayList<>();
        int same = 0;
        for (int r = 0; r < runs.size(); r++) {
            List<Integer> inputs = runs.get(r);
            result.add("run " + (r + 1) + ": inputs=" + inputs.size());
            List<List<Integer>> outputs = new ArrayList<>();
            for (int version = 0; version < 3; version++) {
                Interpreter interpreter = new Interpreter(programs.get(version), inputs);
                interpreter.call("main", List.of());
                int steps = sum(interpreter.steps), calls = sum(interpreter.calls);
                result.add("  " + VERSIONS.get(version) + ": steps=" + steps + " calls=" + calls +
                           " output=" + list(interpreter.output));
                addCounts(profiles.get(version), interpreter.steps);
                addCounts(dynamic.get(version), interpreter.kinds);
                totalSteps[version] += steps;
                if (version == 0)
                    addCounts(originalCalls, interpreter.calls);
                outputs.add(interpreter.output);
            }
            boolean equal =
                outputs.get(0).equals(outputs.get(1)) && outputs.get(1).equals(outputs.get(2));
            if (equal)
                same++;
            result.add("  result: " + (equal ? "same" : "different"));
        }
        result.add("== profile ==");
        for (TacParser.Function function : original.functions()) {
            String name = function.name;
            result.add(name + ": calls=" + originalCalls.getOrDefault(name, 0) +
                       " original=" + profiles.get(0).getOrDefault(name, 0) +
                       " optimized=" + profiles.get(1).getOrDefault(name, 0) +
                       " allocated=" + profiles.get(2).getOrDefault(name, 0));
        }
        EnumMap<TacParser.Kind, Integer> originalKinds = staticKinds(original),
                                         optimizedKinds = staticKinds(optimized);
        result.add("== summary ==");
        result.add("runs=" + runs.size() + " same=" + same + " different=" + (runs.size() - same));
        result.add("instructions: original=" + sum(originalKinds) +
                   " optimized=" + sum(optimizedKinds));
        List<String> counts = new ArrayList<>();
        for (TacParser.Kind kind : TacParser.Kind.values())
            counts.add(kind + "=" + originalKinds.getOrDefault(kind, 0) + "->" +
                       optimizedKinds.getOrDefault(kind, 0));
        result.add("kinds: " + String.join(" ", counts));
        counts.clear();
        for (int version = 0; version < 3; version++)
            counts.add(VERSIONS.get(version) + "=" + totalSteps[version]);
        result.add("steps: " + String.join(" ", counts));
        for (int version = 0; version < 3; version++) {
            counts = new ArrayList<>();
            for (TacParser.Kind kind : TacParser.Kind.values())
                counts.add(kind + "=" + dynamic.get(version).getOrDefault(kind, 0));
            result.add("dynamic " + VERSIONS.get(version) + ": " + String.join(" ", counts));
        }
        return result;
    }
    static String read(String name) throws IOException {
        return Files.readString(Path.of("input", name), StandardCharsets.US_ASCII);
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    public static void main(String[] args) throws IOException {
        Settings settings = settings(read("params.txt"));
        List<List<Integer>> runs = runs(read("input.txt"));
        TacParser.Program original = TacParser.parse(read("program.tac"));
        List<String> analysis = callGraphLines(original, "original", callGraph(original));
        for (TacParser.Function function : original.functions())
            analysis.addAll(analysis(function, "original"));
        TacParser.Program working = new TacParser.Program(
            original.arrays(),
            original.functions().stream().map(TacParser.Function::copy).toList());
        List<String> passes = new ArrayList<>();
        Map<String, Integer> totals = new HashMap<>();
        for (TacParser.Function function : working.functions())
            passes.addAll(optimize(function, settings, totals));
        CallGraph graph = callGraph(working);
        analysis.addAll(callGraphLines(working, "optimized", graph));
        List<String> removed = working.functions()
                                   .stream()
                                   .map(function -> function.name)
                                   .filter(name
                                           -> settings.enabled().contains("unreachable") &&
                                                  !graph.reachable().contains(name))
                                   .toList();
        TacParser.Program optimized = new TacParser.Program(
            working.arrays(), working.functions()
                                  .stream()
                                  .filter(function -> !removed.contains(function.name))
                                  .toList());
        passes.add("== program ==");
        passes.add("removed functions: " + list(removed));
        passes.add("== total ==");
        passes.add(String.join(" ", settings.enabled()
                                        .stream()
                                        .map(name -> name + "=" + totals.getOrDefault(name, 0))
                                        .toList()));
        List<TacParser.Function> allocatedFunctions = new ArrayList<>();
        List<String> regalloc = new ArrayList<>();
        for (TacParser.Function function : optimized.functions()) {
            analysis.addAll(analysis(function, "optimized"));
            AllocationReport allocation = allocation(function, settings.registers());
            allocatedFunctions.add(allocation.function());
            regalloc.addAll(allocation.lines());
        }
        TacParser.Program allocated = new TacParser.Program(optimized.arrays(), allocatedFunctions);
        Files.createDirectories(Path.of("output"));
        write("optimized.tac", TacParser.programLines(optimized));
        write("analysis.txt", analysis);
        write("passes.txt", passes);
        write("regalloc.txt", regalloc);
        write("comparison.txt", comparison(original, optimized, allocated, runs));
    }
}
