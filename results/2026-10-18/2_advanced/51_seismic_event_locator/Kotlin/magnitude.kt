import java.math.BigDecimal
import java.math.RoundingMode
import kotlin.math.*

object Magnitude {
    data class Values(val distance: Double,val ml: Double?,val md: Double)
    data class Frequency(val counts: java.util.SortedMap<Int,Int>,val completeness: Int,val nb: Int,val b: Double,val sigma: Double,val a: Double)
    fun log10(x: Double)=ln(x)/2.302585092994046
    fun median(values: List<Double>): Double {
        val sorted=values.sorted();
        val k=sorted.size/2;
        return if(sorted.size%2==1)sorted[k] else (sorted[k-1]+sorted[k])/2
    }
    fun perPick(pick: Picker.Pick,distance: Double,p: WaveformIo.Params): Values {
        val l=p.row("local_magnitude");
        val d=p.row("duration_magnitude");
        val ml=if(pick.clipped)null else log10(pick.amplitude.toDouble())+l[0]*log10(distance/100)+l[1]*(distance-100)+l[2];
        return Values(distance,ml,d[0]+d[1]*log10(pick.duration/100.0)+d[2]*distance)
    }
    fun rounded(value: Double,digits: Int)=BigDecimal.valueOf(value).setScale(digits,RoundingMode.HALF_UP).movePointRight(digits).longValueExact()
    fun classNumber(ml: Double)=Math.floorDiv(rounded(ml,2)+5,10L).toInt()
    fun classText(t: Int)=(if(t<0)"-" else "")+abs(t)/10+"."+abs(t)%10
    fun frequency(magnitudes: List<Double>): Frequency {
        val counts=sortedMapOf<Int,Int>();
        for(ml in magnitudes) {
            val t=classNumber(ml);
            counts[t]=counts.getOrDefault(t,0)+1
        };
        var tc=counts.firstKey();
        var maximum=0;
        for(t in counts.keys)if(counts.getValue(t)>maximum) {
            tc=t;
            maximum=counts.getValue(t)
        };
        var nb=0;
        var sum=0L;
        for(t in counts.keys)if(t>=tc) {
            nb+=counts.getValue(t);
            sum+=t.toLong()*counts.getValue(t)
        };
        val mc=tc/10.0;
        val mean=sum/(10.0*nb);
        val b=0.4342944819032518/(mean-(mc-0.05));
        return Frequency(counts,tc,nb,b,b/sqrt(nb.toDouble()),log10(nb.toDouble())+b*mc)
    }
}
