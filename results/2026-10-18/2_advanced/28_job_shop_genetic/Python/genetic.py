def gene_operations(instance, chromosome):
    counts = {job.number: 0 for job in instance.jobs}
    operations = []
    for gene in chromosome:
        operations.append(instance.job_map[gene].operations[counts[gene]])
        counts[gene] += 1
    return operations


def decode(instance, chromosome):
    starts = [0] * len(instance.operations)
    ready = {job.number: 0 for job in instance.jobs}
    free = [0] * instance.machine_count
    for operation in gene_operations(instance, chromosome):
        start = max(ready[operation.job], free[operation.machine - 1])
        starts[operation.ident] = start
        ready[operation.job] = free[operation.machine - 1] = start + operation.duration
    return starts


def tournament(rng, values, size):
    picks = [rng.below(len(values)) for _ in range(size)]
    return min(picks, key=lambda index: (values[index], index))


def preserve_order(keeper, donor, kept):
    fillers = iter([gene for gene in donor if gene not in kept])
    return [gene if gene in kept else next(fillers) for gene in keeper]


def crossover(rng, first, second, job_numbers):
    kept = set()
    for job in job_numbers:
        if rng.below(2) == 0:
            kept.add(job)
    return preserve_order(first, second, kept), preserve_order(second, first, kept)


def swap_mutation(rng, chromosome):
    first = rng.below(len(chromosome))
    second = rng.below(len(chromosome))
    chromosome[first], chromosome[second] = chromosome[second], chromosome[first]


def insert_mutation(rng, chromosome):
    source = rng.below(len(chromosome))
    target = rng.below(len(chromosome))
    chromosome.insert(target, chromosome.pop(source))
