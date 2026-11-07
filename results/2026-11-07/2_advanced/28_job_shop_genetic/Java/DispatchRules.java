import java.util.*;

record Dispatch(int[] starts, int decisions, int ties) {}
final class DispatchRules {
    static int priority(String rule, Operation operation, int[] ready, int[] positions) {
        return switch (rule) {
            case "SPT" -> operation.duration;
            case "LPT" -> -operation.duration;
            case "MWKR" -> -operation.duration - operation.tail;
            case "FIFO" -> ready[operation.job];
            default -> positions[operation.ident];
        };
    }
    static Dispatch schedule(Instance instance, String rule, int[] positions) {
        int[] starts = new int[instance.operations.size()], next = new int[14], ready = new int[14],
              free = new int[instance.machineCount];
        int decisions = 0, ties = 0;
        for (int step = 0; step < starts.length; step++) {
            List<Operation> candidates = new ArrayList<>();
            int[] earliest = new int[starts.length];
            int cutoff = Integer.MAX_VALUE, machine = Integer.MAX_VALUE;
            for (Job job : instance.jobs)
                if (next[job.number()] < job.operations().size()) {
                    Operation operation = job.operations().get(next[job.number()]);
                    candidates.add(operation);
                    earliest[operation.ident] = Math.max(ready[operation.job], free[operation.machine - 1]);
                    int completion = earliest[operation.ident] + operation.duration;
                    if (completion < cutoff || completion == cutoff && operation.machine < machine) {
                        cutoff = completion;
                        machine = operation.machine;
                    }
                }
            Operation chosen = null;
            int lowest = Integer.MAX_VALUE, conflicts = 0, equal = 0;
            for (Operation operation : candidates)
                if (operation.machine == machine && earliest[operation.ident] < cutoff) {
                    conflicts++;
                    int value = priority(rule, operation, ready, positions);
                    if (value < lowest) {
                        lowest = value;
                        chosen = operation;
                        equal = 1;
                    } else if (value == lowest)
                        equal++;
                }
            if (conflicts > 1)
                decisions++;
            if (equal > 1)
                ties++;
            starts[chosen.ident] = earliest[chosen.ident];
            ready[chosen.job] = free[machine - 1] = starts[chosen.ident] + chosen.duration;
            next[chosen.job]++;
        }
        return new Dispatch(starts, decisions, ties);
    }
}
