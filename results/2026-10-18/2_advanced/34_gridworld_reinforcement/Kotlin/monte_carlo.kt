object MonteCarlo {
    data class Step(val cell: Int, val action: Int, val reward: Long)
    fun update(q: Array<LongArray>, sums: Array<LongArray>, counts: Array<LongArray>, steps: List<Step>, gamma: Int) {
        val first = mutableMapOf<Int,Int>();
        for (t in steps.indices) {
            val step = steps[t];
            first.putIfAbsent(step.cell * 4 + step.action,t)
        }
        var value = 0L
        for (t in steps.indices.reversed()) {
            val step = steps[t];
            value = 10000 * step.reward + DynamicProgramming.floor(gamma * value,100);
            if (first[step.cell * 4 + step.action] == t) {
                sums[step.cell][step.action] += value;
                counts[step.cell][step.action]++;
                q[step.cell][step.action] = DynamicProgramming.floor(sums[step.cell][step.action],counts[step.cell][step.action])
            }
        }
    }
    fun discounted(rewards: List<Long>, gamma: Int): Long {
        var result = 0L;
        for (i in rewards.indices.reversed()) result = 10000 * rewards[i] + DynamicProgramming.floor(gamma * result,100);
        return result
    }
}
