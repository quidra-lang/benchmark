object Sampling {
    class Minstd(seed: Long) {
        var state=seed;
        fun uniform(): Double {
            state=48271*state%2147483647;
            return state.toDouble()/2147483647
        }
    }
    data class Weighted(val sample: IntArray,val weight: Double)
    fun choose(probabilities: DoubleArray,random: Minstd): Int {
        val u=random.uniform();
        var cumulative=0.0;
        for((state,probability) in probabilities.withIndex()) {
            cumulative+=probability;
            if(u<cumulative)return state
        };
        return probabilities.lastIndex
    }
    fun weighted(order: List<Int>,parents: List<List<Int>>,cpts: List<Array<DoubleArray>>,sizes: IntArray,
        evidence: IntArray,random: Minstd): Weighted {
        val sample=IntArray(sizes.size);
        var weight=1.0;
        for(v in order) {
            val row=cpts[v][Learning.parentRow(parents[v],sample,sizes)];
            if(evidence[v]>=0) {
                sample[v]=evidence[v];
                weight*=row[evidence[v]]
            } else sample[v]=choose(row,random)
        };
        return Weighted(sample,weight)
    }
}
