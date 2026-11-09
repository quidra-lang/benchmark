import kotlin.math.abs
object Evaluation {
    val regionsOrder=arrayOf("nonocc","all","disc")
    data class Regions(val nonocc: List<Int>,val all: List<Int>,val disc: List<Int>,val occluded: List<Int>) {
        fun at(i: Int)=if(i==0)nonocc else if(i==1)all else disc
    }
    data class Metrics(val pixels: Int,val valid: Int,val bad1: Int,val bad2: Int,val error: Long,val exact: Int) {
        fun mae()=if(valid==0)"-" else Refinement.two(error,valid.toLong())
    }
    fun regions(truth: IntArray,w: Int,h: Int): Regions {
        val all=mutableListOf<Int>();
        val visible=mutableListOf<Int>();
        val hidden=mutableListOf<Int>();
        val disc=mutableListOf<Int>();
        for(p in truth.indices)if(truth[p]!=0) {
            all.add(p);
            val x=p%w;
            val y=p/w;
            val g=truth[p];
            val target=x-g;
            var occluded=target<0;
            for(x2 in 0 until w)if(!occluded&&truth[y*w+x2]>g&&x2-truth[y*w+x2]==target)occluded=true;
            if(occluded)hidden.add(p) else visible.add(p)
        }
        for(p in visible) {
            val x=p%w;
            val y=p/w;
            var edge=false;
            for(yy in maxOf(0,y-1)..minOf(h-1,y+1))for(xx in maxOf(0,x-1)..minOf(w-1,x+1)) {
                val q=yy*w+xx;
                if(q!=p&&truth[q]!=0&&abs(truth[q]-truth[p])>=2)edge=true
            };
            if(edge)disc.add(p)
        };
        return Regions(visible,all,disc,hidden)
    }
    fun evaluate(image: IntArray,truth: IntArray,region: List<Int>): Metrics {
        var valid=0;
        var bad1=0;
        var bad2=0;
        var exact=0;
        var error=0L;
        for(p in region)if(image[p]==0) {
            bad1++;
            bad2++
        } else {
            valid++;
            val e=abs(image[p]-truth[p]);
            error+=e;
            if(e>1)bad1++;
            if(e>2)bad2++;
            if(e==0)exact++
        };
        return Metrics(region.size,valid,bad1,bad2,error,exact)
    }
    fun gcd(first: Long,second: Long): Long {
        var a=first;
        var b=second;
        while(b!=0L) {
            val t=a%b;
            a=b;
            b=t
        };
        return a
    }
    fun ratio(a: Long,b: Long): String {
        if(b==0L)return "0/1 0.00";
        val divisor=gcd(a,b);
        return "${a/divisor}/${b/divisor} "+Refinement.two(100*a,b)
    }
}
