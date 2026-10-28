object Integrator {
    fun shifted(y: DoubleArray,k: DoubleArray,factor: Double)=DoubleArray(y.size) {
        y[it]+factor*k[it]
    }
    fun step(rate: EpidemicRate,state: DoubleArray,multiplier: Double): DoubleArray {
        val h=0.25;
        val half=h/2;
        val sixth=h/6
        val a=rate(state,multiplier);
        val b=rate(shifted(state,a,half),multiplier);
        val c=rate(shifted(state,b,half),multiplier);
        val d=rate(shifted(state,c,h),multiplier)
        return DoubleArray(state.size) {
            state[it]+sixth*(((a[it]+2*b[it])+2*c[it])+d[it])
        }
    }
    fun simulate(rate: EpidemicRate,initial: DoubleArray,multipliers: DoubleArray,inflows: IntArray): List<DoubleArray> {
        var state=initial.copyOf();
        val daily=mutableListOf<DoubleArray>()
        for(multiplier in multipliers) {
            for(i in inflows)state[i]=0.0;
            repeat(4) {
                state=step(rate,state,multiplier)
            };
            daily.add(state.copyOf())
        }
        return daily
    }
}
