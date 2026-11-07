def priority(rule, operation, ready, gene_positions):
    if rule == "SPT":
        return operation.duration
    if rule == "LPT":
        return -operation.duration
    if rule == "MWKR":
        return -(operation.duration + operation.tail)
    if rule == "FIFO":
        return ready[operation.job]
    return gene_positions[operation.ident]


def giffler_thompson(instance, rule, gene_positions=None):
    starts = [0] * len(instance.operations)
    next_index = {job.number: 0 for job in instance.jobs}
    ready = {job.number: 0 for job in instance.jobs}
    free = [0] * instance.machine_count
    decisions = 0
    ties = 0
    for _ in range(len(instance.operations)):
        candidates = []
        for job in instance.jobs:
            if next_index[job.number] < len(job.operations):
                operation = job.operations[next_index[job.number]]
                earliest = max(ready[job.number], free[operation.machine - 1])
                candidates.append((operation, earliest))
        cutoff = min(earliest + operation.duration for operation, earliest in candidates)
        machine = min(
            operation.machine for operation, earliest in candidates
            if earliest + operation.duration == cutoff
        )
        conflict = [
            (operation, earliest) for operation, earliest in candidates
            if operation.machine == machine and earliest < cutoff
        ]
        values = [priority(rule, operation, ready, gene_positions) for operation, _ in conflict]
        lowest = min(values)
        if len(conflict) > 1:
            decisions += 1
        if values.count(lowest) > 1:
            ties += 1
        operation, earliest = conflict[values.index(lowest)]
        starts[operation.ident] = earliest
        ready[operation.job] = free[machine - 1] = earliest + operation.duration
        next_index[operation.job] += 1
    return starts, decisions, ties
