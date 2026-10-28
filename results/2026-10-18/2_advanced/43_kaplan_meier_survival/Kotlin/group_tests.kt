import kotlin.math.sqrt

object GroupTests {
    val WEIGHTS=listOf("logrank","gehan_wilcoxon","tarone_ware")
    class Result(val groups: List<String>) {
        val events=IntArray(groups.size);
        val observed=DoubleArray(groups.size);
        val expected=DoubleArray(groups.size);
        val covariance=Numerics.zeros(groups.size);
        var chi2=0.0;
        var pvalue=0.0;
        var degrees=0
    }
    private fun finish(result: Result) {
        val n=result.groups.size-1;
        val matrix=Numerics.zeros(n);
        val u=DoubleArray(n);
        for(i in 0 until n) {
            u[i]=result.observed[i]-result.expected[i];
            for(j in 0 until n)matrix[i][j]=result.covariance[i][j]
        };
        val solved=Numerics.solve(matrix,u);
        result.chi2=0.0;
        for(i in 0 until n)result.chi2+=u[i]*solved[i];
        result.degrees=n;
        result.pvalue=Numerics.pvalue(result.chi2,n)
    }
    fun weighted(subjects: List<Dataset.Subject>,groups: List<String>,weight: Int,totalSubjects: Int): Result {
        val result=Result(groups);
        for(time in Estimators.eventTimes(subjects,false)) {
            var n=0;
            var d=0;
            val risk=IntArray(groups.size);
            val events=IntArray(groups.size);
            for(s in subjects) {
                val g=groups.indexOf(s.group);
                if(s.time>=time) {
                    risk[g]++;
                    n++
                };
                if(s.time==time&&s.event==1) {
                    events[g]++;
                    d++
                }
            };
            var nu=if(weight==0)1.0 else n.toDouble()/totalSubjects;
            if(weight==2)nu=sqrt(nu);
            for(h in groups.indices) {
                result.events[h]+=events[h];
                result.observed[h]+=nu*events[h];
                result.expected[h]+=nu*((d*risk[h]).toDouble()/n);
                if(n>=2)for(l in groups.indices) {
                    val m=if(h==l)risk[h]*(n-risk[h]) else -(risk[h]*risk[l]);
                    result.covariance[h][l]+=nu*nu*((d*(n-d)).toDouble()/((n-1)*n*n))*m
                }
            }
        };
        finish(result);
        return result
    }
    fun combined(strata: List<Result>,groups: List<String>): Result {
        val result=Result(groups);
        for(s in strata)for(h in groups.indices) {
            result.events[h]+=s.events[h];
            result.observed[h]+=s.observed[h];
            result.expected[h]+=s.expected[h];
            for(l in groups.indices)result.covariance[h][l]+=s.covariance[h][l]
        };
        finish(result);
        return result
    }
}
