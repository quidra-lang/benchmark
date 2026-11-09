import java.util.PriorityQueue
object CoherenceProgram {
    val reuseLabels=listOf("1","2-4","5-16","17-64","65-256","257+");
    val latencyLabels=listOf("1","2-9","10-29","30-99","100-299","300+")
    class Event(val number: Int,val line: Int,val cycle: Int,val core: Int,val op: String,val address: Int,lineSize: Int) {
        val block=address/lineSize;
        val word=address%lineSize/4;
        var distance=0
    }
    data class Rejection(val line: Int,val reason: String)
    data class Validated(val events: List<Event>,val rejected: List<Rejection>)
    data class Reuse(val core: Int,val accesses: Int,val lines: Int,val distances: IntArray,val cold: Int,
        val capacities: IntArray,val lru: IntArray,val opt: Int)
    data class Future(val block: Int,val next: Int)
    data class Key(val first: Int,val second: Int)
    data class Miss(val kind: String,val sharing: String?)
    data class BusResult(val completion: Int,val transaction: Bus.Transaction)
    data class Processed(val event: Event,val issue: Int,val latency: Int,val service: String,val missKind: String?,
        val hit: Boolean)
    fun validateTrace(lines: List<String>,config: ConfigIo.Config): Validated {
        val accepted=mutableListOf<Event>();
        val rejected=mutableListOf<Rejection>();
        var latest=0;
        for((i,line) in lines.withIndex()) {
            val f=line.split(' ');
            val reason=when {
                f.size !in 3..4||f.any {
                    it.isEmpty()
                }
                ->"fields";
                !ConfigIo.decimalInteger(f[0],7)->"cycle";
                !ConfigIo.decimalInteger(f[1],0)||f[1].toInt()>=config.cores->"core";
                f[2] !in listOf("R","W","FENCE")||f[2]=="FENCE"&&f.size!=3||f[2]!="FENCE"&&f.size!=4->"op";
                f[2]!="FENCE"&&(!ConfigIo.validHexAddress(f[3])||f[3].toLong(16)%4L!=0L||f[3].toLong(16)>0x7fffffffL)->"address";
                f[0].toInt()<latest->"order";
                else->null
            };
            if(reason!=null) {
                rejected.add(Rejection(i+1,reason));
                continue
            };
            latest=f[0].toInt();
            accepted.add(Event(accepted.size+1,i+1,latest,f[1].toInt(),f[2],if(f[2]=="FENCE")0 else f[3].toInt(16),
                config.line))
        };
        return Validated(accepted,rejected)
    }
    fun perCoreEvents(events: List<Event>,cores: Int): List<List<Event>> {
        val result=List(cores) {
            mutableListOf<Event>()
        };
        for(event in events)result[event.core].add(event);
        return result
    }
    class Fenwick(length: Int) {
        val tree=IntArray(length+1);
        fun add(position: Int,value: Int) {
            var i=position;
            while(i<tree.size) {
                tree[i]+=value;
                i+=i and -i
            }
        };
        fun sum(position: Int): Int {
            var result=0;
            var i=position;
            while(i>0) {
                result+=tree[i];
                i-=i and -i
            };
            return result
        }
    }
    fun reuseAnalysis(events: List<Event>,config: ConfigIo.Config): List<Reuse> {
        val byCore=perCoreEvents(events,config.cores);
        val capacities=intArrayOf(config.cap/4,config.cap/2,config.cap,2*config.cap,4*config.cap);
        val analyses=mutableListOf<Reuse>();
        for(core in 0 until config.cores) {
            val accesses=byCore[core].filter {
                it.op!="FENCE"
            };
            val last=mutableMapOf<Int,Int>();
            val tree=Fenwick(accesses.size);
            var cold=0;
            val histogram=IntArray(6);
            val lru=IntArray(5);
            for((i,event) in accesses.withIndex()) {
                val previous=last[event.block];
                if(previous==null)cold++ else {
                    event.distance=tree.sum(i)-tree.sum(previous)+1;
                    tree.add(previous,-1);
                    val d=event.distance;
                    histogram[when {
                        d==1->0;
                        d<=4->1;
                        d<=16->2;
                        d<=64->3;
                        d<=256->4;
                        else->5
                    }]++
                };
                for(j in capacities.indices)if(previous==null||event.distance>capacities[j])lru[j]++;
                tree.add(i+1,1);
                last[event.block]=i+1
            };
            val next=IntArray(accesses.size);
            val upcoming=mutableMapOf<Int,Int>();
            for(i in accesses.lastIndex downTo 0) {
                val block=accesses[i].block;
                next[i]=upcoming.getOrDefault(block,accesses.size+1);
                upcoming[block]=i
            };
            val resident=mutableMapOf<Int,Int>();
            val priorities=PriorityQueue<Future>(compareByDescending<Future> {
                it.next
            }.thenBy {
                it.block
            });
            var opt=0;
            for((i,event) in accesses.withIndex()) {
                val block=event.block;
                if(block !in resident) {
                    opt++;
                    if(resident.size==config.cap) {
                        var victim: Future;
                        do {
                            victim=priorities.remove()
                        }
                        while(resident[victim.block]!=victim.next);
                        resident.remove(victim.block)
                    }
                };
                resident[block]=next[i];
                priorities.add(Future(block,next[i]))
            };
            analyses.add(Reuse(core,accesses.size,last.size,histogram,cold,capacities,lru,opt))
        };
        return analyses
    }
    class WordInfo {
        val reads=sortedSetOf<Int>();
        val writes=sortedSetOf<Int>()
    }
    class Sharing {
        val cores=sortedSetOf<Int>();
        val writers=sortedSetOf<Int>();
        var reads=0;
        var writes=0;
        val words=sortedMapOf<Int,WordInfo>();
        var shared=false;
        var isTrue=false
    }
    fun staticSharing(events: List<Event>): Map<Int,Sharing> {
        val lines=sortedMapOf<Int,Sharing>();
        for(event in events)if(event.op!="FENCE") {
            val info=lines.getOrPut(event.block) {
                Sharing()
            };
            info.cores.add(event.core);
            val word=info.words.getOrPut(event.word) {
                WordInfo()
            };
            if(event.op=="W") {
                info.writers.add(event.core);
                info.writes++;
                word.writes.add(event.core)
            }else {
                info.reads++;
                word.reads.add(event.core)
            }
        };
        for(info in lines.values) {
            info.shared=info.cores.size>=2&&info.writers.isNotEmpty();
            info.isTrue=info.words.values.any {
                it.writes.isNotEmpty()&&(it.reads+it.writes).size>=2
            }
        };
        return lines
    }
    class WordState(val writer: Int) {
        val readers=mutableSetOf<Int>()
    }
    class State(val config: ConfigIo.Config,val scenario: ConfigIo.Scenario,events: List<Event>) {
        val l1=List(config.cores) {
            Cache(config.l1Sets,config.l1Ways,scenario.l1)
        };
        val l2=Cache(config.l2Sets,config.l2Ways,scenario.l2);
        val bus=Bus(config.tb);
        val cores=List(config.cores) {
            Stats.Core()
        };
        val eventLists=perCoreEvents(events,config.cores);
        val indices=IntArray(config.cores);
        val ready=IntArray(config.cores);
        val writeCompletion=IntArray(config.cores);
        val seen=List(config.cores) {
            mutableSetOf<Int>()
        };
        val invalidations=mutableMapOf<Key,MutableSet<Int>>();
        val l2Counters=Stats.Counts();
        val processed=mutableListOf<Processed>();
        val watchLines=mutableListOf<String>();
        val handoffs=mutableMapOf<Int,Int>();
        val lastWriter=mutableMapOf<Int,Int>();
        val wordState=mutableMapOf<Key,WordState>();
        val communications=Array(config.cores) {
            IntArray(config.cores)
        };
        val sharedMisses=mutableMapOf<Key,Int>();
        lateinit var total: Stats.Core;
        var finish=0
        fun lineStates(block: Int)=l1.map {
            it.state(block)
        }+l2.state(block)
        fun issueTransaction(core: Int,kind: String,block: Int,requested: Int): Bus.Transaction {
            val tx=bus.assign(core,kind,block,requested);
            cores[core].bus.add(kind,1);
            if(kind=="WB")l2Counters.add("writebacks",1);
            return tx
        }
        fun snoopOthers(tx: Bus.Transaction,word: Int) {
            for(core in 0 until config.cores) {
                if(core==tx.core)continue;
                val cache=l1[core];
                val old=cache.state(tx.block);
                if(old=="I")continue;
                val change=Protocol.snoop(scenario.protocol,old,tx.kind);
                tx.snoop.add("c$core:$old>${change.state}");
                tx.snoopHits++;
                if(change.state=="I") {
                    cache.remove(tx.block);
                    tx.invalidations++;
                    cores[tx.core].snoop.add("invalidations_sent",1);
                    cores[core].snoop.add("invalidations_received",1);
                    invalidations[Key(core,tx.block)]=mutableSetOf(word)
                }else cache.change(tx.block,change.state);
                if(change.supply) {
                    tx.supplier=core;
                    cores[core].snoop.add("supplied",1)
                };
                if(change.flush)tx.flush=true
            };
            if(tx.flush)l2Counters.add("flushes",1)
        }
        fun accessL2(tx: Bus.Transaction) {
            l2Counters.add("lookups",1);
            if(l2.state(tx.block)!="I") {
                tx.l2="hit";
                l2Counters.add("hits",1);
                l2.touch(tx.block)
            }else {
                tx.l2="miss";
                l2Counters.add("misses",1);
                val evicted=l2.fill(tx.block,"C");
                if(evicted!=null) {
                    var dirty=evicted.state=="D";
                    val copies=mutableListOf<String>();
                    for(core in 0 until config.cores) {
                        val old=l1[core].state(evicted.block);
                        if(old=="I")continue;
                        l1[core].remove(evicted.block);
                        copies.add("c$core:$old");
                        cores[core].snoop.add("back_invalidations",1);
                        if(old in Protocol.dirty)dirty=true
                    };
                    tx.eviction=Bus.Eviction(evicted.block,copies,dirty);
                    l2Counters.add("evictions",1);
                    if(dirty)l2Counters.add("dirty_evictions",1)
                }
            };
            if(tx.flush||tx.kind=="BusWr")l2.change(tx.block,"D")
        }
        fun runTransaction(core: Int,kind: String,block: Int,word: Int,requested: Int): BusResult {
            val tx=issueTransaction(core,kind,block,requested);
            snoopOthers(tx,word);
            if(kind!="BusUpgr")accessL2(tx);
            var completion=tx.start+config.tb;
            if(kind=="BusUpgr")return BusResult(completion,tx);
            if(kind=="BusWr") {
                completion+=config.t2+if(tx.l2=="miss")config.tm else 0
            }else if(tx.supplier!=null)tx.source="c${tx.supplier}" else if(tx.l2=="hit") {
                completion+=config.t2;
                tx.source="L2"
            }else {
                completion+=config.t2+config.tm;
                tx.source="mem"
            };
            return BusResult(completion,tx)
        }
        fun writeBack(core: Int,line: Cache.Line) {
            issueTransaction(core,"WB",line.block,bus.free);
            l2.touch(line.block);
            l2.change(line.block,"D")
        }
        fun classifyMiss(event: Event): Miss {
            val record=invalidations[Key(event.core,event.block)];
            if(event.block !in seen[event.core])return Miss("compulsory",null);
            if(record!=null)return Miss("coherence",if(event.word in record)"true_sharing" else "false_sharing");
            return Miss(if(event.distance>config.cap)"capacity" else "conflict",null)
        }
        fun communicate(event: Event) {
            val key=Key(event.block,event.word);
            val previous=wordState[key];
            if(event.op=="W") {
                val former=lastWriter[event.block];
                if(former!=null&&former!=event.core)handoffs[event.block]=handoffs.getOrDefault(event.block,0)+1;
                lastWriter[event.block]=event.core;
                wordState[key]=WordState(event.core)
            }else if(previous!=null&&previous.writer!=event.core&&previous.readers.add(event.core))communications[previous.writer][event.core]++
        }
        fun renderWatch(event: Event,issue: Int,before: Map<Int,List<String>>) {
            for(block in config.watch) {
                val after=lineStates(block);
                if(block!=event.block&&before[block]==after)continue;
                val columns=(0 until config.cores).joinToString(" ") {
                    "c$it:${after[it]}"
                };
                watchLines.add("${event.number} $issue c${event.core} ${event.op} ${ConfigIo.hexAddress(event.address)} line ${ConfigIo.hexAddress(block*config.line)} $columns L2:${after.last()}")
            }
        }
        fun handleAccess(event: Event,issue: Int,primary: Boolean) {
            val core=event.core;
            val block=event.block;
            val word=event.word;
            val counters=cores[core];
            val cache=l1[core];
            val before=if(primary)config.watch.associateWith {
                lineStates(it)
            } else emptyMap();
            val old=cache.state(block);
            val hit=old!="I";
            counters.simple.add("accesses",1);
            counters.simple.add(if(event.op=="R")"reads" else "writes",1);
            counters.simple.add(if(hit)"hits" else "misses",1);
            val otherCopy=l1.indices.any {
                it!=core&&l1[it].state(block)!="I"
            };
            val transition=Protocol.requester(scenario.protocol,old,event.op,otherCopy);
            var missKind: String?=null;
            if(hit)cache.touch(block) else {
                val miss=classifyMiss(event);
                missKind=miss.kind;
                counters.misses.add(miss.kind,1);
                val sharing=miss.sharing;
                if(sharing!=null) {
                    counters.misses.add(sharing,1);
                    val key=Key(block,if(sharing=="true_sharing")1 else 0);
                    sharedMisses[key]=sharedMisses.getOrDefault(key,0)+1
                }
            };
            seen[core].add(block);
            if(event.op=="W")for((key,words) in invalidations)if(key.first!=core&&key.second==block)words.add(word);
            if(primary)communicate(event);
            val completion: Int;
            val service: String;
            val kind=transition.transaction;
            if(kind==null) {
                completion=issue+config.t1;
                service="l1"
            }else {
                val result=runTransaction(core,kind,block,word,issue+config.t1);
                completion=result.completion;
                val tx=result.transaction;
                service=when {
                    tx.kind=="BusUpgr"->"upgrade";
                    tx.kind=="BusWr"->"through";
                    tx.supplier!=null->"cache";
                    tx.l2=="hit"->"l2";
                    else->"memory"
                }
            };
            if(old!="I")cache.change(block,transition.state) else if(transition.state!="I") {
                val evicted=cache.fill(block,transition.state);
                invalidations.remove(Key(core,block));
                if(evicted!=null&&evicted.state in Protocol.dirty)writeBack(core,evicted)
            };
            val latency=completion-issue;
            counters.service.add(service,1);
            counters.simple.add("latency",latency);
            if(event.op=="R") {
                counters.simple.add("read_latency",latency);
                ready[core]=completion
            }else {
                counters.simple.add("write_latency",latency);
                ready[core]=issue+config.t1;
                writeCompletion[core]=maxOf(writeCompletion[core],completion)
            };
            counters.finish=maxOf(counters.finish,completion);
            processed.add(Processed(event,issue,latency,service,missKind,hit));
            if(primary)renderWatch(event,issue,before)
        }
        fun handleFence(event: Event,issue: Int) {
            val counters=cores[event.core];
            val completion=maxOf(issue,writeCompletion[event.core]);
            counters.simple.add("fences",1);
            counters.simple.add("fence_stall",completion-issue);
            counters.finish=maxOf(counters.finish,completion);
            ready[event.core]=completion
        }
        fun simulate(primary: Boolean) {
            while(true) {
                var chosen: Event?=null;
                var issue=Int.MAX_VALUE;
                for(c in 0 until config.cores)if(indices[c]<eventLists[c].size) {
                    val candidate=eventLists[c][indices[c]];
                    val time=maxOf(candidate.cycle,ready[c]);
                    if(time<issue) {
                        chosen=candidate;
                        issue=time
                    }
                };
                val event=chosen?:break;
                indices[event.core]++;
                if(event.op=="FENCE")handleFence(event,issue) else handleAccess(event,issue,primary)
            };
            total=Stats.total(cores);
            finish=total.finish
        }
    }
    fun formatTraceConfig(c: ConfigIo.Config,trace: List<String>,valid: Validated): List<String> {
        val lines=mutableListOf("trace lines ${trace.size} accepted ${valid.events.size} rejected ${valid.rejected.size}");
        for(rejection in valid.rejected)lines.add("reject line ${rejection.line} ${rejection.reason}");
        lines.add("geometry cores ${c.cores} line ${c.line} l1 ${c.l1Size} ${c.l1Ways} sets ${c.l1Sets} l2 ${c.l2Size} ${c.l2Ways} sets ${c.l2Sets}");
        lines.add("latency l1 ${c.t1} l2 ${c.t2} memory ${c.tm} bus ${c.tb}");
        return lines
    }
    fun formatReuse(analyses: List<Reuse>,c: ConfigIo.Config): List<String> {
        val lines=mutableListOf<String>();
        for(record in analyses) {
            lines.add("reuse c${record.core} accesses ${record.accesses} lines ${record.lines} distance ${Stats.ranges(record.distances,reuseLabels)} cold ${record.cold}");
            val misses=record.capacities.indices.joinToString(" ") {
                "${record.capacities[it]}:${record.lru[it]}"
            };
            lines.add("mrc c${record.core} lru $misses opt ${c.cap}:${record.opt}")
        };
        return lines
    }
    fun lengthHistogram(accesses: List<Processed>): String {
        val counts=IntArray(6);
        for(access in accesses) {
            val l=access.latency;
            counts[when {
                l==1->0;
                l<=9->1;
                l<=29->2;
                l<=99->3;
                l<=299->4;
                else->5
            }]++
        };
        return Stats.ranges(counts,latencyLabels)
    }
    fun scenarioReport(state: State): List<String> {
        val c=state.config;
        val s=state.scenario;
        val lines=mutableListOf("scenario ${s.name} ${s.protocol} ${s.l1} ${s.l2}");
        for(core in 0 until c.cores)lines.addAll(Stats.sixLines("c$core",state.cores[core]));
        lines.addAll(Stats.sixLines("total",state.total));
        val l2=state.l2Counters;
        lines.add("l2 "+l2.named(listOf("lookups","hits","misses","flushes","writebacks","evictions","dirty_evictions")));
        val transactions=state.bus.transactions.size;
        val busy=c.tb*transactions;
        lines.add("bus transactions $transactions busy $busy wait ${state.bus.wait} utilization ${Stats.decimal(100*busy,state.finish)}");
        val kinds=state.total.bus;
        val dataBytes=c.line*(kinds.get("BusRd")+kinds.get("BusRdX")+kinds.get("WB"))+4*kinds.get("BusWr");
        val memoryBytes=c.line*(l2.get("misses")+l2.get("dirty_evictions"));
        lines.add("traffic command_bytes ${8*transactions} data_bytes $dataBytes memory_bytes $memoryBytes");
        var snoops=0;
        var hits=0;
        val fanout=IntArray(c.cores);
        for(tx in state.bus.transactions)if(tx.kind!="WB") {
            snoops++;
            hits+=tx.snoopHits;
            if(tx.kind!="BusRd")fanout[tx.invalidations]++
        };
        lines.add("snoops probes ${(c.cores-1)*snoops} hits $hits fanout "+Stats.ranges(fanout,(0 until c.cores).map {
            it.toString()
        }));
        lines.add("latencies reads ${state.total.simple.get("read_latency")} writes ${state.total.simple.get("write_latency")} histogram ${lengthHistogram(state.processed)}");
        return lines
    }
    fun rankScenarios(states: List<State>): List<String> {
        val ordered=states.sortedWith(compareBy<State> {
            it.finish
        }.thenBy {
            it.bus.transactions.size
        }.thenBy {
            it.scenario.order
        });
        val lines=mutableListOf("ranking");
        for((i,state) in ordered.withIndex()) {
            val length=state.total.simple.get("latency");
            val accesses=state.total.simple.get("accesses");
            lines.add("${i+1} ${state.scenario.name} finish ${state.finish} transactions ${state.bus.transactions.size} amat ${Stats.fraction(length,accesses)} ${Stats.decimal(length,accesses)}")
        };
        return lines
    }
    class Hot {
        val counts=Stats.Counts();
        val cores=sortedSetOf<Int>();
        var total=0
    }
    fun hotLines(state: State): List<String> {
        val hot=mutableMapOf<Int,Hot>();
        for(tx in state.bus.transactions) {
            val info=hot.getOrPut(tx.block) {
                Hot()
            };
            info.counts.add(tx.kind,1);
            info.counts.add("invalidations",tx.invalidations);
            info.total++;
            info.cores.add(tx.core)
        };
        for(item in state.processed)if(item.missKind!=null) {
            val info=hot.getOrPut(item.event.block) {
                Hot()
            };
            info.counts.add("misses",1);
            if(item.missKind=="coherence")info.counts.add("coherence",1)
        };
        val blocks=hot.keys.filter {
            hot.getValue(it).total>0
        }.sortedWith(compareByDescending<Int> {
            hot.getValue(it).total
        }.thenBy {
            it
        });
        val lines=mutableListOf("hot ${state.scenario.name}");
        for((i,block) in blocks.take(state.config.top).withIndex()) {
            val info=hot.getValue(block);
            lines.add("${i+1} ${ConfigIo.hexAddress(block*state.config.line)} transactions ${info.total} ${info.counts.named(Stats.transactions)} ${info.counts.named(listOf("misses","coherence","invalidations"))} cores ${Stats.coreString(info.cores)}")
        };
        return lines
    }
    fun intervalRows(state: State): List<String> {
        val c=state.config;
        val width=c.interval;
        val count=state.finish/width+1;
        val accesses=Array(count) {
            IntArray(c.cores)
        };
        val misses=IntArray(count);
        val transactions=IntArray(count);
        val busy=IntArray(count);
        for(item in state.processed) {
            val bucket=item.issue/width;
            accesses[bucket][item.event.core]++;
            if(item.missKind!=null)misses[bucket]++
        };
        for(tx in state.bus.transactions) {
            val first=tx.start;
            val last=first+c.tb;
            transactions[first/width]++;
            for(k in first/width..(last-1)/width)if(k<count)busy[k]+=maxOf(0,minOf(last,(k+1)*width)-maxOf(first,k*width))
        };
        val lines=mutableListOf("intervals ${state.scenario.name} $width");
        for(k in 0 until count)lines.add("$k ${k*width}-${(k+1)*width-1} accesses ${accesses[k].joinToString(" ")} misses ${misses[k]} transactions ${transactions[k]} busy ${busy[k]} utilization ${Stats.decimal(100*busy[k],width)}");
        return lines
    }
    fun slowestRows(state: State): List<String> {
        val ordered=state.processed.sortedWith(compareByDescending<Processed> {
            it.latency
        }.thenBy {
            it.event.number
        });
        val lines=mutableListOf("slowest ${state.scenario.name}");
        for((i,item) in ordered.take(state.config.top).withIndex()) {
            val event=item.event;
            lines.add("${i+1} event ${event.number} cycle ${item.issue} c${event.core} ${event.op} ${ConfigIo.hexAddress(event.address)} latency ${item.latency} service ${item.service}")
        };
        return lines
    }
    fun regionFor(address: Int,config: ConfigIo.Config)=config.regions.firstOrNull {
        address in it.start..it.end
    }?.name?:"other"
    fun regionRows(state: State): List<String> {
        val c=state.config;
        val counters=linkedMapOf<String,Stats.Counts>();
        for(region in c.regions)counters[region.name]=Stats.Counts();
        counters["other"]=Stats.Counts();
        for(item in state.processed) {
            val event=item.event;
            val count=counters.getValue(regionFor(event.address,c));
            count.add("accesses",1);
            count.add(if(event.op=="R")"reads" else "writes",1);
            count.add("latency",item.latency);
            count.add(if(item.hit)"hits" else item.missKind!!,1)
        };
        for(tx in state.bus.transactions)counters.getValue(regionFor(tx.block*c.line,c)).add("transactions",1);
        val lines=mutableListOf("regions ${state.scenario.name}");
        for((name,count) in counters) {
            val amat=if(count.get("accesses")==0)"-" else "${Stats.fraction(count.get("latency"),count.get("accesses"))} ${Stats.decimal(count.get("latency"),count.get("accesses"))}";
            lines.add("$name ${count.named(listOf("accesses","reads","writes","hits"))} ${count.named(Stats.misses)} ${count.named(listOf("transactions","latency"))} amat $amat")
        };
        return lines
    }
    fun statsOutput(c: ConfigIo.Config,trace: List<String>,valid: Validated,reuse: List<Reuse>,states: List<State>,
        primary: State): List<String> {
        val sections=mutableListOf(formatTraceConfig(c,trace,valid),formatReuse(reuse,c));
        for(state in states)sections.add(scenarioReport(state));
        sections.addAll(listOf(rankScenarios(states),hotLines(primary),intervalRows(primary),slowestRows(primary),
            regionRows(primary)));
        val lines=mutableListOf<String>();
        for(section in sections) {
            if(lines.isNotEmpty())lines.add("");
            lines.addAll(section)
        };
        return lines
    }
    fun sharingOutput(shared: Map<Int,Sharing>,state: State): List<String> {
        val lines=mutableListOf<String>();
        var count=0;
        var trueLines=0;
        var falseLines=0;
        var totalTrue=0;
        var totalFalse=0;
        for((block,info) in shared) {
            if(!info.shared)continue;
            count++;
            if(info.isTrue)trueLines++ else falseLines++;
            val t=state.sharedMisses.getOrDefault(Key(block,1),0);
            val f=state.sharedMisses.getOrDefault(Key(block,0),0);
            totalTrue+=t;
            totalFalse+=f;
            val words=info.words.entries.joinToString(" ") {
                (number,word)->"w$number=${Stats.coreString(word.reads)}/${Stats.coreString(word.writes)}"
            };
            val kind=if(info.isTrue)"true" else "false";
            lines.add("${ConfigIo.hexAddress(block*state.config.line)} $kind cores ${Stats.coreString(info.cores)} writers ${Stats.coreString(info.writers)} reads ${info.reads} writes ${info.writes} handoffs ${state.handoffs.getOrDefault(block,0)} coherence ${t+f} true $t false $f words $words")
        };
        lines.add("lines $count true_lines $trueLines false_lines $falseLines coherence ${totalTrue+totalFalse} true $totalTrue false $totalFalse");
        lines.add("communication");
        for(c in 0 until state.config.cores)lines.add("c$c "+state.communications[c].joinToString(" "));
        return lines
    }
    fun cacheWay(entry: Cache.Line?,lineSize: Int)=if(entry==null)"-" else "${ConfigIo.hexAddress(entry.block*lineSize)}:${entry.state}"
    fun cacheRows(lines: MutableList<String>,cache: Cache,label: String,lineSize: Int) {
        for(row in 0 until cache.numberSets) {
            val ways=cache.entries[row].joinToString(" ") {
                cacheWay(it,lineSize)
            };
            lines.add("$label $row $ways ${cache.replacement.lowercase()} ${cache.order(row)} fills ${cache.fills[row]} evictions ${cache.evictions[row]}")
        }
    }
    fun finalStateOutput(state: State): List<String> {
        val lines=mutableListOf<String>();
        val inL1=mutableSetOf<Int>();
        for(core in 0 until state.config.cores) {
            val cache=state.l1[core];
            cacheRows(lines,cache,"c$core",state.config.line);
            val counts=Stats.Counts();
            for(entry in cache.lines()) {
                counts.add(entry.state,1);
                inL1.add(entry.block)
            };
            lines.add("c$core lines ${cache.lines().size} "+counts.named(listOf("M","O","E","S","V")))
        };
        cacheRows(lines,state.l2,"L2",state.config.line);
        val counts=Stats.Counts();
        for(entry in state.l2.lines())counts.add(entry.state,1);
        lines.add("L2 lines ${state.l2.lines().size} dirty ${counts.get("D")} clean ${counts.get("C")} in_l1 ${inL1.size}");
        return lines
    }
    fun run() {
        val config=ConfigIo.readConfig();
        val trace=ConfigIo.readTrace();
        val valid=validateTrace(trace,config);
        val reuse=reuseAnalysis(valid.events,config);
        val shared=staticSharing(valid.events);
        val states=config.scenarios.map {
            scenario->State(config,scenario,valid.events).also {
                it.simulate(scenario.name==config.primary)
            }
        };
        val primary=states.first {
            it.scenario.name==config.primary
        };
        ConfigIo.writeLines("stats.txt",statsOutput(config,trace,valid,reuse,states,primary));
        ConfigIo.writeLines("bus_log.txt",primary.bus.transactions.map {
            primary.bus.line(it,config.line)
        });
        ConfigIo.writeLines("watch.txt",primary.watchLines);
        ConfigIo.writeLines("sharing.txt",sharingOutput(shared,primary));
        ConfigIo.writeLines("final_state.txt",finalStateOutput(primary))
    }
}
fun main() {
    CoherenceProgram.run()
}
