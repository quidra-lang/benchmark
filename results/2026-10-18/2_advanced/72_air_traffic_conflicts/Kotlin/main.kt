import kotlin.math.*
object AirTraffic {
    const val PI=3.141592653589793
    lateinit var settings: FlightPlans.Settings;
    lateinit var types: Map<String,FlightPlans.AircraftType>;
    lateinit var sectors: List<FlightPlans.Sector>;
    lateinit var initial: Map<String,FlightPlans.Plan>;
    val finalPlans=sortedMapOf<String,FlightPlans.Plan>();
    val trajectoriesInitial=sortedMapOf<String,Trajectory.Built>();
    val trajectoriesFinal=sortedMapOf<String,Trajectory.Built>();
    lateinit var initialConflicts: List<Conflict.Event>;
    lateinit var finalConflicts: List<Conflict.Event>;
    val unresolved=mutableSetOf<Conflict.AircraftPair>();
    val resolved=mutableSetOf<Conflict.AircraftPair>();
    val unresolvedConflicts=mutableListOf<Conflict.Event>();
    val rounds=mutableListOf<Round>();
    lateinit var samples: List<Int>
    class Trial(val aircraft: String,val name: String) {
        var status="";
        var blocker: Conflict.Event?=null
    }
    class Round(val number: Int,val target: Conflict.Event) {
        val trials=mutableListOf<Trial>();
        var accepted: Trial?=null
    }
    data class Involvement(val conflict: Conflict.Event,val partner: String)
    data class Interval(val lo: Double,val hi: Double)
    class Transit(val callsign: String,val sector: Int,val entry: Double,var exit: Double) {
        var previous="-";
        var next="-";
        var previousIndex=-1;
        var nextIndex=-1
    }
    data class Period(val sector: Int,val number: Int,val start: Int,val end: Int,val entriesInitial: Int,
        val entriesFinal: Int,val peakInitial: Int,val peakFinal: Int,val meanFinal: Double,val status: String)
    class Usage {
        val flights=mutableSetOf<String>();
        var time=0.0
    }
    data class Observation(val time: Int,val loss: Double,val distance: Double)
    class Alert(val pair: Conflict.AircraftPair,observation: Observation) {
        val first=observation.time;
        var last=observation.time;
        var count=1;
        val predicted=observation.loss;
        var minimum=observation.distance;
        var lead: Double?=null
    }
    data class Cell(val column: Int,val row: Int)
    data class RadarPosition(val position: Trajectory.Vec,val segment: Trajectory.Segment,val cell: Cell?)
    fun f(value: Double,digits: Int=3)=Report.decimal(value,digits)
    fun <K> add(counts: MutableMap<K,Int>,key: K) {
        counts[key]=counts.getOrDefault(key,0)+1
    }
    fun active(conflict: Conflict.Event,time: Double)=conflict.start<=time&&time<conflict.end
    fun activeConflicts(conflicts: List<Conflict.Event>,time: Double)=conflicts.filter {
        active(it,time)
    }
    fun involvement(conflicts: List<Conflict.Event>): Map<String,List<Involvement>> {
        val result=sortedMapOf<String,MutableList<Involvement>>();
        for(conflict in conflicts) {
            result.getOrPut(conflict.pair.first) {
                mutableListOf()
            }.add(Involvement(conflict,conflict.pair.second));
            result.getOrPut(conflict.pair.second) {
                mutableListOf()
            }.add(Involvement(conflict,conflict.pair.first))
        };
        return result
    }
    fun blocker(changed: String,trajectory: Trajectory.Built,partner: String,start: Double): Conflict.Event? {
        var first: Conflict.Event?=null;
        for(other in trajectoriesFinal.keys) {
            if(other==changed)continue;
            val pair=Conflict.AircraftPair.of(changed,other);
            if(pair in unresolved)continue;
            val a=if(pair.first==changed)trajectory else trajectoriesFinal.getValue(pair.first);
            val b=if(pair.second==changed)trajectory else trajectoriesFinal.getValue(pair.second);
            for(conflict in Conflict.pair(pair.first,a,pair.second,b,settings.dh.toDouble(),settings.dv.toDouble()))if(other==partner||conflict.start<start+settings.lookahead) {
                val old=first;
                if(old==null||Conflict.order.compare(conflict,old)<0)first=conflict
            }
        };
        return first
    }
    fun resolve() {
        for((code,plan) in initial) {
            val copy=plan.copy();
            finalPlans[code]=copy;
            trajectoriesFinal[code]=Trajectory.build(copy,types)
        };
        val manoeuvres=Resolution.manoeuvres(settings.maxDelay);
        while(true) {
            val target=Conflict.all(trajectoriesFinal,settings.dh.toDouble(),settings.dv.toDouble()).firstOrNull {
                it.pair !in unresolved
            }?:break;
            val round=Round(rounds.size+1,target);
            val priority=Resolution.priority(finalPlans.getValue(target.pair.first),finalPlans.getValue(target.pair.second));
            for(side in 0..1) {
                if(round.accepted!=null)break;
                val aircraft=priority[side];
                val partner=priority[1-side];
                for(manoeuvre in manoeuvres) {
                    val trial=Trial(aircraft,manoeuvre.name);
                    val proposal=Resolution.propose(finalPlans.getValue(aircraft),manoeuvre,types,settings);
                    if(proposal==null)trial.status="infeasible" else {
                        val trajectory=Trajectory.build(proposal,types);
                        val blocked=blocker(aircraft,trajectory,partner,target.start);
                        if(blocked!=null) {
                            trial.status="blocked";
                            trial.blocker=blocked
                        } else {
                            trial.status="accepted";
                            proposal.history.add(manoeuvre.name);
                            finalPlans[aircraft]=proposal;
                            trajectoriesFinal[aircraft]=trajectory;
                            round.accepted=trial
                        }
                    };
                    round.trials.add(trial);
                    if(round.accepted!=null)break
                }
            };
            if(round.accepted==null) {
                unresolved.add(target.pair);
                unresolvedConflicts.add(target)
            } else resolved.add(target.pair);
            rounds.add(round)
        }
    }
    fun track(segment: Trajectory.Segment): Double {
        val angle=atan2(segment.velocity.x,segment.velocity.y)*180/PI;
        return if(angle<0)angle+360 else angle
    }
    fun contains(sector: FlightPlans.Sector,p: Trajectory.Vec)=sector.x1/10.0<=p.x&&p.x<sector.x2/10.0&&sector.y1/10.0<=p.y&&p.y<sector.y2/10.0&&sector.lower*100.0<=p.z&&p.z<sector.upper*100.0
    fun classify(conflicts: List<Conflict.Event>,finalPairs: Set<Conflict.AircraftPair>,last: Boolean=false) {
        for(conflict in conflicts) {
            val piece=conflict.closest;
            val a=piece.a;
            val b=piece.b;
            val pa=Trajectory.position(a,piece.loss.tc);
            val pb=Trajectory.position(b,piece.loss.tc);
            conflict.levelA=pa.z/100;
            conflict.levelB=pb.z/100;
            conflict.trackA=track(a);
            conflict.trackB=track(b);
            val angle=abs(conflict.trackA-conflict.trackB);
            conflict.angle=if(angle>180)360-angle else angle;
            val dot=a.velocity.x*b.velocity.x+a.velocity.y*b.velocity.y;
            val cross=a.velocity.x*b.velocity.y-a.velocity.y*b.velocity.x;
            conflict.geometry=if(dot*dot>cross*cross) {
                if(dot<0)"head_on" else "trailing"
            } else "crossing";
            val distance=piece.loss.distance;
            conflict.severity=if(10*distance<4.0*settings.dh)"HIGH" else if(10*distance<7.0*settings.dh)"MEDIUM" else "LOW";
            val midpoint=Trajectory.Vec((pa.x+pb.x)/2,(pa.y+pb.y)/2,(pa.z+pb.z)/2);
            conflict.sector=sectors.firstOrNull {
                contains(it,midpoint)
            }
            ?.name?:"-";
            conflict.outcome=if(last||conflict.pair in finalPairs)"remaining" else if(conflict.pair in resolved)"resolved" else "indirect"
        }
    }
    fun trajectoriesCsv(): List<String> {
        val lines=mutableListOf("callsign,segment,leg,phase,t_start,t_end,x_start,y_start,fl_start,x_end,y_end,fl_end");
        for((code,trajectory) in trajectoriesFinal)for(segment in trajectory.segments) {
            val a=segment.start;
            val b=segment.end;
            lines.add("$code,${segment.number},${segment.leg},${segment.phase},${f(segment.ts)},${f(segment.te)},${f(a.x)},${f(a.y)},${(a.z/100).toInt()},${f(b.x)},${f(b.y)},${(b.z/100).toInt()}")
        };
        return lines
    }
    fun conflictLines(label: String,conflicts: List<Conflict.Event>,trajectories: Map<String,Trajectory.Built>): List<String> {
        val lines=mutableListOf("CONFLICTS plan=$label count=${conflicts.size}");
        val geometry=mutableMapOf<String,Int>();
        val severity=mutableMapOf<String,Int>();
        var duration=0.0;
        var minimum=Double.POSITIVE_INFINITY;
        for((i,conflict) in conflicts.withIndex()) {
            val piece=conflict.closest;
            val loss=piece.loss;
            lines.add("CONFLICT ${i+1} ${conflict.pair.name} start=${f(conflict.start)} end=${f(conflict.end)} duration=${f(conflict.end-conflict.start)} outcome=${conflict.outcome}");
            lines.add("  CPA t=${f(loss.tc)} dist=${f(loss.distance)} vert=${f(loss.vertical,1)} levels=${f(conflict.levelA,2)}/${f(conflict.levelB,2)} tracks=${f(conflict.trackA,1)}/${f(conflict.trackB,1)} angle=${f(conflict.angle,1)}");
            lines.add("  TYPE geometry=${conflict.geometry} phases=${piece.a.phase}/${piece.b.phase} segments=${piece.a.number}/${piece.b.number} sector=${conflict.sector} severity=${conflict.severity}");
            for(part in conflict.pieces)lines.add("  PIECE ${part.a.number}/${part.b.number} ${f(part.loss.lo)} ${f(part.loss.hi)}");
            add(geometry,conflict.geometry);
            add(severity,conflict.severity);
            duration+=conflict.end-conflict.start;
            minimum=min(minimum,loss.distance)
        };
        lines.add("SUMMARY count=${conflicts.size} total=${f(duration)} min_dist=${if(conflicts.isEmpty())"-" else f(minimum)} head_on=${geometry.getOrDefault("head_on",0)} crossing=${geometry.getOrDefault("crossing",0)} trailing=${geometry.getOrDefault("trailing",0)} high=${severity.getOrDefault("HIGH",0)} medium=${severity.getOrDefault("MEDIUM",0)} low=${severity.getOrDefault("LOW",0)}");
        val involved=involvement(conflicts);
        for((code,items) in involved)lines.add("FLIGHT $code conflicts=${items.size} first=${f(items.minOf{it.conflict.start})} partners=${items.map{it.partner}.toSortedSet().joinToString(",")}");
        lines.add("TIMELINE from=${settings.sampleStart} to=${settings.sampleEnd} step=60");
        for((code,items) in involved) {
            val timeline=samples.map {
                time->if(Trajectory.active(trajectories.getValue(code),time.toDouble())==null)'.' else if(items.any {
                    active(it.conflict,time.toDouble())
                })'X' else '-'
            }.joinToString("");
            lines.add("$code $timeline")
        };
        return lines
    }
    fun resolutionLines(): List<String> {
        val lines=mutableListOf<String>();
        var trialCount=0;
        var infeasible=0;
        var blocked=0;
        var accepted=0;
        var level=0;
        var speed=0;
        var delay=0;
        for(round in rounds) {
            val target=round.target;
            lines.add("ROUND ${round.number} ${target.pair.name} start=${f(target.start)} end=${f(target.end)} dist=${f(target.closest.loss.distance)}");
            for(trial in round.trials) {
                trialCount++;
                var line="  TRY ${trial.aircraft} ${trial.name} ${trial.status}";
                if(trial.status=="infeasible")infeasible++;
                if(trial.status=="blocked") {
                    blocked++;
                    val blocker=trial.blocker!!;
                    line+=" ${blocker.pair.name} start=${f(blocker.start)}"
                };
                lines.add(line)
            };
            val chosen=round.accepted;
            if(chosen==null)lines.add("  RESULT unresolved") else {
                accepted++;
                if(chosen.name.startsWith("level_"))level++ else if(chosen.name=="speed_down")speed++ else delay++;
                lines.add("  RESULT resolved ${chosen.aircraft} ${chosen.name}")
            }
        };
        val before=involvement(initialConflicts);
        val after=involvement(finalConflicts);
        var totalExtra=0.0;
        var totalDelay=0L;
        for((code,plan) in finalPlans) {
            val old=initial.getValue(code);
            val first=trajectoriesInitial.getValue(code);
            val last=trajectoriesFinal.getValue(code);
            val extra=last.arrival-first.arrival;
            totalExtra+=extra;
            totalDelay+=plan.delay;
            lines.add("FLIGHT $code departure=${plan.departure+plan.delay} delay=${plan.delay} level=${Report.signed(plan.offset)} speed=${old.speed}->${plan.speed} arrival=${f(first.arrival)}->${f(last.arrival)} extra=${f(extra)} length=${f(last.length)} conflicts=${before[code]?.size?:0}->${after[code]?.size?:0} manoeuvres=${plan.history.joinToString(",").ifEmpty{"-"}}")
        };
        for(conflict in unresolvedConflicts)lines.add("UNRESOLVED ${conflict.pair.name} start=${f(conflict.start)} dist=${f(conflict.closest.loss.distance)}");
        lines.add("TOTAL rounds=${rounds.size} resolved=$accepted unresolved=${unresolvedConflicts.size} level=$level speed=$speed delay=$delay total_delay=$totalDelay total_extra=${f(totalExtra)} trials=$trialCount infeasible=$infeasible blocked=$blocked");
        return lines
    }
    fun inside(segment: Trajectory.Segment,sector: FlightPlans.Sector): Interval? {
        val low=doubleArrayOf(sector.x1/10.0,sector.y1/10.0,sector.lower*100.0);
        val high=doubleArrayOf(sector.x2/10.0,sector.y2/10.0,sector.upper*100.0);
        var lo=segment.ts;
        var hi=segment.te;
        for(axis in 0..2) {
            val p=segment.start.component(axis);
            val v=segment.velocity.component(axis);
            if(v==0.0) {
                if(!(low[axis]<=p&&p<high[axis]))return null
            } else {
                val r1=(low[axis]-p)/v;
                val r2=(high[axis]-p)/v;
                lo=max(lo,segment.ts+min(r1,r2));
                hi=min(hi,segment.ts+max(r1,r2))
            }
        };
        return if(hi-lo>1e-6)Interval(lo,hi) else null
    }
    fun transits(trajectories: Map<String,Trajectory.Built>): List<Transit> {
        val all=mutableListOf<Transit>();
        for(code in trajectories.keys.sorted()) {
            val flight=mutableListOf<Transit>();
            for(sector in sectors) {
                val combined=mutableListOf<Interval>();
                for(segment in trajectories.getValue(code).segments) {
                    val interval=inside(segment,sector)?:continue;
                    if(combined.isNotEmpty()&&interval.lo-combined.last().hi<=1e-6)combined[combined.lastIndex]=Interval(combined.last().lo,
                        interval.hi) else combined.add(interval)
                };
                for(interval in combined)flight.add(Transit(code,sector.index,interval.lo,interval.hi))
            };
            flight.sortWith(compareBy<Transit> {
                it.entry
            }.thenBy {
                it.sector
            });
            for(i in 0 until flight.size-1) {
                val before=flight[i];
                val after=flight[i+1];
                if(abs(after.entry-before.exit)<=1e-6) {
                    before.next=sectors[after.sector].name;
                    before.nextIndex=after.sector;
                    after.previous=sectors[before.sector].name;
                    after.previousIndex=before.sector
                }
            };
            all.addAll(flight)
        };
        return all
    }
    fun transitLines(transits: List<Transit>)=listOf("callsign,sector,entry,exit,duration,from,to")+transits.map {
        "${it.callsign},${sectors[it.sector].name},${f(it.entry)},${f(it.exit)},${f(it.exit-it.entry)},${it.previous},${it.next}"
    }
    fun occupancy(trajectories: Map<String,Trajectory.Built>): Array<IntArray> {
        val values=Array(sectors.size) {
            IntArray(samples.size)
        };
        for((j,time) in samples.withIndex())for(code in trajectories.keys.sorted()) {
            val observed=Trajectory.current(trajectories.getValue(code),time.toDouble())?:continue;
            for(sector in sectors)if(contains(sector,observed.position))values[sector.index][j]++
        };
        return values
    }
    fun periods(before: Array<IntArray>,after: Array<IntArray>,first: List<Transit>,last: List<Transit>): List<Period> {
        val result=mutableListOf<Period>();
        for(sector in sectors)for(j in samples.indices step 5) {
            val start=samples[j];
            val end=start+300;
            var peakInitial=0;
            var peakFinal=0;
            var sum=0;
            for(k in j until j+5) {
                peakInitial=max(peakInitial,before[sector.index][k]);
                peakFinal=max(peakFinal,after[sector.index][k]);
                sum+=after[sector.index][k]
            };
            val entriesInitial=first.count {
                it.sector==sector.index&&start<=it.entry&&it.entry<end
            };
            val entriesFinal=last.count {
                it.sector==sector.index&&start<=it.entry&&it.entry<end
            };
            val status=if(peakFinal>sector.capacity)"OVER" else if(peakInitial>sector.capacity)"RELIEVED" else "OK";
            result.add(Period(sector.index,j/5+1,start,end,entriesInitial,entriesFinal,peakInitial,peakFinal,
                sum/5.0,status))
        };
        return result
    }
    fun sectorLoad(periods: List<Period>)=listOf("sector,period,start,end,entries_initial,entries_final,peak_initial,peak_final,mean_final,capacity,status")+periods.map {
        p->val sector=sectors[p.sector];
        "${sector.name},${p.number},${p.start},${p.end},${p.entriesInitial},${p.entriesFinal},${p.peakInitial},${p.peakFinal},${f(p.meanFinal,1)},${sector.capacity},${p.status}"
    }
    fun levelUsage(trajectories: Map<String,Trajectory.Built>): Map<Int,Usage> {
        val result=mutableMapOf<Int,Usage>();
        for(code in trajectories.keys.sorted())for(segment in trajectories.getValue(code).segments)if(segment.phase=="LVL") {
            val level=(segment.start.z/100).toInt();
            val usage=result.getOrPut(level) {
                Usage()
            };
            usage.flights.add(code);
            usage.time+=segment.te-segment.ts
        };
        return result
    }
    fun sectorSummary(label: String,index: Int,occupancy: Array<IntArray>,transits: List<Transit>,conflicts: List<Conflict.Event>): String {
        var entries=0;
        var dwell=0.0;
        for(transit in transits)if(transit.sector==index) {
            entries++;
            dwell+=transit.exit-transit.entry
        };
        var peak=0;
        var over=0;
        for(j in samples.indices step 5) {
            var periodPeak=0;
            for(k in j until j+5)periodPeak=max(periodPeak,occupancy[index][k]);
            peak=max(peak,periodPeak);
            if(periodPeak>sectors[index].capacity)over++
        };
        val count=conflicts.count {
            it.sector==sectors[index].name
        };
        return "$label entries=$entries time=${f(dwell)} mean=${if(entries==0)"-" else f(dwell/entries)} peak=$peak over=$over conflicts=$count"
    }
    fun sectorReport(before: Array<IntArray>,after: Array<IntArray>,first: List<Transit>,last: List<Transit>): List<String> {
        val lines=mutableListOf<String>();
        for(sector in sectors) {
            val index=sector.index;
            lines.add("SECTOR ${sector.name} x=${sector.x1}..${sector.x2} y=${sector.y1}..${sector.y2} fl=${sector.lower}..${sector.upper} capacity=${sector.capacity}");
            lines.add(sectorSummary("INITIAL",index,before,first,initialConflicts));
            lines.add(sectorSummary("FINAL",index,after,last,finalConflicts));
            val height=max(sector.capacity+1,after[index].max());
            val rows=(height downTo 1).map {
                level->after[index].map {
                    if(it>=level)'#' else if(level==sector.capacity)'-' else '.'
                }.joinToString("")
            };
            lines.addAll(Report.chart(rows))
        };
        val initialUsage=levelUsage(trajectoriesInitial);
        val finalUsage=levelUsage(trajectoriesFinal);
        lines.add("LEVELS");
        for(level in (initialUsage.keys+finalUsage.keys).sortedDescending()) {
            val old=initialUsage[level]?:Usage();
            val now=finalUsage[level]?:Usage();
            lines.add("LEVEL $level flights=${old.flights.size}->${now.flights.size} time=${f(old.time)}->${f(now.time)}")
        };
        val handoffs=Array(sectors.size) {
            IntArray(sectors.size)
        };
        var count=0;
        for(transit in last)if(transit.nextIndex>=0) {
            handoffs[transit.sector][transit.nextIndex]++;
            count++
        };
        lines.add("HANDOFFS plan=final count=$count");
        for(a in sectors.indices)for(b in sectors.indices)if(handoffs[a][b]>0)lines.add("HANDOFF ${sectors[a].name} ${sectors[b].name} ${handoffs[a][b]}");
        return lines
    }
    fun alertLines(label: String,trajectories: Map<String,Trajectory.Built>,conflicts: List<Conflict.Event>): List<String> {
        val observations=mutableMapOf<Conflict.AircraftPair,MutableList<Observation>>();
        for(time in samples) {
            val flying=sortedMapOf<String,Trajectory.Observed>();
            for(code in trajectories.keys) {
                val observed=Trajectory.current(trajectories.getValue(code),time.toDouble());
                if(observed!=null)flying[code]=observed
            };
            val names=flying.keys.toList();
            for(a in names.indices)for(b in a+1 until names.size) {
                val first=names[a];
                val second=names[b];
                val pa=flying.getValue(first);
                val pb=flying.getValue(second);
                val loss=Conflict.loss(pa.position-pb.position,pa.segment.velocity-pb.segment.velocity,
                    0.0,settings.alert.toDouble(),settings.dh.toDouble(),settings.dv.toDouble());
                if(loss!=null)observations.getOrPut(Conflict.AircraftPair(first,second)) {
                    mutableListOf()
                }.add(Observation(time,time+loss.lo,loss.distance))
            }
        };
        val alerts=mutableListOf<Alert>();
        for((pair,events) in observations) {
            var group: Alert?=null;
            for(observation in events) {
                val previous=group;
                if(previous==null||observation.time-previous.last!=60) {
                    val next=Alert(pair,observation);
                    group=next;
                    alerts.add(next)
                } else {
                    previous.last=observation.time;
                    previous.count++;
                    previous.minimum=min(previous.minimum,observation.distance)
                }
            }
        };
        alerts.sortWith(compareBy<Alert> {
            it.first
        }.thenBy {
            it.pair.first
        }.thenBy {
            it.pair.second
        });
        val detected=BooleanArray(conflicts.size);
        for(alert in alerts)for((i,conflict) in conflicts.withIndex())if(conflict.pair==alert.pair&&conflict.start<alert.last+settings.alert.toDouble()&&conflict.end>alert.first) {
            detected[i]=true;
            if(alert.lead==null)alert.lead=conflict.start-alert.first
        };
        val lines=mutableListOf("ALERTS plan=$label horizon=${settings.alert} count=${alerts.size}");
        var trueCount=0;
        var missed=0;
        var leadSum=0.0;
        for((i,alert) in alerts.withIndex()) {
            val lead=alert.lead;
            val status=if(lead==null)"status=false lead=-" else {
                trueCount++;
                leadSum+=lead;
                "status=true lead=${f(lead)}"
            };
            lines.add("ALERT ${i+1} ${alert.pair.name} first=${alert.first} last=${alert.last} samples=${alert.count} predicted=${f(alert.predicted)} min_dist=${f(alert.minimum)} $status")
        };
        for((i,conflict) in conflicts.withIndex())if(!detected[i]) {
            missed++;
            lines.add("MISSED ${conflict.pair.name} start=${f(conflict.start)} end=${f(conflict.end)}")
        };
        lines.add("SUMMARY alerts=${alerts.size} true=$trueCount false=${alerts.size-trueCount} missed=$missed mean_lead=${if(trueCount==0)"-" else f(leadSum/trueCount)}");
        return lines
    }
    fun cell(position: Trajectory.Vec): Cell? {
        val r=settings.radar;
        val column=floor((10*position.x-r[0])*r[4]/(r[2]-r[0]));
        val row=floor((10*position.y-r[1])*r[5]/(r[3]-r[1]));
        if(column<0||column>=r[4]||row<0||row>=r[5])return null;
        return Cell(column.toInt(),r[5]-1-row.toInt())
    }
    fun gridRows(grid: Array<CharArray>)=grid.map {
        it.concatToString()
    }
    fun radarSnapshot(label: String,trajectories: Map<String,Trajectory.Built>,conflicts: List<Conflict.Event>,
        time: Int): List<String> {
        val width=settings.radar[4];
        val height=settings.radar[5];
        val grid=Array(height) {
            CharArray(width) {
                '.'
            }
        };
        val positions=sortedMapOf<String,RadarPosition>();
        val placements=mutableMapOf<Cell,MutableList<String>>();
        for(code in trajectories.keys.sorted()) {
            val observed=Trajectory.current(trajectories.getValue(code),time.toDouble())?:continue;
            val cell=cell(observed.position);
            positions[code]=RadarPosition(observed.position,observed.segment,cell);
            if(cell!=null)placements.getOrPut(cell) {
                mutableListOf()
            }.add(code)
        };
        val active=activeConflicts(conflicts,time.toDouble());
        val conflicted=active.flatMap {
            listOf(it.pair.first,it.pair.second)
        }.toSet();
        for((cell,names) in placements) {
            val name=names.first();
            grid[cell.row][cell.column]=if(names.size>1)('0'.code+names.size).toChar() else if(name in conflicted)name[0].lowercaseChar() else name[0]
        };
        for(code in positions.keys) {
            val predicted=Trajectory.current(trajectories.getValue(code),time+settings.leader.toDouble())?:continue;
            val cell=cell(predicted.position);
            if(cell!=null&&grid[cell.row][cell.column]=='.')grid[cell.row][cell.column]='*'
        };
        val lines=mutableListOf("RADAR plan=$label t=$time aircraft=${positions.size} conflicts=${active.size}");
        lines.addAll(Report.chart(gridRows(grid)));
        for((code,value) in positions) {
            val p=value.position;
            val c=value.cell;
            val cellText=if(c==null)"outside" else "${c.column},${c.row}";
            lines.add("$code x=${f(p.x)} y=${f(p.y)} fl=${f(p.z/100,2)} track=${f(track(value.segment),1)} phase=${value.segment.phase} cell=$cellText")
        };
        for(conflict in active) {
            val a=positions.getValue(conflict.pair.first).position;
            val b=positions.getValue(conflict.pair.second).position;
            val dx=a.x-b.x;
            val dy=a.y-b.y;
            lines.add("CONFLICT ${conflict.pair.name} dist=${f(sqrt(dx*dx+dy*dy))} vert=${f(abs(a.z-b.z),1)}")
        };
        return lines
    }
    fun density(label: String,trajectories: Map<String,Trajectory.Built>): List<String> {
        val width=settings.radar[4];
        val height=settings.radar[5];
        val counts=Array(height) {
            IntArray(width)
        };
        for(time in samples)for(code in trajectories.keys.sorted()) {
            val observed=Trajectory.current(trajectories.getValue(code),time.toDouble())?:continue;
            val cell=cell(observed.position);
            if(cell!=null)counts[cell.row][cell.column]++
        };
        val maximum=counts.maxOf {
            it.max()
        };
        val rows=counts.map {
            row->row.map {
                if(it==0)'.' else if(it<10)('0'.code+it).toChar() else '#'
            }.joinToString("")
        };
        return listOf("DENSITY plan=$label from=${settings.sampleStart} to=${settings.sampleEnd} step=60 max=$maximum")+Report.chart(rows)
    }
    fun strips(transits: List<Transit>): List<String> {
        val lines=mutableListOf<String>();
        for(code in initial.keys) {
            val plan=finalPlans.getValue(code);
            val before=trajectoriesInitial.getValue(code);
            val after=trajectoriesFinal.getValue(code);
            lines.add("STRIP $code type=${plan.type} waypoints=${plan.waypoints.size} length=${f(after.length)} manoeuvres=${plan.history.joinToString(",").ifEmpty{"-"}}");
            for((k,point) in plan.waypoints.withIndex()) {
                val old=before.waypointTimes[k];
                val now=after.waypointTimes[k];
                lines.add("WPT $k at=${point.x}:${point.y} eta=${f(old.time)}->${f(now.time)} fl=${old.level}->${now.level}")
            };
            val sequence=transits.filter {
                it.callsign==code
            }.joinToString(",") {
                "${sectors[it.sector].name}@${f(it.entry)}"
            }.ifEmpty {
                "-"
            };
            lines.add("SECTORS $sequence")
        };
        return lines
    }
    fun run() {
        val input=FlightPlans.read();
        initial=input.plans;
        types=input.types;
        sectors=input.sectors;
        settings=input.settings;
        for((code,plan) in initial)trajectoriesInitial[code]=Trajectory.build(plan,types);
        initialConflicts=Conflict.all(trajectoriesInitial,settings.dh.toDouble(),settings.dv.toDouble());
        resolve();
        finalConflicts=Conflict.all(trajectoriesFinal,settings.dh.toDouble(),settings.dv.toDouble());
        val finalPairs=finalConflicts.map {
            it.pair
        }.toSet();
        classify(initialConflicts,finalPairs);
        classify(finalConflicts,finalPairs,true);
        samples=(settings.sampleStart until settings.sampleEnd step 60).toList();
        val first=transits(trajectoriesInitial);
        val last=transits(trajectoriesFinal);
        val before=occupancy(trajectoriesInitial);
        val after=occupancy(trajectoriesFinal);
        val periods=periods(before,after,first,last);
        Report.write("trajectories.csv",trajectoriesCsv());
        Report.write("conflicts.txt",conflictLines("initial",initialConflicts,trajectoriesInitial)+conflictLines("final",
            finalConflicts,trajectoriesFinal));
        Report.write("resolutions.txt",resolutionLines());
        Report.write("sector_transits.csv",transitLines(last));
        Report.write("sector_load.csv",sectorLoad(periods));
        Report.write("sector_report.txt",sectorReport(before,after,first,last));
        Report.write("alerts.txt",alertLines("initial",trajectoriesInitial,initialConflicts)+alertLines("final",
            trajectoriesFinal,finalConflicts));
        val radar=mutableListOf<String>();
        for(time in settings.snapshots) {
            radar.addAll(radarSnapshot("initial",trajectoriesInitial,initialConflicts,time));
            radar.addAll(radarSnapshot("final",trajectoriesFinal,finalConflicts,time))
        };
        radar.addAll(density("initial",trajectoriesInitial));
        radar.addAll(density("final",trajectoriesFinal));
        Report.write("radar.txt",radar);
        Report.write("strips.txt",strips(last))
    }
}
fun main()=AirTraffic.run()
