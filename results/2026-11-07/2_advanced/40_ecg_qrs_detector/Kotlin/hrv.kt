import kotlin.math.abs

object Hrv {
    fun sum(values: List<Long>)=values.sum()
    fun squares(values: List<Long>)=values.sumOf {
        it*it
    }
    fun mean(values: List<Long>)=if(values.isEmpty())-1L else Report.rdiv(100*sum(values),values.size.toLong())
    fun heartRate(values: List<Long>)=if(values.isEmpty())-1L else Report.rdiv(6000000L*values.size,sum(values))
    class Rr {
        var count=0;
        var shortBeat=0;
        var longBeat=0;
        var mean=-1L;
        var hr=-1L;
        var shortest=Long.MAX_VALUE;
        var longest=-1L
    }
    fun rr(beats: List<Beat>): Rr {
        val result=Rr();
        val values=mutableListOf<Long>();
        for(b in beats)if(b.number>1) {
            values+=b.rr;
            if(b.rr<result.shortest) {
                result.shortest=b.rr;
                result.shortBeat=b.number
            };
            if(b.rr>result.longest) {
                result.longest=b.rr;
                result.longBeat=b.number
            }
        };
        result.count=values.size;
        result.mean=mean(values);
        result.hr=heartRate(values);
        return result
    }
    class Nn {
        var e=0;
        var k=0;
        var nn50=0;
        var maximum=0;
        var mean=-1L;
        var sdnn=-1L;
        var rmssd=-1L;
        var sdsd=-1L;
        var pnn50=-1L;
        var sd1=-1L;
        var sd2=-1L;
        val histogram=sortedMapOf<Long,Int>()
    }
    fun nn(beats: List<Beat>): Nn {
        val result=Nn();
        val normal=BooleanArray(beats.size);
        val values=mutableListOf<Long>();
        val differences=mutableListOf<Long>();
        val sums=mutableListOf<Long>();
        for(i in 2 until beats.size) {
            val b=beats[i];
            val previous=beats[i-1];
            if(b.label=="N"&&previous.label=="N"&&5*abs(b.rr-previous.rr)<=previous.rr) {
                normal[i]=true;
                values+=b.rr;
                if(normal[i-1]) {
                    differences+=b.rr-previous.rr;
                    sums+=b.rr+previous.rr
                }
            }
        };
        val e=values.size;
        val k=differences.size;
        result.e=e;
        result.k=k;
        result.mean=mean(values);
        val total=sum(values);
        if(e>=2)result.sdnn=Report.root(e*squares(values)-total*total,e.toLong()*(e-1));
        val ds=sum(differences);
        val ys=sum(sums);
        val d2=squares(differences);
        result.nn50=differences.count {
            abs(it)>50
        };
        if(k>0) {
            result.rmssd=Report.root(d2,k.toLong());
            result.pnn50=Report.rdiv(10000L*result.nn50,k.toLong())
        };
        if(k>=2) {
            val numerator=k*d2-ds*ds;
            val denominator=k.toLong()*(k-1);
            result.sdsd=Report.root(numerator,denominator);
            result.sd1=Report.root(numerator,2*denominator);
            result.sd2=Report.root(k*squares(sums)-ys*ys,2*denominator)
        };
        for(u in values) {
            val bin=16*u/125;
            result.histogram[bin]=result.histogram.getOrDefault(bin,0)+1
        };
        result.maximum=result.histogram.values.maxOrNull()?:0;
        return result
    }
    fun ranges(indices: List<Int>): List<IntArray> {
        val result=mutableListOf<IntArray>();
        for(i in indices) {
            if(result.isNotEmpty()&&result.last()[1]+1==i)result.last()[1]=i else result+=intArrayOf(i,i)
        };
        return result
    }
}
