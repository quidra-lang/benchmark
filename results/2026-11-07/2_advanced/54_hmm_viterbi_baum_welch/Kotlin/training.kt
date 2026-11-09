object Training {
    data class Pair(val observations: IntArray,val path: IntArray)
    fun smooth(template: ModelIo.Model,name: String,pi: DoubleArray,a: Array<DoubleArray>,b: Array<DoubleArray>,alpha: Double): ModelIo.Model {
        for(i in pi.indices) {
            pi[i]+=alpha;
            for(j in a[i].indices)a[i][j]+=alpha;
            for(c in b[i].indices)b[i][c]+=alpha
        };
        return ModelIo.Model(name,template.states,template.symbols,template.missing,pi,a,b)
    }
    fun baumWelch(model: ModelIo.Model,sequences: List<IntArray>,alpha: Double): ModelIo.Model {
        val k=model.states.size;
        val m=model.symbols.size;
        val pi=DoubleArray(k);
        val a=Array(k) {
            DoubleArray(k)
        };
        val b=Array(k) {
            DoubleArray(m)
        };
        for(observations in sequences) {
            val fb=Inference.backward(model,observations);
            for(i in 0 until k)pi[i]+=fb.gamma[0][i];
            for(t in observations.indices)for(i in 0 until k) {
                if(observations[t]>=0)b[i][observations[t]]+=fb.gamma[t][i];
                if(t+1<observations.size)for(j in 0 until k)a[i][j]+=Inference.xi(model,fb,t,i,j)
            }
        };
        return smooth(model,"BAUM_WELCH",pi,a,b,alpha)
    }
    fun count(template: ModelIo.Model,pairs: List<Pair>,alpha: Double,name: String): ModelIo.Model {
        val k=template.states.size;
        val m=template.symbols.size;
        val pi=DoubleArray(k);
        val a=Array(k) {
            DoubleArray(k)
        };
        val b=Array(k) {
            DoubleArray(m)
        };
        for(pair in pairs) {
            val path=pair.path;
            val observations=pair.observations;
            pi[path[0]]++;
            for(t in path.indices) {
                if(observations[t]>=0)b[path[t]][observations[t]]++;
                if(t+1<path.size)a[path[t]][path[t+1]]++
            }
        };
        return smooth(template,name,pi,a,b,alpha)
    }
    fun loglik(model: ModelIo.Model,sequences: List<IntArray>): Double {
        var sum=0.0;
        for(observations in sequences)sum+=Inference.forward(model,observations).loglik;
        return sum
    }
}
