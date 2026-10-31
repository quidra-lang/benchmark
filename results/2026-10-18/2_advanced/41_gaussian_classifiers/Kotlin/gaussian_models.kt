import kotlin.math.*

object GaussianModels {
    val NAMES=listOf("NB","LDA","QDA")
    class Statistics(training: List<Dataset.Row>,features: IntArray,classes: Int) {
        val rows=training.size;
        val p=features.size;
        val counts=IntArray(classes);
        val means=Array(classes) {
            DoubleArray(p)
        };
        val scatter=Array(classes) {
            Linalg.zeros(p)
        };
        val center=DoubleArray(p);
        val variances=DoubleArray(p)
        init {
            for(r in training) {
                counts[r.y]++;
                for(j in 0 until p)means[r.y][j]+=r.values[features[j]]
            };
            for(k in 0 until classes)for(j in 0 until p)means[k][j]/=counts[k].toDouble();
            for(k in 0 until classes)for(a in 0 until p)for(b in 0 until p) {
                var sum=0.0;
                for(r in training)if(r.y==k)sum+=(r.values[features[a]]-means[k][a])*(r.values[features[b]]-means[k][b]);
                scatter[k][a][b]=sum
            };
            for(j in 0 until p) {
                var sum=0.0;
                for(r in training)sum+=r.values[features[j]];
                center[j]=sum/rows;
                sum=0.0;
                for(r in training) {
                    val difference=r.values[features[j]]-center[j];
                    sum+=difference*difference
                };
                variances[j]=sum/rows
            }
        }
        fun pooled(): Array<DoubleArray> {
            val result=Linalg.zeros(p);
            for(a in 0 until p)for(b in 0 until p) {
                var sum=0.0;
                for(matrix in scatter)sum+=matrix[a][b];
                result[a][b]=sum/(rows-counts.size)
            };
            return result
        }
    }
    fun argmax(values: DoubleArray): Int {
        var best=0;
        for(i in 1 until values.size)if(values[i]>values[best])best=i;
        return best
    }
    fun argmin(values: DoubleArray): Int {
        var best=0;
        for(i in 1 until values.size)if(values[i]<values[best])best=i;
        return best
    }
    class Prediction(val predicted: Int,val decision: Int,val posterior: DoubleArray,val logPosterior: DoubleArray,val confidence: Double)
    class Model(rows: List<Dataset.Row>,features: IntArray,classes: Int,val kind: Int,prior: String,epsilon: Double,gamma: Double) {
        val features=features.copyOf();
        val statistics=Statistics(rows,features,classes);
        val priors=DoubleArray(classes);
        val logDet=DoubleArray(classes);
        val covariance=Array(classes) {
            Linalg.zeros(features.size)
        };
        val factors=Array(classes) {
            Linalg.zeros(features.size)
        };
        val maxVariance=statistics.variances.max();
        val added=epsilon*maxVariance;
        val normalizer=features.size*ln(2*PI)/2
        init {
            val pooled=if(kind==1)statistics.pooled() else null;
            for(k in 0 until classes) {
                priors[k]=if(prior=="empirical")statistics.counts[k].toDouble()/rows.size else 1.0/classes;
                val matrix=pooled?:Linalg.zeros(features.size);
                if(kind!=1)for(a in features.indices)for(b in features.indices) {
                    if(kind==0) {
                        if(a==b)matrix[a][b]=statistics.scatter[k][a][b]/statistics.counts[k]+added
                    }else {
                        val value=statistics.scatter[k][a][b]/(statistics.counts[k]-1);
                        matrix[a][b]=if(a==b)value else value*(1-gamma)
                    }
                };
                covariance[k]=matrix;
                if(kind==1&&k>0) {
                    factors[k]=factors[0];
                    logDet[k]=logDet[0]
                }else {
                    factors[k]=Linalg.cholesky(matrix);
                    logDet[k]=Linalg.logDet(factors[k])
                }
            }
        }
        fun vector(values: DoubleArray)=DoubleArray(features.size) {
            values[features[it]]
        }
        fun distancesVector(vector: DoubleArray)=DoubleArray(priors.size) {
            k->val difference=DoubleArray(features.size) {
                vector[it]-statistics.means[k][it]
            };
            Linalg.quadratic(factors[k],difference)
        }
        fun distances(values: DoubleArray)=distancesVector(vector(values))
        fun scores(vector: DoubleArray): DoubleArray {
            val q=distancesVector(vector);
            return DoubleArray(q.size) {
                ln(priors[it])-normalizer-logDet[it]/2-q[it]/2
            }
        }
        fun predict(values: DoubleArray)=argmax(scores(vector(values)))
        fun inferVector(vector: DoubleArray,costs: Array<DoubleArray>?): Prediction {
            val scores=scores(vector);
            val predicted=argmax(scores);
            val maximum=scores[predicted];
            val posterior=DoubleArray(scores.size);
            var sum=0.0;
            for(k in scores.indices) {
                posterior[k]=exp(scores[k]-maximum);
                sum+=posterior[k]
            };
            val logPosterior=DoubleArray(scores.size);
            var confidence=0.0;
            for(k in scores.indices) {
                posterior[k]/=sum;
                logPosterior[k]=(scores[k]-maximum)-ln(sum);
                confidence=maxOf(confidence,posterior[k])
            };
            var decision=predicted;
            if(costs!=null) {
                val risks=DoubleArray(scores.size);
                for(b in risks.indices)for(k in scores.indices)risks[b]+=posterior[k]*costs[k][b];
                decision=argmin(risks)
            };
            return Prediction(predicted,decision,posterior,logPosterior,confidence)
        }
        fun infer(values: DoubleArray,costs: Array<DoubleArray>?)=inferVector(vector(values),costs)
    }
}
