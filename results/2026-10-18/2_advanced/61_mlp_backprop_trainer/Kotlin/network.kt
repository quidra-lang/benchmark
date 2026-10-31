class Network(val name: String,val inputs: Int,val units: IntArray,val activations: Array<String>) {
    val layers=units.size;
    val classes=units.last();
    var parameters=0;
    var weights=0;
    val starts=IntArray(layers);
    val biases=IntArray(layers);
    val weight: BooleanArray;
    val initial: DoubleArray
    init {
        var previous=inputs
        for(l in 0 until layers) {
            starts[l]=parameters;
            val count=units[l]*previous;
            weights+=count;
            parameters+=count;
            biases[l]=parameters;
            parameters+=units[l];
            previous=units[l]
        }
        weight=BooleanArray(parameters);
        initial=DoubleArray(parameters)
        for(l in 0 until layers)for(p in starts[l] until biases[l])weight[p]=true
    }
    data class Pass(val z: Array<DoubleArray>,val a: Array<DoubleArray>,val scores: DoubleArray,val delta: DoubleArray,val loss: Double)
    data class Backward(val gradient: DoubleArray,val input: DoubleArray)
    fun forward(theta: DoubleArray,image: Dataset.Image): Pass {
        val z=Array(layers) {
            DoubleArray(0)
        };
        val a=Array(layers+1) {
            DoubleArray(0)
        };
        a[0]=image.values;
        var output: Layers.Output?=null
        for(l in 0 until layers) {
            val previous=if(l==0)inputs else units[l-1];
            z[l]=Layers.linear(theta,starts[l],biases[l],previous,units[l],a[l])
            if(l+1==layers) {
                val result=Layers.output(activations[l],z[l],image.label);
                output=result;
                a[l+1]=result.scores
            }
            else a[l+1]=DoubleArray(units[l]) {
                j->Layers.activation(activations[l],z[l][j])
            }
        }
        val result=output!!;
        return Pass(z,a,result.scores,result.delta,result.loss)
    }
    fun backward(theta: DoubleArray,pass: Pass): Backward {
        val delta=Array(layers) {
            DoubleArray(0)
        };
        delta[layers-1]=pass.delta
        for(l in layers-2 downTo 0) {
            delta[l]=DoubleArray(units[l]);
            for(j in 0 until units[l]) {
                val value=Layers.backward(theta,starts[l+1],units[l],units[l+1],j,delta[l+1]);
                delta[l][j]=value*Layers.derivative(activations[l],pass.z[l][j],pass.a[l+1][j])
            }
        }
        val gradient=DoubleArray(parameters);
        val input=DoubleArray(inputs)
        for(l in 0 until layers) {
            val previous=if(l==0)inputs else units[l-1];
            for(j in 0 until units[l]) {
                for(i in 0 until previous)gradient[starts[l]+j*previous+i]=delta[l][j]*pass.a[l][i];
                gradient[biases[l]+j]=delta[l][j]
            }
        }
        for(i in 0 until inputs)input[i]=Layers.backward(theta,starts[0],inputs,units[0],i,delta[0])
        return Backward(gradient,input)
    }
}
