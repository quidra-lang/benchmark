import kotlin.math.*

object Cox {
    data class Risk(val events: Int,val s0: Double,val s1: DoubleArray)
    class Evaluation(n: Int,p: Int) {
        var likelihood=0.0;
        val score=DoubleArray(p);
        val theta=DoubleArray(n);
        val risks=DoubleArray(n);
        val information=Numerics.zeros(p);
        val times=sortedMapOf<Int,Risk>()
    }
    fun evaluate(subjects: List<Dataset.Subject>,x: Array<DoubleArray>,beta: DoubleArray): Evaluation {
        val n=subjects.size;
        val p=beta.size;
        val result=Evaluation(n,p);
        for(i in 0 until n) {
            for(c in 0 until p)result.theta[i]+=beta[c]*x[i][c];
            result.risks[i]=exp(result.theta[i])
        };
        val order=subjects.indices.sortedWith(compareByDescending<Int> {
            subjects[it].time
        }.thenBy {
            subjects[it].id
        });
        var s0=0.0;
        val s1=DoubleArray(p);
        val s2=Numerics.zeros(p);
        var position=0;
        while(position<n) {
            var end=position;
            val time=subjects[order[position]].time;
            while(end<n&&subjects[order[end]].time==time)end++;
            for(j in position until end) {
                val i=order[j];
                val r=result.risks[i];
                s0+=r;
                for(c in 0 until p) {
                    s1[c]+=r*x[i][c];
                    for(d in 0 until p)s2[c][d]+=r*x[i][c]*x[i][d]
                }
            };
            var events=0;
            var theta=0.0;
            val eventX=DoubleArray(p);
            for(j in position until end) {
                val i=order[j];
                if(subjects[i].event==1) {
                    events++;
                    theta+=result.theta[i];
                    for(c in 0 until p)eventX[c]+=x[i][c]
                }
            };
            if(events>0) {
                result.likelihood+=theta-events*ln(s0);
                for(c in 0 until p) {
                    result.score[c]+=eventX[c]-events*s1[c]/s0;
                    for(d in 0 until p)result.information[c][d]+=events*(s2[c][d]/s0-(s1[c]/s0)*(s1[d]/s0))
                };
                result.times[time]=Risk(events,s0,s1.copyOf())
            };
            position=end
        };
        return result
    }
    data class Iteration(val number: Int,val likelihood: Double,val beta: DoubleArray)
    class Fit(val beta: DoubleArray,val initial: Evaluation) {
        lateinit var finalEvaluation: Evaluation;
        val iterations=mutableListOf<Iteration>()
    }
    fun fit(subjects: List<Dataset.Subject>,x: Array<DoubleArray>): Fit {
        val beta=DoubleArray(x[0].size);
        val result=Fit(beta,evaluate(subjects,x,beta));
        for(iteration in 1..25) {
            val before=if(iteration==1)result.initial else evaluate(subjects,x,beta);
            val delta=Numerics.solve(before.information,before.score);
            for(c in beta.indices)beta[c]+=delta[c];
            result.iterations+=Iteration(iteration,before.likelihood,beta.copyOf())
        };
        result.finalEvaluation=evaluate(subjects,x,beta);
        return result
    }
}
