using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed record Dispatch(int[] starts, int decisions, int ties);
static class DispatchRules {
    public static int Priority(string rule, Operation operation, int[] ready, int[] positions) {
        return rule switch { "SPT" => operation.duration, "LPT" => -operation.duration,
                             "MWKR" => -operation.duration - operation.tail, "FIFO" => ready[operation.job],
                             _ => positions[operation.ident] };
    }
    public static Dispatch Schedule(Instance instance, string rule, int[] positions) {
        int[] starts = new int[instance.operations.Count], next = new int[14], ready = new int[14],
              free = new int[instance.machineCount];
        int decisions = 0, ties = 0;
        for (int step = 0; step < starts.Length; step++) {
            List<Operation> candidates = new();
            int[] earliest = new int[starts.Length];
            int cutoff = int.MaxValue, machine = int.MaxValue;
            foreach (Job job in instance.jobs)
                if (next[job.number] < job.operations.Count) {
                    Operation operation = job.operations[next[job.number]];
                    candidates.Add(operation);
                    earliest[operation.ident] = Math.Max(ready[operation.job], free[operation.machine - 1]);
                    int completion = earliest[operation.ident] + operation.duration;
                    if (completion < cutoff || completion == cutoff && operation.machine < machine) {
                        cutoff = completion;
                        machine = operation.machine;
                    }
                }
            Operation chosen = null;
            int lowest = int.MaxValue, conflicts = 0, equal = 0;
            foreach (Operation operation in candidates)
                if (operation.machine == machine && earliest[operation.ident] < cutoff) {
                    conflicts++;
                    int value = Priority(rule, operation, ready, positions);
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
