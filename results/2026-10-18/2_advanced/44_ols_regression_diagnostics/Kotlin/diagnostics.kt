import kotlin.math.*

object Diagnostics {
    class Result(n: Int,r: Int) {
        val standardized=DoubleArray(n);
        val studentized=DoubleArray(n);
        val cooks=DoubleArray(n);
        val dffits=DoubleArray(n);
        val flags=Array(n) {
            ""
        };
        val dfbetas=Array(n) {
            DoubleArray(r)
        };
        var dw=0.0;
        var bp=0.0;
        var bpP=0.0;
        var jb=0.0;
        var jbP=0.0;
        var skewness=0.0;
        var kurtosis=0.0;
        var bpDegrees=0
    }
    fun compute(x: Array<DoubleArray>,y: DoubleArray,w: DoubleArray,fit: QrSolver.Fit,sigma: Double,degrees: Int,settings: Dataframe.Settings): Result {
        val n=y.size;
        val r=fit.rank;
        val result=Result(n,r);
        for(i in 0 until n) {
            val h=fit.leverage[i];
            val z=fit.epsilon[i]/(sigma*sqrt(1-h));
            result.standardized[i]=z;
            result.studentized[i]=z*sqrt((degrees-1)/(degrees-z*z));
            result.cooks[i]=z*z*h/(r*(1-h));
            result.dffits[i]=result.studentized[i]*sqrt(h/(1-h));
            var flags="";
            if(h>settings.number("LEVERAGE")*r/n)flags+="H";
            if(abs(result.studentized[i])>settings.number("STUDENTIZED"))flags+="O";
            if(result.cooks[i]>settings.number("COOK")/n)flags+="C";
            if(abs(result.dffits[i])>settings.number("DFFITS")*sqrt(r.toDouble()/n))flags+="F";
            result.flags[i]=flags.ifEmpty {
                "-"
            };
            val deleted=sigma*sqrt((degrees-z*z)/(degrees-1));
            for(k in 0 until r)result.dfbetas[i][k]=fit.g[i][k]*fit.epsilon[i]/(1-h)/(deleted*sqrt(fit.variance[k]))
        };
        var dw=0.0;
        for(i in 1 until n) {
            val difference=fit.epsilon[i]-fit.epsilon[i-1];
            dw+=difference*difference
        };
        result.dw=dw/fit.rss;
        val accepted=Array(n) {
            i->DoubleArray(r) {
                k->x[i][fit.accepted[k]]
            }
        };
        val squares=DoubleArray(n);
        val ones=DoubleArray(n) {
            1.0
        };
        var sum=0.0;
        for(i in 0 until n) {
            squares[i]=fit.epsilon[i]*fit.epsilon[i];
            sum+=squares[i]
        };
        val auxiliary=QrSolver.fit(accepted,squares,ones,settings.number("RANK_TOL"));
        var mean=sum/n;
        var total=0.0;
        for(value in squares)total+=(value-mean)*(value-mean);
        result.bp=n*(1-auxiliary.rss/total);
        result.bpDegrees=auxiliary.rank-1;
        result.bpP=Inference.pchi(result.bp,result.bpDegrees);
        sum=0.0;
        for(value in fit.epsilon)sum+=value;
        mean=sum/n;
        var m2=0.0;
        var m3=0.0;
        var m4=0.0;
        for(value in fit.epsilon) {
            val delta=value-mean;
            m2+=delta*delta;
            m3+=delta*delta*delta;
            m4+=delta*delta*delta*delta
        };
        m2/=n;
        m3/=n;
        m4/=n;
        result.skewness=m3/(m2*sqrt(m2));
        result.kurtosis=m4/(m2*m2);
        result.jb=n/6.0*(result.skewness*result.skewness+(result.kurtosis-3)*(result.kurtosis-3)/4);
        result.jbP=Inference.pchi(result.jb,2);
        return result
    }
}
