import java.math.BigInteger;
import java.util.*;
final class Regalloc {
    record Potential(String node, int degree) {}
    final TreeMap<String, Set<String>> neighbors = new TreeMap<>();
    final Map<String, BigInteger> costs = new HashMap<>();
    final Map<String, Set<String>> partners = new HashMap<>();
    final List<String> order = new ArrayList<>();
    final List<Potential> potential = new ArrayList<>();
    final Map<String, Integer> colors = new HashMap<>();
    final Set<String> spills = new HashSet<>();
    Regalloc(TacParser.Function function, Cfg graph, Dataflow flow, int registers) {
        Set<String> nodes = new TreeSet<>(function.parameters);
        for (var entry : graph.instructions.entrySet())
            if (graph.reachable.contains(graph.blockOf.get(entry.getKey()))) {
                TacParser.Instruction instruction = entry.getValue();
                nodes.addAll(instruction.used());
                if (instruction.destination() != null)
                    nodes.add(instruction.destination());
            }
        for (String node : nodes) {
            neighbors.put(node, new TreeSet<>());
            costs.put(node, BigInteger.ZERO);
            partners.put(node, new HashSet<>());
        }
        for (int blockNumber : graph.reachable) {
            Cfg.Block block = graph.blocks.get(blockNumber);
            Set<String> state = new HashSet<>(flow.live.outgoing().get(blockNumber));
            for (int i = block.instructions.size() - 1; i >= 0; i--) {
                TacParser.Instruction instruction =
                    graph.instructions.get(block.instructions.get(i));
                String destination = instruction.destination();
                if (destination != null) {
                    String partner = instruction.kind() == TacParser.Kind.COPY &&
                                             instruction.a() instanceof TacParser.Variable v
                                         ? v.name()
                                         : null;
                    for (String variable : state)
                        if (!variable.equals(destination) && !variable.equals(partner))
                            edge(destination, variable);
                }
                state = Dataflow.liveTransfer(instruction, state);
            }
            BigInteger weight = BigInteger.TEN.pow(graph.depth.get(blockNumber));
            for (int number : block.instructions) {
                TacParser.Instruction instruction = graph.instructions.get(number);
                List<String> occurrences = instruction.used();
                if (instruction.destination() != null)
                    occurrences.add(instruction.destination());
                for (String variable : occurrences)
                    costs.put(variable, costs.get(variable).add(weight));
            }
        }
        Set<String> entry = new HashSet<>(flow.live.incoming().get(1));
        entry.addAll(function.parameters);
        for (String parameter : function.parameters) {
            costs.put(parameter, costs.get(parameter).add(BigInteger.ONE));
            for (String variable : entry)
                if (!variable.equals(parameter))
                    edge(parameter, variable);
        }
        for (TacParser.Instruction instruction : function.instructions())
            if (instruction.kind() == TacParser.Kind.COPY &&
                instruction.a() instanceof TacParser.Variable v &&
                !v.name().equals(instruction.destination())) {
                String first = instruction.destination(), second = v.name();
                if (partners.containsKey(first))
                    partners.get(first).add(second);
                if (partners.containsKey(second))
                    partners.get(second).add(first);
            }
        Set<String> remaining = new TreeSet<>(nodes);
        while (!remaining.isEmpty()) {
            Map<String, Integer> degrees = new HashMap<>();
            for (String node : remaining) {
                int degree = 0;
                for (String neighbor : neighbors.get(node))
                    if (remaining.contains(neighbor))
                        degree++;
                degrees.put(node, degree);
            }
            String chosen = null;
            for (String node : remaining)
                if (degrees.get(node) < registers &&
                    (chosen == null || degrees.get(node) < degrees.get(chosen)))
                    chosen = node;
            if (chosen == null) {
                for (String node : remaining)
                    if (chosen == null || costs.get(node)
                                                  .multiply(BigInteger.valueOf(degrees.get(chosen)))
                                                  .compareTo(costs.get(chosen).multiply(
                                                      BigInteger.valueOf(degrees.get(node)))) < 0)
                        chosen = node;
                potential.add(new Potential(chosen, degrees.get(chosen)));
            }
            order.add(chosen);
            remaining.remove(chosen);
        }
        for (int i = order.size() - 1; i >= 0; i--) {
            String node = order.get(i);
            TreeSet<Integer> free = new TreeSet<>();
            for (int register = 0; register < registers; register ++)
                free.add(register);
            for (String neighbor : neighbors.get(node))
                if (colors.containsKey(neighbor))
                    free.remove(colors.get(neighbor));
            if (free.isEmpty()) {
                spills.add(node);
                continue;
            }
            TreeSet<Integer> preferred = new TreeSet<>();
            for (String partner : partners.get(node))
                if (colors.containsKey(partner) && free.contains(colors.get(partner)))
                    preferred.add(colors.get(partner));
            colors.put(node, preferred.isEmpty() ? free.first() : preferred.first());
        }
    }
    void edge(String first, String second) {
        neighbors.get(first).add(second);
        neighbors.get(second).add(first);
    }
}
