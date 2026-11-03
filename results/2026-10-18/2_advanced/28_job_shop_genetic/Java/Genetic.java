import java.util.*;

final class Genetic {
    static List<Operation> operations(Instance instance, List<Integer> chromosome) {
        int[] counts = new int[14];
        List<Operation> operations = new ArrayList<>();
        for (int gene : chromosome)
            operations.add(instance.named.get(gene).operations().get(counts[gene]++));
        return operations;
    }
    static int[] decode(Instance instance, List<Integer> chromosome) {
        int[] starts = new int[instance.operations.size()], ready = new int[14],
              free = new int[instance.machineCount];
        for (Operation operation : operations(instance, chromosome)) {
            int start = Math.max(ready[operation.job], free[operation.machine - 1]);
            starts[operation.ident] = start;
            ready[operation.job] = free[operation.machine - 1] = start + operation.duration;
        }
        return starts;
    }
    static int tournament(Minstd random, int[] values, int size) {
        int best = random.below(values.length);
        for (int i = 1; i < size; i++) {
            int pick = random.below(values.length);
            if (values[pick] < values[best] || values[pick] == values[best] && pick < best)
                best = pick;
        }
        return best;
    }
    static List<Integer> preserve(List<Integer> keeper, List<Integer> donor, Set<Integer> kept) {
        List<Integer> fillers = new ArrayList<>();
        for (int gene : donor)
            if (!kept.contains(gene))
                fillers.add(gene);
        List<Integer> child = new ArrayList<>();
        int position = 0;
        for (int gene : keeper)
            child.add(kept.contains(gene) ? gene : fillers.get(position++));
        return child;
    }
    static List<List<Integer>> crossover(Minstd random, List<Integer> first, List<Integer> second,
                                         List<Job> jobs) {
        Set<Integer> kept = new HashSet<>();
        for (Job job : jobs)
            if (random.below(2) == 0)
                kept.add(job.number());
        return List.of(preserve(first, second, kept), preserve(second, first, kept));
    }
    static void swap(Minstd random, List<Integer> chromosome) {
        int first = random.below(chromosome.size()), second = random.below(chromosome.size());
        Collections.swap(chromosome, first, second);
    }
    static void insert(Minstd random, List<Integer> chromosome) {
        int source = random.below(chromosome.size()), target = random.below(chromosome.size());
        chromosome.add(target, chromosome.remove(source));
    }
}
