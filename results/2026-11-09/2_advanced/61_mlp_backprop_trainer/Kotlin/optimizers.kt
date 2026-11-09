import kotlin.math.sqrt

object Optimizers {
    class State(val run: Dataset.Run,size: Int) {
        val first=DoubleArray(size);
        val second=DoubleArray(size);
        var pi1=1.0;
        var pi2=1.0
        fun update(theta: DoubleArray,gradient: DoubleArray,eta: Double) {
            if(run.optimizer=="ADAM") {
                pi1*=run.beta1;
                pi2*=run.beta2
            }
            for(p in theta.indices) {
                val g=gradient[p]
                if(run.optimizer=="SGD")theta[p]=theta[p]-eta*g
                else if(run.optimizer=="MOMENTUM") {
                    second[p]=run.momentum*second[p]+g;
                    theta[p]=theta[p]-eta*second[p]
                }
                else {
                    first[p]=run.beta1*first[p]+(1-run.beta1)*g;
                    second[p]=run.beta2*second[p]+(1-run.beta2)*g*g;
                    val m=first[p]/(1-pi1);
                    val v=second[p]/(1-pi2);
                    theta[p]=theta[p]-eta*m/(sqrt(v)+run.epsilon)
                }
            }
        }
    }
    fun rate(run: Dataset.Run,settings: Dataset.Settings,epoch: Int): Double {
        var eta=run.eta;
        repeat((epoch-1)/settings.decayStep) {
            eta*=settings.gamma
        };
        return eta
    }
}
