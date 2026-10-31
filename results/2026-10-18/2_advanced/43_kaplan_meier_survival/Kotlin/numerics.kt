import kotlin.math.*

object Numerics {
    const val Z=1.959963984540054
    fun zeros(n: Int)=Array(n) {
        DoubleArray(n)
    }
    fun solve(matrix: Array<DoubleArray>,right: DoubleArray): DoubleArray {
        val n=right.size;
        val a=Array(n) {
            matrix[it].copyOf()
        };
        val b=right.copyOf();
        val x=DoubleArray(n);
        for(k in 0 until n)for(i in k+1 until n) {
            val f=a[i][k]/a[k][k];
            for(j in k until n)a[i][j]-=f*a[k][j];
            b[i]-=f*b[k]
        };
        for(i in n-1 downTo 0) {
            var value=b[i];
            for(j in i+1 until n)value-=a[i][j]*x[j];
            x[i]=value/a[i][i]
        };
        return x
    }
    fun inverse(matrix: Array<DoubleArray>): Array<DoubleArray> {
        val n=matrix.size;
        val result=zeros(n);
        for(c in 0 until n) {
            val unit=DoubleArray(n);
            unit[c]=1.0;
            val y=solve(matrix,unit);
            for(a in 0 until n)result[a][c]=y[a]
        };
        return result
    }
    fun logGamma(a: Double): Double {
        val coefficients=doubleArrayOf(76.18009172947146,-86.50532032941677,24.01409824083091,-1.231739572450155,0.001208650973866179,-0.000005395239384953);
        val xi0=a+5.5;
        val xi1=xi0-(a+0.5)*ln(xi0);
        var sigma=1.000000000190015;
        var y=a;
        for(coefficient in coefficients) {
            y+=1;
            sigma+=coefficient/y
        };
        return -xi1+ln(2.5066282746310005*sigma/a)
    }
    fun gammaQ(a: Double,x: Double): Double {
        if(x==0.0)return 1.0;
        val pref=exp(-x+a*ln(x)-logGamma(a));
        if(x<a+1) {
            var alpha=a;
            var xi=1/a;
            var sigma=xi;
            for(i in 0 until 1000) {
                alpha+=1;
                xi*=x/alpha;
                sigma+=xi;
                if(abs(xi)<abs(sigma)*1e-15)break
            };
            return 1-sigma*pref
        };
        val eps=1e-300;
        var b=x+1-a;
        var c=1/eps;
        var d=1/b;
        var h=d;
        for(i in 1..1000) {
            val an=-i*(i-a);
            b+=2;
            d=an*d+b;
            if(abs(d)<eps)d=eps;
            c=b+an/c;
            if(abs(c)<eps)c=eps;
            d=1/d;
            val delta=d*c;
            h*=delta;
            if(abs(delta-1)<1e-15)break
        };
        return pref*h
    }
    fun pvalue(chi2: Double,degrees: Int)=gammaQ(degrees/2.0,chi2/2)
}
