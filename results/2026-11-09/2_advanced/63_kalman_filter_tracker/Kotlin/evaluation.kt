import java.util.Locale
import kotlin.math.sqrt

object Evaluation {
    data class Continuity(val covered: Int,val breaks: Int,val swaps: Int,val delay: Int)
    fun squared(a: DoubleArray,b: DoubleArray): Double {
        val x=a[0]-b[0];
        val y=a[1]-b[1];
        return x*x+y*y
    }
    fun distance(a: DoubleArray,b: DoubleArray)=sqrt(squared(a,b))
    fun ospa(first: List<DoubleArray>,second: List<DoubleArray>,cutoff: Double): Double {
        if(first.isEmpty()&&second.isEmpty())return 0.0;
        if(first.isEmpty()||second.isEmpty())return cutoff;
        val smaller=if(first.size<=second.size)first else second;
        val larger=if(first.size<=second.size)second else first;
        val costs=Array(smaller.size) {
            r->DoubleArray(larger.size) {
                c->val d=minOf(cutoff,distance(smaller[r],larger[c]));
                d*d
            }
        };
        var sum=0.0;
        for(pair in Association.minimum(costs))sum+=costs[pair.row][pair.column];
        return sqrt((sum+cutoff*cutoff*(larger.size-smaller.size))/larger.size)
    }
    fun continuity(labels: IntArray): Continuity {
        var covered=0;
        var groups=0;
        var swaps=0;
        var previous=0;
        var delay=-1;
        var previousCovered=false;
        for(i in labels.indices) {
            val label=labels[i];
            if(label==0) {
                previousCovered=false;
                continue
            };
            covered++;
            if(delay<0)delay=i;
            if(!previousCovered)groups++;
            if(previous!=0&&label!=previous)swaps++;
            previous=label;
            previousCovered=true
        };
        return Continuity(covered,maxOf(0,groups-1),swaps,delay)
    }
    fun real(value: Double): String {
        val s=String.format(Locale.ROOT,"%.4f",value);
        return if(s.startsWith("-")&&s.toDouble()==0.0)s.substring(1) else s
    }
}
