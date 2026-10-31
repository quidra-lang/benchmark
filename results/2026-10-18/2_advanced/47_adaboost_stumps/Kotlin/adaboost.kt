import kotlin.math.*

object Adaboost {
    data class Round(val stump: Stumps.Stump,val polarity: Int,val error: Double,val alpha: Double,
        val z: Double,val bound: Double,val loss: Double,val weights: DoubleArray)
    class Model {
        val rounds=mutableListOf<Round>();
        var stop="completed";
        var cuts=emptyArray<DoubleArray>()
    }
    fun discrete(rows: List<Dataset.Row>,initial: DoubleArray,maximum: Int,shrinkage: Double): Model {
        val search=Stumps.Search(rows);
        val weights=initial.copyOf();
        var bound=1.0;
        val model=Model();
        for(t in 0 until maximum) {
            val candidate=Stumps.discrete(search,weights);
            val e=candidate.error;
            if(e>=0.5) {
                model.stop="weak";
                break
            };
            val alpha=if(e<=0.0000000001)1.0 else shrinkage*(0.5*ln((1-e)/e));
            val stump=Stumps.Stump(candidate.stump.feature,candidate.stump.thresholds,doubleArrayOf(-candidate.polarity*alpha,candidate.polarity*alpha));
            val before=weights.copyOf();
            var z=0.0;
            for(i in weights.indices) {
                val decision=if(rows[i].x[stump.feature]>stump.thresholds[0])candidate.polarity else -candidate.polarity;
                weights[i]*=exp(if(decision==rows[i].label)-alpha else alpha);
                z+=weights[i]
            };
            for(i in weights.indices)weights[i]/=z;
            bound*=z;
            model.rounds+=Round(stump,candidate.polarity,e,alpha,z,bound,Double.NaN,before);
            if(e<=0.0000000001) {
                model.stop="perfect";
                break
            }
        };
        return model
    }
    fun samme(rows: List<Dataset.Row>,classes: Int,maximum: Int): Model {
        val search=Stumps.Search(rows);
        val weights=DoubleArray(rows.size) {
            1.0/rows.size
        };
        val model=Model();
        for(t in 0 until maximum) {
            val candidate=Stumps.multiclass(search,weights,classes);
            val e=candidate.error;
            if(e>=(classes-1).toDouble()/classes) {
                model.stop="weak";
                break
            };
            val alpha=if(e<=0.0000000001)1.0 else ln((1-e)/e)+ln((classes-1).toDouble());
            var sum=0.0;
            val before=weights.copyOf();
            for(i in weights.indices) {
                if(candidate.stump.output(rows[i].x).toInt()!=rows[i].label)weights[i]*=exp(alpha);
                sum+=weights[i]
            };
            for(i in weights.indices)weights[i]/=sum;
            model.rounds+=Round(candidate.stump,0,e,alpha,Double.NaN,Double.NaN,Double.NaN,before);
            if(e<=0.0000000001) {
                model.stop="perfect";
                break
            }
        };
        return model
    }
}
