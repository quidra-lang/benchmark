import kotlin.math.*

object Linalg {
    fun zeros(n: Int)=Array(n) {
        DoubleArray(n)
    }
    fun dot(a: DoubleArray,b: DoubleArray): Double {
        var sum=0.0;
        for(i in a.indices)sum+=a[i]*b[i];
        return sum
    }
    fun cholesky(a: Array<DoubleArray>): Array<DoubleArray> {
        val n=a.size;
        val l=zeros(n);
        for(i in 0 until n)for(j in 0..i) {
            var sum=0.0;
            for(k in 0 until j)sum+=l[i][k]*l[j][k];
            val s=a[i][j]-sum;
            l[i][j]=if(i==j)sqrt(s) else s/l[j][j]
        };
        return l
    }
    fun forward(l: Array<DoubleArray>,r: DoubleArray): DoubleArray {
        val z=DoubleArray(l.size);
        for(i in l.indices) {
            var sum=0.0;
            for(k in 0 until i)sum+=l[i][k]*z[k];
            z[i]=(r[i]-sum)/l[i][i]
        };
        return z
    }
    fun backward(l: Array<DoubleArray>,u: DoubleArray): DoubleArray {
        val n=l.size;
        val v=DoubleArray(n);
        for(i in n-1 downTo 0) {
            var sum=0.0;
            for(k in i+1 until n)sum+=l[k][i]*v[k];
            v[i]=(u[i]-sum)/l[i][i]
        };
        return v
    }
    fun logDet(l: Array<DoubleArray>): Double {
        var sum=0.0;
        for(i in l.indices)sum+=ln(l[i][i]);
        return 2*sum
    }
    fun quadratic(l: Array<DoubleArray>,r: DoubleArray): Double {
        val z=forward(l,r);
        return dot(z,z)
    }
    data class Eigen(val values: DoubleArray,val vectors: Array<DoubleArray>,val sweeps: Int)
    fun jacobi(a: Array<DoubleArray>): Eigen {
        val n=a.size;
        val m=Array(n) {
            a[it].copyOf()
        };
        val v=zeros(n);
        for(i in 0 until n)v[i][i]=1.0;
        var sweeps=0;
        while(true) {
            var sum=0.0;
            for(i in 0 until n-1)for(j in i+1 until n)sum+=m[i][j]*m[i][j];
            if(sqrt(sum)<1e-12||sweeps==50)break;
            for(a0 in 0 until n-1)for(b0 in a0+1 until n) {
                if(m[a0][b0]==0.0)continue;
                val theta=(m[b0][b0]-m[a0][a0])/(2*m[a0][b0]);
                val t=(if(theta>=0)1.0 else -1.0)/(abs(theta)+sqrt(theta*theta+1));
                val co=1/sqrt(t*t+1);
                val si=t*co;
                for(k in 0 until n) {
                    if(k==a0||k==b0)continue;
                    val x=m[k][a0];
                    val y=m[k][b0];
                    m[k][a0]=co*x-si*y;
                    m[a0][k]=m[k][a0];
                    m[k][b0]=si*x+co*y;
                    m[b0][k]=m[k][b0]
                };
                val w=m[a0][b0];
                m[a0][a0]-=t*w;
                m[b0][b0]+=t*w;
                m[a0][b0]=0.0;
                m[b0][a0]=0.0;
                for(k in 0 until n) {
                    val x=v[k][a0];
                    val y=v[k][b0];
                    v[k][a0]=co*x-si*y;
                    v[k][b0]=si*x+co*y
                }
            };
            sweeps++
        };
        return Eigen(DoubleArray(n) {
            m[it][it]
        },v,sweeps)
    }
    fun decreasing(values: DoubleArray)=values.indices.sortedWith(compareByDescending<Int> {
        values[it]
    }.thenBy {
        it
    })
}
