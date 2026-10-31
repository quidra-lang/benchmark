import kotlin.math.abs

object Picker {
    class Pick(val station: WaveformIo.Station,val sample: Int,val duration: Int,val ratio: Double,val amplitude: Long,val clipped: Boolean) {
        var event=0;
        var residual=0.0;
        var firstResidual=0.0;
        var assigned=false;
        var state="unassociated";
        fun time()=sample/100.0
    }
    fun finish(station: WaveformIo.Station,p: WaveformIo.Params,d: LongArray,e: LongArray,begin: Int,end: Int,maximum: Double) {
        station.triggers++;
        val duration=end-begin;
        if(duration<p.integer("min_duration")) {
            station.shortTriggers++;
            return
        };
        var k=begin;
        while(k-1>=begin-p.integer("sta_window")+1&&e[k-1]>=p.get("noise_level"))k--;
        var amplitude=0L;
        var clipped=false;
        for(j in k until minOf(k+p.integer("amplitude_window"),d.size)) {
            amplitude=maxOf(amplitude,abs(d[j]));
            if(abs(station.samples[j])>=p.get("clip_level"))clipped=true
        };
        station.picks+=Pick(station,station.start+k,duration,maximum,amplitude,clipped)
    }
    fun detect(s: WaveformIo.Station,p: WaveformIo.Params): List<Pick> {
        var sum=0L;
        for(value in s.samples)sum+=value;
        val n=s.samples.size;
        s.mean=Math.floorDiv(sum,n.toLong());
        val d=LongArray(n);
        val e=LongArray(n);
        val prefix=LongArray(n+1);
        val absolute=mutableListOf<Double>();
        for(i in 0 until n) {
            d[i]=s.samples[i]-s.mean;
            e[i]=d[i]*d[i];
            prefix[i+1]=prefix[i]+e[i];
            absolute+=abs(d[i]).toDouble();
            s.peak=maxOf(s.peak,abs(d[i]));
            if(abs(s.samples[i])>=p.get("clip_level"))s.clipped++
        };
        s.noise=Magnitude.median(absolute);
        val sw=p.integer("sta_window");
        val lw=p.integer("lta_window");
        val on=p.row("trigger_on");
        val off=p.row("trigger_off");
        var active=false;
        var begin=0;
        var maximum=0.0;
        for(i in sw+lw-1 until n) {
            val sta=prefix[i+1]-prefix[i-sw+1];
            val lta=prefix[i-sw+1]-prefix[i-sw-lw+1];
            val ratio=(sta*lw).toDouble()/(lta*sw);
            if(!active) {
                if(sta*lw*on[1].toLong()>=on[0].toLong()*lta*sw) {
                    active=true;
                    begin=i;
                    maximum=ratio
                }
            } else if(sta*lw*off[1].toLong()<off[0].toLong()*lta*sw) {
                finish(s,p,d,e,begin,i,maximum);
                active=false
            } else maximum=maxOf(maximum,ratio)
        };
        if(active)finish(s,p,d,e,begin,n,maximum);
        return s.picks
    }
}
