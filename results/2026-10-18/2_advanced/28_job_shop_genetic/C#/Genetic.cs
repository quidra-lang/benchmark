using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

static class Genetic {
    public static List<Operation> Operations(Instance instance, List<int> chromosome) {
        int[] counts = new int[14];
        List<Operation> operations = new();
        foreach (int gene in chromosome)
            operations.Add(instance.named[gene].operations[counts[gene]++]);
        return operations;
    }
    public static int[] Decode(Instance instance, List<int> chromosome) {
        int[] starts = new int[instance.operations.Count], ready = new int[14],
              free = new int[instance.machineCount];
        foreach (Operation operation in Operations(instance, chromosome)) {
            int start = Math.Max(ready[operation.job], free[operation.machine - 1]);
            starts[operation.ident] = start;
            ready[operation.job] = free[operation.machine - 1] = start + operation.duration;
        }
        return starts;
    }
    public static int Tournament(Minstd random, int[] values, int size) {
        int best = random.Below(values.Length);
        for (int i = 1; i < size; i++) {
            int pick = random.Below(values.Length);
            if (values[pick] < values[best] || values[pick] == values[best] && pick < best)
                best = pick;
        }
        return best;
    }
    public static List<int> Preserve(List<int> keeper, List<int> donor, HashSet<int> kept) {
        List<int> fillers = new();
        foreach (int gene in donor)
            if (!kept.Contains(gene))
                fillers.Add(gene);
        List<int> child = new();
        int position = 0;
        foreach (int gene in keeper)
            child.Add(kept.Contains(gene) ? gene : fillers[position++]);
        return child;
    }
    public static List<List<int>> Crossover(Minstd random, List<int> first, List<int> second,
                                            List<Job> jobs) {
        HashSet<int> kept = new();
        foreach (Job job in jobs)
            if (random.Below(2) == 0)
                kept.Add(job.number);
        return [Preserve(first, second, kept), Preserve(second, first, kept)];
    }
    public static void Swap(Minstd random, List<int> chromosome) {
        int first = random.Below(chromosome.Count), second = random.Below(chromosome.Count);
        Program.Swap(chromosome, first, second);
    }
    public static void Insert(Minstd random, List<int> chromosome) {
        int source = random.Below(chromosome.Count), target = random.Below(chromosome.Count);
        chromosome.Insert(target, Program.RemoveAt(chromosome, source));
    }
}
