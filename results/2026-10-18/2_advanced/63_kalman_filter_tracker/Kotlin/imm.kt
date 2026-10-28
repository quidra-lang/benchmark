import kotlin.math.*

class Imm(densities: DoubleArray,transitions: DoubleArray,initial: DoubleArray,sigma: Double,velocity: Double,measurement: DoubleArray) {
    val models=Array(2) {
        Kalman("CV",densities[it],sigma,velocity,0.0,measurement)
    };
    val transition=Array(2) {
        i->doubleArrayOf(transitions[2*i],transitions[2*i+1])
    };
    var probabilities=initial.copyOf()
    fun step(interval: Double,measurement: DoubleArray?) {
        val mu=probabilities;
        val predicted=DoubleArray(2) {
            j->transition[0][j]*mu[0]+transition[1][j]*mu[1]
        };
        val likelihoods=DoubleArray(2);
        val oldStates=Array(2) {
            models[it].x
        };
        val oldCovariances=Array(2) {
            models[it].p
        }
        for(j in 0..1) {
            val w0=transition[0][j]*mu[0]/predicted[j];
            val w1=transition[1][j]*mu[1]/predicted[j];
            val mixed=DoubleArray(4) {
                r->w0*oldStates[0][r]+w1*oldStates[1][r]
            };
            val covariance=Array(4) {
                r->DoubleArray(4) {
                    s->w0*(oldCovariances[0][r][s]+(oldStates[0][r]-mixed[r])*(oldStates[0][s]-mixed[s]))+w1*(oldCovariances[1][r][s]+(oldStates[1][r]-mixed[r])*(oldStates[1][s]-mixed[s]))
                }
            }
            val model=models[j];
            model.x=mixed;
            model.p=covariance;
            model.predict(interval);
            var likelihood=1.0;
            if(measurement!=null) {
                val update=model.update(measurement);
                likelihood=exp(-update.distance/2)/(2*PI*sqrt(Matrix.determinant2(update.covariance)))
            };
            likelihoods[j]=likelihood
        }
        val denominator=likelihoods[0]*predicted[0]+likelihoods[1]*predicted[1];
        probabilities=DoubleArray(2) {
            likelihoods[it]*predicted[it]/denominator
        }
    }
    fun estimate()=DoubleArray(4) {
        r->probabilities[0]*models[0].x[r]+probabilities[1]*models[1].x[r]
    }
}
