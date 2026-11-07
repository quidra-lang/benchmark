import java.io.File
object Simulator {
    lateinit var settings: Cluster.Settings;
    lateinit var controls: List<Cluster.Control>;
    lateinit var requests: List<Cluster.Request>;
    val nodes=mutableListOf<RaftNode>();
    lateinit var network: Network;
    lateinit var random: Minstd;
    val checker=Checker();
    var time=0;
    var leaderTicks=0;
    var multiTicks=0;
    var gapStart=-1;
    var maximumTerm=0;
    var committedCount=0;
    val trace=mutableListOf<String>();
    val timelines=mutableListOf<String>();
    val elections=mutableListOf<Election>();
    val leaders=sortedMapOf<Int,Leader>();
    val gaps=mutableListOf<Gap>();
    val referenceStates=mutableMapOf<Int,Map<String,Int>>();
    val referenceState=sortedMapOf<String,Int>();
    val keyRequests=sortedMapOf<String,Int>();
    val keyCommitted=sortedMapOf<String,Int>();
    val statuses=mutableMapOf<String,Int>();
    val latencies=mutableListOf<Int>()
    class Election(val time: Int,val node: Int,val term: Int,val trigger: String,val votes: Set<Int>) {
        var won=-1
    }
    class Leader(val node: Int,val elected: Int,votes: Set<Int>) {
        val votes=votes.toSet();
        var appended=1;
        var ended=-1;
        var commit=0;
        var reason="ACTIVE"
    }
    data class Gap(val first: Int,val last: Int)
    fun node(number: Int)=nodes[number-1]
    fun majority(count: Int)=2*count>settings.nodes
    fun nodeSet(numbers: Collection<Int>)=numbers.toSortedSet().joinToString(",") {
        "n$it"
    }.ifEmpty {
        "-"
    }
    fun trace(content: String) {
        trace.add("$time $content")
    }
    fun electionTimer(node: RaftNode) {
        node.electionDeadline=time+random.between(settings.electionMin,settings.electionMax)
    }
    fun send(node: RaftNode,destination: Int,kind: String,data: Network.Payload) {
        network.send(time,node.number,destination,node.term,kind,data)
    }
    fun sendAppend(node: RaftNode,destination: Int) {
        val previous=node.next[destination]-1;
        val entries=node.log.subList(previous,minOf(previous+settings.batch,node.lastIndex)).toList();
        send(node,destination,"AE",Network.AppendRequest(previous,node.termAt(previous),entries,node.commit))
    }
    fun broadcast(node: RaftNode) {
        for(other in nodes)if(other!==node)sendAppend(node,other.number)
    }
    fun endLeadership(node: RaftNode,reason: String) {
        val record=leaders.getValue(node.term);
        record.ended=time;
        record.reason=reason;
        record.commit=node.commit;
        node.cancelTransfer()
    }
    fun control(event: Cluster.Control) {
        val args=event.arguments;
        when(event.kind) {
            "CRASH"-> {
                val node=Simulator.node(args.first());
                trace("CRASH n${node.number} ${node.role} term ${node.term}");
                if(node.role==RaftNode.Role.LEADER)endLeadership(node,"CRASH");
                node.crash()
            };
            "RESTART"-> {
                val node=Simulator.node(args.first());
                node.up=true;
                electionTimer(node);
                trace("RESTART n${node.number} term ${node.term} length ${node.lastIndex} deadline ${node.electionDeadline}")
            };
            "PARTITION"-> {
                network.partition(event.groups);
                trace("PARTITION "+event.groups.joinToString(" ") {
                    nodeSet(it)
                })
            };
            "HEAL"-> {
                network.heal();
                trace("HEAL")
            };
            else->startTransfer(node(args.first()),args[1])
        }
    }
    fun attempt(request: Cluster.Request) {
        request.attempts++;
        var destination=request.destination;
        var redirected=0;
        var reason: String;
        var node: RaftNode;
        while(true) {
            node=Simulator.node(destination);
            if(!node.up) {
                reason="down";
                break
            };
            if(node.role==RaftNode.Role.LEADER) {
                if(node.transferTarget!=0) {
                    reason="transfer";
                    break
                };
                node.log.add(RaftNode.Entry(node.term,request.command,request.number));
                leaders.getValue(node.term).appended++;
                request.accepted=true;
                request.index=node.lastIndex;
                request.term=node.term;
                request.scheduled=-1;
                trace("ACCEPT r${request.number} n${node.number} index ${node.lastIndex} term ${node.term}");
                return
            };
            if(node.knownLeader==0||redirected>=settings.nodes-1) {
                reason="noleader";
                break
            };
            destination=node.knownLeader;
            trace("REDIRECT r${request.number} n${node.number} n$destination");
            redirected++;
            request.redirects++
        };
        val prefix="REJECT r${request.number} n${node.number} $reason";
        if(request.attempts<settings.attempts) {
            request.destination=node.number%settings.nodes+1;
            request.scheduled=time+settings.retry;
            trace("$prefix retry n${request.destination} at ${request.scheduled}")
        } else {
            request.abandoned=true;
            request.scheduled=-1;
            trace("$prefix giveup")
        }
    }
    fun startElection(node: RaftNode,trigger: String) {
        node.term++;
        node.role=RaftNode.Role.CANDIDATE;
        node.votedFor=node.number;
        node.votes=mutableSetOf(node.number);
        node.knownLeader=0;
        electionTimer(node);
        node.stats.elections++;
        node.electionRecord=elections.size;
        elections.add(Election(time,node.number,node.term,trigger,node.votes));
        trace("ELECTION n${node.number} term ${node.term} last ${node.lastIndex}/${node.lastTerm} deadline ${node.electionDeadline}");
        for(other in nodes)if(other!==node)send(node,other.number,"RV",Network.VoteRequest(node.lastIndex,
            node.lastTerm))
    }
    fun voteRequest(node: RaftNode,message: Network.Message) {
        val data=message.data as Network.VoteRequest;
        val reason=when {
            message.term<node.term->"term";
            node.votedFor!=0&&node.votedFor!=message.source->"voted";
            !node.acceptsLog(data.lastIndex,data.lastTerm)->"log";
            else->null
        };
        if(reason==null) {
            node.votedFor=message.source;
            node.stats.votesGranted++;
            electionTimer(node);
            trace("VOTE n${node.number} n${message.source} term ${node.term} deadline ${node.electionDeadline}")
        } else trace("DENY n${node.number} n${message.source} term ${node.term} $reason");
        send(node,message.source,"RVR",Network.VoteResponse(reason==null))
    }
    fun voteResponse(node: RaftNode,message: Network.Message) {
        val data=message.data as Network.VoteResponse;
        if(node.role!=RaftNode.Role.CANDIDATE||message.term!=node.term||!data.granted)return;
        node.votes.add(message.source);
        if(majority(node.votes.size))becomeLeader(node)
    }
    fun becomeLeader(node: RaftNode) {
        node.role=RaftNode.Role.LEADER;
        node.knownLeader=node.number;
        node.next=IntArray(settings.nodes+1);
        node.match=IntArray(settings.nodes+1);
        for(other in nodes)if(other!==node)node.next[other.number]=node.lastIndex+1;
        node.log.add(RaftNode.Entry(node.term,"NOOP",0));
        node.stats.leaderTerms++;
        elections[node.electionRecord].won=time;
        checker.leader(node);
        leaders[node.term]=Leader(node.number,time,node.votes);
        trace("LEADER n${node.number} term ${node.term} votes ${nodeSet(node.votes)} noop ${node.lastIndex}");
        broadcast(node);
        node.heartbeatDeadline=time+settings.heartbeat;
        node.quorumDeadline=time+settings.quorum;
        node.heard=mutableSetOf()
    }
    fun truncate(node: RaftNode,first: Int) {
        val removed=node.log.subList(first-1,node.log.size).toList();
        node.log.subList(first-1,node.log.size).clear();
        node.stats.truncated+=removed.size;
        checker.truncate(first,removed);
        trace("TRUNCATE n${node.number} from $first removed ${removed.size}")
    }
    fun appendRequest(node: RaftNode,message: Network.Message) {
        if(message.term<node.term) {
            send(node,message.source,"AER",Network.AppendResponse(false,0));
            return
        };
        val data=message.data as Network.AppendRequest;
        if(node.role==RaftNode.Role.CANDIDATE) {
            node.role=RaftNode.Role.FOLLOWER;
            trace("YIELD n${node.number} term ${node.term} n${message.source}")
        };
        node.knownLeader=message.source;
        electionTimer(node);
        val previous=data.previous;
        if(previous>node.lastIndex||node.termAt(previous)!=data.previousTerm) {
            node.stats.aeFail++;
            val hint=if(previous>node.lastIndex)node.lastIndex else previous-1;
            send(node,message.source,"AER",Network.AppendResponse(false,hint));
            return
        };
        node.stats.aeOk++;
        var index=previous;
        for(entry in data.entries) {
            index++;
            if(index<=node.lastIndex&&node.termAt(index)!=entry.term)truncate(node,index);
            if(index>node.lastIndex) {
                node.log.add(entry);
                node.stats.appended++
            }
        };
        val confirmed=previous+data.entries.size;
        val commit=minOf(data.commit,confirmed);
        if(commit>node.commit)advanceCommit(node,commit);
        send(node,message.source,"AER",Network.AppendResponse(true,confirmed))
    }
    fun appendResponse(node: RaftNode,message: Network.Message) {
        if(node.role!=RaftNode.Role.LEADER||message.term!=node.term)return;
        val data=message.data as Network.AppendResponse;
        val source=message.source;
        val confirmed=data.match;
        node.heard.add(source);
        if(data.success) {
            node.match[source]=maxOf(node.match[source],confirmed);
            node.next[source]=maxOf(node.next[source],confirmed+1);
            checkCommit(node);
            if(source==node.transferTarget&&!node.transferSent&&node.match[source]==node.lastIndex)sendTimeoutNow(node) else if(node.next[source]<=node.lastIndex)sendAppend(node,
                source)
        } else {
            node.next[source]=maxOf(node.match[source]+1,minOf(node.next[source]-1,confirmed+1));
            trace("BACKTRACK n${node.number} n$source next ${node.next[source]}");
            sendAppend(node,source)
        }
    }
    fun checkCommit(node: RaftNode) {
        for(index in node.lastIndex downTo node.commit+1) {
            if(node.termAt(index)!=node.term)return;
            val count=1+nodes.count {
                it!==node&&node.match[it.number]>=index
            };
            if(majority(count)) {
                trace("COMMIT n${node.number} ${node.commit+1}-$index term ${node.term}");
                advanceCommit(node,index);
                return
            }
        }
    }
    fun advanceCommit(node: RaftNode,index: Int) {
        for(p in node.commit+1..index)checker.commit(p,node.termAt(p),time);
        node.commit=index;
        val first=node.applied+1;
        for(p in first..index) {
            val entry=node.log[p-1];
            val result=RaftNode.applyCommand(node.store,entry.command);
            node.stats.applies++;
            checker.apply(p,entry,result)
        };
        node.applied=index;
        trace("APPLY n${node.number} $first-$index")
    }
    fun receive(message: Network.Message) {
        val node=Simulator.node(message.destination);
        if(message.term>node.term) {
            val old=node.role;
            trace("TERM n${node.number} ${node.term}->${message.term} ${message.kind} n${message.source} $old");
            if(old==RaftNode.Role.LEADER)endLeadership(node,"STEPDOWN");
            node.term=message.term;
            node.votedFor=0;
            node.knownLeader=0;
            node.role=RaftNode.Role.FOLLOWER;
            if(old==RaftNode.Role.LEADER)electionTimer(node)
        };
        when(message.kind) {
            "RV"->voteRequest(node,message);
            "RVR"->voteResponse(node,message);
            "AE"->appendRequest(node,message);
            "AER"->appendResponse(node,message);
            else->if(message.term!=node.term||node.role!=RaftNode.Role.FOLLOWER)trace("IGNORE n${node.number} TN n${message.source} term ${message.term}") else startElection(node,
                "transfer")
        }
    }
    fun startTransfer(node: RaftNode,destination: Int) {
        val prefix="TRANSFER n${node.number} n$destination";
        if(!node.up||node.role!=RaftNode.Role.LEADER||node.transferTarget!=0||node.number==destination) {
            trace("$prefix ignored");
            return
        };
        trace("$prefix start match ${node.match[destination]}/${node.lastIndex}");
        node.transferTarget=destination;
        node.transferSent=false;
        node.transferDeadline=time+settings.electionMin;
        if(node.match[destination]==node.lastIndex)sendTimeoutNow(node) else sendAppend(node,destination)
    }
    fun sendTimeoutNow(node: RaftNode) {
        trace("TIMEOUTNOW n${node.number} n${node.transferTarget} term ${node.term} index ${node.lastIndex}");
        node.transferSent=true;
        send(node,node.transferTarget,"TN",Network.Immediate())
    }
    fun timers(node: RaftNode) {
        if(node.role==RaftNode.Role.LEADER) {
            if(node.quorumDeadline==time) {
                if(!majority(1+node.heard.size)) {
                    trace("STEPDOWN n${node.number} term ${node.term} heard ${nodeSet(node.heard)}");
                    endLeadership(node,"QUORUM");
                    node.role=RaftNode.Role.FOLLOWER;
                    node.knownLeader=0;
                    electionTimer(node);
                    return
                };
                node.heard=mutableSetOf();
                node.quorumDeadline=time+settings.quorum
            };
            if(node.transferTarget!=0&&node.transferDeadline==time) {
                trace("TRANSFER n${node.number} n${node.transferTarget} abort");
                node.cancelTransfer()
            };
            if(node.heartbeatDeadline==time) {
                broadcast(node);
                node.heartbeatDeadline=time+settings.heartbeat
            }
        } else if(node.electionDeadline==time)startElection(node,"timeout")
    }
    fun endOfTick() {
        checker.checkLogs(nodes);
        val active=nodes.filter {
            it.up&&it.role==RaftNode.Role.LEADER
        };
        for(node in active)node.stats.leaderTicks++;
        if(active.isNotEmpty()) {
            leaderTicks++;
            if(active.size>=2)multiTicks++;
            if(gapStart>=0) {
                gaps.add(Gap(gapStart,time-1));
                gapStart=-1
            }
        } else if(gapStart<0)gapStart=time;
        if(time%settings.sample==0)timelines.add("TIMELINE $time "+nodes.joinToString(" ") {
            (if(it.up)it.role.toString().take(1) else "D")+it.term
        })
    }
    fun simulate() {
        for(node in nodes) {
            electionTimer(node);
            trace("START n${node.number} deadline ${node.electionDeadline}")
        };
        for(t in 0..settings.end) {
            time=t;
            for(event in controls)if(event.time==time)control(event);
            for(request in requests)if(!request.accepted&&!request.abandoned&&request.scheduled==time)attempt(request);
            for(message in network.arrivals(time))if(network.deliver(message,node(message.destination).up))receive(message);
            for(node in nodes)if(node.up)timers(node);
            endOfTick()
        };
        if(gapStart>=0)gaps.add(Gap(gapStart,settings.end));
        finishStatistics()
    }
    fun add(counts: MutableMap<String,Int>,key: String) {
        counts[key]=counts.getOrDefault(key,0)+1
    }
    fun finishStatistics() {
        maximumTerm=nodes.maxOf {
            it.term
        };
        committedCount=checker.committed.size;
        val needed=nodes.map {
            it.applied
        }.toSet();
        referenceStates[0]=emptyMap();
        for(index in 1..committedCount) {
            RaftNode.applyCommand(referenceState,checker.applied.getValue(index).entry.command);
            if(index in needed)referenceStates[index]=referenceState.toMap()
        };
        for(request in requests) {
            val key=request.command.split(' ')[1];
            add(keyRequests,key);
            if(request.accepted) {
                val committed=checker.committed[request.index];
                if(committed!=null&&committed.term==request.term) {
                    request.status="COMMITTED";
                    request.latency=committed.time-request.time;
                    request.result=checker.applied.getValue(request.index).result;
                    latencies.add(request.latency);
                    add(keyCommitted,key)
                } else request.status=if(nodes.any {
                    it.lastIndex>=request.index&&it.termAt(request.index)==request.term
                })"UNCOMMITTED" else "LOST"
            } else request.status=if(request.abandoned)"FAILED" else "WAITING";
            add(statuses,request.status)
        }
    }
    fun leaderLines(): List<String> {
        val lines=mutableListOf<String>();
        for(record in elections)lines.add("ELECTION ${record.time} n${record.node} term ${record.term} trigger ${record.trigger} votes ${record.votes.size} ${if(record.won<0)"LOST" else "WON ${record.won}"}");
        for(term in 1..maximumTerm) {
            val termElections=elections.filter {
                it.term==term
            };
            val candidates=termElections.map {
                it.node
            }.toSet();
            val record=leaders[term];
            if(record==null) {
                lines.add("TERM $term NONE candidates ${nodeSet(candidates)}");
                continue
            };
            val start=termElections.first().time;
            val end=if(record.ended<0)"-" else record.ended.toString();
            val reason=if(record.ended<0)"ACTIVE" else record.reason;
            val commit=if(record.ended<0)node(record.node).commit else record.commit;
            lines.add("TERM $term LEADER n${record.node} elected ${record.elected} votes ${nodeSet(record.votes)} ended $end $reason appended ${record.appended} commit $commit candidates ${nodeSet(candidates)} started $start wait ${record.elected-start}")
        };
        for(node in nodes) {
            val s=node.stats;
            lines.add("NODE n${node.number} elections ${s.elections} leader_terms ${s.leaderTerms} leader_ticks ${s.leaderTicks} votes_granted ${s.votesGranted}")
        };
        lines.addAll(timelines);
        for(gap in gaps)lines.add("GAP ${gap.first}-${gap.last} length ${gap.last-gap.first+1}");
        val longest=gaps.maxOfOrNull {
            it.last-it.first+1
        }?:0;
        lines.add("SUMMARY terms $maximumTerm leaders ${leaders.size} elections ${elections.size} leader_ticks $leaderTicks multi_ticks $multiTicks ticks ${settings.end+1} gaps ${gaps.size} longest $longest");
        return lines
    }
    fun logLines(): List<String> {
        val lines=mutableListOf<String>();
        for(node in nodes) {
            val status=if(node.up)node.role.toString() else "DOWN";
            val voted=if(node.votedFor==0)"-" else "n${node.votedFor}";
            lines.add("NODE n${node.number} $status term ${node.term} voted $voted commit ${node.commit} applied ${node.applied} length ${node.lastIndex}");
            for((i,entry) in node.log.withIndex())lines.add("${i+1} ${entry.term} ${entry.command}"+if(entry.request==0)"" else " r${entry.request}")
        };
        var prefix=0;
        for(i in 0 until nodes.minOf {
            it.lastIndex
        }) {
            if(nodes.drop(1).any {
                it.log[i]!=nodes.first().log[i]
            })break;
            prefix++
        };
        lines.add("AGREE prefix $prefix committed $committedCount");
        for(node in nodes) {
            var common=0;
            for(index in 1..minOf(node.lastIndex,committedCount)) {
                if(node.termAt(index)!=checker.committed.getValue(index).term)break;
                common=index
            };
            val s=node.stats;
            lines.add("DIFF n${node.number} common $common behind ${committedCount-common} extra ${node.lastIndex-common} ae_ok ${s.aeOk} ae_fail ${s.aeFail} appended ${s.appended} truncated ${s.truncated} applies ${s.applies}")
        };
        return lines
    }
    fun requestLine(request: Cluster.Request): String {
        var line="REQUEST r${request.number} at ${request.time} n${request.initialDestination} ${request.command} attempts ${request.attempts} redirects ${request.redirects} ";
        if(request.accepted) {
            line+="${request.status} index ${request.index} term ${request.term}";
            if(request.status=="COMMITTED")line+=" latency ${request.latency} result ${request.result}"
        } else line+=if(request.abandoned)"FAILED" else "WAITING next ${request.scheduled}";
        return line
    }
    fun stateLines(): List<String> {
        val lines=mutableListOf<String>();
        for(node in nodes) {
            val status=if(node.up)"UP" else "DOWN";
            val replay=if(node.store==referenceStates[node.applied])"match" else "mismatch";
            lines.add("NODE n${node.number} $status applied ${node.applied} keys ${node.store.size} replay $replay");
            for((key,value) in node.store)lines.add("$key $value")
        };
        for(request in requests)lines.add(requestLine(request));
        for((key,count) in keyRequests)lines.add("KEY $key requests $count committed ${keyCommitted.getOrDefault(key,0)} final ${referenceState[key]?.toString()?:"missing"}");
        lines.add("REQUESTS total ${requests.size} "+listOf("COMMITTED","UNCOMMITTED","LOST","FAILED",
            "WAITING").joinToString(" ") {
            "${it.lowercase()} ${statuses.getOrDefault(it,0)}"
        });
        lines.add("LATENCY count ${latencies.size} total ${latencies.sum()} min ${latencies.minOrNull()?:0} max ${latencies.maxOrNull()?:0}");
        return lines
    }
    fun statistics(values: IntArray)=Network.fields.indices.joinToString(" ") {
        "${Network.fields[it]} ${values[it]}"
    }
    fun safetyLines(): List<String> {
        val lines=checker.lines(maximumTerm).toMutableList();
        lines.add("MESSAGES "+statistics(network.total));
        for(i in Network.types.indices)lines.add("TYPE ${Network.types[i]} "+statistics(network.byType[i]));
        for(a in 1..settings.nodes)for(b in 1..settings.nodes)if(a!=b) {
            val link=network.link(a,b);
            val dropped=(3..6).sumOf {
                link.stats[it]
            };
            lines.add("LINK n$a->n$b delay ${link.delay} loss ${link.loss} sent ${link.stats[0]} delivered ${link.stats[1]} dropped $dropped")
        };
        lines.add("DRAWS ${random.draws}");
        lines.add(if(checker.violations.all {
            it==0
        })"RESULT SAFE" else "RESULT UNSAFE");
        return lines
    }
    fun write(name: String,lines: List<String>) {
        File("output",name).writeText(lines.joinToString("\n")+if(lines.isEmpty())"" else "\n")
    }
    fun run() {
        val input=Cluster.read();
        settings=input.settings;
        controls=input.controls;
        requests=input.requests;
        for(i in 1..settings.nodes)nodes.add(RaftNode(i));
        network=Network(settings.nodes);
        random=Minstd(settings.seed);
        simulate();
        File("output").mkdirs();
        write("trace.txt",trace);
        write("leaders.txt",leaderLines());
        write("logs.txt",logLines());
        write("state.txt",stateLines());
        write("safety.txt",safetyLines())
    }
}
fun main()=Simulator.run()
