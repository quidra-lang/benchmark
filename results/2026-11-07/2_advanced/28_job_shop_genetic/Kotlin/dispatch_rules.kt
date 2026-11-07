data class Dispatch(val starts: IntArray, val decisions: Int, val ties: Int)
object DispatchRules {
    fun priority(rule: String, operation: Operation, ready: IntArray, positions: IntArray): Int = when (rule) {
        "SPT" -> operation.duration
        "LPT" -> -operation.duration
        "MWKR" -> -operation.duration - operation.tail
        "FIFO" -> ready[operation.job]
        else -> positions[operation.ident]
    }
    fun schedule(instance: Instance, rule: String, positions: IntArray = IntArray(0)): Dispatch {
        val starts = IntArray(instance.operations.size);
        val next = IntArray(14);
        val ready = IntArray(14);
        val free = IntArray(instance.machineCount)
        var decisions = 0;
        var ties = 0
        repeat(starts.size) {
            val candidates = instance.jobs.mapNotNull {
                job -> if (next[job.number] < job.operations.size) job.operations[next[job.number]] else null
            }
            val earliest = candidates.associate {
                it.ident to maxOf(ready[it.job], free[it.machine - 1])
            }
            val cutoff = candidates.minOf {
                earliest.getValue(it.ident) + it.duration
            }
            val machine = candidates.filter {
                earliest.getValue(it.ident) + it.duration == cutoff
            }.minOf {
                it.machine
            }
            val conflicts = candidates.filter {
                it.machine == machine && earliest.getValue(it.ident) < cutoff
            }
            val lowest = conflicts.minOf {
                priority(rule, it, ready, positions)
            }
            val equal = conflicts.filter {
                priority(rule, it, ready, positions) == lowest
            }
            val chosen = equal.first()
            if (conflicts.size > 1) decisions++;
            if (equal.size > 1) ties++
            starts[chosen.ident] = earliest.getValue(chosen.ident);
            val completion = starts[chosen.ident] + chosen.duration
            ready[chosen.job] = completion;
            free[machine - 1] = completion;
            next[chosen.job]++
        }
        return Dispatch(starts, decisions, ties)
    }
}
