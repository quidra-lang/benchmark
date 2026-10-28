import kotlin.math.sqrt

object Pca {
    fun means(values: Array<DoubleArray>): DoubleArray {
        val n=values.size;
        val p=values[0].size;
        val result=DoubleArray(p);
        for(j in 0 until p) {
            for(i in 0 until n)result[j]+=values[i][j];
            result[j]/=n
        };
        return result
    }
    fun covariance(values: Array<DoubleArray>,mean: DoubleArray): Array<DoubleArray> {
        val p=mean.size;
        val n=values.size;
        val result=Array(p) {
            DoubleArray(p)
        };
        for(j in 0 until p)for(k in j until p) {
            var sum=0.0;
            for(i in 0 until n)sum+=(values[i][j]-mean[j])*(values[i][k]-mean[k]);
            val value=sum/(n-1);
            result[j][k]=value;
            result[k][j]=value
        };
        return result
    }
    fun deviations(covariance: Array<DoubleArray>)=DoubleArray(covariance.size) {
        sqrt(covariance[it][it])
    }
    fun correlation(covariance: Array<DoubleArray>,sd: DoubleArray)=Array(sd.size) {
        j->DoubleArray(sd.size) {
            k->if(j==k)1.0 else covariance[j][k]/(sd[j]*sd[k])
        }
    }
    fun standardize(values: DoubleArray,means: DoubleArray,scales: DoubleArray)=DoubleArray(values.size) {
        j->if(values[j].isNaN())0.0 else (values[j]-means[j])/scales[j]
    }
    fun scores(z: DoubleArray,vectors: Array<DoubleArray>)=DoubleArray(vectors.size) {
        Matrix.dot(z,vectors[it])
    }
    fun residuals(z: DoubleArray,scores: DoubleArray,vectors: Array<DoubleArray>,count: Int): DoubleArray {
        val result=DoubleArray(z.size);
        for(j in z.indices) {
            var sum=0.0;
            for(k in 0 until count)sum+=scores[k]*vectors[k][j];
            result[j]=z[j]-sum
        };
        return result
    }
    fun t2(scores: DoubleArray,eigenvalues: DoubleArray,count: Int): Double {
        var sum=0.0;
        for(k in 0 until count)sum+=scores[k]*scores[k]/eigenvalues[k];
        return sum
    }
}
