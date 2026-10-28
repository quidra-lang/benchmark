import java.io.File
import java.util.Locale
import kotlin.math.*

object Tracker {
    val filters=arrayOf("cv","ca","abg","imm","rts");
    val params=mutableMapOf<String,List<String>>();
    val measurements=mutableListOf<MutableList<DoubleArray>>();
    lateinit var times: DoubleArray;
    var scans=0;
    var primary=0;
    var conflictMeasurements=0;
    var conflictTracks=0;
    var greedyDifferences=0
    val targets=mutableListOf<Target>();
    val tracks=mutableListOf<Track>();
    val evaluated=mutableListOf<Track>();
    val rows=mutableListOf<String>();
    val log=mutableListOf<String>();
    lateinit var labels: Array<Array<IntArray>>;
    lateinit var ospa: Array<DoubleArray>;
    lateinit var sizes: Array<IntArray>;
    lateinit var continuity: Array<Array<Evaluation.Continuity>>;
    lateinit var matched: Array<Track?>;
    lateinit var results: Array<TargetResult?>;
    lateinit var overallPosition: DoubleArray;
    lateinit var overallVelocity: DoubleArray
    class Target(val number: Int) {
        var first=scans+1;
        var last=0;
        val positions=Array(scans+1) {
            DoubleArray(0)
        }
    }
    class Track(val number: Int,scan: Int,measurement: DoubleArray,val kalman: Kalman) {
        val birth=scan;
        var lastHit=scan;
        var confirmed=0;
        var deleted=0;
        var hits=1;
        var misses=0;
        var longest=0;
        var target=-1;
        var status="tentative";
        val observations=arrayOfNulls<DoubleArray>(scans+1);
        val nis=DoubleArray(scans+1);
        lateinit var high: DoubleArray;
        val primaryMatches=IntArray(scans+1);
        lateinit var estimates: Array<Array<DoubleArray>>;
        lateinit var primaryCovariances: Array<Array<DoubleArray>>;
        val modelLogs=DoubleArray(2);
        var path=0.0;
        var meanDistance=0.0;
        var commonFirst=0;
        var commonLast=0;
        init {
            observations[scan]=measurement
        }
    }
    data class TargetResult(val position: DoubleArray,val velocity: DoubleArray,val velocityCount: Int,val nees: DoubleArray)
    fun f(value: Double)=Evaluation.real(value)
    fun optional(value: Int)=if(value==0)"-" else value.toString()
    fun parameter(name: String)=real(name,0)
    fun real(name: String,i: Int)=params.getValue(name)[i].toDouble()
    fun integer(name: String,i: Int)=params.getValue(name)[i].toInt()
    fun values(name: String)=params.getValue(name).map {
        it.toDouble()
    }.toDoubleArray()
    fun lines(name: String)=File("input",name).readLines()
    fun read() {
        var input=lines("measurements.csv");
        scans=input.last().substringBefore(',').toInt();
        times=DoubleArray(scans+1);
        repeat(scans+1) {
            measurements.add(mutableListOf())
        }
        for(line in input.drop(1)) {
            val w=line.split(',');
            val k=w[0].toInt();
            times[k]=w[1].toDouble();
            measurements[k].add(doubleArrayOf(w[2].toDouble(),w[3].toDouble()))
        }
        input=lines("truth.csv");
        for(line in input.drop(1)) {
            val w=line.split(',');
            val number=w[0].toInt();
            val scan=w[1].toInt();
            if(targets.isEmpty()||targets.last().number!=number)targets.add(Target(number));
            val t=targets.last();
            t.first=minOf(t.first,scan);
            t.last=scan;
            t.positions[scan]=doubleArrayOf(w[2].toDouble(),w[3].toDouble())
        }
        for(line in lines("params.txt")) {
            val w=line.split(' ');
            params[w[0]]=w.drop(1)
        };
        primary=if(params.getValue("MODEL")[0]=="CV")0 else 1
    }
    fun makeKalman(model: String,measurement: DoubleArray)=Kalman(model,parameter("Q_"+model),
        parameter("SIGMA"),parameter("INIT_VELOCITY_VARIANCE"),parameter("INIT_ACCELERATION_VARIANCE"),
        measurement)
    fun listed(keyword: String,items: List<String>)=keyword+" "+if(items.isEmpty())"none" else items.joinToString(" ")
    fun pairs(keyword: String,pairs: List<Association.Pair>,live: List<Track>)=listed(keyword,pairs.map {
        "${live[it.row].number}:${it.column+1}"
    })
    fun trackAll() {
        rows.add("track,scan,x,y,vx,vy,status")
        for(scan in 1..scans) {
            val live=tracks.filter {
                it.status!="deleted"
            };
            val points=measurements[scan];
            if(scan>1)for(t in live)t.kalman.predict(times[scan]-times[scan-1]);
            val a=live.size;
            val b=points.size;
            val costs=Array(a) {
                DoubleArray(b)
            };
            val usable=Array(a) {
                BooleanArray(b)
            };
            val innovations=Array(a) {
                arrayOfNulls<Kalman.Innovation>(b)
            };
            val rowGates=IntArray(a);
            val columnGates=IntArray(b);
            val gated=mutableListOf<Association.Pair>();
            val gateLines=mutableListOf<String>()
            for(i in 0 until a)for(j in 0 until b) {
                val v=live[i].kalman.innovation(points[j]);
                if(v.distance<=parameter("GATE")) {
                    costs[i][j]=v.distance;
                    usable[i][j]=true;
                    innovations[i][j]=v;
                    rowGates[i]++;
                    columnGates[j]++;
                    gated.add(Association.Pair(i,j));
                    gateLines.add("${live[i].number}:${j+1}=${f(v.distance)}")
                }
            }
            val assigned=Association.optimal(costs,usable);
            gated.sortWith(compareBy<Association.Pair> {
                costs[it.row][it.column]
            }.thenBy {
                it.row
            }.thenBy {
                it.column
            });
            val greedy=mutableListOf<Association.Pair>();
            val usedRows=BooleanArray(a);
            val usedColumns=BooleanArray(b)
            for(p in gated)if(!usedRows[p.row]&&!usedColumns[p.column]) {
                greedy.add(p);
                usedRows[p.row]=true;
                usedColumns[p.column]=true
            };
            greedy.sortWith(Association.order);
            if(assigned!=greedy)greedyDifferences++
            val matches=IntArray(a) {
                -1
            };
            usedColumns.fill(false);
            for(p in assigned) {
                matches[p.row]=p.column;
                usedColumns[p.column]=true
            };
            val missed=mutableListOf<String>();
            val confirmed=mutableListOf<String>();
            val deleted=mutableListOf<String>();
            val created=mutableListOf<String>();
            val processed=live.toMutableList()
            for(i in 0 until a) {
                val t=live[i];
                val j=matches[i];
                if(j>=0) {
                    t.kalman.update(points[j],innovations[i][j]!!);
                    t.observations[scan]=points[j];
                    t.nis[scan]=costs[i][j];
                    t.lastHit=scan;
                    t.hits++;
                    t.misses=0
                } else {
                    t.misses++;
                    missed.add(t.number.toString())
                }
                if(t.status=="confirmed") {
                    if(t.misses>=integer("DELETE",0)) {
                        t.status="deleted";
                        t.deleted=scan;
                        deleted.add(t.number.toString())
                    }
                } else if(t.hits>=integer("CONFIRM",0)) {
                    t.status="confirmed";
                    t.confirmed=scan;
                    confirmed.add(t.number.toString())
                } else if(scan-t.birth+1>=integer("CONFIRM",1)) {
                    t.status="deleted";
                    t.deleted=scan;
                    deleted.add(t.number.toString())
                }
            }
            for(j in 0 until b)if(!usedColumns[j]) {
                val t=Track(tracks.size+1,scan,points[j],makeKalman(params.getValue("MODEL")[0],points[j]));
                tracks.add(t);
                processed.add(t);
                created.add("${t.number}:${j+1}")
            }
            val cm=columnGates.count {
                it>=2
            };
            val ct=rowGates.count {
                it>=2
            };
            conflictMeasurements+=cm;
            conflictTracks+=ct;
            val tentative=tracks.count {
                it.status=="tentative"
            };
            val confirmedCount=tracks.count {
                it.status=="confirmed"
            }
            log.add("scan $scan tracks $a measurements $b");
            log.add(listed("gate",gateLines));
            log.add(pairs("assign",assigned,live));
            log.add(pairs("greedy",greedy,live));
            log.add(listed("missed",missed));
            log.add(listed("new",created));
            log.add(listed("confirmed",confirmed));
            log.add(listed("deleted",deleted));
            log.add("status tentative $tentative confirmed $confirmedCount");
            log.add("conflicts measurements $cm tracks $ct")
            for(t in processed) {
                var row="${t.number},$scan";
                for(c in 0..3)row+=",${f(t.kalman.x[c])}";
                rows.add(row+","+t.status)
            }
        };
        evaluated.addAll(tracks.filter {
            it.confirmed!=0
        })
    }
    fun compareFilters() {
        for(t in evaluated) {
            t.estimates=Array(5) {
                Array(scans+1) {
                    DoubleArray(0)
                }
            };
            t.primaryCovariances=Array(scans+1) {
                emptyArray<DoubleArray>()
            };
            var primaryHistory=emptyList<Kalman.Snapshot>()
            for(filter in 0..1) {
                val k=makeKalman(filters[filter].uppercase(Locale.ROOT),t.observations[t.birth]!!);
                val history=mutableListOf<Kalman.Snapshot>();
                var likelihood=0.0;
                for(scan in t.birth..t.lastHit) {
                    if(scan>t.birth) {
                        k.predict(times[scan]-times[scan-1]);
                        val measurement=t.observations[scan];
                        if(measurement!=null)likelihood+=k.update(measurement).likelihood
                    };
                    t.estimates[filter][scan]=k.x.copyOf(4);
                    history.add(k.snapshot())
                };
                t.modelLogs[filter]=likelihood;
                if(filter==primary)primaryHistory=history
            }
            val smooth=Kalman.smooth(primaryHistory);
            for(scan in t.birth..t.lastHit) {
                val i=scan-t.birth;
                t.primaryCovariances[scan]=primaryHistory[i].p;
                t.estimates[4][scan]=smooth[i].copyOf(4)
            }
            val abg=DoubleArray(6);
            t.observations[t.birth]!!.copyInto(abg);
            val alpha=real("ABG",0);
            val beta=real("ABG",1);
            val gamma=real("ABG",2);
            val imm=Imm(values("IMM_Q"),values("IMM_TRANSITION"),values("IMM_INITIAL"),parameter("SIGMA"),
                parameter("INIT_VELOCITY_VARIANCE"),t.observations[t.birth]!!);
            t.high=DoubleArray(scans+1);
            var gap=0;
            var previous: DoubleArray?=null
            for(scan in t.birth..t.lastHit) {
                if(scan>t.birth) {
                    val interval=times[scan]-times[scan-1];
                    val measurement=t.observations[scan];
                    for(axis in 0..1) {
                        var p=abg[axis];
                        var v=abg[axis+2];
                        var w=abg[axis+4];
                        p=p+interval*v+interval*interval*w/2;
                        v=v+interval*w;
                        if(measurement!=null) {
                            val residual=measurement[axis]-p;
                            p=p+alpha*residual;
                            v=v+beta*residual/interval;
                            w=w+2*gamma*residual/(interval*interval)
                        };
                        abg[axis]=p;
                        abg[axis+2]=v;
                        abg[axis+4]=w
                    };
                    imm.step(interval,measurement)
                }
                t.estimates[2][scan]=abg.copyOf(4);
                t.estimates[3][scan]=imm.estimate();
                t.high[scan]=imm.probabilities[1];
                gap=if(t.observations[scan]==null)gap+1 else 0;
                t.longest=maxOf(t.longest,gap);
                val before=previous;
                if(before!=null)t.path+=Evaluation.distance(before,t.estimates[4][scan]);
                previous=t.estimates[4][scan]
            }
        }
    }
    fun evaluateScans() {
        labels=Array(5) {
            Array(targets.size) {
                IntArray(scans+1)
            }
        };
        ospa=Array(5) {
            DoubleArray(scans)
        };
        sizes=Array(scans) {
            IntArray(2)
        };
        val threshold=parameter("MATCH_DISTANCE");
        val cutoff=parameter("OSPA_CUTOFF")
        for(scan in 1..scans) {
            val active=evaluated.filter {
                it.birth<=scan&&scan<=it.lastHit
            };
            val present=targets.indices.filter {
                targets[it].positions[scan].isNotEmpty()
            };
            val truth=present.map {
                targets[it].positions[scan]
            };
            sizes[scan-1]=intArrayOf(truth.size,active.size)
            for(filter in 0..4) {
                val estimates=active.map {
                    it.estimates[filter][scan]
                };
                val costs=Array(active.size) {
                    DoubleArray(truth.size)
                };
                val usable=Array(active.size) {
                    BooleanArray(truth.size)
                };
                for(i in active.indices)for(j in truth.indices) {
                    costs[i][j]=Evaluation.distance(estimates[i],truth[j]);
                    usable[i][j]=costs[i][j]<=threshold
                };
                for(pair in Association.optimal(costs,usable)) {
                    val t=active[pair.row];
                    val b=present[pair.column];
                    labels[filter][b][scan]=t.number;
                    if(filter==primary)t.primaryMatches[scan]=targets[b].number
                };
                ospa[filter][scan-1]=Evaluation.ospa(estimates,truth,cutoff)
            }
        };
        continuity=Array(5) {
            f->Array(targets.size) {
                b->val t=targets[b];
                Evaluation.continuity(labels[f][b].copyOfRange(t.first,t.last+1))
            }
        }
    }
    fun matchTracks() {
        val a=evaluated.size;
        val b=targets.size;
        val costs=Array(a) {
            DoubleArray(b)
        };
        val usable=Array(a) {
            BooleanArray(b)
        };
        val cutoff=parameter("OSPA_CUTOFF")
        for(i in 0 until a) {
            val t=evaluated[i];
            for(j in 0 until b) {
                val target=targets[j];
                val first=maxOf(t.birth,target.first);
                val last=minOf(t.lastHit,target.last);
                if(first>last)continue;
                var total=0.0;
                var accepted=false;
                var count=0
                for(scan in minOf(t.birth,target.first)..maxOf(t.lastHit,target.last)) {
                    val inTrack=t.birth<=scan&&scan<=t.lastHit;
                    val inTarget=target.first<=scan&&scan<=target.last;
                    if(!inTrack&&!inTarget)continue;
                    count++;
                    if(inTrack&&inTarget) {
                        val d=Evaluation.distance(t.estimates[primary][scan],target.positions[scan]);
                        total+=minOf(cutoff,d);
                        if(d<cutoff)accepted=true
                    } else total+=cutoff
                };
                costs[i][j]=total/count;
                usable[i][j]=accepted
            }
        }
        matched=arrayOfNulls(b);
        for(pair in Association.optimal(costs,usable)) {
            val t=evaluated[pair.row];
            val j=pair.column;
            val target=targets[j];
            t.target=j;
            t.meanDistance=costs[pair.row][j];
            t.commonFirst=maxOf(t.birth,target.first);
            t.commonLast=minOf(t.lastHit,target.last);
            matched[j]=t
        }
    }
    fun evaluateErrors() {
        results=arrayOfNulls(targets.size);
        val totalsP=DoubleArray(5);
        val totalsV=DoubleArray(5);
        var countP=0;
        var countV=0
        for(b in targets.indices) {
            val t=matched[b]?:continue;
            val target=targets[b];
            val position=DoubleArray(5);
            val velocity=DoubleArray(5);
            val nees=DoubleArray(t.commonLast-t.commonFirst+1);
            var velocityCount=0
            for(scan in t.commonFirst..t.commonLast) {
                var trueVelocity: DoubleArray?=null;
                if(scan>target.first&&scan<target.last) {
                    val interval=times[scan+1]-times[scan-1];
                    trueVelocity=doubleArrayOf((target.positions[scan+1][0]-target.positions[scan-1][0])/interval,
                        (target.positions[scan+1][1]-target.positions[scan-1][1])/interval);
                    velocityCount++
                }
                for(filter in 0..4) {
                    val estimate=t.estimates[filter][scan];
                    val pe=Evaluation.squared(estimate,target.positions[scan]);
                    position[filter]+=pe;
                    totalsP[filter]+=pe;
                    if(trueVelocity!=null) {
                        val v=doubleArrayOf(estimate[2],estimate[3]);
                        val ve=Evaluation.squared(v,trueVelocity);
                        velocity[filter]+=ve;
                        totalsV[filter]+=ve
                    }
                }
                val error=doubleArrayOf(t.estimates[primary][scan][0]-target.positions[scan][0],t.estimates[primary][scan][1]-target.positions[scan][1]);
                val p=t.primaryCovariances[scan];
                val p2=arrayOf(doubleArrayOf(p[0][0],p[0][1]),doubleArrayOf(p[1][0],p[1][1]));
                nees[scan-t.commonFirst]=Matrix.quadratic2(error,Matrix.inverse(p2))
            }
            val n=t.commonLast-t.commonFirst+1;
            for(filter in 0..4) {
                position[filter]=sqrt(position[filter]/n);
                velocity[filter]=sqrt(velocity[filter]/velocityCount)
            };
            countP+=n;
            countV+=velocityCount;
            results[b]=TargetResult(position,velocity,velocityCount,nees)
        }
        overallPosition=DoubleArray(5) {
            sqrt(totalsP[it]/countP)
        };
        overallVelocity=DoubleArray(5) {
            sqrt(totalsV[it]/countV)
        }
    }
    fun scores(values: DoubleArray): String {
        var best=0;
        var text="";
        for(k in 0..4) {
            if(k>0)text+=" ";
            text+=filters[k]+" "+f(values[k]);
            if(f(values[k]).toDouble()<f(values[best]).toDouble())best=k
        };
        return text+" best "+filters[best]
    }
    fun segments(labels: IntArray,first: Int,last: Int,includeLabel: Boolean): List<String> {
        val result=mutableListOf<String>();
        var scan=first;
        while(scan<=last) {
            if(labels[scan]==0) {
                scan++;
                continue
            };
            val start=scan;
            val label=labels[scan];
            while(scan+1<=last&&labels[scan+1]==label)scan++;
            result.add("$start-$scan"+if(includeLabel)":$label" else "");
            scan++
        };
        return result
    }
    fun section(lines: MutableList<String>,title: String) {
        if(lines.isNotEmpty())lines.add("");
        lines.add(title)
    }

    fun evaluationLines(): List<String> {
        val lines=mutableListOf<String>();
        section(lines,"summary");
        val totalMeasurements=measurements.sumOf {
            it.size
        };
        val falseTracks=evaluated.count {
            t->t.primaryMatches.all {
                it==0
            }
        };
        val used=evaluated.sumOf {
            it.hits
        };
        val lost=matched.count {
            it==null
        }
        lines.addAll(listOf("scans $scans","measurements $totalMeasurements","targets ${targets.size}",
            "tracks_created ${tracks.size}","tracks_confirmed ${evaluated.size}","false_tracks $falseTracks",
            "missed_targets $lost","measurements_used $used","conflict_measurements $conflictMeasurements",
            "conflict_tracks $conflictTracks","greedy_differences $greedyDifferences"))
        section(lines,"targets");
        for(target in targets) {
            var path=0.0;
            for(k in target.first+1..target.last)path+=Evaluation.distance(target.positions[k-1],target.positions[k]);
            lines.add("target ${target.number} first ${target.first} last ${target.last} scans ${target.last-target.first+1} path ${f(path)} mean_speed ${f(path/(times[target.last]-times[target.first]))}")
        }
        val bound=parameter("CONSISTENCY_BOUND");
        val allNis=mutableListOf<Double>();
        section(lines,"tracks");
        for(t in evaluated) {
            var sum=0.0;
            var count=0;
            var inside=0;
            for(k in t.birth+1..t.lastHit)if(t.observations[k]!=null) {
                val value=t.nis[k];
                sum+=value;
                count++;
                if(value<=bound)inside++;
                allNis.add(value)
            }
            lines.add("track ${t.number} birth ${t.birth} confirmed ${t.confirmed} end ${t.lastHit} deleted ${optional(t.deleted)} hits ${t.hits} misses ${t.lastHit-t.birth+1-t.hits} longest_gap ${t.longest} path ${f(t.path)} nis ${f(sum/count)} nis_inside $inside/$count")
        }
        section(lines,"matching");
        for(t in evaluated) {
            var line="track ${t.number} target "+if(t.target<0)"-" else targets[t.target].number.toString();
            if(t.target>=0)line+=" common ${t.commonLast-t.commonFirst+1} mean_distance ${f(t.meanDistance)}";
            val count=t.primaryMatches.count {
                it!=0
            };
            line+=" matched_scans $count "+listed("segments",segments(t.primaryMatches,t.birth,t.lastHit,true));
            lines.add(line)
        }
        section(lines,"rmse");
        for(b in targets.indices) {
            val target=targets[b];
            val t=matched[b];
            if(t==null) {
                lines.add("target ${target.number} track -");
                continue
            };
            val result=results[b]!!;
            lines.add("target ${target.number} track ${t.number} common ${t.commonLast-t.commonFirst+1} "+scores(result.position));
            lines.add("target ${target.number} velocity ${result.velocityCount} "+scores(result.velocity))
        };
        lines.add("overall position "+scores(overallPosition));
        lines.add("overall velocity "+scores(overallVelocity))
        section(lines,"consistency");
        for(b in targets.indices) {
            val target=targets[b];
            val t=matched[b];
            if(t==null) {
                lines.add("target ${target.number} track -");
                continue
            };
            val values=results[b]!!.nees;
            val inside=values.count {
                it<=bound
            };
            lines.add("target ${target.number} track ${t.number} nees ${f(Matrix.total(values)/values.size)} inside $inside/${values.size}")
        }
        val edges=values("NIS_EDGES");
        val observed=IntArray(edges.size+1);
        for(value in allNis) {
            var bin=0;
            while(bin<edges.size&&value>=edges[bin])bin++;
            observed[bin]++
        };
        var histogram="nis_histogram total ${allNis.size} observed";
        for(count in observed)histogram+=" $count";
        histogram+=" expected";
        var lower=0.0;
        for(k in 0..edges.size) {
            val upperProbability=if(k==edges.size)0.0 else exp(-edges[k]/2);
            histogram+=" "+f(allNis.size*(exp(-lower/2)-upperProbability));
            if(k<edges.size)lower=edges[k]
        };
        lines.add(histogram)
        section(lines,"models");
        for(t in evaluated)lines.add("track ${t.number} updates ${t.hits-1} cv ${f(t.modelLogs[0])} ca ${f(t.modelLogs[1])} better "+if(t.modelLogs[0]>=t.modelLogs[1])"cv" else "ca")
        section(lines,"ospa cutoff ${f(parameter("OSPA_CUTOFF"))} order 2");
        lines.add("scan targets tracks cv ca abg imm rts");
        for(k in 0 until scans) {
            var line="${k+1} ${sizes[k][0]} ${sizes[k][1]}";
            for(filter in 0..4)line+=" "+f(ospa[filter][k]);
            lines.add(line)
        };
        var mean="mean";
        for(filter in 0..4)mean+=" "+f(Matrix.total(ospa[filter])/scans);
        lines.add(mean)
        section(lines,"continuity");
        for(filter in 0..4) {
            val covered=continuity[filter].sumOf {
                it.covered
            };
            val breaks=continuity[filter].sumOf {
                it.breaks
            };
            val swaps=continuity[filter].sumOf {
                it.swaps
            };
            lines.add("${filters[filter]} covered $covered breaks $breaks swaps $swaps");
            for(b in targets.indices) {
                val target=targets[b];
                val c=continuity[filter][b];
                lines.add("  target ${target.number} scans ${target.last-target.first+1} covered ${c.covered} breaks ${c.breaks} swaps ${c.swaps} delay "+if(c.delay<0)"-" else c.delay.toString())
            }
        }
        section(lines,"imm");
        for(t in evaluated) {
            var sum=0.0;
            var maximum=t.birth;
            var count=0;
            val high=IntArray(scans+1);
            for(scan in t.birth..t.lastHit) {
                sum+=t.high[scan];
                if(t.high[scan]>t.high[maximum])maximum=scan;
                if(t.high[scan]>0.5) {
                    high[scan]=1;
                    count++
                }
            };
            lines.add("track ${t.number} mean_high ${f(sum/(t.lastHit-t.birth+1))} max_high ${f(t.high[maximum])} at $maximum high_scans $count "+listed("segments",
                segments(high,t.birth,t.lastHit,false)))
        };
        return lines
    }
    fun cell(point: DoubleArray): IntArray? {
        val xmin=real("PLOT_X",0);
        val xmax=real("PLOT_X",1);
        val ymin=real("PLOT_Y",0);
        val ymax=real("PLOT_Y",1);
        val width=integer("PLOT_SIZE",0);
        val height=integer("PLOT_SIZE",1);
        val dx=(xmax-xmin)/width;
        val dy=(ymax-ymin)/height;
        val c=floor((point[0]-xmin)/dx).toInt();
        val r=floor((ymax-point[1])/dy).toInt();
        return if(c>=0&&c<width&&r>=0&&r<height)intArrayOf(r,c) else null
    }
    fun grid(height: Int,width: Int)=Array(height) {
        CharArray(width) {
            ' '
        }
    }
    fun framed(rows: Array<CharArray>): List<String> {
        val lines=mutableListOf<String>();
        val border="+"+"-".repeat(rows[0].size)+"+";
        lines.add(border);
        for(row in rows)lines.add("|"+row.concatToString()+"|");
        lines.add(border);
        return lines
    }
    fun plotLines(): List<String> {
        val width=integer("PLOT_SIZE",0);
        val height=integer("PLOT_SIZE",1);
        val characters=CharArray(tracks.size+1);
        for(i in evaluated.indices)characters[evaluated[i].number]=if(i<26)('A'.code+i).toChar() else ('a'.code+i-26).toChar();
        val trajectory=grid(height,width)
        for(target in targets)for(k in target.first..target.last) {
            val c=cell(target.positions[k]);
            if(c!=null)trajectory[c[0]][c[1]]='.'
        };
        for(t in evaluated)for(k in t.birth..t.lastHit) {
            val c=cell(t.estimates[4][k]);
            if(c!=null)trajectory[c[0]][c[1]]=characters[t.number]
        }
        val lines=mutableListOf<String>();
        lines.add("tracks x ${f(real("PLOT_X",0))} ${f(real("PLOT_X",1))} y ${f(real("PLOT_Y",0))} ${f(real("PLOT_Y",1))} size $width $height");
        lines.addAll(framed(trajectory));
        for(t in evaluated)lines.add("${characters[t.number]} track ${t.number} target "+if(t.target<0)"-" else targets[t.target].number.toString())
        val counts=Array(height) {
            IntArray(width)
        };
        for(k in 1..scans)for(measurement in measurements[k]) {
            val c=cell(measurement);
            if(c!=null)counts[c[0]][c[1]]++
        };
        val density=grid(height,width);
        for(r in 0 until height)for(c in 0 until width) {
            val n=counts[r][c];
            density[r][c]=if(n==0)' ' else if(n<10)('0'.code+n).toChar() else '#'
        };
        lines.add("");
        lines.add("measurements");
        lines.addAll(framed(density));
        lines.add("");
        lines.add("timeline")
        for(b in targets.indices) {
            val target=targets[b];
            val timeline=StringBuilder();
            for(k in 1..scans)timeline.append(if(target.positions[k].isEmpty())' ' else if(labels[primary][b][k]==0)'.' else characters[labels[primary][b][k]]);
            lines.add("${target.number} |$timeline|")
        }
        lines.add("");
        lines.add("ospa "+filters[primary]);
        val bars=grid(10,scans);
        for(k in 0 until scans) {
            val h=floor(10*ospa[primary][k]/parameter("OSPA_CUTOFF")).toInt();
            for(r in 0 until 10)if(h>=10-r)bars[r][k]='#'
        };
        lines.addAll(framed(bars));
        return lines
    }
    fun write(name: String,lines: List<String>) {
        File("output",name).writeText(lines.joinToString("\n")+"\n")
    }
    fun run() {
        read();
        trackAll();
        compareFilters();
        evaluateScans();
        matchTracks();
        evaluateErrors();
        File("output").mkdirs();
        val smoothed=mutableListOf("track,scan,x,y,vx,vy");
        for(t in evaluated)for(k in t.birth..t.lastHit) {
            var line="${t.number},$k";
            for(value in t.estimates[4][k])line+=","+f(value);
            smoothed.add(line)
        };
        write("tracks.csv",rows);
        write("smoothed.csv",smoothed);
        write("association_log.txt",log);
        write("evaluation.txt",evaluationLines());
        write("track_plot.txt",plotLines())
    }
}
fun main()=Tracker.run()
