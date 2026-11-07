import kotlin.math.sqrt

object Kmeans {
    data class Run(val centers: Array<DoubleArray>,val assignment: IntArray,val iterations: Int,val inertia: Double)
    fun squared(x: Double,y: Double,center: DoubleArray): Double {
        val dx=x-center[0];
        val dy=y-center[1];
        return dx*dx+dy*dy
    }
    fun distance(a: Dataset.Point,b: Dataset.Point): Double {
        val dx=a.x-b.x;
        val dy=a.y-b.y;
        return sqrt(dx*dx+dy*dy)
    }
    fun assign(points: List<Dataset.Point>,centers: Array<DoubleArray>): IntArray {
        val result=IntArray(points.size);
        for(i in points.indices) {
            val p=points[i];
            var best=0;
            var minimum=squared(p.x,p.y,centers[0]);
            for(j in 1 until centers.size) {
                val value=squared(p.x,p.y,centers[j]);
                if(value<minimum) {
                    minimum=value;
                    best=j
                }
            };
            result[i]=best
        };
        return result
    }
    fun fit(points: List<Dataset.Point>,initial: Array<DoubleArray>,maximum: Int): Run {
        val k=initial.size;
        val centers=Array(k) {
            initial[it].copyOf()
        };
        var assignment=assign(points,centers);
        var iterations=0;
        for(t in 1..maximum) {
            val sums=Array(k) {
                DoubleArray(2)
            };
            val counts=IntArray(k);
            for(i in points.indices) {
                val j=assignment[i];
                counts[j]++;
                sums[j][0]+=points[i].x;
                sums[j][1]+=points[i].y
            };
            for(j in 0 until k)if(counts[j]>0) {
                centers[j][0]=sums[j][0]/counts[j];
                centers[j][1]=sums[j][1]/counts[j]
            };
            val next=assign(points,centers);
            val same=assignment.contentEquals(next);
            assignment=next;
            iterations=t;
            if(same)break
        };
        var inertia=0.0;
        for(i in points.indices)inertia+=squared(points[i].x,points[i].y,centers[assignment[i]]);
        return Run(centers,assignment,iterations,inertia)
    }
}
