import kotlin.math.abs

object Detector {
    class Peak(val time: Int,val r: Int,val peakI: Long,val peakF: Long,val slope: Long) {
        var thrI=0L;
        var thrF=0L;
        var kind=""
    }
    fun peaks(f: Filters.Signals): List<Peak> {
        val result=mutableListOf<Peak>();
        for(n in f.integrated.indices) {
            val value=f.integrated[n];
            if(value<=0)continue;
            if((maxOf(0,n-20) until n).any {
                f.integrated[it]>=value
            })continue;
            if((n+1 until minOf(f.integrated.size,n+21)).any {
                f.integrated[it]>value
            })continue;
            var r=maxOf(0,n-30);
            for(j in r+1..n)if(abs(f.band[j])>abs(f.band[r]))r=j;
            var slope=0L;
            for(j in maxOf(0,n-29)..n)slope=maxOf(slope,abs(f.derivative[j]));
            result+=Peak(n,r,value,abs(f.band[r]),slope)
        };
        return result
    }
    fun levels(f: Filters.Signals): LongArray {
        var maxI=0L;
        var sumI=0L;
        var maxF=0L;
        var sumF=0L;
        for(i in 0 until 400) {
            val a=f.integrated[i];
            val b=abs(f.band[i]);
            maxI=maxOf(maxI,a);
            sumI+=a;
            maxF=maxOf(maxF,b);
            sumF+=b
        };
        return longArrayOf(maxI/3,sumI/800,maxF/3,sumF/800)
    }
    fun width(band: LongArray,r: Int): Int {
        val peak=abs(band[r]);
        var first=-1;
        var last=-1;
        for(j in maxOf(0,r-25) until minOf(band.size,r+26))if(4*abs(band[j])>=peak) {
            if(first==-1)first=j;
            last=j
        };
        return 5*(last-first+1)
    }
}
