import kotlin.math.*

object Estimators {
    fun risk(subjects: List<Dataset.Subject>,time: Int)=subjects.count {
        it.time>=time
    }
    fun eventTimes(subjects: List<Dataset.Subject>,reverse: Boolean)=subjects.filter {
        it.event==if(reverse)0 else 1
    }.map {
        it.time
    }.toSortedSet().toList()
    class Row {
        var time=0;
        var risk=0;
        var events=0;
        var censored=0;
        var survival=1.0;
        var se=0.0;
        var lower=Double.NaN;
        var upper=Double.NaN;
        var hazard=0.0;
        var hazardSe=0.0
    }
    fun km(subjects: List<Dataset.Subject>,reverse: Boolean): List<Row> {
        val times=eventTimes(subjects,reverse);
        val result=mutableListOf<Row>();
        var survival=1.0;
        var greenwood=0.0;
        var hazard=0.0;
        var variance=0.0;
        for(i in times.indices) {
            val time=times[i];
            val n=risk(subjects,time);
            var d=0;
            var censored=0;
            for(s in subjects) {
                val event=if(reverse)1-s.event else s.event;
                if(s.time==time&&event==1)d++;
                if(event==0&&s.time>=time&&(i+1==times.size||s.time<times[i+1]))censored++
            };
            survival*=(n-d).toDouble()/n;
            hazard+=d.toDouble()/n;
            variance+=d.toDouble()/(n*n);
            val r=Row();
            r.time=time;
            r.risk=n;
            r.events=d;
            r.censored=censored;
            r.survival=survival;
            r.hazard=hazard;
            r.hazardSe=sqrt(variance);
            if(n==d) {
                greenwood=Double.NaN;
                r.se=Double.NaN
            }else {
                greenwood+=d.toDouble()/(n*(n-d));
                r.se=survival*sqrt(greenwood);
                val log=ln(survival);
                val omega=Numerics.Z*sqrt(greenwood)/(-log);
                r.lower=exp(log*exp(omega));
                r.upper=exp(log*exp(-omega))
            };
            result+=r
        };
        return result
    }
    fun at(rows: List<Row>,time: Int): Row {
        var result=Row();
        for(r in rows) {
            if(r.time>time)break;
            result=r
        };
        return result
    }
    class Life {
        var start=0;
        var end=0;
        var risk=0;
        var events=0;
        var withdrawn=0;
        var exposed2=0;
        var q=0.0;
        var survival=0.0;
        var se=0.0;
        var hazard=0.0
    }
    fun life(subjects: List<Dataset.Subject>,width: Int,count: Int): List<Life> {
        val result=mutableListOf<Life>();
        var survival=1.0;
        var greenwood=0.0;
        for(i in 0 until count) {
            val r=Life();
            r.start=i*width;
            r.end=(i+1)*width;
            r.risk=risk(subjects,r.start);
            for(s in subjects)if(s.time>=r.start&&s.time<r.end) {
                if(s.event==1)r.events++ else r.withdrawn++
            };
            val f=2*r.risk-r.withdrawn;
            r.exposed2=f;
            r.q=(2*r.events).toDouble()/f;
            survival*=(f-2*r.events).toDouble()/f;
            greenwood+=(4*r.events).toDouble()/(f*(f-2*r.events));
            r.survival=survival;
            r.se=survival*sqrt(greenwood);
            r.hazard=(2000*r.events).toDouble()/(width*(f-r.events));
            result+=r
        };
        return result
    }
}
