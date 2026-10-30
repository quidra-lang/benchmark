import java.util.ArrayDeque
import java.util.TreeSet
object ProcessMining {
    lateinit var input: Eventlog.Input;
    lateinit var reference: Conformance.Net
    val events=mutableListOf<Eventlog.Event>();
    lateinit var cases: List<Eventlog.Case>;
    lateinit var activities: List<String>;
    lateinit var resources: List<String>;
    val errors=mutableListOf<String>();
    val log=mutableListOf<Dfg.Trace>();
    val filtered=mutableListOf<Dfg.Trace>();
    lateinit var counts: MutableMap<Dfg.Pair,Long>;
    val variants=mutableListOf<Variant>();
    val variantIds=mutableMapOf<String,Int>();
    var keptCases=0;
    var keptEvents=0;
    val nets=mutableListOf<Conformance.Net>();
    val netNames=listOf("reference","alpha","alpha_plus");
    val referenceReplays=mutableMapOf<String,Conformance.Totals>()
    data class Identity(val id: String,val activity: String,val timestamp: String)
    class Variant(val trace: List<String>,val cases: List<Eventlog.Case>) {
        var number=0;
        var keep=true
    }
    class Discovery(val activities: List<String>,val relation: Array<Array<String>>) {
        lateinit var net: Conformance.Net;
        lateinit var starts: List<String>;
        lateinit var ends: List<String>;
        val maximal=mutableListOf<AlphaMiner.Candidate>();
        var candidates=0;
        var causal=0
    }
    data class Edge(val from: Int,val transition: Int,val to: Int)
    class Reach {
        var markings=0;
        var edges=0;
        var unsafe=0;
        var deadlocks=0;
        var stuck=0;
        var terminal=false;
        var sound=false;
        val dead=mutableListOf<String>();
        val follows=mutableMapOf<Dfg.Pair,Long>()
    }
    class Prefix {
        var weight=0L;
        val followers=TreeSet<String>()
    }
    fun parameter(name: String)=input.parameters.getValue(name).toLong()
    fun threshold(name: String)=Report.parse(input.parameters.getValue(name))
    fun fraction(n: Number,d: Number)=Report.fraction(n,d)
    fun fraction(value: Report.Fraction)=Report.fraction(value)
    fun names(values: Collection<String>)=Report.names(values)
    fun yes(value: Boolean)=if(value)"yes" else "no"
    fun <K> add(map: MutableMap<K,Long>,key: K,value: Long=1L) {
        map[key]=map.getOrDefault(key,0L)+value
    }
    fun <K> get(map: Map<K,Long>,key: K)=map.getOrDefault(key,0L)
    fun compareTrace(a: List<String>,b: List<String>): Int {
        for(i in 0 until minOf(a.size,b.size)) {
            val order=a[i].compareTo(b[i]);
            if(order!=0)return order
        };
        return a.size.compareTo(b.size)
    }
    fun pairOrder(values: Map<Dfg.Pair,Long>,frequency: Boolean=false)=values.keys.sortedWith(Comparator {
        a,b->val c=if(frequency)values.getValue(b).compareTo(values.getValue(a)) else 0;
        if(c!=0)c else Dfg.compare(a,b)
    })
    fun nameOrder(values: Map<String,Long>)=values.keys.sortedWith(compareByDescending<String> {
        values.getValue(it)
    }.thenBy {
        it
    })
    fun <K> waitValue(values: MutableMap<K,MutableList<Int>>,key: K,value: Int) {
        values.getOrPut(key) {
            mutableListOf()
        }.add(value)
    }
    fun mean(values: List<Int>)=if(values.isEmpty())"-" else fraction(values.sumOf {
        it.toLong()
    },values.size)
    fun prepare() {
        val adopted=mutableSetOf<Identity>();
        val allActivities=TreeSet<String>();
        val allResources=TreeSet<String>();
        for(row in input.rows) {
            val time=Eventlog.timestamp(row.timestamp);
            if(time<0) {
                errors.add("line ${row.line}: bad timestamp ${row.timestamp}");
                continue
            };
            if(!adopted.add(Identity(row.caseId,row.activity,row.timestamp))) {
                errors.add("line ${row.line}: duplicate event ${row.caseId} ${row.activity} ${row.timestamp}");
                continue
            };
            events.add(Eventlog.Event(row.line,row.caseId,row.activity,row.timestamp,row.resource,
                time));
            allActivities.add(row.activity);
            allResources.add(row.resource)
        };
        activities=allActivities.toList();
        resources=allResources.toList();
        cases=Eventlog.group(events);
        for(c in cases)log.add(Dfg.Trace(c.trace,1));
        counts=Dfg.counts(log);
        for((trace,group) in cases.groupBy {
            it.trace
        })variants.add(Variant(trace,group));
        variants.sortWith(Comparator {
            a,b->val c=b.cases.size.compareTo(a.cases.size);
            if(c!=0)c else compareTrace(a.trace,b.trace)
        });
        for((i,v) in variants.withIndex()) {
            v.number=i+1;
            v.keep=(1 until v.trace.size).all {
                Dfg.count(counts,v.trace[it-1],v.trace[it])>=parameter("filter_min_follows")
            };
            for(c in v.cases)variantIds[c.id]=v.number;
            if(v.keep) {
                filtered.add(Dfg.Trace(v.trace,v.cases.size.toLong()));
                keptCases+=v.cases.size;
                keptEvents+=v.trace.size*v.cases.size
            }
        }
    }
    fun logSummary(): List<String> {
        val lines=errors.map {
            "ERROR $it"
        }.toMutableList();
        val earliest=events.minBy {
            it.time
        };
        val latest=events.maxBy {
            it.time
        };
        lines.add("LOG rows ${input.rows.size} adopted ${events.size} rejected ${errors.size} cases ${cases.size} activities ${activities.size} resources ${resources.size} first ${earliest.timestamp} last ${latest.timestamp}");
        val eventCount=mutableMapOf<String,Long>();
        val caseCount=mutableMapOf<String,Long>();
        val starts=mutableMapOf<String,Long>();
        val ends=mutableMapOf<String,Long>();
        val rework=mutableMapOf<String,Long>();
        val waits=mutableMapOf<String,MutableList<Int>>();
        val workers=mutableMapOf<String,MutableSet<String>>();
        val weekdayEvents=LongArray(7);
        val weekdayStarts=LongArray(7);
        val weekdayEnds=LongArray(7);
        val lengths=mutableListOf<Int>();
        val durations=mutableListOf<Int>();
        for(c in cases) {
            lengths.add(c.events.size);
            durations.add(c.duration);
            for((name,n) in c.trace.groupingBy {
                it
            }.eachCount()) {
                add(caseCount,name);
                if(n>=2)add(rework,name)
            };
            add(starts,c.trace.first());
            add(ends,c.trace.last());
            weekdayStarts[(c.events.first().time/1440+3)%7]++;
            weekdayEnds[(c.events.last().time/1440+3)%7]++;
            for((i,e) in c.events.withIndex()) {
                add(eventCount,e.activity);
                workers.getOrPut(e.activity) {
                    mutableSetOf()
                }.add(e.resource);
                weekdayEvents[(e.time/1440+3)%7]++;
                if(i>0)waitValue(waits,e.activity,e.time-c.events[i-1].time)
            }
        };
        for(name in activities)lines.add("ACTIVITY $name events ${get(eventCount,name)} cases ${get(caseCount,name)} start ${get(starts,name)} end ${get(ends,name)} rework ${get(rework,name)} wait ${mean(waits[name]?:emptyList())} resources ${workers.getValue(name).size} model ${yes(reference.transitionIndex.containsKey(name))}");
        for((label,values) in listOf("LENGTH" to lengths,"DURATION" to durations))lines.add("$label min ${values.min()} max ${values.max()} mean ${mean(values)} median ${fraction(Eventlog.median(values))}");
        val days=IntArray(durations.max()/1440+1);
        var late=0;
        for(duration in durations) {
            days[duration/1440]++;
            if(duration>parameter("sla_minutes"))late++
        };
        for(d in days.indices)lines.add("DAYS $d cases ${days[d]} share ${Report.percentage(days[d],cases.size)}");
        lines.add("SLA limit ${parameter("sla_minutes")} late $late share ${Report.percentage(late,cases.size)}");
        for((i,day) in listOf("Mon","Tue","Wed","Thu","Fri","Sat","Sun").withIndex())lines.add("WEEKDAY $day events ${weekdayEvents[i]} starts ${weekdayStarts[i]} ends ${weekdayEnds[i]}");
        return lines
    }
    fun variantLines(): List<String> {
        val lines=mutableListOf<String>();
        for(v in variants) {
            val durations=v.cases.map {
                it.duration
            };
            val late=durations.count {
                it>parameter("sla_minutes")
            };
            lines.add("VARIANT ${v.number} count ${v.cases.size} share ${Report.percentage(v.cases.size,cases.size)} length ${v.trace.size} first ${v.cases.first().id} duration ${mean(durations)} late $late fitness ${fraction(referenceReplays.getValue(v.cases.first().id).fitness())} ${if(v.keep)"KEEP" else "DROP"} ${names(v.trace)}")
        };
        lines.add("FILTER min_follows ${parameter("filter_min_follows")} variants ${filtered.size} of ${variants.size} cases $keptCases of ${cases.size} events $keptEvents of ${events.size}");
        return lines
    }
    fun relation(names: List<String>,counts: Map<Dfg.Pair,Long>,triangles: Map<Dfg.Pair,Long>?=null)=Array(names.size) {
        i->Array(names.size) {
            j->if(triangles==null)Dfg.basic(counts,names[i],names[j]) else AlphaMiner.plus(counts,
                triangles,names[i],names[j])
        }
    }
    fun dfgLines(): List<String> {
        val starts=mutableMapOf<String,Long>();
        val endCount=mutableMapOf<String,Long>();
        val ends=mutableMapOf<String,MutableList<Int>>();
        val waiting=mutableMapOf<Dfg.Pair,MutableList<Int>>();
        val edgeCases=mutableMapOf<Dfg.Pair,Long>();
        for(c in cases) {
            add(starts,c.trace.first());
            add(endCount,c.trace.last());
            waitValue(ends,c.trace.last(),c.duration);
            val present=mutableSetOf<Dfg.Pair>();
            for(i in 1 until c.events.size) {
                val a=c.events[i-1];
                val b=c.events[i];
                val pair=Dfg.Pair(a.activity,b.activity);
                waitValue(waiting,pair,b.time-a.time);
                present.add(pair)
            };
            for(pair in present)add(edgeCases,pair)
        };
        val lines=mutableListOf<String>();
        for(name in nameOrder(starts))lines.add("START $name count ${get(starts,name)}");
        for(name in nameOrder(endCount))lines.add("END $name count ${get(endCount,name)} duration ${mean(ends.getValue(name))}");
        for(pair in pairOrder(counts,true)) {
            val values=waiting.getValue(pair);
            lines.add("EDGE ${pair.first} ${pair.second} count ${counts.getValue(pair)} cases ${get(edgeCases,pair)} mean ${mean(values)} min ${values.min()} max ${values.max()}")
        };
        lines.addAll(Dfg.footprint(activities,relation(activities,counts)));
        return lines
    }
    fun maskNames(mask: Int,names: List<String>)=names.filterIndexed {
        i,_->(mask and (1 shl i))!=0
    }
    fun discover(log: List<Dfg.Trace>,names: List<String>,relation: Array<Array<String>>): Discovery {
        val d=Discovery(names,relation);
        val candidates=mutableSetOf<AlphaMiner.Candidate>();
        val queue=ArrayDeque<AlphaMiner.Candidate>();
        for(a in names.indices)for(b in names.indices)if(relation[a][b]=="->") {
            d.causal++;
            if(relation[a][a]=="#"&&relation[b][b]=="#") {
                val pair=AlphaMiner.Candidate(1 shl a,1 shl b);
                if(candidates.add(pair))queue.add(pair)
            }
        };
        while(queue.isNotEmpty()) {
            val pair=queue.removeFirst();
            for(a in names.indices)for(side in 0..1) {
                val extended=AlphaMiner.extend(pair,a,side,relation);
                if(extended!=null&&candidates.add(extended))queue.add(extended)
            }
        };
        d.candidates=candidates.size;
        d.maximal.addAll(candidates.filter {
            pair->names.indices.all {
                a->(0..1).all {
                    side->AlphaMiner.extend(pair,a,side,relation)==null
                }
            }
        });
        d.maximal.sortWith(Comparator(AlphaMiner::compare));
        d.starts=log.map {
            it.activities.first()
        }.distinct().sorted();
        d.ends=log.map {
            it.activities.last()
        }.distinct().sorted();
        val places=listOf("start")+(1..d.maximal.size).map {
            "p$it"
        }+listOf("end");
        d.net=Conformance.Net(places,names,0,places.lastIndex);
        for(t in d.starts)d.net.arc("start",t);
        for(t in d.ends)d.net.arc(t,"end");
        for((i,pair) in d.maximal.withIndex()) {
            val place="p${i+1}";
            for(a in maskNames(pair.left,names))d.net.arc(a,place);
            for(b in maskNames(pair.right,names))d.net.arc(place,b)
        };
        return d
    }
    fun pairsLine(d: Discovery)="PAIRS causal ${d.causal} candidates ${d.candidates} maximal ${d.maximal.size}"
    fun netLines(d: Discovery): List<String> {
        val lines=mutableListOf("PLACE start - ${names(d.starts)}");
        for((i,pair) in d.maximal.withIndex())lines.add("PLACE p${i+1} ${names(maskNames(pair.left,d.activities))} ${names(maskNames(pair.right,d.activities))}");
        lines.add("PLACE end ${names(d.ends)} -");
        val net=d.net;
        for(t in net.transitions.indices)lines.add("TRANSITION ${net.transitions[t]} in ${names(net.inputs[t].map{net.places[it]})} out ${names(net.outputs[t].map{net.places[it]})}");
        lines.add("NET places ${net.places.size} transitions ${net.transitions.size} arcs ${net.arcs()}");
        return lines
    }
    fun workflows(): List<String> {
        val follows=Dfg.counts(filtered);
        val activityNames=filtered.flatMap {
            it.activities
        }.distinct().sorted();
        val loops=activityNames.filter {
            Dfg.count(follows,it,it)>0
        };
        val alpha=discover(filtered,activityNames,relation(activityNames,follows));
        val lines=mutableListOf("LOG variants ${filtered.size} cases $keptCases activities ${names(activityNames)}",
            "LOOPS ${names(loops)}","MINER alpha");
        lines.addAll(Dfg.footprint(activityNames,alpha.relation));
        lines.add(pairsLine(alpha));
        lines.addAll(netLines(alpha));
        val retained=activityNames.filter {
            it !in loops
        };
        val reduced=filtered.map {
            Dfg.Trace(it.activities.filter {
                a->a !in loops
            },it.weight)
        };
        val reducedCounts=Dfg.counts(reduced);
        val triangles=AlphaMiner.triangles(reduced);
        val plus=discover(reduced,retained,relation(retained,reducedCounts,triangles));
        lines.add("MINER alpha_plus");
        for(pair in pairOrder(triangles))lines.add("TRIANGLE ${pair.first} ${pair.second} count ${triangles.getValue(pair)}");
        lines.addAll(Dfg.footprint(retained,plus.relation));
        lines.add(pairsLine(plus));
        val expanded=Conformance.Net(plus.net.places,activityNames,plus.net.initial,plus.net.finish);
        for((t,transition) in plus.net.transitions.withIndex()) {
            for(place in plus.net.inputs[t])expanded.arc(plus.net.places[place],transition);
            for(place in plus.net.outputs[t])expanded.arc(transition,plus.net.places[place])
        };
        for(loop in loops) {
            var before=0;
            var after=0;
            for((i,a) in retained.withIndex()) {
                if(Dfg.count(follows,a,loop)>0)before=before or (1 shl i);
                if(Dfg.count(follows,loop,a)>0)after=after or (1 shl i)
            };
            var place="-";
            for((i,pair) in plus.maximal.withIndex())if(pair.left==before&&pair.right==after) {
                place="p${i+1}";
                expanded.arc(place,loop);
                expanded.arc(loop,place);
                break
            };
            lines.add("LOOP $loop before ${names(maskNames(before,retained))} after ${names(maskNames(after,retained))} place $place")
        };
        plus.net=expanded;
        lines.addAll(netLines(plus));
        nets.addAll(listOf(reference,alpha.net,plus.net));
        return lines
    }
    fun heuristic(): List<String> {
        val lines=mutableListOf<String>();
        val loops1=mutableSetOf<String>();
        val loops2=mutableSetOf<Dfg.Pair>();
        val edges=mutableSetOf<Dfg.Pair>();
        val triangles=AlphaMiner.triangles(log);
        val minimum=parameter("positive_observations");
        for(a in activities) {
            val count=Dfg.count(counts,a,a);
            if(count==0L)continue;
            val measure=HeuristicMiner.loop(count);
            val accepted=count>=minimum&&measure>=threshold("loop1_threshold");
            if(accepted) {
                loops1.add(a);
                edges.add(Dfg.Pair(a,a))
            };
            lines.add("L1 $a count $count measure ${fraction(measure)} ${if(accepted)"ACCEPT" else "REJECT"}")
        };
        for(i in activities.indices)for(j in i+1 until activities.size) {
            val a=activities[i];
            val b=activities[j];
            val count=Dfg.count(triangles,a,b)+Dfg.count(triangles,b,a);
            if(a in loops1||b in loops1||count==0L)continue;
            val measure=HeuristicMiner.loop(count);
            val accepted=count>=minimum&&measure>=threshold("loop2_threshold");
            if(accepted)loops2.add(Dfg.Pair(a,b));
            lines.add("L2 $a $b count $count measure ${fraction(measure)} ${if(accepted)"ACCEPT" else "REJECT"}")
        };
        val measures=mutableMapOf<Dfg.Pair,Report.Fraction>();
        val bestOut=mutableMapOf<String,Report.Fraction>();
        val bestIn=mutableMapOf<String,Report.Fraction>();
        for(pair in counts.keys)if(pair.first!=pair.second) {
            val measure=HeuristicMiner.dependency(counts,pair.first,pair.second);
            measures[pair]=measure;
            val out=bestOut[pair.first];
            val incoming=bestIn[pair.second];
            if(out==null||measure>out)bestOut[pair.first]=measure;
            if(incoming==null||measure>incoming)bestIn[pair.second]=measure
        };
        for(pair in measures.keys.sortedWith(Comparator(Dfg::compare))) {
            val a=pair.first;
            val b=pair.second;
            val measure=measures.getValue(pair);
            val canonical=if(a<b)pair else Dfg.Pair(b,a);
            val verdict=when {
                canonical in loops2->"LOOP2";
                counts.getValue(pair)<minimum->"REJECT_COUNT";
                measure<threshold("dependency_threshold")->"REJECT_MEASURE";
                bestOut.getValue(a).subtract(measure)>threshold("relative_to_best")&&bestIn.getValue(b).subtract(measure)>threshold("relative_to_best")->"REJECT_BEST";
                else->"ACCEPT"
            };
            if(verdict=="LOOP2"||verdict=="ACCEPT")edges.add(pair);
            lines.add("DEP $a $b count ${counts.getValue(pair)} reverse ${Dfg.count(counts,b,a)} measure ${fraction(measure)} $verdict")
        };
        val inputs=mutableMapOf<String,List<String>>();
        val outputs=mutableMapOf<String,List<String>>();
        for(a in activities) {
            val ins=activities.filter {
                Dfg.Pair(it,a) in edges
            };
            val outs=activities.filter {
                Dfg.Pair(a,it) in edges
            };
            inputs[a]=ins;
            outputs[a]=outs;
            lines.add("NODE $a in ${names(ins)} out ${names(outs)}")
        };
        for(a in activities)for(side in 0..1) {
            val neighbors=(if(side==0)outputs.getValue(a) else inputs.getValue(a)).filter {
                it!=a
            };
            for(i in neighbors.indices)for(j in i+1 until neighbors.size) {
                val b=neighbors[i];
                val c=neighbors[j];
                val measure=if(side==0)HeuristicMiner.split(counts,a,b,c) else HeuristicMiner.join(counts,
                    a,b,c);
                lines.add("${if(side==0)"SPLIT" else "JOIN"} $a $b $c measure ${fraction(measure)} ${if(measure>=threshold("and_threshold"))"AND" else "XOR"}")
            }
        };
        lines.add("GRAPH activities ${activities.size} edges ${edges.size} loops1 ${loops1.size} loops2 ${loops2.size}");
        return lines
    }
    fun explore(net: Conformance.Net): Reach {
        val result=Reach();
        val markings=mutableListOf(net.initialMarking());
        val reverse=mutableListOf(mutableListOf<Int>());
        val edges=mutableListOf<Edge>();
        val indices=mutableMapOf(markings[0].joinToString(",") to 0);
        val enabledEver=BooleanArray(net.transitions.size);
        var index=0;
        while(index<markings.size) {
            val marking=markings[index];
            var enabled=false;
            for(t in net.transitions.indices)if(Conformance.enabled(net,marking,t)) {
                enabled=true;
                enabledEver[t]=true;
                val after=Conformance.fire(net,marking,t);
                if(after.any {
                    it>1
                }) {
                    result.unsafe++;
                    continue
                };
                val key=after.joinToString(",");
                val destination=indices[key]?:markings.size.also {
                    indices[key]=it;
                    markings.add(after);
                    reverse.add(mutableListOf())
                };
                edges.add(Edge(index,t,destination));
                reverse[destination].add(index)
            };
            if(!enabled&&!marking.contentEquals(net.finalMarking()))result.deadlocks++;
            index++
        };
        val terminal=indices[net.finalMarking().joinToString(",")];
        result.terminal=terminal!=null;
        val reachable=BooleanArray(markings.size);
        val queue=ArrayDeque<Int>();
        if(terminal!=null) {
            reachable[terminal]=true;
            queue.add(terminal)
        };
        while(queue.isNotEmpty()) {
            val at=queue.removeFirst();
            for(before in reverse[at])if(!reachable[before]) {
                reachable[before]=true;
                queue.add(before)
            }
        };
        result.stuck=reachable.count {
            !it
        };
        for(t in enabledEver.indices)if(!enabledEver[t])result.dead.add(net.transitions[t]);
        for(edge in edges)for(t in net.transitions.indices)if(Conformance.enabled(net,markings[edge.to],
            t))result.follows[Dfg.Pair(net.transitions[edge.transition],net.transitions[t])]=1;
        result.markings=markings.size;
        result.edges=edges.size;
        result.sound=result.unsafe==0&&result.stuck==0&&result.dead.isEmpty();
        return result
    }
    fun reachLine(name: String,r: Reach)="REACHABILITY $name markings ${r.markings} edges ${r.edges} unsafe ${r.unsafe} deadlocks ${r.deadlocks} stuck ${r.stuck} final ${yes(r.terminal)} dead ${names(r.dead)} sound ${yes(r.sound)}"
    fun footprintLines(name: String,net: Conformance.Net,reach: Reach): List<String> {
        val activityNames=(activities+net.transitions).distinct().sorted();
        val differences=mutableListOf<String>();
        var differing=0;
        for(a in activityNames)for(b in activityNames) {
            val observed=Dfg.basic(counts,a,b);
            val model=Dfg.basic(reach.follows,a,b);
            if(observed!=model) {
                differing++;
                if(name=="reference"&&a<=b)differences.add("DIFF $a $b log $observed model $model")
            }
        };
        val cells=activityNames.size*activityNames.size;
        return listOf("FOOTPRINT $name activities ${activityNames.size} cells $cells differing $differing fitness ${fraction(cells-differing,cells)}")+differences
    }
    fun prefixes(): MutableMap<List<String>,Prefix> {
        val result=mutableMapOf<List<String>,Prefix>();
        for(c in cases)for(length in 0..c.trace.size) {
            val key=c.trace.take(length);
            val prefix=result.getOrPut(key) {
                Prefix()
            };
            prefix.weight++;
            if(length<c.trace.size)prefix.followers.add(c.trace[length])
        };
        return result
    }
    fun precision(name: String,net: Conformance.Net,prefixes: Map<List<String>,Prefix>): List<String> {
        var fitting=0L;
        var allowed=0L;
        var escaping=0L;
        val escapeWeights=mutableMapOf<String,Long>();
        val states=mutableMapOf<List<String>,IntArray?>();
        for(prefix in prefixes.keys.sortedWith(Comparator(::compareTrace))) {
            var marking: IntArray?=net.initialMarking();
            if(prefix.isNotEmpty()) {
                val before=states[prefix.dropLast(1)];
                val transition=net.transitionIndex[prefix.last()];
                marking=if(before!=null&&transition!=null&&Conformance.enabled(net,before,transition))Conformance.fire(net,
                    before,transition) else null
            };
            states[prefix]=marking;
            if(marking==null)continue;
            fitting++;
            val value=prefixes.getValue(prefix);
            for(t in net.transitions.indices)if(Conformance.enabled(net,marking,t)) {
                allowed+=value.weight;
                val transition=net.transitions[t];
                if(transition !in value.followers) {
                    escaping+=value.weight;
                    add(escapeWeights,transition,value.weight)
                }
            }
        };
        val lines=mutableListOf("PRECISION $name prefixes $fitting allowed $allowed escaping $escaping precision ${if(allowed==0L)fraction(1,1) else fraction(allowed-escaping,allowed)}");
        for(transition in nameOrder(escapeWeights))lines.add("ESCAPE $name $transition weight ${escapeWeights.getValue(transition)}");
        return lines
    }
    fun replayCase(net: Conformance.Net,c: Eventlog.Case): Conformance.Totals {
        val r=Conformance.Totals(net.places.size,net.transitions.size);
        val tokens=List(net.places.size) {
            ArrayDeque<Int>()
        };
        tokens[net.initial].add(c.events.first().time);
        r.produced=1;
        for(event in c.events) {
            val transition=net.transitionIndex[event.activity];
            if(transition==null) {
                r.skipped++;
                continue
            };
            for(place in net.inputs[transition]) {
                r.consumed++;
                if(tokens[place].isNotEmpty()) {
                    val produced=tokens[place].removeFirst();
                    val wait=event.time-produced;
                    r.waitingCount[place]++;
                    r.waitingSum[place]+=wait;
                    r.waitingMax[place]=maxOf(r.waitingMax[place],wait.toLong());
                    r.routes[place][transition]++
                } else {
                    r.missing++;
                    r.placeMissing[place]++
                }
            };
            for(place in net.outputs[transition]) {
                tokens[place].add(event.time);
                r.produced++
            }
        };
        r.consumed++;
        if(tokens[net.finish].isNotEmpty())tokens[net.finish].removeFirst() else {
            r.missing++;
            r.placeMissing[net.finish]++
        };
        for(place in net.places.indices) {
            val remaining=tokens[place].size.toLong();
            r.placeRemaining[place]=remaining;
            r.remaining+=remaining;
            r.deviating[place]=if(r.placeMissing[place]>0||remaining>0)1 else 0
        };
        return r
    }
    fun replayLines(name: String,net: Conformance.Net): List<String> {
        val total=Conformance.Totals(net.places.size,net.transitions.size);
        var fitting=0;
        for(c in cases) {
            val r=replayCase(net,c);
            if(name=="reference")referenceReplays[c.id]=r;
            if(r.missing==0L&&r.remaining==0L)fitting++;
            total.missing+=r.missing;
            total.remaining+=r.remaining;
            total.consumed+=r.consumed;
            total.produced+=r.produced;
            total.skipped+=r.skipped;
            for(p in net.places.indices) {
                total.placeMissing[p]+=r.placeMissing[p];
                total.placeRemaining[p]+=r.placeRemaining[p];
                total.deviating[p]+=r.deviating[p];
                total.waitingCount[p]+=r.waitingCount[p];
                total.waitingSum[p]+=r.waitingSum[p];
                total.waitingMax[p]=maxOf(total.waitingMax[p],r.waitingMax[p]);
                for(t in net.transitions.indices)total.routes[p][t]+=r.routes[p][t]
            }
        };
        val lines=mutableListOf("REPLAY $name cases ${cases.size} fitting $fitting skipped ${total.skipped} missing ${total.missing} remaining ${total.remaining} consumed ${total.consumed} produced ${total.produced} fitness ${fraction(total.fitness())}");
        for(p in net.places.indices)lines.add("PLACE $name ${net.places[p]} missing ${total.placeMissing[p]} remaining ${total.placeRemaining[p]} deviating ${total.deviating[p]} tokens ${total.waitingCount[p]} mean ${if(total.waitingCount[p]==0L)"-" else fraction(total.waitingSum[p],total.waitingCount[p])} max ${if(total.waitingCount[p]==0L)"-" else total.waitingMax[p].toString()}");
        for(p in net.places.indices) {
            val routes=net.transitions.indices.filter {
                p in net.inputs[it]
            }.map {
                "${net.transitions[it]}=${total.routes[p][it]}"
            };
            if(routes.size>=2)lines.add("ROUTE $name ${net.places[p]} ${routes.joinToString(",")}")
        };
        return lines
    }
    fun conformance(): List<String> {
        val lines=mutableListOf("MODEL places ${reference.places.size} transitions ${reference.transitions.size} arcs ${reference.arcs()}");
        val reaches=nets.mapIndexed {
            i,net->val reach=explore(net);
            lines.add(reachLine(netNames[i],reach));
            reach
        };
        for(i in nets.indices)lines.addAll(footprintLines(netNames[i],nets[i],reaches[i]));
        val prefixes=prefixes();
        for(i in nets.indices)lines.addAll(precision(netNames[i],nets[i],prefixes));
        for(i in nets.indices)lines.addAll(replayLines(netNames[i],nets[i]));
        return lines
    }
    fun csv(): List<String> {
        val lines=mutableListOf("case_id,variant,events,skipped,missing,remaining,consumed,produced,fitness");
        for(c in cases) {
            val r=referenceReplays.getValue(c.id);
            lines.add("${c.id},${variantIds.getValue(c.id)},${c.events.size},${r.skipped},${r.missing},${r.remaining},${r.consumed},${r.produced},${fraction(r.fitness())}")
        };
        return lines
    }
    fun resourceLines(): List<String> {
        val eventCount=mutableMapOf<String,Long>();
        val caseCount=mutableMapOf<String,Long>();
        val work=mutableMapOf<Dfg.Pair,Long>();
        val handovers=mutableMapOf<Dfg.Pair,Long>();
        val handoverCases=mutableMapOf<Dfg.Pair,Long>();
        val subcontracts=mutableMapOf<Dfg.Pair,Long>();
        val together=mutableMapOf<Dfg.Pair,Long>();
        for(c in cases) {
            val present=TreeSet<String>();
            val pairs=mutableSetOf<Dfg.Pair>();
            for((i,e) in c.events.withIndex()) {
                present.add(e.resource);
                add(eventCount,e.resource);
                add(work,Dfg.Pair(e.resource,e.activity));
                if(i>0) {
                    val pair=Dfg.Pair(c.events[i-1].resource,e.resource);
                    add(handovers,pair);
                    pairs.add(pair)
                };
                if(i>1) {
                    val a=c.events[i-2].resource;
                    val b=c.events[i-1].resource;
                    if(a==e.resource&&a!=b)add(subcontracts,Dfg.Pair(a,b))
                }
            };
            for(worker in present)add(caseCount,worker);
            for(pair in pairs)add(handoverCases,pair);
            val workers=present.toList();
            for(i in workers.indices)for(j in i+1 until workers.size)add(together,Dfg.Pair(workers[i],
                workers[j]))
        };
        val lines=mutableListOf<String>();
        for((i,resource) in resources.withIndex()) {
            val tasks=activities.filter {
                Dfg.count(work,resource,it)>0
            }.map {
                "$it=${Dfg.count(work,resource,it)}"
            };
            lines.add("RESOURCE ${i+1} $resource events ${get(eventCount,resource)} cases ${get(caseCount,resource)} work ${tasks.joinToString(",")}")
        };
        for(pair in pairOrder(handovers,true))if(pair.first!=pair.second)lines.add("HANDOVER ${pair.first} ${pair.second} count ${handovers.getValue(pair)} cases ${get(handoverCases,pair)}");
        lines.addAll(Dfg.table(resources.map {
            a->resources.map {
                b->Dfg.count(handovers,a,b).toString()
            }
        },5));
        for(pair in pairOrder(subcontracts,true))lines.add("SUBCONTRACT ${pair.first} ${pair.second} count ${subcontracts.getValue(pair)}");
        for(pair in pairOrder(together,true))lines.add("TOGETHER ${pair.first} ${pair.second} cases ${together.getValue(pair)}");
        val total=handovers.values.sum();
        val own=handovers.filterKeys {
            it.first==it.second
        }.values.sum();
        lines.add("TOTAL handovers $total self $own other ${total-own}");
        return lines
    }
    @JvmStatic fun main(args: Array<String>) {
        input=Eventlog.read();
        reference=Conformance.read();
        prepare();
        val workflow=workflows();
        val checks=conformance();
        Report.write("log_summary.txt",logSummary());
        Report.write("variants.txt",variantLines());
        Report.write("dfg.txt",dfgLines());
        Report.write("alpha_net.txt",workflow);
        Report.write("heuristic_net.txt",heuristic());
        Report.write("conformance.csv",csv());
        Report.write("conformance.txt",checks);
        Report.write("resources.txt",resourceLines())
    }
}
