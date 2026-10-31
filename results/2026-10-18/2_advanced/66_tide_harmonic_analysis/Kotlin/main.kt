import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.TreeMap
import kotlin.math.*
object TideAnalysis {
    lateinit var settings: Records.Settings;
    lateinit var constituents: List<Records.Constituent>;
    val results=mutableListOf<Result>()
    data class Selection(val selected: List<Records.Constituent>,val status: Array<String>)
    data class Error(val amplitude: Double,val phase: Double,val snr: Double)
    data class Day(val date: LocalDate,val highs: Int,val lows: Int,val hhw: Double?,val llw: Double?,val range: Double?)
    data class Event(val first: Int,val last: Int,val peak: Int,val positive: Boolean)
    data class DailyMean(val date: LocalDate,val level: Double,val filled: Int)
    data class MeanStats(val average: Double,val slope: Double,val maximum: DailyMean,val minimum: DailyMean)
    data class Validation(val split: Int,val train: Int,val test: Int,val constituents: Int,val rms: Double,val inSample: Double,val skill: Double)
    class Tides {
        var form=0.0;
        var spring=0.0;
        var neap=0.0;
        var mhhw=0.0;
        var mhw=0.0;
        var mlw=0.0;
        var mllw=0.0;
        var mtl=0.0;
        var dtl=0.0;
        var mn=0.0;
        var gt=0.0;
        var hat=0.0;
        var lat=0.0;
        var rise=0.0;
        var fall=0.0;
        var ratio=0.0;
        var relative=0.0;
        var above=0.0;
        var below=0.0;
        var type="";
        var dominance="";
        lateinit var highest: Predict.Extremum;
        lateinit var lowest: Predict.Extremum;
        lateinit var widest: Day;
        lateinit var narrowest: Day
    }
    class Result {
        lateinit var station: Records.Station;
        lateinit var clean: Cleaning.Record;
        lateinit var selection: Selection;
        lateinit var model: HarmonicFit.Model;
        val residuals=DoubleArray(10001);
        lateinit var hourly: DoubleArray;
        var ss=0.0;
        var s2=0.0;
        var rms=0.0;
        var maxAbs=0.0;
        var explained=0.0;
        var lag1=0.0;
        var dof=0;
        var raw=0;
        val errors=mutableListOf<Error>();
        lateinit var extrema: MutableList<Predict.Extremum>;
        val days=mutableListOf<Day>();
        val events=mutableListOf<Event>();
        val means=mutableListOf<DailyMean>();
        lateinit var meanStats: MeanStats;
        lateinit var validation: Validation;
        lateinit var tides: Tides
    }
    fun integer(name: String,i: Int)=settings.integer(name,i)
    fun real(name: String,i: Int)=settings.real(name,i)
    fun f(value: Double,places: Int)=Report.f(value,places)
    fun hour(t: Int)=Records.hour(settings,t)
    fun minute(m: Int)=Records.minute(settings,m)
    fun height(r: Result,t: Double)=Predict.height(r.model,t)
    fun height(r: Result,t: Int)=height(r,t.toDouble())
    fun select(length: Int): Selection {
        val selected=mutableListOf<Records.Constituent>();
        val status=Array(constituents.size) {
            ""
        };
        for((i,c) in constituents.withIndex()) {
            if(c.speed*length<360*real("rayleigh",0)) {
                status[i]="short";
                continue
            };
            var conflict: String?=null;
            for(chosen in selected)if(abs(c.speed-chosen.speed)*length<360*real("rayleigh",0)) {
                conflict=chosen.name;
                break
            };
            if(conflict!=null)status[i]="conflict:$conflict" else {
                status[i]="fitted";
                selected.add(c)
            }
        };
        return Selection(selected,status)
    }
    fun index(r: Result,name: String)=r.model.selected.indexOfFirst {
        it.name==name
    }
    fun constant(r: Result,name: String)=r.model.constants[index(r,name)]
    fun analyze(station: Records.Station) {
        val r=Result();
        r.station=station;
        r.clean=Cleaning.prepare(station,integer("flat_run",0));
        val c=r.clean;
        r.selection=select(c.last-c.first);
        val prefit=HarmonicFit.fit(c.values,c.candidates,r.selection.selected);
        val preliminary=DoubleArray(10001);
        var preSs=0.0;
        for(t in c.candidates) {
            preliminary[t]=c.values[t]-Predict.height(prefit,t.toDouble());
            preSs+=preliminary[t]*preliminary[t]
        };
        c.prefitRms=sqrt(preSs/c.candidates.size);
        Cleaning.spikes(c,preliminary,settings);
        r.model=HarmonicFit.fit(c.values,c.times,r.selection.selected);
        val p=r.model.coefficients.size;
        val n=c.times.size;
        r.dof=n-p;
        var mean=0.0
        for(t in c.times) {
            mean+=c.values[t];
            val residual=c.values[t]-height(r,t);
            r.residuals[t]=residual;
            r.ss+=residual*residual;
            r.maxAbs=maxOf(r.maxAbs,abs(residual))
        };
        mean/=n;
        var variance=0.0;
        var lagProduct=0.0;
        var lagSquares=0.0;
        for(t in c.times) {
            val v=c.values[t]-mean;
            variance+=v*v;
            if(t<10000&&c.usable[t+1]) {
                lagProduct+=r.residuals[t]*r.residuals[t+1];
                lagSquares+=r.residuals[t]*r.residuals[t]
            }
        };
        r.s2=r.ss/r.dof;
        r.rms=sqrt(r.ss/n);
        r.explained=100*(1-r.ss/variance);
        r.lag1=lagProduct/lagSquares
        for(k in r.model.constants.indices) {
            val item=r.model.constants[k];
            val ia=2*k+1;
            val ib=2*k+2;
            val a=item.a;
            val b=item.b;
            val amp=item.amplitude;
            val va=r.s2*r.model.inverse[ia][ia];
            val vb=r.s2*r.model.inverse[ib][ib];
            val cab=r.s2*r.model.inverse[ia][ib];
            val ea=sqrt(a*a*va+b*b*vb+2*a*b*cab)/amp;
            val ep=sqrt(b*b*va+a*a*vb-2*a*b*cab)/(amp*amp)*180/HarmonicFit.PI;
            val ratio=amp/ea;
            r.errors.add(Error(ea,ep,ratio*ratio))
        };
        prediction(r);
        validation(r);
        events(r);
        dailyMeans(r);
        r.tides=tides(r);
        results.add(r)
    }
    fun prediction(r: Result) {
        val count=integer("predict",2);
        r.hourly=Predict.hours(r.model,settings.ts,count);
        r.extrema=Predict.extrema(r.model,settings.ts,count,integer("grid_minutes",0));
        r.raw=r.extrema.size
        while(r.extrema.size>=2) {
            var chosen=0;
            var difference=abs(r.extrema[0].height-r.extrema[1].height);
            for(i in 1 until r.extrema.size-1) {
                val d=abs(r.extrema[i].height-r.extrema[i+1].height);
                if(d<difference) {
                    difference=d;
                    chosen=i
                }
            };
            if(difference>=real("min_range",0))break;
            r.extrema.removeAt(chosen+1);
            r.extrema.removeAt(chosen)
        }
        val byDate=TreeMap<LocalDate,MutableList<Predict.Extremum>>();
        for(e in r.extrema) {
            e.rounded=floor(e.minute+0.5).toInt();
            val date=Records.dateMinute(settings,e.rounded);
            val group=byDate.getOrPut(date) {
                mutableListOf()
            };
            group.add(e)
        }
        for(group in byDate.values) {
            var high: Predict.Extremum?=null;
            var low: Predict.Extremum?=null;
            for(e in group)if(e.high) {
                val previous=high;
                if(previous==null||e.height>previous.height)high=e
            } else {
                val previous=low;
                if(previous==null||e.height<previous.height)low=e
            };
            for(e in group)e.label=if(e.high) {
                if(e===high)"HHW" else "LHW"
            } else {
                if(e===low)"LLW" else "HLW"
            }
        }
        for(d in 0 until count/24) {
            val date=settings.start.toLocalDate().plusDays(d.toLong());
            val group=byDate[date]?:emptyList();
            var highs=0;
            var lows=0;
            var high: Double?=null;
            var low: Double?=null;
            for(e in group)if(e.high) {
                highs++;
                val previous=high;
                if(previous==null||e.height>previous)high=e.height
            } else {
                lows++;
                val previous=low;
                if(previous==null||e.height<previous)low=e.height
            };
            r.days.add(Day(date,highs,lows,high,low,if(high==null||low==null)null else high-low))
        }
    }
    fun validation(r: Result) {
        val c=r.clean;
        val split=c.first+(c.last-c.first)/2;
        val train=c.times.filter {
            it<=split
        };
        val test=c.times.filter {
            it>split
        };
        val selection=select(train.last()-train.first());
        val model=HarmonicFit.fit(c.values,train,selection.selected);
        var mean=0.0;
        for(t in test)mean+=c.values[t];
        mean/=test.size;
        var errors=0.0;
        var inSample=0.0;
        var variance=0.0;
        for(t in test) {
            val error=c.values[t]-Predict.height(model,t.toDouble());
            val difference=c.values[t]-mean;
            errors+=error*error;
            inSample+=r.residuals[t]*r.residuals[t];
            variance+=difference*difference
        };
        r.validation=Validation(split,train.size,test.size,selection.selected.size,sqrt(errors/test.size),sqrt(inSample/test.size),1-errors/variance)
    }
    fun eventSign(r: Result,t: Int)=if(!r.clean.usable[t])0 else if(r.residuals[t]>real("surge",0))1 else if(r.residuals[t]<-real("surge",0))-1 else 0
    fun events(r: Result) {
        var t=r.clean.first;
        while(t<=r.clean.last) {
            val sign=eventSign(r,t);
            if(sign==0) {
                t++;
                continue
            };
            val first=t;
            var peak=t;
            while(t+1<=r.clean.last&&eventSign(r,t+1)==sign) {
                t++;
                if(sign*r.residuals[t]>sign*r.residuals[peak])peak=t
            };
            if(t-first+1>=integer("surge",1))r.events.add(Event(first,t,peak,sign>0));
            t++
        }
    }
    fun dailyMeans(r: Result) {
        val weights=intArrayOf(0,2,1,1,2,0,1,1,0,2,0,1,1,0,1,0,0,1,0,1);
        val first=Records.dateHour(settings,r.clean.first);
        val last=Records.dateHour(settings,r.clean.last);
        var date=first
        while(!date.isAfter(last)) {
            val noon=Records.noon(settings,date);
            if(noon-19>=r.clean.first&&noon+19<=r.clean.last) {
                var sum=0.0;
                var filled=0;
                for(j in -19..19) {
                    val t=noon+j;
                    val value=if(r.clean.usable[t])r.clean.values[t] else {
                        filled++;
                        height(r,t)
                    };
                    sum+=weights[abs(j)]*value
                };
                r.means.add(DailyMean(date,sum/30,filled))
            };
            date=date.plusDays(1)
        }
        var xm=0.0;
        var vm=0.0;
        var maximum=r.means.first();
        var minimum=maximum;
        val origin=maximum.date;
        for(day in r.means) {
            xm+=ChronoUnit.DAYS.between(origin,day.date);
            vm+=day.level;
            if(day.level>maximum.level)maximum=day;
            if(day.level<minimum.level)minimum=day
        };
        xm/=r.means.size;
        vm/=r.means.size;
        var numerator=0.0;
        var denominator=0.0;
        for(day in r.means) {
            val x=ChronoUnit.DAYS.between(origin,day.date)-xm;
            val v=day.level-vm;
            numerator+=x*v;
            denominator+=x*x
        };
        r.meanStats=MeanStats(vm,1000*(numerator/denominator),maximum,minimum)
    }
    fun tides(r: Result): Tides {
        val t=Tides();
        val m2=constant(r,"M2").amplitude;
        val s2=constant(r,"S2").amplitude;
        val k1=constant(r,"K1").amplitude;
        val o1=constant(r,"O1").amplitude;
        t.form=(k1+o1)/(m2+s2);
        t.type=if(t.form<0.25)"semidiurnal" else if(t.form<1.5)"mixed_semidiurnal" else if(t.form<3)"mixed_diurnal" else "diurnal";
        t.spring=2*(m2+s2);
        t.neap=2*(m2-s2);
        var nh=0;
        var nl=0;
        var nhh=0;
        var nll=0;
        t.highest=r.extrema.first {
            it.high
        };
        t.lowest=r.extrema.first {
            !it.high
        };
        t.widest=r.days.first {
            it.range!=null
        };
        t.narrowest=t.widest
        for(e in r.extrema)if(e.high) {
            t.mhw+=e.height;
            nh++;
            if(e.height>t.highest.height)t.highest=e
        } else {
            t.mlw+=e.height;
            nl++;
            if(e.height<t.lowest.height)t.lowest=e
        };
        for(day in r.days) {
            val hhw=day.hhw;
            val llw=day.llw;
            val range=day.range;
            if(hhw!=null) {
                t.mhhw+=hhw;
                nhh++
            };
            if(llw!=null) {
                t.mllw+=llw;
                nll++
            };
            if(range!=null) {
                if(range>t.widest.range!!)t.widest=day;
                if(range<t.narrowest.range!!)t.narrowest=day
            }
        }
        t.mhw/=nh;
        t.mlw/=nl;
        t.mhhw/=nhh;
        t.mllw/=nll;
        t.mtl=(t.mhw+t.mlw)/2;
        t.dtl=(t.mhhw+t.mllw)/2;
        t.mn=t.mhw-t.mlw;
        t.gt=t.mhhw-t.mllw;
        var amplitudes=0.0;
        for(c in r.model.constants)amplitudes+=c.amplitude;
        t.hat=r.model.coefficients[0]+amplitudes;
        t.lat=r.model.coefficients[0]-amplitudes;
        var rise=0;
        var fall=0;
        for(i in 1 until r.extrema.size) {
            val a=r.extrema[i-1];
            val b=r.extrema[i];
            if(!a.high&&b.high) {
                t.rise+=b.rounded-a.rounded;
                rise++
            };
            if(a.high&&!b.high) {
                t.fall+=b.rounded-a.rounded;
                fall++
            }
        };
        t.rise/=rise;
        t.fall/=fall;
        t.ratio=constant(r,"M4").amplitude/m2;
        t.relative=2*constant(r,"M2").phase-constant(r,"M4").phase;
        while(t.relative<0)t.relative+=360;
        while(t.relative>=360)t.relative-=360;
        t.dominance=if(t.relative<180)"flood" else "ebb";
        var above=0;
        var below=0;
        for(value in r.hourly) {
            if(value>t.mhhw)above++;
            if(value<t.mllw)below++
        };
        t.above=100.0*above/r.hourly.size;
        t.below=100.0*below/r.hourly.size;
        return t
    }
    fun cleaningLines(): List<String> {
        val lines=mutableListOf<String>();
        for(r in results) {
            val c=r.clean;
            val counts=mutableMapOf<String,Int>();
            for(t in c.first..c.last) {
                val reason=c.reasons[t];
                if(reason!=null)counts[reason]=counts.getOrDefault(reason,0)+1
            };
            lines.add("station=${r.station.code} name=${r.station.name}");
            lines.add("span start=${hour(c.first)} end=${hour(c.last)} hours=${c.last-c.first+1} record_length=${c.last-c.first}");
            lines.add("counts rows=${r.station.rows} numeric=${c.numeric} na=${counts.getOrDefault("na",0)} absent=${counts.getOrDefault("absent",0)} flat=${counts.getOrDefault("flat",0)} spikes=${counts.getOrDefault("spike",0)} usable=${c.times.size}");
            for(run in c.runs)lines.add("flat start=${hour(run.first)} end=${hour(run.last)} value=${f(run.value,3)} removed=${run.last-run.first}");
            lines.add("spike_test window=${integer("spike",0)} candidates=${c.candidates.size} tested=${c.tested} prefit_rms=${f(c.prefitRms,4)}");
            for(spike in c.spikes)lines.add("spike time=${hour(spike.time)} value=${f(spike.value,3)} residual=${f(spike.residual,4)} median=${f(spike.median,4)} mad=${f(spike.mad,4)} limit=${f(spike.limit,4)}");
            for(gap in c.gaps)lines.add("gap start=${hour(gap.first)} end=${hour(gap.last)} hours=${gap.last-gap.first+1} cause=${gap.cause}")
        };
        return lines
    }
    fun constituentLines(): List<String> {
        val lines=mutableListOf("station,constituent,speed,status,amplitude,phase,amplitude_error,phase_error,snr,significant");
        for(r in results) {
            var k=0;
            for((i,c) in constituents.withIndex()) {
                val status=r.selection.status[i];
                var line="${r.station.code},${c.name},${f(c.speed,7)},$status";
                if(status!="fitted")line+=",,,,,," else {
                    val v=r.model.constants[k];
                    val e=r.errors[k++];
                    val significant=if(e.snr>=real("snr_min",0))"yes" else "no";
                    line+=",${f(v.amplitude,4)},${f(v.phase,2)},${f(e.amplitude,4)},${f(e.phase,2)},${f(e.snr,1)},$significant"
                };
                lines.add(line)
            }
        };
        return lines
    }
    fun predictionLines(): List<String> {
        val lines=mutableListOf<String>();
        var header="time";
        for(r in results)header+=","+r.station.code;
        lines.add(header);
        for(i in 0..integer("predict",2)) {
            var line=hour(settings.ts+i);
            for(r in results)line+=","+f(r.hourly[i],3);
            lines.add(line)
        };
        return lines
    }
    fun extremeLines(): List<String> {
        val lines=mutableListOf<String>();
        for(r in results) {
            lines.add("station=${r.station.code} extremes=${r.extrema.size} raw=${r.raw} removed=${r.raw-r.extrema.size}");
            var previous: Predict.Extremum?=null;
            for(e in r.extrema) {
                val before=previous;
                val change=if(before==null)"none" else f(e.height-before.height,3);
                lines.add("${minute(e.rounded)} ${e.label} ${f(e.height,3)} change=$change");
                previous=e
            };
            for(day in r.days)lines.add("day date=${day.date} high_waters=${day.highs} low_waters=${day.lows} hhw=${Report.optional(day.hhw,3)} llw=${Report.optional(day.llw,3)} range=${Report.optional(day.range,3)}")
        };
        return lines
    }
    fun stationSummary(r: Result): List<String> {
        val c=r.clean;
        val t=r.tides;
        val lines=mutableListOf("[station ${r.station.code}] ${r.station.name}","record first=${hour(c.first)} last=${hour(c.last)} length=${c.last-c.first} usable=${c.times.size}",
            "fit constituents=${r.model.selected.size} unknowns=${r.model.coefficients.size} dof=${r.dof} mean_level=${f(r.model.coefficients[0],4)}",
            "residual rms=${f(r.rms,4)} max_abs=${f(r.maxAbs,4)} explained_percent=${f(r.explained,4)} lag1_autocorrelation=${f(r.lag1,4)}")
        val top=c.times.sortedWith(compareByDescending<Int> {
            abs(r.residuals[it])
        }.thenBy {
            it
        });
        for(i in 0 until integer("top_residuals",0)) {
            val time=top[i];
            lines.add("top_residual rank=${i+1} time=${hour(time)} observed=${f(c.values[time],3)} fitted=${f(height(r,time),4)} residual=${f(r.residuals[time],4)}")
        };
        val v=r.validation;
        lines.add("validation split=${hour(v.split)} train=${v.train} test=${v.test} constituents=${v.constituents} rms=${f(v.rms,4)} in_sample_rms=${f(v.inSample,4)} skill=${f(v.skill,4)}");
        lines.add("form_number=${f(t.form,4)} type=${t.type}");
        lines.add("ranges spring=${f(t.spring,3)} neap=${f(t.neap,3)} mn=${f(t.mn,3)} gt=${f(t.gt,3)}");
        lines.add("asymmetry rise_minutes=${f(t.rise,1)} fall_minutes=${f(t.fall,1)} m4_m2_ratio=${f(t.ratio,4)} relative_phase=${f(t.relative,2)} dominance=${t.dominance}");
        lines.add("datums mhhw=${f(t.mhhw,3)} mhw=${f(t.mhw,3)} mtl=${f(t.mtl,3)} dtl=${f(t.dtl,3)} mlw=${f(t.mlw,3)} mllw=${f(t.mllw,3)}");
        lines.add("bounds hat=${f(t.hat,3)} lat=${f(t.lat,3)}");
        val nh=r.extrema.count {
            it.high
        };
        val nl=r.extrema.count {
            !it.high
        };
        lines.add("window high_waters=$nh low_waters=$nl highest=${f(t.highest.height,3)} highest_time=${minute(t.highest.rounded)} lowest=${f(t.lowest.height,3)} lowest_time=${minute(t.lowest.rounded)}");
        lines.add("daily_range widest=${f(t.widest.range!!,3)} widest_date=${t.widest.date} narrowest=${f(t.narrowest.range!!,3)} narrowest_date=${t.narrowest.date}");
        lines.add("exceedance above_mhhw=${f(t.above,2)} below_mllw=${f(t.below,2)}")
        val dw=r.model.selected[index(r,"S2")].speed-r.model.selected[index(r,"M2")].speed;
        val dg=constant(r,"S2").phase-constant(r,"M2").phase;
        val q0=(settings.ts*dw-dg)/180;
        val q1=((settings.ts+integer("predict",2))*dw-dg)/180;
        val first=floor(minOf(q0,q1)).toInt()-1;
        val last=ceil(maxOf(q0,q1)).toInt()+1;
        for(q in first..last) {
            val time=(dg+180*q)/dw;
            if(time>=settings.ts&&time<=settings.ts+integer("predict",2))lines.add((if(q%2==0)"spring" else "neap")+" time="+minute(floor(time*60+0.5).toInt()))
        };
        lines.add("surges count=${r.events.size} threshold=${f(real("surge",0),3)} min_hours=${integer("surge",1)}");
        for(event in r.events) {
            val type=if(event.positive)"positive" else "negative";
            lines.add("surge type=$type start=${hour(event.first)} end=${hour(event.last)} hours=${event.last-event.first+1} peak=${f(r.residuals[event.peak],4)} peak_time=${hour(event.peak)}")
        };
        val m=r.meanStats;
        lines.add("daily_mean days=${r.means.size} average=${f(m.average,4)} slope_mm_per_day=${f(m.slope,3)} max=${f(m.maximum.level,4)} max_date=${m.maximum.date} min=${f(m.minimum.level,4)} min_date=${m.minimum.date}");
        for(day in r.means)lines.add("daily_mean date=${day.date} level=${f(day.level,4)} filled=${day.filled}");
        return lines
    }
    fun lag(station: Result,reference: Result,high: Boolean): Double {
        var sum=0.0;
        var count=0;
        for(e in station.extrema)if(e.high==high) {
            var distance=Int.MAX_VALUE;
            var chosen=0;
            for(other in reference.extrema)if(other.high==high) {
                val d=abs(e.rounded-other.rounded);
                if(d<distance||d==distance&&other.rounded<chosen) {
                    distance=d;
                    chosen=other.rounded
                }
            };
            sum+=e.rounded-chosen;
            count++
        };
        return sum/count
    }
    data class Correlation(val value: Double,val count: Int)
    fun correlation(a: Result,b: Result,lag: Int): Correlation {
        var mx=0.0;
        var my=0.0;
        var count=0;
        for(t in a.clean.times) {
            val u=t+lag;
            if(u in 0..10000&&b.clean.usable[u]) {
                mx+=a.residuals[t];
                my+=b.residuals[u];
                count++
            }
        };
        mx/=count;
        my/=count;
        var sxy=0.0;
        var sxx=0.0;
        var syy=0.0;
        for(t in a.clean.times) {
            val u=t+lag;
            if(u in 0..10000&&b.clean.usable[u]) {
                val x=a.residuals[t]-mx;
                val y=b.residuals[u]-my;
                sxy+=x*y;
                sxx+=x*x;
                syy+=y*y
            }
        };
        return Correlation(sxy/sqrt(sxx*syy),count)
    }
    fun plot(r: Result): List<String> {
        val width=integer("plot",1);
        val top=integer("plot",2);
        val bottom=integer("plot",3);
        val step=integer("plot",4);
        val rows=(top-bottom)/step+1;
        val cells=Array(rows) {
            CharArray(width) {
                ' '
            }
        };
        val zero=floor((top-100*r.model.coefficients[0])/step+0.5).toInt();
        if(zero in 0 until rows)cells[zero].fill('-');
        val marks=CharArray(width);
        for(e in r.extrema) {
            val column=(e.rounded-60*settings.ts+30)/60;
            if(column in 0 until width)marks[column]=if(e.high)'H' else 'L'
        };
        for(column in 0 until width) {
            val row=floor((top-100*r.hourly[column])/step+0.5).toInt();
            if(row<0)cells[0][column]='^' else if(row>=rows)cells[rows-1][column]='v' else cells[row][column]=if(marks[column]=='\u0000')'*' else marks[column]
        };
        val labels=Array(rows) {
            f((top-it*step)/100.0,2)
        };
        return Report.plot(cells,labels)
    }
    fun summary(): List<String> {
        val lines=mutableListOf<String>();
        for(r in results)lines.addAll(stationSummary(r));
        val reference=results.first {
            it.station.code==settings.text("reference",0)
        };
        val plotted=results.first {
            it.station.code==settings.text("plot",0)
        };
        lines.add("[comparison] reference=${reference.station.code}")
        for(r in results)if(r!==reference) {
            lines.add("${r.station.code} tide hw_lag_min=${f(lag(r,reference,true),1)} lw_lag_min=${f(lag(r,reference,false),1)} range_ratio=${f(r.tides.gt/reference.tides.gt,4)} mtl_diff=${f(r.tides.mtl-reference.tides.mtl,3)}");
            for(name in arrayOf("M2","S2","K1","O1")) {
                val own=constant(r,name);
                val ref=constant(reference,name);
                var difference=own.phase-ref.phase;
                if(difference>180)difference-=360;
                if(difference<=-180)difference+=360;
                val timeLag=difference/r.model.selected[index(r,name)].speed*60;
                lines.add("${r.station.code} $name amplitude_ratio=${f(own.amplitude/ref.amplitude,4)} phase_diff=${f(difference,2)} time_lag_min=${f(timeLag,1)}")
            }
        }
        val limit=integer("correlation_lag",0);
        lines.add("[correlation] max_lag=$limit");
        for(i in results.indices)for(j in i+1 until results.size) {
            val a=results[i];
            val b=results[j];
            var best: Correlation?=null;
            var zero: Correlation?=null;
            var bestLag=0;
            for(lag in -limit..limit) {
                val value=correlation(a,b,lag);
                if(lag==0)zero=value;
                val previous=best;
                if(previous==null||value.value>previous.value||value.value==previous.value&&(abs(lag)<abs(bestLag)||abs(lag)==abs(bestLag)&&lag<bestLag)) {
                    best=value;
                    bestLag=lag
                }
            };
            lines.add("${a.station.code}-${b.station.code} lag0=${f(zero!!.value,4)} best_lag=$bestLag best=${f(best!!.value,4)} pairs=${best!!.count}")
        };
        lines.add("[plot] station=${plotted.station.code} start=${hour(settings.ts)} hours=${integer("plot",1)} step_cm=${integer("plot",4)}");
        lines.addAll(plot(plotted));
        return lines
    }
    fun run() {
        val data=Records.read();
        settings=data.settings;
        constituents=data.constituents;
        for(station in data.stations)analyze(station);
        Report.write("cleaning.txt",cleaningLines());
        Report.write("constituents.csv",constituentLines());
        Report.write("predictions.csv",predictionLines());
        Report.write("extremes.txt",extremeLines());
        Report.write("summary.txt",summary())
    }
}
fun main()=TideAnalysis.run()
