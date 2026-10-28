import java.io.File
import java.util.PriorityQueue

object Causal {
    val TYPES=arrayOf("LOCAL","NOFUNDS","SEND","BCAST","RECV")
    class Params {
        var seed=0;
        var end=0;
        var cutTime=0;
        val comparisons=mutableListOf<List<String>>();
        val cuts=mutableListOf<IntArray>();
        val thresholds=mutableListOf<Int>()
    }
    fun readParams(): Params {
        val p=Params()
        for(line in File("input/params.txt").readLines()) {
            val w=line.split(' ');
            when(w[0]) {
                "SEED"->p.seed=w[1].toInt()
                "END"->p.end=w[1].toInt()
                "CUTCOUNT"->p.cutTime=w[1].toInt()
                "COMPARE"->p.comparisons.add(w.drop(1))
                "PREDICATE"->p.thresholds.add(w[1].toInt())
                "CUT"->p.cuts.add(w.drop(1).map {
                    it.toInt()
                }.toIntArray())
            }
        }
        return p
    }
    class Event(val number: Int,val local: Int,val process: Int,val time: Int,val kind: Int,
        val lamport: Int,val balance: Int,val vector: IntArray,val details: String,val message: Message?,
        val copy: Packet?)
    class Message(val id: Int,val source: Int,val amount: Int,val broadcast: Boolean,val tag: String,val stamp: IntArray?) {
        lateinit var send: Event;
        val copies=mutableListOf<Packet>()
        fun name()="m$id"
        fun kind()=if(broadcast)"BCAST" else "P2P"
    }
    class Packet(val message: Message?=null,val snapshot: Snapshot.State?=null) {
        var source=0;
        var destination=0;
        var sequence=0;
        var dispatch=0;
        var arrival=0;
        var delivery=-1
        var fifo=false;
        var causal=false;
        var missing=IntArray(0);
        var recv: Event?=null
    }
    data class Item(val time: Int,val process: Int,val serial: Int,val action: Processes.Action?,val packet: Packet?)
    data class Glyph(val time: Int,val process: Int,val kind: Int,val message: Message?,val copy: Packet?,val snapshot: String?)
    class Simulation(val params: Params,val raw: Boolean) {
        val network=Network();
        val names=network.names;
        val processes=Processes.read(names);
        val random=Network.Generator(params.seed)
        var current=0;
        var serial=0
        val messages=mutableListOf<Message>();
        val copies=mutableListOf<Packet>();
        val events=mutableListOf<Event>()
        val snapshots=mutableListOf<Snapshot.State>();
        val snapshotNames=mutableMapOf<String,Snapshot.State>();
        val timeline=mutableListOf<Glyph>()
        val queue=PriorityQueue<Item>(compareBy<Item> {
            it.time
        }.thenBy {
            it.process
        }.thenBy {
            it.serial
        })
        init {
            for(p in Processes.expand(processes,params.end))enqueue(p.time,p.process,p.action,null)
        }
        fun enqueue(time: Int,process: Int,action: Processes.Action?,packet: Packet?) {
            queue.add(Item(time,process,++serial,action,packet))
        }
        fun initial()=processes.sumOf {
            it.initial
        }
        fun event(p: Processes.State,kind: Int,details: String,message: Message?,copy: Packet?): Event {
            Clocks.advance(p,if(kind==4)message!!.send else null)
            val e=Event(events.size+1,p.events.size+1,p.index,current,kind,p.lamport,p.balance,p.vector.copyOf(),details,message,copy)
            p.events.add(e);
            p.counts[kind]++;
            p.minimum=minOf(p.minimum,p.balance);
            events.add(e);
            timeline.add(Glyph(current,p.index,kind,message,copy,null))
            return e
        }
        fun dispatch(source: Int,destination: Int,packet: Packet) {
            network.channels[source][destination]!!.dispatch(packet,current,random);
            enqueue(packet.arrival,destination,null,packet)
        }
        fun send(p: Processes.State,action: Processes.Action,sender: Int) {
            val broadcast=action.kind=="BROADCAST";
            val transfer=action.kind=="TRANSFER"
            val destination=if(broadcast)-1 else if(action.argument=="SENDER")sender else names.indexOf(action.argument)
            val amount=if(transfer)action.value.toInt() else 0
            if(transfer&&amount>p.balance) {
                p.refused++;
                event(p,1,"to ${names[destination]} amount $amount balance ${p.balance}",null,null);
                return
            }
            if(transfer) {
                p.balance-=amount;
                p.outgoing+=amount
            }
            if(broadcast)p.broadcast[p.index]++
            val message=Message(messages.size+1,p.index,amount,broadcast,if(transfer)"transfer" else if(broadcast)action.argument else action.value,
                if(broadcast)p.broadcast.copyOf() else null);
            messages.add(message)
            val destinationText=if(broadcast)"" else " to ${names[destination]}"
            var details="${message.name()}$destinationText tag ${message.tag}"
            if(transfer)details+=" amount $amount balance ${p.balance}"
            message.send=event(p,if(broadcast)3 else 2,details,message,null)
            for(q in names.indices)if(if(broadcast)q!=p.index else q==destination) {
                val c=Packet(message);
                message.copies.add(c);
                copies.add(c);
                dispatch(p.index,q,c)
            }
        }
        fun action(process: Int,action: Processes.Action,sender: Int) {
            val p=processes[process]
            if(action.kind=="LOCAL")event(p,0,action.argument,null,null)
            else if(action.kind=="SNAPSHOT") {
                var snapshot=snapshotNames[action.argument]
                if(snapshot==null) {
                    snapshot=Snapshot.State(action.argument,current,names.size);
                    snapshotNames[snapshot.name]=snapshot;
                    snapshots.add(snapshot)
                }
                if(snapshot.records[process]!=null)snapshot.ignored.add(Snapshot.Ignored(process,current)) else recordSnapshot(snapshot,process,"initiate")
            } else send(p,action,sender)
        }
        fun recordSnapshot(snapshot: Snapshot.State,process: Int,reason: String) {
            snapshot.recordState(processes[process],current,reason);
            timeline.add(Glyph(current,process,5,null,null,snapshot.name))
            for(q in names.indices)if(q!=process) {
                val packet=Packet(snapshot=snapshot);
                dispatch(process,q,packet);
                snapshot.sent[process][q]=current
            }
        }
        fun deliver(c: Packet) {
            val p=processes[c.destination];
            val m=c.message!!
            if(m.broadcast)p.broadcast[c.source]++;
            p.balance+=m.amount;
            p.incoming+=m.amount
            var details="${m.name()} from ${names[c.source]} tag ${m.tag}";
            if(m.amount>0)details+=" amount ${m.amount} balance ${p.balance}"
            c.recv=event(p,4,details,m,c);
            c.delivery=current;
            p.delivered.add(c)
            for(rule in p.rules)if(rule.tag==m.tag)action(p.index,rule.action,c.source)
        }
        fun release(p: Processes.State) {
            while(true) {
                val chosen=p.hold.indexOfFirst {
                    Clocks.deliverable(it,p)
                };
                if(chosen<0)return;
                val c=p.hold.removeAt(chosen);
                deliver(c)
            }
        }
        fun accept(c: Packet) {
            val p=processes[c.destination];
            p.next[c.source]++
            val message=c.message
            if(message==null) {
                val s=c.snapshot!!;
                if(s.records[p.index]==null)recordSnapshot(s,p.index,"marker ${names[c.source]}");
                s.accept(c.source,p.index,current);
                return
            }
            for(s in snapshots)if(s.records[p.index]!=null&&s.accepted[c.source][p.index]<0)s.channels[c.source][p.index].add(c)
            if(!message.broadcast||raw)deliver(c)
            else if(Clocks.deliverable(c,p)) {
                deliver(c);
                release(p)
            }
            else {
                c.causal=true;
                c.missing=Clocks.missing(c,p);
                p.hold.add(c)
            }
        }
        fun arrive(c: Packet) {
            val p=processes[c.destination];
            val buffer=p.reorder[c.source]
            if(raw)accept(c)
            else if(c.sequence!=p.next[c.source]) {
                c.fifo=true;
                buffer[c.sequence]=c;
                network.channels[c.source][c.destination]!!.buffered++
            }
            else {
                accept(c);
                while(buffer.containsKey(p.next[c.source])) {
                    val following=buffer.remove(p.next[c.source])!!;
                    accept(following)
                }
            }
            p.maxHeld=maxOf(p.maxHeld,p.held())
        }
        fun run(): Simulation {
            while(queue.isNotEmpty()&&queue.peek().time<=params.end) {
                val item=queue.remove();
                current=item.time;
                val scheduledAction=item.action;
                if(scheduledAction!=null)action(item.process,scheduledAction,-1) else arrive(item.packet!!)
            }
            return this
        }
    }
    fun yes(condition: Boolean)=if(condition)"yes" else "no"
    fun eventName(s: Simulation,e: Event)="${s.names[e.process]}.${e.local}"
    fun label(s: Simulation,c: Packet)="${c.message!!.name()}->${s.names[c.destination]}"
    fun names(s: Simulation,chosen: IntArray)=chosen.joinToString(",") {
        s.names[it]
    }
    fun history(p: Processes.State)=p.events.filter {
        it.kind==3||it.kind==4&&it.message!!.broadcast
    }.map {
        it.message!!.id
    }
    fun messages(copies: List<Packet>,empty: String,amounts: Boolean): String {
        if(copies.isEmpty())return empty
        return copies.joinToString(" ") {
            val m=it.message!!;
            m.name()+(if(amounts&&m.amount>0)":${m.amount}" else "")
        }
    }
    fun delivered(s: Simulation)=s.copies.count {
        it.recv!=null
    }
    fun trace(s: Simulation): List<String> {
        val lines=s.events.map {
            e->"${e.number} t=${e.time} ${eventName(s,e)} ${TYPES[e.kind]} ${e.details} L=${e.lamport} V=${Clocks.vector(e.vector)}"
        }.toMutableList()
        val count=delivered(s);
        lines.add("SUMMARY events ${s.events.size} messages ${s.messages.size} copies ${s.copies.size} delivered $count undelivered ${s.copies.size-count} draws ${s.random.draws}")
        for(p in s.processes)lines.add("FINAL ${s.names[p.index]} events ${p.events.size} L=${p.lamport} V=${Clocks.vector(p.vector)} B=${Clocks.vector(p.broadcast)} balance ${p.balance} in ${p.incoming} out ${p.outgoing} refused ${p.refused} min ${p.minimum}")
        for(p in s.processes)lines.add("COUNTS ${s.names[p.index]} local ${p.counts[0]} nofunds ${p.counts[1]} send ${p.counts[2]} bcast ${p.counts[3]} recv ${p.counts[4]}")
        return lines
    }
    fun waitMode(s: Simulation,c: Packet)=if(c.causal)(if(c.fifo)"fifo+causal " else "causal ")+names(s,c.missing) else if(c.fifo)"fifo" else "direct"
    fun copyInfo(s: Simulation,c: Packet): String {
        val m=c.message!!;
        return "${m.name()} from ${s.names[c.source]} ${m.kind()} tag ${m.tag} sent ${m.send.time}"
    }
    fun deliveries(s: Simulation): List<String> {
        val lines=mutableListOf<String>()
        for(p in s.processes) {
            lines.add("PROCESS ${s.names[p.index]}");
            val modes=IntArray(4);
            var wait=0;
            var maximum=0
            for((number,c) in p.delivered.withIndex()) {
                val delay=c.delivery-c.arrival;
                wait+=delay;
                maximum=maxOf(maximum,delay);
                modes[(if(c.fifo)1 else 0)+(if(c.causal)2 else 0)]++;
                lines.add("${number+1} ${copyInfo(s,c)} arrived ${c.arrival} delivered ${c.delivery} wait $delay ${waitMode(s,c)}")
            }
            for(c in s.copies)if(c.destination==p.index&&c.arrival<=s.params.end&&c.recv==null) {
                val place=if(p.reorder[c.source].containsKey(c.sequence))"fifo" else "causal "+names(s,c.missing);
                lines.add("HELD ${copyInfo(s,c)} arrived ${c.arrival} $place")
            }
            for(c in s.copies)if(c.destination==p.index&&c.arrival>s.params.end)lines.add("TRANSIT ${copyInfo(s,c)} arrival ${c.arrival}")
            lines.add("TOTAL delivered ${p.delivered.size} direct ${modes[0]} fifo ${modes[1]} causal ${modes[2]} both ${modes[3]} wait $wait max_wait $maximum max_held ${p.maxHeld}")
            val ids=history(p);
            lines.add("BCASTS "+(if(ids.isEmpty())"none" else ids.joinToString(" ") {
                "m$it"
            }))
        }
        val n=s.names.size
        for(i in 0 until n)for(j in 0 until n)if(i!=j) {
            val c=s.network.channels[i][j]!!;
            lines.add("CHANNEL ${s.names[i]}->${s.names[j]} ${if(c.fifo)"FIFO" else "NONFIFO"} ${c.delay()} messages ${c.messages} markers ${c.markers} buffered ${c.buffered} max_delay ${c.maxDelay} entries ${c.entries}")
        }
        val tags=sortedMapOf<String,IntArray>();
        val broadcasts=mutableListOf<Message>()
        for(c in s.copies) {
            val m=c.message!!;
            val values=tags.getOrPut(m.tag) {
                IntArray(4)
            };
            values[0]++;
            if(c.recv!=null) {
                val latency=c.delivery-m.send.time;
                values[1]++;
                values[2]+=latency;
                values[3]=maxOf(values[3],latency)
            }
        }
        for((tag,a) in tags)lines.add("TAG $tag copies ${a[0]} delivered ${a[1]} latency ${a[2]} max ${a[3]}")
        for(m in s.messages)if(m.broadcast) {
            broadcasts.add(m);
            var stable=0;
            var complete=true;
            for(c in m.copies)if(c.recv==null)complete=false else stable=maxOf(stable,c.delivery);
            lines.add("STABLE ${m.name()} ${s.names[m.source]} tag ${m.tag} sent ${m.send.time} stable ${if(complete)stable.toString() else "none"}")
        }
        var disagreements=0
        for(i in broadcasts.indices)for(j in i+1 until broadcasts.size) {
            val a=broadcasts[i];
            val b=broadcasts[j];
            val earlier=mutableListOf<String>();
            val later=mutableListOf<String>()
            for(p in s.processes) {
                val ids=history(p);
                val x=ids.indexOf(a.id);
                val y=ids.indexOf(b.id);
                if(x>=0&&y>=0)(if(x<y)earlier else later).add(s.names[p.index])
            }
            if(earlier.isNotEmpty()&&later.isNotEmpty()) {
                disagreements++;
                lines.add("DISAGREE ${a.name()} ${b.name()} ${earlier.joinToString(",")} ${later.joinToString(",")}")
            }
        }
        lines.add("DISAGREEMENTS $disagreements");
        return lines
    }

    fun verdict(s: Simulation,details: Snapshot.Cut)=if(details.orphans.isEmpty())"yes" else "no "+details.orphans.joinToString(" ") {
        label(s,it)
    }
    fun snapshots(normal: Simulation,raw: Simulation): List<String> {
        val lines=mutableListOf<String>()
        for(sim in listOf(normal,raw))for(snap in sim.snapshots) {
            val cut=snap.cut();
            val details=Snapshot.inspect(cut,sim);
            var balances=0;
            var channelMoney=0;
            val n=sim.names.size
            val channelCopies=mutableListOf<Packet>();
            val pending=mutableListOf<Packet>()
            for(i in 0 until n) {
                val rec=snap.records[i]!!;
                balances+=rec.balance;
                pending.addAll(rec.pending);
                for(j in 0 until n)if(i!=j)channelCopies.addAll(snap.channels[i][j])
            }
            for(c in channelCopies)channelMoney+=c.message!!.amount;
            val money=balances+channelMoney
            if(sim.raw) {
                lines.add("RAW ${snap.name} completed ${snap.complete} cut ${Clocks.vector(cut)} consistent ${verdict(sim,details)} money $money conserved ${yes(money==sim.initial())}");
                continue
            }
            lines.add("SNAPSHOT ${snap.name} started ${snap.start} completed ${snap.complete}")
            for(i in 0 until n) {
                val rec=snap.records[i]!!;
                lines.add("RECORD ${sim.names[i]} t=${rec.time} ${rec.reason} balance ${rec.balance} L=${rec.lamport} V=${Clocks.vector(rec.vector)} pending ${messages(rec.pending,"none",false)}")
            }
            for(i in 0 until n)for(j in 0 until n)if(i!=j)lines.add("CHANNEL ${sim.names[i]}->${sim.names[j]} marker ${snap.sent[i][j]} ${snap.accepted[i][j]} state ${messages(snap.channels[i][j],"empty",true)}")
            for(ignored in snap.ignored)lines.add("IGNORED ${sim.names[ignored.process]} t=${ignored.time}")
            val vector=snap.records.all {
                Clocks.lessEqual(it!!.vector,cut)
            }
            lines.add("CUT ${Clocks.vector(cut)} consistent ${verdict(sim,details)} vector ${yes(vector)}")
            val all=channelCopies+pending
            lines.add("TRANSIT channels ${channelCopies.size} pending ${pending.size} cut ${details.transit.size} match ${yes(Snapshot.match(all,details.transit))}")
            lines.add("MONEY balances $balances channels $channelMoney total $money initial ${sim.initial()} conserved ${yes(money==sim.initial())}")
        }
        return lines
    }
    fun ranges(sim: Simulation,path: List<Event>): String {
        val parts=mutableListOf<String>();
        var first=0
        while(first<path.size) {
            var last=first;
            while(last+1<path.size&&path[last+1].process==path[last].process&&path[last+1].local==path[last].local+1)last++
            val a=path[first];
            val b=path[last];
            parts.add(eventName(sim,a)+(if(first==last)"" else "-${b.local}"));
            first=last+1
        }
        return if(parts.isEmpty())"-" else parts.joinToString(" ")
    }
    fun chain(sim: Simulation): List<Event> {
        var current=sim.events[0];
        for(e in sim.events)if(e.lamport>current.lamport)current=e
        val reversed=mutableListOf(current)
        while(current.lamport>1) {
            current=if(current.kind==4&&current.message!!.send.lamport==current.lamport-1)current.message!!.send else sim.processes[current.process].events[current.local-2];
            reversed.add(current)
        }
        reversed.reverse();
        return reversed
    }
    fun relationLine(s: Simulation,r: Analysis.Relation,violation: Boolean): String {
        val a=r.first;
        val b=r.second;
        val prefix=if(violation)"VIOLATION " else "RACE ";
        val middle=if(violation)" overtook " else " "
        return "$prefix${s.names[r.process]} ${a.message!!.name()} ${s.names[a.source]}$middle${b.message!!.name()} ${s.names[b.source]}"
    }
    fun fifoCount(relations: List<Analysis.Relation>)=relations.count {
        it.first.source==it.second.source
    }
    fun analysis(sim: Simulation,raw: Simulation): List<String> {
        val lines=mutableListOf<String>();
        val indexed=sim.events.associateBy {
            eventName(sim,it)
        };
        val edges=Analysis.graph(sim)
        for(pair in sim.params.comparisons) {
            val a=indexed.getValue(pair[0]);
            val b=indexed.getValue(pair[1]);
            val relation=Clocks.relation(a.vector,b.vector)
            var path=Analysis.path(a.number-1,b.number-1,edges);
            var graph="->"
            if(path==null) {
                path=Analysis.path(b.number-1,a.number-1,edges);
                graph=if(path==null)"||" else "<-"
            }
            lines.add("COMPARE ${pair[0]} $relation ${pair[1]} L=${a.lamport},${b.lamport} graph $graph agree ${yes(relation==graph)}")
            if(path!=null) {
                val events=path.map {
                    sim.events[it]
                };
                val count=(1 until events.size).count {
                    events[it].process!=events[it-1].process
                };
                lines.add("PATH length ${events.size} messages $count ${ranges(sim,events)}")
            }
            for(e in listOf(a,b)) {
                val future=IntArray(sim.names.size) {
                    q->sim.processes[q].events.count {
                        it.vector[e.process]<e.local
                    }
                };
                lines.add("WINDOW ${eventName(sim,e)} past ${Clocks.vector(e.vector)} future ${Clocks.vector(future)}")
            }
        }
        val c=Analysis.concurrency(sim);
        val n=sim.events.size
        lines.add("CONCURRENCY events $n pairs ${n*(n-1)/2} ordered ${c.ordered} concurrent ${c.concurrent} same_lamport ${c.same} inversions ${c.inversions}")
        for(i in sim.names.indices)for(j in i+1 until sim.names.size)lines.add("PAIR ${sim.names[i]} ${sim.names[j]} ${c.pairs[i][j]}")
        val longest=chain(sim);
        lines.add("CHAIN length ${longest.size} ${ranges(sim,longest)}")
        val races=Analysis.relations(sim,true);
        val violations=Analysis.relations(sim,false);
        val rawViolations=Analysis.relations(raw,false)
        for(r in races)lines.add(relationLine(sim,r,false));
        lines.add("RACES ${races.size}")
        for(r in violations)lines.add(relationLine(sim,r,true));
        lines.add("VIOLATIONS causal ${violations.size} fifo ${fifoCount(violations)}")
        lines.add("RAW events ${raw.events.size} delivered ${delivered(raw)} causal ${rawViolations.size} fifo ${fifoCount(rawViolations)}")
        for(cut in sim.params.cuts) {
            val details=Snapshot.inspect(cut,sim);
            val text=if(details.orphans.isEmpty())" consistent" else " inconsistent orphans "+details.orphans.joinToString(" ") {
                label(sim,it)
            };
            lines.add("CUT ${Clocks.vector(cut)}$text transit ${details.transit.size} money ${details.money} initial ${sim.initial()}")
        }
        val enumeration=Analysis.enumerate(sim,sim.params.cutTime,sim.params.thresholds)
        lines.add("CUTCOUNT t=${sim.params.cutTime} events ${Clocks.vector(enumeration.limits)} product ${enumeration.product} consistent ${enumeration.consistent}")
        lines.add("LEVELS "+enumeration.levels.joinToString(" "))
        for(i in sim.params.thresholds.indices) {
            val p=enumeration.predicates[i];
            lines.add("PREDICATE transit>=${sim.params.thresholds[i]} cuts ${p.cuts} possibly ${yes(p.cuts>0)} definitely ${yes(p.definitely)}")
        }
        return lines
    }
    fun overwrite(line: StringBuilder,at: Int,text: String) {
        while(line.length<at+text.length)line.append(' ');
        for(i in text.indices)line.setCharAt(at+i,text[i])
    }
    fun trim(line: StringBuilder)=line.toString().trimEnd(' ')
    fun header(sim: Simulation,letter: String): String {
        val line=StringBuilder("    $letter ");
        for(i in sim.names.indices)overwrite(line,8*i+6,sim.names[i]);
        return trim(line)
    }
    fun glyph(sim: Simulation,glyph: Glyph,value: Int): String {
        val last=8*sim.names.size-2;
        val line=StringBuilder(value.toString().padStart(5)+" "+" ".repeat(last-5))
        for(i in sim.names.indices)line.setCharAt(8*i+6,'|');
        val own=8*glyph.process+6;
        val symbols=charArrayOf('*','x','S','B','R','#');
        line.setCharAt(own,symbols[glyph.kind])
        if(glyph.kind==5)overwrite(line,own+1,glyph.snapshot!!)
        else if(glyph.kind==2||glyph.kind==3)overwrite(line,own+1,glyph.message!!.name())
        else if(glyph.kind==4) {
            val source=8*glyph.copy!!.source+6;
            val low=minOf(own,source);
            val high=maxOf(own,source)
            for(i in low+1 until high)line.setCharAt(i,if((i-6)%8==0)'+' else '-');
            line.setCharAt(if(source<own)high-1 else low+1,if(source<own)'>' else '<');
            overwrite(line,low+2,glyph.message!!.name())
        }
        return trim(line)
    }
    fun diagram(sim: Simulation): List<String> {
        val lines=mutableListOf(header(sim,"t"));
        for(g in sim.timeline)lines.add(glyph(sim,g,g.time));
        lines.add(header(sim,"L"))
        val events=sim.events.sortedWith(compareBy<Event> {
            it.lamport
        }.thenBy {
            it.process
        })
        for(e in events)lines.add(glyph(sim,Glyph(e.time,e.process,e.kind,e.message,e.copy,null),e.lamport))
        return lines
    }
    fun write(name: String,lines: List<String>) {
        File("output").mkdirs();
        File("output",name).writeText(lines.joinToString("\n")+"\n")
    }
    fun run() {
        val params=readParams();
        val normal=Simulation(params,false).run();
        val raw=Simulation(params,true).run()
        write("trace.txt",trace(normal));
        write("deliveries.txt",deliveries(normal));
        write("snapshots.txt",snapshots(normal,raw));
        write("analysis.txt",analysis(normal,raw));
        write("diagram.txt",diagram(normal))
    }
}
fun main()=Causal.run()
