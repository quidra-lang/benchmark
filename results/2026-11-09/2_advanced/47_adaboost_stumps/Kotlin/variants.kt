import kotlin.math.*

object Variants {
    fun train(variant: String,rows: List<Dataset.Row>,settings: Dataset.Settings): Adaboost.Model {
        val n=rows.size;
        val maximum=settings.integer("ROUNDS");
        val weights=DoubleArray(n) {
            1.0/n
        };
        if(variant=="discrete")return Adaboost.discrete(rows,weights,maximum,1.0);
        val search=Stumps.Search(rows);
        val model=Adaboost.Model();
        if(variant=="real")model.cuts=Stumps.cuts(search,settings.integer("BINS"));
        val scores=DoubleArray(n);
        val probabilities=DoubleArray(n) {
            0.5
        };
        val targets=DoubleArray(n);
        var bound=1.0;
        for(t in 0 until maximum) {
            val candidate: Stumps.Candidate;
            var z=Double.NaN;
            var loss=Double.NaN;
            if(variant=="real") {
                candidate=Stumps.real(search,weights,model.cuts,settings.integer("BINS"),settings.number("SMOOTHING"));
                z=candidate.error;
                if(z>=1-settings.number("CONVERGENCE")) {
                    model.stop="converged";
                    break
                };
                bound*=z
            } else {
                for(i in 0 until n)targets[i]=rows[i].label.toDouble();
                if(variant=="logit") {
                    var sum=0.0;
                    for(i in 0 until n) {
                        weights[i]=probabilities[i]*(1-probabilities[i]);
                        sum+=weights[i];
                        targets[i]=((if(rows[i].label==1)1.0 else 0.0)-probabilities[i])/weights[i];
                        targets[i]=maxOf(-settings.number("CLIP"),minOf(settings.number("CLIP"),targets[i]))
                    };
                    for(i in 0 until n)weights[i]/=sum
                };
                candidate=Stumps.regression(search,targets,weights)
            };
            var stump=candidate.stump;
            if(variant=="logit")stump=Stumps.Stump(stump.feature,stump.thresholds,doubleArrayOf(stump.values[0]/2,stump.values[1]/2));
            val before=weights.copyOf();
            if(variant=="logit") {
                loss=0.0;
                for(i in 0 until n) {
                    scores[i]+=stump.output(rows[i].x);
                    probabilities[i]=1/(1+exp(-2*scores[i]));
                    loss+=ln(1+exp(-2*rows[i].label*scores[i]))
                };
                loss/=n
            } else {
                var sum=0.0;
                for(i in 0 until n) {
                    weights[i]*=exp(-rows[i].label*stump.output(rows[i].x));
                    sum+=weights[i]
                };
                for(i in 0 until n)weights[i]/=sum
            };
            model.rounds+=Adaboost.Round(stump,0,candidate.error,Double.NaN,z,bound,loss,before)
        };
        return model
    }
}
