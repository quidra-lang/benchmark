import kotlin.math.*

object Eigen {
    data class Result(val values: DoubleArray,val vectors: Array<DoubleArray>,val sweeps: Int)
    fun off(a: Array<DoubleArray>): Double {
        var sum=0.0;
        for(p in 0 until a.size-1)for(q in p+1 until a.size)sum+=a[p][q]*a[p][q];
        return sum
    }
    fun rotate(a: Array<DoubleArray>,v: Array<DoubleArray>,p: Int,q: Int) {
        val apq=a[p][q];
        if(apq==0.0)return;
        val theta=(a[q][q]-a[p][p])/(2*apq);
        var t=1/(abs(theta)+sqrt(theta*theta+1));
        if(theta<0)t=-t;
        val c=1/sqrt(t*t+1);
        val s=t*c;
        for(r in a.indices)if(r!=p&&r!=q) {
            val arp=a[r][p];
            val arq=a[r][q];
            val first=c*arp-s*arq;
            val second=s*arp+c*arq;
            a[r][p]=first;
            a[p][r]=first;
            a[r][q]=second;
            a[q][r]=second
        };
        a[p][p]-=t*apq;
        a[q][q]+=t*apq;
        a[p][q]=0.0;
        a[q][p]=0.0;
        for(r in v.indices) {
            val first=v[r][p];
            val second=v[r][q];
            v[r][p]=c*first-s*second;
            v[r][q]=s*first+c*second
        }
    }
    fun jacobi(matrix: Array<DoubleArray>): Result {
        val n=matrix.size;
        val a=Matrix.copy(matrix);
        val v=Matrix.identity(n);
        val initial=off(a);
        var count=0;
        if(initial>0)for(sweep in 1..100) {
            for(p in 0 until n-1)for(q in p+1 until n)rotate(a,v,p,q);
            val current=off(a);
            if(count==0&&current<1e-16*initial)count=sweep;
            if(current<1e-22*initial)break
        };
        val order=(0 until n).sortedWith(compareByDescending<Int> {
            a[it][it]
        }.thenBy {
            it
        });
        val values=DoubleArray(n) {
            a[order[it]][order[it]]
        };
        val vectors=Array(n) {
            Matrix.column(v,order[it]).also {
                u->Matrix.normalize(u);
                Matrix.orient(u)
            }
        };
        return Result(values,vectors,count)
    }
    data class Power(val value: Double,val vector: DoubleArray,val agreement: Int)
    fun power(matrix: Array<DoubleArray>,reference: Array<DoubleArray>): List<Power> {
        val n=matrix.size;
        val b=Matrix.copy(matrix);
        val result=mutableListOf<Power>();
        for(k in 0 until n) {
            var x=DoubleArray(n) {
                1.0
            };
            var agreement=0;
            for(iteration in 1..1000) {
                x=Matrix.multiply(b,x);
                Matrix.normalize(x);
                var positive=0.0;
                var negative=0.0;
                for(j in 0 until n) {
                    positive=maxOf(positive,abs(x[j]-reference[k][j]));
                    negative=maxOf(negative,abs(x[j]+reference[k][j]))
                };
                if(agreement==0&&minOf(positive,negative)<0.000001)agreement=iteration
            };
            val value=Matrix.dot(x,Matrix.multiply(b,x));
            Matrix.normalize(x);
            Matrix.orient(x);
            result+=Power(value,x,agreement);
            Matrix.deflate(b,value,x)
        };
        return result
    }
}
