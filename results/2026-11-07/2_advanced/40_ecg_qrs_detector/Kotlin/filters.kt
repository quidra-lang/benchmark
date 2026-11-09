object Filters {
    class Signals(n: Int) {
        val low=LongArray(n);
        val band=LongArray(n);
        val derivative=LongArray(n);
        val squared=LongArray(n);
        val integrated=LongArray(n)
    }
    private fun at(a: LongArray,i: Int)=if(i<0)0L else a[i]
    fun apply(x: LongArray): Signals {
        val f=Signals(x.size);
        val c=LongArray(x.size);
        var running=0L;
        var window=0L;
        for(i in x.indices) {
            c[i]=2*at(c,i-1)-at(c,i-2)+x[i]-2*at(x,i-6)+at(x,i-12);
            f.low[i]=Report.div(c[i],32);
            running+=f.low[i]-at(f.low,i-32);
            f.band[i]=at(f.low,i-16)-Report.div(running,32);
            f.derivative[i]=Report.div(2*f.band[i]+at(f.band,i-1)-at(f.band,i-3)-2*at(f.band,i-4),8);
            f.squared[i]=f.derivative[i]*f.derivative[i];
            window+=f.squared[i]-at(f.squared,i-30);
            f.integrated[i]=Report.div(window,30)
        };
        return f
    }
}
