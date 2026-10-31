import kotlin.math.sqrt

object QrSolver {
    class Fit(val rank: Int,val accepted: IntArray,val beta: DoubleArray,val effects: DoubleArray,
        val inverse: Array<DoubleArray>,val variance: DoubleArray,val g: Array<DoubleArray>,
        val leverage: DoubleArray,val fitted: DoubleArray,val residual: DoubleArray,val epsilon: DoubleArray,
        val rss: Double)
    fun fit(x: Array<DoubleArray>,y: DoubleArray,w: DoubleArray,tolerance: Double): Fit {
        val n=y.size;
        val p=x[0].size;
        val a=DoubleArray(n) {
            sqrt(w[it])
        };
        val z=DoubleArray(n) {
            a[it]*y[it]
        };
        val original=Array(n) {
            i->DoubleArray(p) {
                j->a[i]*x[i][j]
            }
        };
        val matrix=Array(n) {
            original[it].copyOf()
        };
        val norm=DoubleArray(p);
        val r=Array(p) {
            DoubleArray(p)
        };
        for(j in 0 until p) {
            var sum=0.0;
            for(i in 0 until n)sum+=original[i][j]*original[i][j];
            norm[j]=sqrt(sum)
        };
        val accepted=mutableListOf<Int>();
        for(j in 0 until p) {
            val k=accepted.size;
            var sum=0.0;
            for(i in k until n)sum+=matrix[i][j]*matrix[i][j];
            val eta=sqrt(sum);
            if(eta<=tolerance*norm[j])continue;
            accepted+=j;
            val alpha=if(matrix[k][j]>=0)-eta else eta;
            val v=DoubleArray(n);
            for(i in k until n)v[i]=matrix[i][j];
            v[k]-=alpha;
            var volume=0.0;
            for(i in k until n)volume+=v[i]*v[i];
            for(l in 0 until k)r[l][k]=matrix[l][j];
            r[k][k]=alpha;
            for(l in j+1 until p) {
                sum=0.0;
                for(i in k until n)sum+=v[i]*matrix[i][l];
                val delta=2*sum/volume;
                for(i in k until n)matrix[i][l]-=delta*v[i]
            };
            sum=0.0;
            for(i in k until n)sum+=v[i]*z[i];
            val delta=2*sum/volume;
            for(i in k until n)z[i]-=delta*v[i]
        };
        val rank=accepted.size;
        val beta=DoubleArray(p) {
            Double.NaN
        };
        val effects=z.copyOf(rank);
        for(k in rank-1 downTo 0) {
            var sum=0.0;
            for(l in k+1 until rank)sum+=r[k][l]*beta[accepted[l]];
            beta[accepted[k]]=(effects[k]-sum)/r[k][k]
        };
        val inverse=Array(rank) {
            DoubleArray(rank)
        };
        for(m in 0 until rank)for(l in rank-1 downTo 0) {
            var sum=0.0;
            for(q in l+1 until rank)sum+=r[l][q]*inverse[q][m];
            inverse[l][m]=((if(l==m)1.0 else 0.0)-sum)/r[l][l]
        };
        val variance=DoubleArray(rank);
        for(k in 0 until rank)for(m in 0 until rank)variance[k]+=inverse[k][m]*inverse[k][m];
        val g=Array(n) {
            DoubleArray(rank)
        };
        val leverage=DoubleArray(n);
        val fitted=DoubleArray(n);
        val residual=DoubleArray(n);
        val epsilon=DoubleArray(n);
        var rss=0.0;
        for(i in 0 until n) {
            val u=DoubleArray(rank);
            for(k in 0 until rank)for(m in 0 until rank)u[k]+=original[i][accepted[m]]*inverse[m][k];
            for(k in 0 until rank) {
                leverage[i]+=u[k]*u[k];
                for(m in 0 until rank)g[i][k]+=inverse[k][m]*u[m];
                fitted[i]+=x[i][accepted[k]]*beta[accepted[k]]
            };
            residual[i]=y[i]-fitted[i];
            epsilon[i]=a[i]*residual[i];
            rss+=epsilon[i]*epsilon[i]
        };
        return Fit(rank,accepted.toIntArray(),beta,effects,inverse,variance,g,leverage,fitted,residual,epsilon,rss)
    }
}
