import java.io.File
import java.math.BigDecimal
import java.math.RoundingMode
import kotlin.math.*

object Main {
    lateinit var params: WaveformIo.Params
    lateinit var stations: List<WaveformIo.Station>
    val picks=mutableListOf<Picker.Pick>();
    lateinit var candidates: List<Associator.Candidate>;
    val events=mutableListOf<Event>();
    val clusters=mutableListOf<List<Event>>()
    data class Jack(val station: WaveformIo.Station,val dx: Double,val dy: Double,val dz: Double,val shift: Double)
    class Event(val number: Int,val used: List<Picker.Pick>,val first: Locator.Run) {
        var cluster=0;
        lateinit var relocated: Locator.Run;
        lateinit var observations: List<Locator.Observation>;
        lateinit var ellipse: Locator.Ellipse;
        val jack=mutableListOf<Jack>();
        var maximum: Jack?=null;
        var startRms=0.0;
        var gap=0.0;
        var dmin=0.0;
        var dh=0.0;
        var dz=0.0;
        var md=0.0;
        var ml: Double?=null;
        var mlc: Double?=null;
        var quality="C";
        val magnitudes=mutableListOf<Magnitude.Values>();
        fun solution()=relocated.solution
    }
    fun decimal(value: Double,digits: Int): String {
        var rounded=BigDecimal.valueOf(value).setScale(digits,RoundingMode.HALF_UP);
        if(rounded.signum()==0)rounded=BigDecimal.ZERO.setScale(digits);
        return rounded.toPlainString()
    }
    fun magnitude(value: Double?)=if(value==null)"-" else decimal(value,2)
    fun time(sample: Int)="${sample/100}.${(sample%100).toString().padStart(2,'0')}"
    fun write(name: String,lines: List<String>) {
        File("output/$name").writeText(lines.joinToString("\n",postfix="\n"),Charsets.US_ASCII)
    }
    fun observations(input: List<Picker.Pick>,corrected: Boolean)=input.map {
        Locator.Observation(it.station,it.time()-if(corrected)it.station.correction else 0.0)
    }
    fun locate() {
        for(candidate in candidates) {
            candidate.picks=candidate.picks.sortedBy {
                it.station.order
            };
            val first=Locator.locate(observations(candidate.picks,false),params);
            candidate.passes+=first;
            val retained=mutableListOf<Picker.Pick>();
            for(i in candidate.picks.indices) {
                val pick=candidate.picks[i];
                if(abs(first.residuals[i])>params.get("residual_limit"))candidate.dropped+=pick else retained+=pick
            };
            if(candidate.dropped.isNotEmpty()&&retained.size<params.integer("min_stations")) {
                candidate.rejected=true;
                for(pick in candidate.picks)pick.state="rejected";
                continue
            };
            var adopted=first;
            if(candidate.dropped.isNotEmpty()) {
                adopted=Locator.locate(observations(retained,false),params);
                candidate.passes+=adopted
            };
            val event=Event(events.size+1,retained,adopted);
            candidate.event=event;
            for(i in retained.indices) {
                val pick=retained[i];
                pick.state="used";
                pick.event=event.number;
                pick.firstResidual=adopted.residuals[i]
            };
            for(pick in candidate.dropped) {
                pick.state="dropped";
                pick.event=event.number
            };
            events+=event
        }
    }
    fun used(station: WaveformIo.Station)=events.flatMap {
        it.used
    }.filter {
        it.station===station
    }
    fun relocate() {
        val velocity=params.get("velocity");
        for(station in stations) {
            val used=used(station);
            var sum=0.0;
            for(pick in used)sum+=pick.firstResidual;
            station.correction=if(used.isEmpty())0.0 else sum/used.size
        };
        for(event in events) {
            event.observations=observations(event.used,true);
            event.startRms=Locator.rms(event.first.solution,event.observations,velocity);
            event.relocated=Locator.geiger(event.first.solution,event.observations,velocity);
            for(i in event.used.indices)event.used[i].residual=event.relocated.residuals[i];
            val solution=event.solution();
            event.ellipse=Locator.ellipse(solution,event.observations,velocity);
            val angles=mutableListOf<Double>();
            event.dmin=Double.POSITIVE_INFINITY;
            for(pick in event.used) {
                val station=pick.station;
                var phi=atan2(station.x-solution[0],station.y-solution[1])*180/Locator.PI;
                if(phi<0)phi+=360;
                angles+=phi;
                val distance=sqrt(Locator.sq(station.x-solution[0])+Locator.sq(station.y-solution[1]));
                event.dmin=minOf(event.dmin,distance)
            };
            angles.sort();
            event.gap=angles.first()+360-angles.last();
            for(i in 1 until angles.size)event.gap=maxOf(event.gap,angles[i]-angles[i-1]);
            for(grade in listOf("A","B")) {
                val bound=params.row("quality_${grade.lowercase()}");
                if(event.gap<=bound[0]&&event.relocated.rms<=bound[1]&&event.ellipse.smaj<=bound[2]) {
                    event.quality=grade;
                    break
                }
            };
            event.dh=sqrt(Locator.sq(solution[0]-event.first.solution[0])+Locator.sq(solution[1]-event.first.solution[1]));
            event.dz=solution[2]-event.first.solution[2];
            for(i in event.used.indices) {
                val remaining=event.observations.filterIndexed {
                    j,_->j!=i
                };
                val alternative=Locator.geiger(solution,remaining,velocity).solution;
                val dx=alternative[0]-solution[0];
                val dy=alternative[1]-solution[1];
                val dz=alternative[2]-solution[2];
                val shift=sqrt(dx*dx+dy*dy);
                val jack=Jack(event.used[i].station,dx,dy,dz,shift);
                event.jack+=jack;
                if(event.maximum==null||shift>event.maximum!!.shift)event.maximum=jack
            }
        }
    }
    fun magnitudes() {
        val residuals=stations.associateWith {
            mutableListOf<Double>()
        };
        for(event in events) {
            val local=mutableListOf<Double>();
            val duration=mutableListOf<Double>();
            for(pick in event.used) {
                val values=Magnitude.perPick(pick,Locator.distance(event.solution(),pick.station)/1000,params);
                event.magnitudes+=values;
                duration+=values.md;
                values.ml?.let {
                    local+=it
                }
            };
            event.ml=if(local.isEmpty())null else Magnitude.median(local);
            event.md=Magnitude.median(duration);
            for(i in event.used.indices) {
                val ml=event.magnitudes[i].ml;
                if(ml!=null)residuals.getValue(event.used[i].station).add(ml-event.ml!!)
            }
        };
        for(station in stations) {
            val values=residuals.getValue(station);
            var sum=0.0;
            for(value in values)sum+=value;
            station.magnitudeCorrection=if(values.isEmpty())0.0 else sum/values.size
        };
        for(event in events) {
            val values=mutableListOf<Double>();
            for(i in event.used.indices) {
                val ml=event.magnitudes[i].ml;
                if(ml!=null)values+=ml-event.used[i].station.magnitudeCorrection
            };
            event.mlc=if(values.isEmpty())null else Magnitude.median(values)
        }
    }
    fun cluster() {
        val bounds=params.row("cluster");
        val seen=BooleanArray(events.size);
        for(i in events.indices) {
            if(seen[i])continue;
            val members=mutableListOf<Event>();
            val queue=ArrayDeque<Int>();
            queue.addLast(i);
            seen[i]=true;
            while(queue.isNotEmpty()) {
                val current=queue.removeFirst();
                val event=events[current];
                members+=event;
                for(j in events.indices) {
                    if(seen[j])continue;
                    val a=event.solution();
                    val b=events[j].solution();
                    val distance=sqrt(Locator.sq(a[0]-b[0])+Locator.sq(a[1]-b[1])+Locator.sq(a[2]-b[2]));
                    if(abs(a[3]-b[3])<=bounds[1]&&distance<=bounds[0]) {
                        seen[j]=true;
                        queue.addLast(j)
                    }
                }
            };
            members.sortBy {
                it.number
            };
            clusters.add(members);
            for(event in members)event.cluster=clusters.size
        }
    }
    fun reassociate() {
        val stationSets=events.map {
            event->event.used.map {
                it.station.order
            }.toMutableSet()
        };
        for(pick in picks) {
            if(pick.state!="unassociated")continue;
            var best: Event?=null;
            var error=0.0;
            for(event in events) {
                if(pick.station.order in stationSets[event.number-1])continue;
                val s=event.solution();
                val residual=pick.time()-s[3]-Locator.distance(s,pick.station)/params.get("velocity")-pick.station.correction;
                if(abs(residual)<=params.get("residual_limit")&&(best==null||abs(residual)<abs(error))) {
                    best=event;
                    error=residual
                }
            };
            if(best!=null) {
                pick.state="added";
                pick.event=best.number;
                pick.residual=error;
                stationSets[best.number-1]+=pick.station.order
            }
        }
    }
    fun picksReport(): List<String> {
        val out=mutableListOf("station,sample,time_s,duration,snr,amplitude,clipped,event,status,residual");
        for(pick in picks)out+="${pick.station.code},${pick.sample},${time(pick.sample)},${pick.duration},${decimal(pick.ratio,2)},${pick.amplitude},${if(pick.clipped)"yes" else "no"},${pick.event},${pick.state},${if(pick.state in listOf("used","added"))decimal(pick.residual,4) else "-"}";
        return out
    }
    fun solutionLine(label: String,s: DoubleArray,rms: Double)="$label x=${decimal(s[0],1)} y=${decimal(s[1],1)} z=${decimal(s[2],1)} t0=${decimal(s[3],3)} rms=${decimal(rms,4)}"
    fun iterations(out: MutableList<String>,run: Locator.Run) {
        for(row in run.trace)out+=solutionLine("ITER ${row.number}",row.solution,row.rms)
    }
    fun pass(out: MutableList<String>,number: Int,input: List<Picker.Pick>,run: Locator.Run) {
        out+="PASS $number stations=${input.joinToString(","){it.station.code}}";
        val grid=run.grid!!;
        out+=solutionLine("GRID",grid.solution,grid.rms);
        out+="PROFILE ${grid.profile.joinToString(" "){decimal(it,4)}}";
        iterations(out,run);
        for(i in input.indices) {
            val pick=input[i];
            val distance=Locator.distance(run.solution,pick.station);
            out+="RES ${pick.station.code} dist=${decimal(distance,1)} tt=${decimal(distance/params.get("velocity"),4)} obs=${time(pick.sample)} res=${decimal(run.residuals[i],4)}"
        }
    }
    fun locationReport(): List<String> {
        val out=mutableListOf<String>();
        for(candidate in candidates) {
            out+="CANDIDATE ${candidate.number} picks=${candidate.picks.size} first=${time(candidate.first.sample)}";
            pass(out,1,candidate.picks,candidate.passes[0]);
            for(pick in candidate.dropped) {
                val i=candidate.picks.indexOf(pick);
                out+="DROP ${pick.station.code} res=${decimal(candidate.passes[0].residuals[i],4)}"
            };
            if(candidate.rejected)out+="RESULT REJECTED stations=${candidate.picks.size-candidate.dropped.size}" else {
                val event=candidate.event!!;
                if(candidate.passes.size==2)pass(out,2,event.used,candidate.passes[1]);
                out+="RESULT EVENT ${event.number}"
            }
        };
        out+="CORRECTIONS";
        for(station in stations)out+="${station.code} n=${used(station).size} correction=${decimal(station.correction,4)}";
        for(event in events) {
            out+="EVENT ${event.number}";
            out+=solutionLine("START",event.first.solution,event.startRms);
            iterations(out,event.relocated);
            for(pick in event.used) {
                val distance=Locator.distance(event.solution(),pick.station);
                out+="RES ${pick.station.code} dist=${decimal(distance,1)} tt=${decimal(distance/params.get("velocity"),4)} obs=${time(pick.sample)} corr=${decimal(pick.station.correction,4)} res=${decimal(pick.residual,4)}"
            };
            val e=event.ellipse;
            out+="ELLIPSE smaj=${decimal(e.smaj,1)} smin=${decimal(e.smin,1)} az=${decimal(e.az,1)} erz=${decimal(e.erz,1)} ert=${decimal(e.ert,4)}";
            out+="SHIFT dh=${decimal(event.dh,1)} dz=${decimal(event.dz,1)}";
            out+="GAP ${decimal(event.gap,1)} DMIN ${decimal(event.dmin,1)} QUALITY ${event.quality}";
            for(j in event.jack)out+="JACK ${j.station.code} dx=${decimal(j.dx,1)} dy=${decimal(j.dy,1)} dz=${decimal(j.dz,1)} shift=${decimal(j.shift,1)}";
            val maximum=event.maximum!!;
            out+="JACKKNIFE max=${decimal(maximum.shift,1)} station=${maximum.station.code}"
        };
        val points=mutableListOf<DoubleArray>();
        var sd=0.0;
        var st=0.0;
        var sdd=0.0;
        var sdt=0.0;
        for(event in events)for(pick in event.used) {
            val d=Locator.distance(event.solution(),pick.station)/1000;
            val t=pick.time()-event.solution()[3];
            points+=doubleArrayOf(d,t);
            sd+=d;
            st+=t;
            sdd+=d*d;
            sdt+=d*t
        };
        val n=points.size;
        val slope=(n*sdt-sd*st)/(n*sdd-sd*sd);
        val intercept=(st-slope*sd)/n;
        var sum=0.0;
        for(point in points)sum+=Locator.sq(point[1]-intercept-slope*point[0]);
        out+="FIT n=$n velocity=${decimal(1000/slope,1)} intercept=${decimal(intercept,4)} rms=${decimal(sqrt(sum/n),4)}";
        for(c in clusters.indices) {
            val members=clusters[c];
            if(members.size<2)continue;
            val center=DoubleArray(3);
            var low=Double.POSITIVE_INFINITY;
            var high=Double.NEGATIVE_INFINITY;
            for(event in members) {
                for(a in 0..2)center[a]+=event.solution()[a];
                low=minOf(low,event.solution()[3]);
                high=maxOf(high,event.solution()[3])
            };
            out+="CLUSTER ${c+1} events=${members.joinToString(","){it.number.toString()}} x=${decimal(center[0]/members.size,1)} y=${decimal(center[1]/members.size,1)} z=${decimal(center[2]/members.size,1)} span=${decimal(high-low,3)}"
        };
        out+="ADDED";
        for(pick in picks)if(pick.state=="added")out+="${pick.station.code} sample=${pick.sample} event=${pick.event} res=${decimal(pick.residual,4)}";
        out+="SUMMARY picks=${picks.size} candidates=${candidates.size} events=${events.size} rejected=${candidates.count{it.rejected}} unassociated=${picks.count{it.state=="unassociated"}}";
        val depths=mutableListOf<Double>();
        val qualities=IntArray(3);
        sum=0.0;
        for(event in events) {
            depths+=event.solution()[2];
            qualities[event.quality[0]-'A']++;
            sum+=event.relocated.rms
        };
        out+="DEPTH min=${decimal(depths.min(),1)} median=${decimal(Magnitude.median(depths),1)} max=${decimal(depths.max(),1)}";
        out+="QUALITY A=${qualities[0]} B=${qualities[1]} C=${qualities[2]} mean_rms=${decimal(sum/events.size,4)}";
        return out
    }
    fun catalog(): List<String> {
        val out=mutableListOf("event,origin_time,x,y,depth,rms,stations,gap,dmin,smaj,smin,azimuth,erz,ml,md,quality,cluster");
        for(event in events) {
            val s=event.solution();
            val e=event.ellipse;
            out+="${event.number},${decimal(s[3],3)},${decimal(s[0],1)},${decimal(s[1],1)},${decimal(s[2],1)},${decimal(event.relocated.rms,4)},${event.used.size},${decimal(event.gap,1)},${decimal(event.dmin,1)},${decimal(e.smaj,1)},${decimal(e.smin,1)},${decimal(e.az,1)},${decimal(e.erz,1)},${magnitude(event.ml)},${decimal(event.md,2)},${event.quality},${event.cluster}"
        };
        return out
    }
    fun stationReport(): List<String> {
        val out=mutableListOf<String>();
        for(s in stations) {
            out+="STATION ${s.code} x=${s.x} y=${s.y} elevation=${s.elevation}";
            out+="SAMPLES start=${s.start} count=${s.samples.size} mean=${s.mean} noise=${decimal(s.noise,1)} peak=${s.peak} clipped=${s.clipped}";
            out+="TRIGGERS total=${s.triggers} short=${s.shortTriggers} picks=${s.picks.size}";
            var line="PICKS";
            for(state in listOf("used","dropped","added","rejected","unassociated"))line+=" $state=${s.picks.count{it.state==state}}";
            out+=line;
            val used=used(s);
            var before=0.0;
            var after=0.0;
            var nm=0;
            for(pick in used) {
                before+=pick.firstResidual*pick.firstResidual;
                after+=pick.residual*pick.residual;
                if(!pick.clipped)nm++
            };
            out+="RESIDUALS n=${used.size} rms=${if(used.isEmpty())"-" else decimal(sqrt(before/used.size),4)} correction=${decimal(s.correction,4)} after=${if(used.isEmpty())"-" else decimal(sqrt(after/used.size),4)}";
            out+="MAGNITUDES n=$nm correction=${decimal(s.magnitudeCorrection,2)}"
        };
        return out
    }

    fun canvas(width: Int,height: Int)=Array(height) {
        CharArray(width) {
            ' '
        }
    }
    fun frame(out: MutableList<String>,grid: Array<CharArray>) {
        val edge="+"+"-".repeat(grid[0].size)+"+";
        out+=edge;
        for(row in grid)out+="|"+row.concatToString()+"|";
        out+=edge
    }
    fun magnitudeReport(): List<String> {
        val out=mutableListOf<String>();
        val magnitudes=mutableListOf<Double>();
        for(event in events) {
            val count=event.magnitudes.count {
                it.ml!=null
            };
            out+="EVENT ${event.number} ML=${magnitude(event.ml)} n=$count MD=${decimal(event.md,2)}";
            for(i in event.used.indices) {
                val pick=event.used[i];
                val value=event.magnitudes[i];
                val local=if(pick.clipped)" clipped" else " ml=${decimal(value.ml!!,2)} res=${decimal(value.ml!!-event.ml!!,2)}";
                out+="${pick.station.code} r=${decimal(value.distance,3)} amp=${pick.amplitude}$local dur=${pick.duration} md=${decimal(value.md,2)}"
            };
            event.ml?.let {
                magnitudes+=it
            }
        };
        out+="CORRECTED";
        for(event in events)out+="EVENT ${event.number} MLC=${magnitude(event.mlc)}";
        val frequency=Magnitude.frequency(magnitudes);
        out+="FMD";
        for(t in frequency.counts.firstKey()..frequency.counts.lastKey()) {
            var cumulative=0;
            for(key in frequency.counts.keys)if(key>=t)cumulative+=frequency.counts.getValue(key);
            out+="M=${Magnitude.classText(t)} N=${frequency.counts.getOrDefault(t,0)} CUM=$cumulative"
        };
        out+="MC ${Magnitude.classText(frequency.completeness)}";
        out+="BVALUE ${decimal(frequency.b,3)} SIGMA ${decimal(frequency.sigma,3)} N ${frequency.nb}";
        out+="AVALUE ${decimal(frequency.a,3)}";
        val x=mutableListOf<Double>();
        val y=mutableListOf<Double>();
        var sx=0.0;
        var sy=0.0;
        for(event in events) {
            val ml=event.ml;
            if(ml!=null) {
                x+=event.md;
                y+=ml;
                sx+=event.md;
                sy+=ml
            }
        };
        val n=x.size;
        val xm=sx/n;
        val ym=sy/n;
        var xx=0.0;
        var xy=0.0;
        var yy=0.0;
        for(i in 0 until n) {
            xx+=(x[i]-xm)*(x[i]-xm);
            xy+=(x[i]-xm)*(y[i]-ym);
            yy+=(y[i]-ym)*(y[i]-ym)
        };
        val slope=xy/xx;
        out+="MLMD n=$n slope=${decimal(slope,3)} intercept=${decimal(ym-slope*xm,3)} r=${decimal(xy/sqrt(xx*yy),3)} mean_diff=${decimal(ym-xm,3)}";
        val v=params.row("timeline");
        val duration=v[0].toInt();
        val width=v[1].toInt();
        val low=v[2].toInt();
        val high=v[3].toInt();
        val height=v[4].toInt();
        val grid=canvas(width,height);
        for(event in events) {
            val ml=event.ml?:continue;
            val t=Magnitude.rounded(event.solution()[3],3);
            val h=Magnitude.rounded(ml,2);
            if(t<0||t>=1000L*duration||h<100L*low)continue;
            val col=(t*width/(1000L*duration)).toInt();
            val level=minOf((h-100L*low)*height/(100L*(high-low)),(height-1).toLong()).toInt();
            for(k in 0..level) {
                val row=height-1-k;
                if(k==level)grid[row][col]='o' else if(grid[row][col]==' ')grid[row][col]='|'
            }
        };
        out+="TIMELINE t=0..$duration ML=$low..$high";
        frame(out,grid);
        return out
    }
    fun position(x: Long,y: Long,z: Long,chart: Int): IntArray? {
        val a=params.row("map_area");
        val size=params.row("map_size");
        val section=params.row("section");
        val xmin=a[0].toLong();
        val xmax=a[1].toLong();
        val ymin=a[2].toLong();
        val ymax=a[3].toLong();
        val width=size[0].toInt();
        val height=size[1].toInt();
        val sh=section[1].toInt();
        val zmax=section[0].toLong();
        if(chart==0) {
            if(x<10*xmin||x>=10*xmax||y<10*ymin||y>=10*ymax)return null;
            return intArrayOf(((x-10*xmin)*width/(10*(xmax-xmin))).toInt(),height-1-((y-10*ymin)*height/(10*(ymax-ymin))).toInt())
        };
        if(z>=10*zmax)return null;
        val value=if(chart==1)x else y;
        val lo=if(chart==1)xmin else ymin;
        val hi=if(chart==1)xmax else ymax;
        if(value<10*lo||value>=10*hi)return null;
        return intArrayOf(((value-10*lo)*width/(10*(hi-lo))).toInt(),(z*sh/(10*zmax)).toInt())
    }
    fun positionText(point: IntArray?)=if(point==null)"outside" else "${point[0]},${point[1]}"
    fun symbol(event: Event): Char {
        val ml=event.ml?:return '?';
        val h=Magnitude.rounded(ml,2);
        return if(h<100)'.' else if(h<200)'o' else if(h<300)'O' else '@'
    }
    fun place(grid: Array<CharArray>,point: IntArray?,symbol: Char) {
        if(point==null)return;
        val priority=" ?.oO@^";
        if(priority.indexOf(symbol)>priority.indexOf(grid[point[1]][point[0]]))grid[point[1]][point[0]]=symbol
    }
    fun mapReport(): List<String> {
        val width=params.row("map_size")[0].toInt();
        val height=params.row("map_size")[1].toInt();
        val sectionHeight=params.row("section")[1].toInt();
        val charts=listOf(canvas(width,height),canvas(width,sectionHeight),canvas(width,sectionHeight));
        val positions=mutableListOf<Array<IntArray?>>();
        for(event in events) {
            val x=Magnitude.rounded(event.solution()[0],1);
            val y=Magnitude.rounded(event.solution()[1],1);
            val z=Magnitude.rounded(event.solution()[2],1);
            val pos=arrayOfNulls<IntArray>(3);
            for(chart in 0..2) {
                pos[chart]=position(x,y,z,chart);
                place(charts[chart],pos[chart],symbol(event))
            };
            positions.add(pos)
        };
        val stationPositions=mutableListOf<IntArray?>();
        for(station in stations) {
            val pos=position(10L*station.x,10L*station.y,0,0);
            stationPositions.add(pos);
            place(charts[0],pos,'^')
        };
        val a=params.row("map_area");
        val xmin=a[0].toLong();
        val xmax=a[1].toLong();
        val ymin=a[2].toLong();
        val ymax=a[3].toLong();
        val zmax=params.row("section")[0].toLong();
        val out=mutableListOf<String>();
        out+="MAP x=$xmin..$xmax y=$ymin..$ymax";
        frame(out,charts[0]);
        out+="SECTION EW x=$xmin..$xmax z=0..$zmax";
        frame(out,charts[1]);
        out+="SECTION NS y=$ymin..$ymax z=0..$zmax";
        frame(out,charts[2]);
        out+="LEGEND ^ station . ML<1 o ML<2 O ML<3 @ ML>=3 ? no ML";
        for(i in stations.indices)out+="STATION ${stations[i].code} map=${positionText(stationPositions[i])}";
        for(i in events.indices) {
            val event=events[i];
            val pos=positions[i];
            out+="EVENT ${event.number} ${symbol(event)} map=${positionText(pos[0])} ew=${positionText(pos[1])} ns=${positionText(pos[2])}"
        };
        return out
    }
    @JvmStatic fun main(args: Array<String>) {
        val data=WaveformIo.read();
        stations=data.stations;
        params=data.params;
        for(station in stations)picks.addAll(Picker.detect(station,params));
        picks.sortWith(compareBy<Picker.Pick> {
            it.sample
        }.thenBy {
            it.station.order
        });
        candidates=Associator.associate(picks,params.integer("association_window"),params.integer("min_stations"));
        locate();
        relocate();
        magnitudes();
        cluster();
        reassociate();
        write("picks.csv",picksReport());
        write("locations.txt",locationReport());
        write("catalog.csv",catalog());
        write("magnitudes.txt",magnitudeReport());
        write("stations.txt",stationReport());
        write("map.txt",mapReport())
    }
}
