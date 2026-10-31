object Genetic {
    fun operations(instance: Instance, chromosome: List<Int>): List<Operation> {
        val counts = IntArray(14)
        return chromosome.map {
            gene -> instance.named.getValue(gene).operations[counts[gene]++]
        }
    }
    fun decode(instance: Instance, chromosome: List<Int>): IntArray {
        val starts = IntArray(instance.operations.size);
        val ready = IntArray(14);
        val free = IntArray(instance.machineCount)
        for (operation in operations(instance, chromosome)) {
            val start = maxOf(ready[operation.job], free[operation.machine - 1]);
            starts[operation.ident] = start;
            ready[operation.job] = start + operation.duration;
            free[operation.machine - 1] = start + operation.duration
        }
        return starts
    }
    fun tournament(random: Minstd, values: IntArray, size: Int): Int {
        var best = random.below(values.size)
        repeat(size - 1) {
            val pick = random.below(values.size);
            if (values[pick] < values[best] || values[pick] == values[best] && pick < best) best = pick
        }
        return best
    }
    fun preserve(keeper: List<Int>, donor: List<Int>, kept: Set<Int>): MutableList<Int> {
        val fillers = donor.filter {
            it !in kept
        }.iterator()
        return keeper.map {
            if (it in kept) it else fillers.next()
        }.toMutableList()
    }
    fun crossover(random: Minstd, first: List<Int>, second: List<Int>, jobs: List<Job>): List<MutableList<Int>> {
        val kept = jobs.filter {
            random.below(2) == 0
        }.map {
            it.number
        }.toSet()
        return listOf(preserve(first, second, kept), preserve(second, first, kept))
    }
    fun swap(random: Minstd, chromosome: MutableList<Int>) {
        val first = random.below(chromosome.size);
        val second = random.below(chromosome.size);
        val old = chromosome[first];
        chromosome[first] = chromosome[second];
        chromosome[second] = old
    }
    fun insert(random: Minstd, chromosome: MutableList<Int>) {
        val source = random.below(chromosome.size);
        val target = random.below(chromosome.size);
        chromosome.add(target, chromosome.removeAt(source))
    }
}
