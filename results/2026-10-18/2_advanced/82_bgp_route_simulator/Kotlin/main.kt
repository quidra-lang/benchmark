private const val HEADER="event,time,kind,status,convergence_time,updates,withdrawals,drops,best_changes,routes_changed,max_exploration"
private data class SessionKey(val owner:Int,val link:Int)
private data class OwnerPrefix(val owner:Int,val prefix:Topology.Prefix):Comparable<OwnerPrefix> {
    override fun compareTo(other:OwnerPrefix):Int {
        val c=owner.compareTo(other.owner);
        return if(c!=0)c else prefix.compareTo(other.prefix)
    }
}
private data class Imported(val route:Decision.Route?,val rule:Policy.Rule?)
private data class Advertised(val content:Decision.Attribute?,val rule:Policy.Rule?)
private data class BestLine(val time:Int,val owner:Int,val prefix:Topology.Prefix,val route:Decision.Route?)
private data class Divergence(val first:Int,val repeat:Int,val cycle:List<BestLine>)
private class Session(val owner:Int,val link:Topology.Link) {
    val incoming=sortedMapOf<Topology.Prefix,Decision.Attribute>();
    val outgoing=sortedMapOf<Topology.Prefix,Decision.Attribute>();
    var pending=sortedSetOf<Topology.Prefix>();
    var timer:Int?=null;
    var sent=0;
    var received=0
}
private class Router(val owner:Int,links:List<Topology.Link>) {
    val origination=sortedMapOf<Topology.Prefix,Decision.Route>();
    val rib=sortedMapOf<Topology.Prefix,Decision.Route>();
    val sessions=links.map {
        Session(owner,it)
    };
    var changes=0
}
private class Period(val number:Int,val event:Simulator.Event,routers:Map<Int,Router>) {
    val before=routers.mapValues {
        (_,router)->router.rib.toMap()
    };
    var updates=0;
    var withdrawals=0;
    var drops=0;
    var bestChanges=0;
    var routesChanged=0;
    var convergenceTime=0;
    var deliveryTimes=0;
    val exploration=sortedMapOf<OwnerPrefix,Int>();
    val bestLines=mutableListOf<BestLine>();
    val states=mutableMapOf<String,Int>();
    var divergence:Divergence?=null;
    var status=""
    fun finish(routers:Map<Int,Router>) {
        for(router in routers.values) {
            val old=before.getValue(router.owner);
            for(prefix in old.keys+router.rib.keys)if(old[prefix]!=router.rib[prefix])routesChanged++
        }
    }
    fun csv()=listOf(number,event.time,event.kind,status,convergenceTime,updates,withdrawals,drops,bestChanges,
        routesChanged,exploration.values.maxOrNull()?:0).joinToString(",")
}
private data class Hop(val owner:Int,val prefix:Topology.Prefix,val link:Topology.Link?)
private data class Forwarding(val result:String,val visits:List<Int>,val hops:List<Hop>) {
    val count get()=hops.count {
        it.link!=null
    };
    val arrival get()=hops.last().owner
}
private data class TraceStatus(val result:String,val visits:List<Int>)
private class TraceRecord(val index:Int,val start:Int,val status:TraceStatus) {
    var end:Int?=null
}
private data class RingKey(val prefix:Topology.Prefix,val path:List<Int>)
private class RingRecord(val prefix:Topology.Prefix,val path:List<Int>,val start:Int) {
    var end:Int?=null
}
private fun collapse(path:List<Int>):List<Int> {
    val result=mutableListOf<Int>();
    for(owner in path)if(result.lastOrNull()!=owner)result.add(owner);
    return result
}
private fun valleyPosition(pattern:String):Int {
    var p=0;
    while(p<pattern.length&&pattern[p]=='U')p++;
    if(p<pattern.length&&pattern[p]=='P')p++;
    while(p<pattern.length&&pattern[p]=='D')p++;
    return p
}
private fun messageText(message:Simulator.Message)="#${message.serial} ${message.sender}->${message.receiver} ${message.link.name} ${message.prefix}"
private class Simulation(val network:Topology,val policies:Policy,params:Simulator.Params) {
    val defaults=params.defaults;
    val stepcap=params.stepcap;
    val traces=params.traces;
    val routers=sortedMapOf<Int,Router>();
    val sessions=mutableListOf<Session>();
    val bySession=mutableMapOf<SessionKey,Session>();
    val messages=Simulator.MessageQueue();
    var time=0;
    val logs=mutableListOf<String>();
    val periods=mutableListOf<Period>();
    val changedPrefixes=sortedSetOf<Topology.Prefix>();
    val traceRecords=mutableListOf<TraceRecord>();
    val ongoingTraces=mutableMapOf<Int,TraceRecord>();
    val ringRecords=mutableListOf<RingRecord>();
    val ongoingRings=mutableMapOf<RingKey,RingRecord>();
    lateinit var period:Period
    init {
        for(owner in network.routerIds.keys) {
            val router=Router(owner,network.atAs.getValue(owner));
            routers[owner]=router;
            for(session in router.sessions) {
                sessions.add(session);
                bySession[SessionKey(owner,session.link.number)]=session
            }
        }
    }
    fun log(content:String) {
        logs.add("$time $content")
    }
    fun importRoute(session:Session,prefix:Topology.Prefix,attribute:Decision.Attribute):Imported {
        val rule=policies.applied("IMPORT",session.owner,session.link,prefix,attribute.path,attribute.communities);
        var localPref=defaults.getValue(session.link.role(session.owner));
        if(rule!=null&&rule.has("DENY"))return Imported(null,rule);
        var med=attribute.med;
        var communities=attribute.communities;
        if(rule!=null) {
            localPref=rule.value("LOCALPREF",localPref);
            med=rule.value("MED",med);
            communities=Policy.edit(communities,rule)
        }
        return Imported(Decision.Route(attribute.path,attribute.origin,med,communities,localPref,session.link),rule)
    }
    fun candidates(owner:Int,prefix:Topology.Prefix):MutableList<Decision.Route> {
        val routes=mutableListOf<Decision.Route>();
        for(session in routers.getValue(owner).sessions) {
            val attribute=session.incoming[prefix]?:continue;
            val route=importRoute(session,prefix,attribute).route;
            if(route!=null)routes.add(route)
        }
        return routes
    }
    fun advertised(session:Session,prefix:Topology.Prefix):Advertised {
        val owner=session.owner;
        val link=session.link;
        val route=routers.getValue(owner).rib[prefix]?:return Advertised(null,null);
        if(!route.local&&route.neighbor==link.other(owner)||Policy.NO_EXPORT in route.communities)return Advertised(null,
            null);
        val rule=policies.applied("EXPORT",owner,link,prefix,route.path,route.communities);
        if(rule!=null&&rule.has("DENY"))return Advertised(null,rule);
        val allowed=rule!=null&&rule.has("ALLOW");
        if(!allowed&&!route.local&&route.link!!.role(owner)!="customer"&&link.role(owner)!="customer")return Advertised(null,
            rule);
        val prepend=rule?.value("PREPEND",0)?:0;
        val med=rule?.value("MED",0)?:0;
        val communities=if(rule==null)route.communities else Policy.edit(route.communities,rule);
        val path=List(1+prepend) {
            owner
        }+route.path;
        return Advertised(Decision.Attribute(path,route.origin,med,communities),rule)
    }
    fun redecide(owner:Int,prefix:Topology.Prefix) {
        val router=routers.getValue(owner);
        val route=router.origination[prefix]?:candidates(owner,prefix).let {
            if(it.isEmpty())null else Decision.best(it,network.routerIds).route
        };
        if(router.rib[prefix]==route)return;
        if(route==null)router.rib.remove(prefix) else router.rib[prefix]=route;
        log("BEST $owner $prefix ${Report.route(route)}");
        router.changes++;
        period.bestChanges++;
        val key=OwnerPrefix(owner,prefix);
        period.exploration[key]=period.exploration.getOrDefault(key,0)+1;
        period.bestLines.add(BestLine(time,owner,prefix,route));
        changedPrefixes.add(prefix);
        for(session in router.sessions)if(session.link.up) {
            session.pending.add(prefix);
            if(session.timer==null)processPending(session)
        }
    }
    fun processPending(session:Session) {
        var sent=0;
        for(prefix in session.pending) {
            val advertised=advertised(session,prefix);
            val content=advertised.content;
            if(session.outgoing[prefix]==content)continue;
            if(content==null)session.outgoing.remove(prefix) else session.outgoing[prefix]=content;
            val message=messages.send(time,session.owner,session.link.other(session.owner),session.link,prefix,content);
            val suffix=if(content==null)"WITHDRAW" else "ANNOUNCE "+Report.attribute(content);
            log("SEND ${messageText(message)} $suffix");
            session.sent++;
            sent++;
            period.updates++;
            if(content==null)period.withdrawals++;
            advertised.rule?.let {
                it.hits++
            }
        }
        session.pending.clear();
        session.timer=if(sent>0&&session.link.mrai>=1)time+session.link.mrai else null
    }
    fun receive(message:Simulator.Message) {
        val session=bySession.getValue(SessionKey(message.receiver,message.link.number));
        val prefix=message.prefix;
        val content=message.content;
        session.received++;
        period.convergenceTime=time-period.event.time;
        val result=if(content==null) {
            session.incoming.remove(prefix);
            "WITHDRAW"
        }else if(message.receiver in content.path) {
            session.incoming.remove(prefix);
            "ANNOUNCE loop"
        }else {
            session.incoming[prefix]=content;
            val imported=importRoute(session,prefix,content);
            val rule=imported.rule;
            rule?.let {
                it.hits++
            };
            if(imported.route==null)"ANNOUNCE deny ${rule!!.name}" else if(rule==null)"ANNOUNCE accept" else "ANNOUNCE accept ${rule.name}"
        };
        log("RECV ${messageText(message)} $result");
        redecide(message.receiver,prefix)
    }
    fun originate(owner:Int,prefix:Topology.Prefix,origin:String,communities:List<Policy.Community>) {
        routers.getValue(owner).origination[prefix]=Decision.Route.originated(origin,communities);
        redecide(owner,prefix)
    }
    fun linkDown(link:Topology.Link) {
        link.up=false;
        link.downCount++;
        for(message in messages.removeLink(link)) {
            log("DROP "+messageText(message));
            period.drops++
        }
        val remembered=sortedMapOf<Int,List<Topology.Prefix>>();
        for(owner in listOf(link.first,link.second).sorted()) {
            val session=bySession.getValue(SessionKey(owner,link.number));
            remembered[owner]=session.incoming.keys.toList();
            session.incoming.clear();
            session.outgoing.clear();
            session.pending.clear();
            session.timer=null
        }
        for((owner,prefixes) in remembered)for(prefix in prefixes)redecide(owner,prefix)
    }
    fun linkUp(link:Topology.Link) {
        link.up=true;
        for(owner in listOf(link.first,link.second).sorted()) {
            val session=bySession.getValue(SessionKey(owner,link.number));
            session.pending=routers.getValue(owner).rib.keys.toSortedSet();
            processPending(session)
        }
    }
    fun changePolicy(rule:Policy.Rule,active:Boolean) {
        rule.active=active;
        val router=routers.getValue(rule.owner);
        if(rule.direction=="IMPORT") {
            val prefixes=sortedSetOf<Topology.Prefix>();
            for(session in router.sessions)prefixes.addAll(session.incoming.keys);
            for(prefix in prefixes)redecide(rule.owner,prefix)
        }else for(session in router.sessions)if(session.link.up) {
            session.pending.addAll(router.rib.keys);
            session.pending.addAll(session.outgoing.keys);
            if(session.timer==null)processPending(session)
        }
    }
    fun executeEvent(event:Simulator.Event) {
        log("EVENT ${period.number} ${event.text}");
        val f=event.fields;
        when(event.kind) {
            "INITIAL"->for(initial in network.initial)originate(initial.owner,initial.prefix,initial.origin,
                initial.communities);
            "ANNOUNCE"->originate(f[1].toInt(),Topology.prefix(f[2]),f[3],Policy.communities(f.drop(4)));
            "WITHDRAW"-> {
                val owner=f[1].toInt();
                val prefix=Topology.prefix(f[2]);
                routers.getValue(owner).origination.remove(prefix);
                redecide(owner,prefix)
            };
            "LINK_DOWN"->linkDown(network.byName.getValue(f[2]));
            "LINK_UP"->linkUp(network.byName.getValue(f[2]));
            else->changePolicy(policies.byName.getValue(f[2]),event.kind=="POLICY_ON")
        }
    }
    fun globalState():String {
        val state=StringBuilder();
        for(session in sessions) {
            state.append("I[");
            for((prefix,attribute) in session.incoming)state.append(prefix).append('=').append(Report.attribute(attribute)).append(';');
            state.append("]O[");
            for((prefix,attribute) in session.outgoing)state.append(prefix).append('=').append(Report.attribute(attribute)).append(';');
            state.append("]P[");
            for(prefix in session.pending)state.append(prefix).append(';');
            state.append("]T").append(session.timer?.let {
                it-time
            }?:"-").append('|')
        }
        state.append("Q[");
        for(message in messages.ordered())state.append(message.arrival-time).append(',').append(message.receiver).append(',').append(message.sender).append(',').append(message.link.number).append(',').append(message.prefix).append('=').append(message.content?.let {
            Report.attribute(it)
        }?:"WITHDRAW").append(';');
        return state.append(']').toString()
    }
    fun detectDivergence() {
        if(period.divergence!=null||period.deliveryTimes>stepcap)return;
        val state=globalState();
        val first=period.states[state];
        if(first==null)period.states[state]=time else period.divergence=Divergence(first,time,period.bestLines.filter {
            first<it.time&&it.time<=time
        })
    }
    fun quiet()=messages.nextTime()==null&&sessions.all {
        it.pending.isEmpty()
    }
    fun nextMoment(boundary:Int?):Int {
        var next=boundary?:Int.MAX_VALUE;
        messages.nextTime()?.let {
            next=minOf(next,it)
        };
        for(session in sessions)session.timer?.let {
            next=minOf(next,it)
        };
        return next
    }
    fun runPeriod(number:Int,event:Simulator.Event,boundary:Int?) {
        period=Period(number,event,routers);
        periods.add(period);
        time=event.time;
        changedPrefixes.clear();
        executeEvent(event);
        var quietNow:Boolean;
        while(true) {
            var delivered=false;
            while(messages.nextTime()==time) {
                receive(messages.take());
                delivered=true
            }
            for(session in sessions)if(session.timer==time) {
                session.timer=null;
                if(session.pending.isNotEmpty())processPending(session)
            }
            if(changedPrefixes.isNotEmpty())forwardingChecks();
            if(delivered) {
                period.deliveryTimes++;
                detectDivergence()
            }
            quietNow=quiet();
            if(boundary==null) {
                if(quietNow||period.divergence!=null||period.deliveryTimes>=stepcap)break
            }else if(time==boundary)break;
            time=nextMoment(boundary);
            changedPrefixes.clear()
        }
        period.status=if(period.divergence!=null)"DIVERGENT" else if(quietNow)"CONVERGED" else if(boundary==null)"CAPPED" else "UNSETTLED";
        period.finish(routers);
        period.states.clear()
    }
    fun run(events:List<Simulator.Event>) {
        for(i in events.indices)runPeriod(i,events[i],events.getOrNull(i+1)?.let {
            it.time-1
        })
    }
    fun forwardPath(source:Int,address:Long):Forwarding {
        val visits=mutableListOf(source);
        val visited=mutableSetOf(source);
        val hops=mutableListOf<Hop>();
        var owner=source;
        while(true) {
            val selected=routers.getValue(owner).rib.keys.filter {
                it.contains(address)
            }.maxByOrNull {
                it.length
            }?:return Forwarding(if(hops.isEmpty())"UNREACHABLE" else "BLACKHOLE",visits,hops);
            val route=routers.getValue(owner).rib.getValue(selected);
            hops.add(Hop(owner,selected,route.link));
            if(route.local)return Forwarding("DELIVERED",visits,hops);
            owner=route.link!!.other(owner);
            visits.add(owner);
            if(!visited.add(owner))return Forwarding("LOOP",visits,hops)
        }
    }
    fun prefixLoops(prefix:Topology.Prefix):Set<List<Int>> {
        val arrows=mutableMapOf<Int,Int>();
        for(router in routers.values) {
            val route=router.rib[prefix];
            if(route!=null&&!route.local)arrows[router.owner]=route.link!!.other(router.owner)
        }
        val finished=mutableSetOf<Int>();
        val loops=mutableSetOf<List<Int>>();
        for(start in network.routerIds.keys) {
            if(start in finished)continue;
            val path=mutableListOf<Int>();
            val positions=mutableMapOf<Int,Int>();
            var current=start;
            while(current in arrows&&current !in finished&&current !in positions) {
                positions[current]=path.size;
                path.add(current);
                current=arrows.getValue(current)
            }
            val position=positions[current];
            if(position!=null) {
                val cycle=path.drop(position);
                val first=cycle.indexOf(cycle.min());
                loops.add(cycle.drop(first)+cycle.take(first))
            }
            finished.addAll(path)
        }
        return loops
    }
    fun forwardingChecks() {
        for(prefix in changedPrefixes) {
            val loops=prefixLoops(prefix);
            val iterator=ongoingRings.iterator();
            while(iterator.hasNext()) {
                val entry=iterator.next();
                if(entry.key.prefix==prefix&&entry.key.path !in loops) {
                    entry.value.end=time;
                    iterator.remove()
                }
            }
            for(loop in loops.sortedBy {
                it.first()
            }) {
                val key=RingKey(prefix,loop);
                if(key !in ongoingRings) {
                    val record=RingRecord(prefix,loop,time);
                    ringRecords.add(record);
                    ongoingRings[key]=record
                }
            }
        }
        for((index,trace) in traces.withIndex()) {
            val path=forwardPath(trace.source,trace.value);
            val status=if(path.result in listOf("LOOP","BLACKHOLE"))TraceStatus(path.result,path.visits.toList()) else null;
            val record=ongoingTraces[index];
            if(record!=null&&record.status!=status) {
                record.end=time;
                ongoingTraces.remove(index)
            }
            if(status!=null&&index !in ongoingTraces) {
                val created=TraceRecord(index,time,status);
                traceRecords.add(created);
                ongoingTraces[index]=created
            }
        }
    }
    fun ribLines():List<String> {
        val lines=mutableListOf<String>();
        for(router in routers.values) {
            val local=router.rib.values.count {
                it.local
            };
            val sent=router.sessions.sumOf {
                it.sent
            };
            val received=router.sessions.sumOf {
                it.received
            };
            lines.add("AS ${router.owner} routes ${router.rib.size} local $local sent $sent received $received changes ${router.changes}");
            for(session in router.sessions) {
                val accepted=session.incoming.count {
                    (prefix,attribute)->importRoute(session,prefix,attribute).route!=null
                };
                val link=session.link;
                lines.add("SESSION ${link.name} ${link.other(router.owner)} ${link.role(router.owner)} ${if(link.up)"UP" else "DOWN"} in ${session.incoming.size} accepted $accepted out ${session.outgoing.size} sent ${session.sent} received ${session.received} flaps ${link.downCount}")
            }
            for((prefix,route) in router.rib) {
                val candidates=candidates(router.owner,prefix);
                var line="$prefix ${Report.route(route)} candidates ${candidates.size}";
                if(!route.local)line+=" reason "+Decision.best(candidates,network.routerIds).reason;
                lines.add(line);
                candidates.removeAll {
                    it==route
                };
                while(candidates.isNotEmpty()) {
                    val alternate=Decision.best(candidates,network.routerIds).route;
                    lines.add("ALT "+Report.route(alternate));
                    candidates.remove(alternate)
                }
            }
        }
        return lines
    }
    fun traceLines(trace:Simulator.Trace):List<String> {
        val path=forwardPath(trace.source,trace.value);
        val lines=mutableListOf("TRACE ${trace.source} ${trace.address} ${path.result} hops ${path.count}");
        for(hop in path.hops) {
            val beginning="HOP ${hop.owner} ${hop.prefix}";
            val link=hop.link;
            lines.add(beginning+if(link==null)" LOCAL" else " next ${link.other(hop.owner)} link ${link.name}")
        }
        if(path.result=="LOOP")lines.add("HOP ${path.visits.last()} REVISIT")else if(path.result in listOf("BLACKHOLE",
            "UNREACHABLE"))lines.add("HOP ${path.visits.last()} NOROUTE");
        if(path.hops.isEmpty())lines.add("CONTROL NONE")else {
            val route=routers.getValue(trace.source).rib.getValue(path.hops.first().prefix);
            val notation=if(route.local)"LOCAL" else Report.path(route.path);
            val match=path.result=="DELIVERED"&&collapse(route.path)==path.visits.drop(1);
            lines.add("CONTROL $notation ${if(match)"MATCH" else "MISMATCH"}")
        }
        if(path.count>0) {
            val pattern=path.hops.filter {
                it.link!=null
            }.joinToString("") {
                it.link!!.direction(it.owner).toString()
            };
            lines.add("PATTERN $pattern ${if(valleyPosition(pattern)==pattern.length)"VALLEYFREE" else "VALLEY"}")
        }
        return lines
    }
    fun pathLines():List<String> {
        val lines=mutableListOf<String>();
        for(trace in traces)lines.addAll(traceLines(trace));
        val prefixes=routers.values.flatMap {
            it.origination.keys
        }.toSortedSet();
        val names=prefixes.joinToString(",");
        lines.add("PREFIXES"+if(names.isEmpty())"" else " $names");
        for(source in network.routerIds.keys) {
            val symbols=StringBuilder();
            for(prefix in prefixes) {
                val path=forwardPath(source,prefix.address);
                val symbol=if(path.result=="DELIVERED") {
                    if(path.count==0)'*' else if(prefix in routers.getValue(path.arrival).origination)'+' else 'X'
                }else when(path.result) {
                    "LOOP"->'L';
                    "BLACKHOLE"->'B';
                    else->'U'
                };
                symbols.append(symbol)
            }
            lines.add("REACH $source"+if(symbols.isEmpty())"" else " $symbols")
        }
        return lines
    }
    fun auditLines():List<String> {
        val lines=mutableListOf<String>();
        var loops=0;
        var blackholes=0;
        for(record in traceRecords.sortedWith(compareBy<TraceRecord> {
            it.start
        }.thenBy {
            it.index
        })) {
            val trace=traces[record.index];
            val result=record.status.result;
            val visits=record.status.visits;
            if(result=="LOOP")loops++ else blackholes++;
            var line="$result ${trace.source} ${trace.address} from ${record.start} to ${record.end?:"END"}";
            if(result=="BLACKHOLE")line+=" at ${visits.last()}";
            lines.add(line+" path "+Report.path(visits))
        }
        for(record in ringRecords.sortedWith(compareBy<RingRecord> {
            it.start
        }.thenBy {
            it.prefix
        }.thenBy {
            it.path.first()
        }))lines.add("RING ${record.prefix} from ${record.start} to ${record.end?:"END"} path ${Report.path(record.path)}");
        var routes=0;
        var valleys=0;
        for(router in routers.values)for((prefix,route) in router.rib) {
            if(route.local)continue;
            routes++;
            val path=collapse(listOf(router.owner)+route.path);
            val pattern=path.zipWithNext().joinToString("") {
                (first,second)->network.connecting(first,second).direction(first).toString()
            };
            val violation=valleyPosition(pattern);
            if(violation!=pattern.length) {
                valleys++;
                lines.add("VALLEY ${router.owner} $prefix path ${Report.path(route.path)} pattern $pattern leaker ${path[violation]}")
            }
        }
        for(rule in policies.rules)lines.add("RULE ${rule.name} ${rule.direction} ${if(rule.active)"ON" else "OFF"} hits ${rule.hits}");
        var divergent=0;
        for(period in periods) {
            val divergence=period.divergence?:continue;
            divergent++;
            lines.add("DIVERGENT event ${period.number} first ${divergence.first} repeat ${divergence.repeat} period ${divergence.repeat-divergence.first}");
            val oscillations=sortedMapOf<OwnerPrefix,Int>();
            for(line in divergence.cycle) {
                lines.add("CYCLE ${line.time} ${line.owner} ${line.prefix} ${Report.route(line.route)}");
                val key=OwnerPrefix(line.owner,line.prefix);
                oscillations[key]=oscillations.getOrDefault(key,0)+1
            }
            for((key,count) in oscillations)lines.add("OSCILLATE ${key.owner} ${key.prefix} changes $count")
        }
        lines.add("SUMMARY loops $loops blackholes $blackholes rings ${ringRecords.size} routes $routes valleys $valleys divergent $divergent end $time");
        return lines
    }
    fun writeOutputs() {
        Report.write("updates.txt",logs);
        Report.write("convergence.csv",listOf(HEADER)+periods.map {
            it.csv()
        });
        Report.write("ribs.txt",ribLines());
        Report.write("paths.txt",pathLines());
        Report.write("audit.txt",auditLines())
    }
}
fun main() {
    val network=Topology();
    val policies=Policy();
    val simulation=Simulation(network,policies,Simulator.params());
    simulation.run(Simulator.events());
    simulation.writeOutputs()
}
