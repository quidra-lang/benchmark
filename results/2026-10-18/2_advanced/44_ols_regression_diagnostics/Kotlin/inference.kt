import java.util.Locale
import kotlin.math.*

object Inference {
    fun logGamma(x: Double): Double {
        val c=doubleArrayOf(76.18009172947146,-86.50532032941677,24.01409824083091,-1.231739572450155,0.001208650973866179,-0.000005395239384953);
        val t=x+5.5;
        val total=t-(x+0.5)*ln(t);
        var sum=1.000000000190015;
        for(j in 1..c.size)sum+=c[j-1]/(x+j);
        return -total+ln(2.5066282746310005*sum/x)
    }
    fun small(value: Double)=if(abs(value)<1e-300)1e-300 else value
    fun betaFraction(a: Double,b: Double,x: Double): Double {
        var c=1.0;
        var d=1/small(1-(a+b)*x/(a+1));
        var h=d;
        for(m in 1..1000) {
            var q=m*(b-m)*x/((a-1+2*m)*(a+2*m));
            d=1/small(1+q*d);
            c=small(1+q/c);
            h*=d*c;
            q=-(a+m)*(a+b+m)*x/((a+2*m)*(a+1+2*m));
            d=1/small(1+q*d);
            c=small(1+q/c);
            val delta=d*c;
            h*=delta;
            if(abs(delta-1)<1e-15)break
        };
        return h
    }
    fun beta(x: Double,a: Double,b: Double): Double {
        if(x<=0)return 0.0;
        if(x>=1)return 1.0;
        val front=exp(logGamma(a+b)-logGamma(a)-logGamma(b)+a*ln(x)+b*ln(1-x));
        return if(x<(a+1)/(a+b+2))front*betaFraction(a,b,x)/a else 1-front*betaFraction(b,a,1-x)/b
    }
    fun gammaQ(a: Double,x: Double): Double {
        if(x==0.0)return 1.0;
        val front=exp(-x+a*ln(x)-logGamma(a));
        if(x<a+1) {
            var t=1/a;
            var sum=t;
            var e=a;
            for(i in 0 until 1000) {
                e+=1;
                t*=x/e;
                sum+=t;
                if(abs(t)<abs(sum)*1e-15)break
            };
            return 1-sum*front
        };
        var b=x+1-a;
        var c=1/1e-300;
        var d=1/b;
        var h=d;
        for(i in 1..1000) {
            val q=-i*(i-a);
            b+=2;
            d=1/small(q*d+b);
            c=small(b+q/c);
            val delta=d*c;
            h*=delta;
            if(abs(delta-1)<1e-15)break
        };
        return front*h
    }
    fun pt(t: Double,degrees: Int)=beta(degrees/(degrees+t*t),degrees/2.0,0.5)
    fun pf(f: Double,a: Int,b: Int)=beta(b/(b+a*f),b/2.0,a/2.0)
    fun pchi(value: Double,degrees: Int)=gammaQ(degrees/2.0,value/2)
    fun quantile(confidence: Double,degrees: Int): Double {
        var lo=0.0;
        var hi=1000.0;
        repeat(100) {
            val mid=(lo+hi)/2;
            if(pt(mid,degrees)>1-confidence)lo=mid else hi=mid
        };
        return (lo+hi)/2
    }
    fun mark(p: Double)=if(p<0.001)"***" else if(p<0.01)"**" else if(p<0.05)"*" else if(p<0.1)"." else ""
    fun real(value: Double): String {
        if(value.isNaN())return "NA";
        val text=String.format(Locale.ROOT,"%.4f",value);
        return if(text=="-0.0000")"0.0000" else text
    }
    fun pvalue(value: Double)=if(value.isNaN())"NA" else if(value<0.0001)"<0.0001" else real(value)
}
