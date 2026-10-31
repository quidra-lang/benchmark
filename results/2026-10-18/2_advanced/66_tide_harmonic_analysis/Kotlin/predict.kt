import kotlin.math.*
object Predict {
    class Extremum(val high: Boolean,val minute: Double,val height: Double) {
        var rounded=0;
        var label=""
    }
    fun height(m: HarmonicFit.Model,t: Double): Double {
        var value=m.coefficients[0];
        for(k in m.selected.indices) {
            val angle=HarmonicFit.angle(m.selected[k].speed,t);
            val c=m.constants[k];
            value+=c.a*cos(angle)+c.b*sin(angle)
        };
        return value
    }
    fun hours(m: HarmonicFit.Model,start: Int,count: Int)=DoubleArray(count+1) {
        height(m,(start+it).toDouble())
    }
    fun extrema(m: HarmonicFit.Model,start: Int,hours: Int,grid: Int): MutableList<Extremum> {
        val count=hours*60/grid;
        val values=DoubleArray(count+1) {
            j->height(m,(60*start+j*grid)/60.0)
        };
        val result=mutableListOf<Extremum>();
        for(j in 1 until count) {
            val left=values[j-1];
            val center=values[j];
            val right=values[j+1];
            val high=left<center&&center>right;
            val low=left>center&&center<right;
            if(!high&&!low)continue;
            val delta=(left-right)/(2*(left-2*center+right));
            val minute=60*start+j*grid+delta*grid;
            val z=center-(left-right)*delta/4;
            result.add(Extremum(high,minute,z))
        };
        return result
    }
}
