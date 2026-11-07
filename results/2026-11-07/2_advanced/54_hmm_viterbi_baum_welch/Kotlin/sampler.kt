object Sampler {
    class Random(var state: Long) {
        fun next(): Double {
            state=48271*state%2147483647;
            return state/2147483647.0
        }
    }
    data class Synthetic(val states: IntArray,val observations: IntArray)
    fun draw(weights: DoubleArray,random: Random): Int {
        var total=0.0;
        for(weight in weights)total+=weight;
        val threshold=random.next()*total;
        var cumulative=0.0;
        for(i in weights.indices) {
            cumulative+=weights[i];
            if(threshold<cumulative)return i
        };
        return weights.lastIndex
    }
    fun synthetic(model: ModelIo.Model,length: Int,random: Random): Synthetic {
        val states=IntArray(length);
        val observations=IntArray(length);
        for(t in 0 until length) {
            states[t]=draw(if(t==0)model.pi else model.a[states[t-1]],random);
            observations[t]=draw(model.b[states[t]],random)
        };
        return Synthetic(states,observations)
    }
    fun posterior(model: ModelIo.Model,forward: Array<DoubleArray>,random: Random): IntArray {
        val path=IntArray(forward.size);
        path[path.lastIndex]=draw(forward.last(),random);
        for(t in path.size-2 downTo 0) {
            val weights=DoubleArray(model.states.size) {
                i->forward[t][i]*model.a[i][path[t+1]]
            };
            path[t]=draw(weights,random)
        };
        return path
    }
}
