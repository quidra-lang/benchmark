import kotlin.math.abs
object Cleaning {
    data class Run(val first: Int,val last: Int,val value: Double)
    data class Spike(val time: Int,val value: Double,val residual: Double,val median: Double,val mad: Double,val limit: Double)
    data class Gap(val first: Int,val last: Int,val cause: String)
    class Record {
        var first=0;
        var last=0;
        var numeric=0;
        var tested=0;
        var prefitRms=0.0;
        val values=DoubleArray(10001);
        val candidate=BooleanArray(10001);
        val usable=BooleanArray(10001);
        val reasons=arrayOfNulls<String>(10001);
        val candidates=mutableListOf<Int>();
        val times=mutableListOf<Int>();
        val runs=mutableListOf<Run>();
        val spikes=mutableListOf<Spike>();
        val gaps=mutableListOf<Gap>()
    }
    fun median(values: List<Double>): Double {
        val sorted=values.sorted();
        val n=sorted.size;
        return if(n%2==1)sorted[n/2] else (sorted[n/2-1]+sorted[n/2])/2
    }
    fun prepare(station: Records.Station,minimumRun: Int): Record {
        val r=Record();
        val numeric=mutableListOf<Int>();
        for((time,value) in station.values)if(value!=null) {
            numeric.add(time);
            r.values[time]=value/1000.0
        };
        r.first=numeric.first();
        r.last=numeric.last();
        r.numeric=numeric.size;
        for(t in r.first..r.last) {
            if(!station.values.containsKey(t))r.reasons[t]="absent" else if(station.values[t]==null)r.reasons[t]="na"
        };
        var i=0;
        while(i<numeric.size) {
            val first=numeric[i];
            var last=first;
            while(i+1<numeric.size&&numeric[i+1]==last+1&&station.values[numeric[i+1]]==station.values[first]) {
                i++;
                last=numeric[i]
            };
            if(last-first+1>=minimumRun) {
                r.runs.add(Run(first,last,r.values[first]));
                for(t in first+1..last)r.reasons[t]="flat"
            };
            i++
        };
        for(t in numeric)if(r.reasons[t]==null) {
            r.candidates.add(t);
            r.candidate[t]=true
        };
        return r
    }
    fun spikes(r: Record,residuals: DoubleArray,s: Records.Settings) {
        val width=s.integer("spike",0);
        val required=s.integer("spike",1);
        for(t in r.candidates) {
            val values=mutableListOf<Double>();
            for(u in maxOf(r.first,t-width)..minOf(r.last,t+width))if(r.candidate[u])values.add(residuals[u]);
            if(values.size<required)continue;
            r.tested++;
            val center=median(values);
            val deviations=values.map {
                abs(it-center)
            };
            val mad=median(deviations);
            val limit=maxOf(s.real("spike",2)*1.4826*mad,s.real("spike",3));
            if(abs(residuals[t]-center)>limit) {
                r.reasons[t]="spike";
                r.spikes.add(Spike(t,r.values[t],residuals[t],center,mad,limit))
            }
        };
        for(t in r.candidates)if(r.reasons[t]==null) {
            r.usable[t]=true;
            r.times.add(t)
        };
        var t=r.first;
        while(t<=r.last) {
            if(r.reasons[t]==null) {
                t++;
                continue
            };
            val first=t;
            var cause=r.reasons[t]!!;
            while(t+1<=r.last&&r.reasons[t+1]!=null) {
                t++;
                if(cause!=r.reasons[t])cause="mixed"
            };
            r.gaps.add(Gap(first,t,cause));
            t++
        }
    }
}
