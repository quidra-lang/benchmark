import java.util.*;
final class Dataflow {
    record Definition(String variable, int number) {}
    record Copy(String destination, String source) {}
    interface Transfer<T> {
        Set<T> apply(TacParser.Instruction instruction, int number, Set<T> state);
    }
    record
        Solution<T>(Map<Integer, Set<T>> incoming, Map<Integer, Set<T>> outgoing, int iterations) {}
    final Cfg graph;
    final Solution<Definition> reaching;
    final Solution<String> live;
    final Solution<TacParser.Expression> expressions;
    final Solution<Copy> copies;
    final Map<Integer, Set<Definition>> reachingBefore;
    final Map<Integer, Set<TacParser.Expression>> expressionBefore;
    final Map<Integer, Set<Copy>> copyBefore;
    final Map<Integer, Set<String>> liveBefore = new HashMap<>(), liveAfter = new HashMap<>();
    static Set<Definition> reachingTransfer(TacParser.Instruction instruction, int number,
                                            Set<Definition> state) {
        Set<Definition> result = new HashSet<>(state);
        if (instruction.destination() != null) {
            result.removeIf(definition -> definition.variable().equals(instruction.destination()));
            result.add(new Definition(instruction.destination(), number));
        }
        return result;
    }
    static Set<String> liveTransfer(TacParser.Instruction instruction, Set<String> state) {
        Set<String> result = new HashSet<>(state);
        result.remove(instruction.destination());
        result.addAll(instruction.used());
        return result;
    }
    static Set<TacParser.Expression> expressionTransfer(TacParser.Instruction instruction,
                                                        int number,
                                                        Set<TacParser.Expression> state) {
        Set<TacParser.Expression> result = new HashSet<>(state);
        TacParser.Expression expression = instruction.expression();
        if (expression != null)
            result.add(expression);
        if (instruction.kind() == TacParser.Kind.STORE)
            result.removeIf(
                e -> e.kind() == TacParser.Kind.LOAD && e.operation().equals(instruction.name()));
        if (instruction.kind() == TacParser.Kind.CALL)
            result.removeIf(e -> e.kind() == TacParser.Kind.LOAD);
        if (instruction.destination() != null) {
            TacParser.Variable variable = new TacParser.Variable(instruction.destination());
            result.removeIf(e -> variable.equals(e.a()) || variable.equals(e.b()));
        }
        return result;
    }
    static Set<Copy> copyTransfer(TacParser.Instruction instruction, int number, Set<Copy> state) {
        Set<Copy> result = new HashSet<>(state);
        String destination = instruction.destination();
        if (destination != null)
            result.removeIf(copy
                            -> copy.destination().equals(destination) ||
                                   copy.source().equals(destination));
        if (instruction.kind() == TacParser.Kind.COPY &&
            instruction.a() instanceof TacParser.Variable source &&
            !source.name().equals(destination))
            result.add(new Copy(destination, source.name()));
        return result;
    }
    Dataflow(Cfg graph) {
        this.graph = graph;
        Set<TacParser.Expression> expressionUniverse = new HashSet<>();
        Set<Copy> copyUniverse = new HashSet<>();
        Set<Definition> parameters = new HashSet<>();
        for (String parameter : graph.function.parameters)
            parameters.add(new Definition(parameter, 0));
        for (var entry : graph.instructions.entrySet())
            if (graph.reachable.contains(graph.blockOf.get(entry.getKey()))) {
                TacParser.Instruction instruction = entry.getValue();
                if (instruction.expression() != null)
                    expressionUniverse.add(instruction.expression());
                if (instruction.kind() == TacParser.Kind.COPY &&
                    instruction.a() instanceof TacParser.Variable source &&
                    !source.name().equals(instruction.destination()))
                    copyUniverse.add(new Copy(instruction.destination(), source.name()));
            }
        reaching = forward(true, Set.of(), parameters, Dataflow::reachingTransfer);
        live = liveness();
        expressions = forward(false, expressionUniverse, Set.of(), Dataflow::expressionTransfer);
        copies = forward(false, copyUniverse, Set.of(), Dataflow::copyTransfer);
        reachingBefore = boundaries(reaching.incoming(), Dataflow::reachingTransfer);
        expressionBefore = boundaries(expressions.incoming(), Dataflow::expressionTransfer);
        copyBefore = boundaries(copies.incoming(), Dataflow::copyTransfer);
        for (int block : graph.reachable) {
            Set<String> state = new HashSet<>(live.outgoing().get(block));
            List<Integer> numbers = graph.blocks.get(block).instructions;
            for (int i = numbers.size() - 1; i >= 0; i--) {
                int number = numbers.get(i);
                liveAfter.put(number, new HashSet<>(state));
                state = liveTransfer(graph.instructions.get(number), state);
                liveBefore.put(number, new HashSet<>(state));
            }
        }
    }
    <T> Solution<T> forward(boolean union, Set<T> universe, Set<T> entry, Transfer<T> transfer) {
        Map<Integer, Set<T>> incoming = new HashMap<>(), outgoing = new HashMap<>();
        for (int block : graph.reachable)
            outgoing.put(block, new HashSet<>(universe));
        int iterations = 0;
        while (true) {
            iterations++;
            boolean changed = false;
            for (int number : graph.reversePostorder) {
                List<Integer> predecessors = graph.reachablePredecessors.get(number);
                Set<T> state = new HashSet<>();
                if (union) {
                    for (int predecessor : predecessors)
                        state.addAll(outgoing.get(predecessor));
                    if (number == 1)
                        state.addAll(entry);
                } else if (number != 1) {
                    state.addAll(outgoing.get(predecessors.getFirst()));
                    for (int predecessor : predecessors)
                        state.retainAll(outgoing.get(predecessor));
                }
                incoming.put(number, new HashSet<>(state));
                for (int instruction : graph.blocks.get(number).instructions)
                    state = transfer.apply(graph.instructions.get(instruction), instruction, state);
                if (!state.equals(outgoing.get(number))) {
                    outgoing.put(number, state);
                    changed = true;
                }
            }
            if (!changed)
                return new Solution<>(incoming, outgoing, iterations);
        }
    }
    Solution<String> liveness() {
        Map<Integer, Set<String>> incoming = new HashMap<>(), outgoing = new HashMap<>();
        for (int number : graph.reachable)
            incoming.put(number, new HashSet<>());
        int iterations = 0;
        while (true) {
            iterations++;
            boolean changed = false;
            for (int number : graph.postorder) {
                Set<String> state = new HashSet<>();
                for (int successor : graph.blocks.get(number).successors)
                    state.addAll(incoming.get(successor));
                outgoing.put(number, new HashSet<>(state));
                List<Integer> instructions = graph.blocks.get(number).instructions;
                for (int i = instructions.size() - 1; i >= 0; i--)
                    state = liveTransfer(graph.instructions.get(instructions.get(i)), state);
                if (!state.equals(incoming.get(number))) {
                    incoming.put(number, state);
                    changed = true;
                }
            }
            if (!changed)
                return new Solution<>(incoming, outgoing, iterations);
        }
    }
    <T> Map<Integer, Set<T>> boundaries(Map<Integer, Set<T>> incoming, Transfer<T> transfer) {
        Map<Integer, Set<T>> result = new HashMap<>();
        for (int block : graph.reachable) {
            Set<T> state = new HashSet<>(incoming.get(block));
            for (int number : graph.blocks.get(block).instructions) {
                result.put(number, new HashSet<>(state));
                state = transfer.apply(graph.instructions.get(number), number, state);
            }
        }
        return result;
    }
}
