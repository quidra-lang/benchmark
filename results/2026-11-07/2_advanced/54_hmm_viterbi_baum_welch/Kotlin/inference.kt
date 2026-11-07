import kotlin.math.ln

object Inference {
    data class Forward(val values: Array<DoubleArray>,val scales: DoubleArray,val emissions: Array<DoubleArray>,val loglik: Double)
    data class Fb(val forward: Array<DoubleArray>,val backward: Array<DoubleArray>,val scales: DoubleArray,
        val emissions: Array<DoubleArray>,val gamma: Array<DoubleArray>,val loglik: Double)
    data class Path(val states: IntArray,val logprob: Double)
    data class Decoding(val viterbi: Path,val posterior: IntArray,val confidence: DoubleArray,val fb: Fb)
    fun maximum(values: DoubleArray): Int {
        var best=0;
        for(i in 1 until values.size)if(values[i]>values[best])best=i;
        return best
    }
    fun emission(model: ModelIo.Model,observed: Int,state: Int)=if(observed<0)1.0 else model.b[state][observed]
    fun forward(model: ModelIo.Model,observations: IntArray): Forward {
        val t=observations.size;
        val k=model.states.size;
        val values=Array(t) {
            DoubleArray(k)
        };
        val emissions=Array(t) {
            DoubleArray(k)
        };
        val scales=DoubleArray(t);
        var loglik=0.0;
        for(p in 0 until t) {
            for(j in 0 until k) {
                emissions[p][j]=emission(model,observations[p],j);
                var value=0.0;
                if(p==0)value=model.pi[j] else for(i in 0 until k)value+=values[p-1][i]*model.a[i][j];
                values[p][j]=value*emissions[p][j];
                scales[p]+=values[p][j]
            };
            for(j in 0 until k)values[p][j]/=scales[p];
            loglik+=ln(scales[p])
        };
        return Forward(values,scales,emissions,loglik)
    }
    fun backward(model: ModelIo.Model,observations: IntArray): Fb {
        val f=forward(model,observations);
        val t=observations.size;
        val k=model.states.size;
        val g=Array(t) {
            DoubleArray(k)
        };
        val gamma=Array(t) {
            DoubleArray(k)
        };
        g[t-1].fill(1.0);
        for(p in t-2 downTo 0)for(i in 0 until k) {
            var sum=0.0;
            for(j in 0 until k)sum+=model.a[i][j]*f.emissions[p+1][j]*g[p+1][j];
            g[p][i]=sum/f.scales[p+1]
        };
        for(p in 0 until t)for(i in 0 until k)gamma[p][i]=f.values[p][i]*g[p][i];
        return Fb(f.values,g,f.scales,f.emissions,gamma,f.loglik)
    }
    fun xi(model: ModelIo.Model,fb: Fb,t: Int,i: Int,j: Int)=fb.forward[t][i]*model.a[i][j]*fb.emissions[t+1][j]*fb.backward[t+1][j]/fb.scales[t+1]
    fun viterbi(model: ModelIo.Model,observations: IntArray): Path {
        val t=observations.size;
        val k=model.states.size;
        val logA=Array(k) {
            i->DoubleArray(k) {
                j->ln(model.a[i][j])
            }
        };
        var scores=DoubleArray(k) {
            j->ln(model.pi[j])+if(observations[0]<0)0.0 else ln(model.b[j][observations[0]])
        };
        val previous=Array(t) {
            IntArray(k)
        };
        for(p in 1 until t) {
            val next=DoubleArray(k);
            for(j in 0 until k) {
                val candidates=DoubleArray(k) {
                    i->scores[i]+logA[i][j]
                };
                val best=maximum(candidates);
                previous[p][j]=best;
                next[j]=candidates[best]+if(observations[p]<0)0.0 else ln(model.b[j][observations[p]])
            };
            scores=next
        };
        val path=IntArray(t);
        path[t-1]=maximum(scores);
        val logprob=scores[path[t-1]];
        for(p in t-1 downTo 1)path[p-1]=previous[p][path[p]];
        return Path(path,logprob)
    }
    fun decode(model: ModelIo.Model,observations: IntArray): Decoding {
        val fb=backward(model,observations);
        val path=viterbi(model,observations);
        val posterior=IntArray(observations.size) {
            maximum(fb.gamma[it])
        };
        val confidence=DoubleArray(observations.size) {
            fb.gamma[it][posterior[it]]
        };
        return Decoding(path,posterior,confidence,fb)
    }
}
