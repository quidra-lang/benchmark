import kotlin.math.*

object Layers {
    data class Output(val scores: DoubleArray,val delta: DoubleArray,val loss: Double)
    fun activation(kind: String,z: Double)=if(kind=="TANH")tanh(z) else if(kind=="SIGMOID")1/(1+exp(-z)) else if(z>0)z else 0.0
    fun derivative(kind: String,z: Double,a: Double)=if(kind=="TANH")1-a*a else if(kind=="SIGMOID")a*(1-a) else if(z>0)1.0 else 0.0
    fun linear(theta: DoubleArray,start: Int,bias: Int,inputs: Int,units: Int,previous: DoubleArray): DoubleArray {
        val z=DoubleArray(units);
        for(j in 0 until units) {
            var sum=0.0;
            for(i in 0 until inputs)sum+=theta[start+j*inputs+i]*previous[i];
            z[j]=sum+theta[bias+j]
        };
        return z
    }
    fun backward(theta: DoubleArray,start: Int,inputs: Int,units: Int,own: Int,delta: DoubleArray): Double {
        var sum=0.0;
        for(j in 0 until units)sum+=theta[start+j*inputs+own]*delta[j];
        return sum
    }
    fun output(kind: String,z: DoubleArray,label: Int): Output {
        val k=z.size;
        val scores=DoubleArray(k);
        val delta=DoubleArray(k);
        var loss=0.0
        if(kind=="SOFTMAX") {
            var maximum=z[0];
            for(j in 1 until k)maximum=maxOf(maximum,z[j]);
            var sum=0.0;
            for(j in 0 until k) {
                scores[j]=exp(z[j]-maximum);
                sum+=scores[j]
            }
            for(j in 0 until k) {
                scores[j]/=sum;
                delta[j]=scores[j]-(if(j==label)1 else 0)
            };
            loss=ln(sum)-(z[label]-maximum)
        } else {
            for(j in 0 until k) {
                scores[j]=1/(1+exp(-z[j]));
                val error=scores[j]-(if(j==label)1 else 0);
                loss+=error*error;
                delta[j]=2*error*scores[j]*(1-scores[j])/k
            };
            loss/=k
        }
        return Output(scores,delta,loss)
    }
}
