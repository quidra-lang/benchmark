import kotlin.math.abs
object Aggregation {
    val directions=arrayOf(intArrayOf(1,0),intArrayOf(-1,0),intArrayOf(0,1),intArrayOf(0,-1),intArrayOf(1,1),intArrayOf(-1,-1),intArrayOf(-1,1),intArrayOf(1,-1))
    fun path(base: Array<LongArray>,left: IntArray,w: Int,h: Int,direction: Int,p1: Long,p2: Long,gamma: Long): Array<LongArray> {
        val rx=directions[direction][0];
        val ry=directions[direction][1];
        val n=base[0].size;
        val result=Array(base.size) {
            LongArray(n)
        }
        for(yi in 0 until h) {
            val y=if(ry<0)h-1-yi else yi;
            for(xi in 0 until w) {
                val x=if(rx<0)w-1-xi else xi;
                val p=y*w+x;
                val qx=x-rx;
                val qy=y-ry;
                if(qx<0||qx>=w||qy<0||qy>=h) {
                    result[p]=base[p].copyOf();
                    continue
                };
                val q=qy*w+qx;
                val previous=result[q];
                var minimum=previous[0];
                for(value in previous)minimum=minOf(minimum,value);
                val penalty=maxOf(p1,p2*gamma/(gamma+abs(left[p]-left[q])));
                for(d in 0 until n) {
                    var best=minOf(previous[d],minimum+penalty);
                    if(d>0)best=minOf(best,previous[d-1]+p1);
                    if(d+1<n)best=minOf(best,previous[d+1]+p1);
                    result[p][d]=base[p][d]+best-minimum
                }
            }
        };
        return result
    }
    fun accumulate(total: Array<LongArray>,path: Array<LongArray>) {
        for(p in total.indices)for(d in total[p].indices)total[p][d]+=path[p][d]
    }
}
