include("minstd.jl")
include("cluster.jl")
include("raft_node.jl")
include("network.jl")
include("checker.jl")

words(parts...) = join(string.(parts)," ")
node_set(nodes) = isempty(nodes) ? "-" : join(["n$i" for i in sort!(collect(nodes))],',')
command_text(command) = join(string.(command),' ')
Base.@kwdef mutable struct ElectionRecord
    time::Int
    node::Int
    term::Int
    trigger::String
    votes::Set{Int}
    won::Int = -1
end
Base.@kwdef mutable struct LeaderRecord
    node::Int
    elected::Int
    votes::Set{Int}
    appended::Int = 1
    ended::Int = -1
    reason::String = ""
    commit::Int = 0
end
Base.@kwdef mutable struct RaftSimulation
    settings::NamedTuple
    nodes::Vector{RaftNode}
    network::RaftNetwork
    random::Minstd
    controls::Vector{NamedTuple}
    requests::Vector{ClientRequest}
    checker::SafetyChecker = SafetyChecker()
    time::Int = 0
    trace::Vector{String} = String[]
    elections::Vector{ElectionRecord} = ElectionRecord[]
    leaders::Dict{Int,LeaderRecord} = Dict{Int,LeaderRecord}()
    timelines::Vector{String} = String[]
    leader_ticks::Int = 0
    multi_ticks::Int = 0
    gaps::Vector{Tuple{Int,Int}} = Tuple{Int,Int}[]
    gap_start::Int = -1
    maximum_term::Int = 0
    committed_count::Int = 0
    reference_states::Dict{Int,Dict{String,Int}} = Dict{Int,Dict{String,Int}}()
    reference_state::Dict{String,Int} = Dict{String,Int}()
    status_counts::Dict{String,Int} = Dict{String,Int}()
    latencies::Vector{Int} = Int[]
    key_requests::Dict{String,Int} = Dict{String,Int}()
    key_committed::Dict{String,Int} = Dict{String,Int}()
end
majority(s,count) = 2count>s.settings.nodes
write_trace!(s,content) = push!(s.trace,"$(s.time) $content")
function set_election_timer!(s,node)
    node.election_deadline = s.time+between!(s.random,s.settings.election_min,s.settings.election_max)
end
send_message!(s,node,destination,kind,data) = network_send!(
    s.network,
    s.time,
    node.number,
    destination,
    node.term,
    kind,
    data
)
function send_append!(s,node,destination)
    previous = node.next[destination]-1
    entries = copy(node.log[previous+1:min(previous+s.settings.batch,last_index(node))])
    send_message!(
        s,
        node,
        destination,
        "AE",
        (previous=previous,previous_term=term_at(node,previous),entries=entries,commit=node.commit)
    )
end
function broadcast_append!(s,node)
    for other in s.nodes
        other.number!=node.number && send_append!(s,node,other.number)
    end
end
function end_leadership!(s,node,reason)
    record = s.leaders[node.term]
    record.ended,record.reason,record.commit = s.time,reason,node.commit
    cancel_transfer!(node)
end
function control!(s,event)
    kind,arguments = event.kind,event.arguments
    if kind=="CRASH"
        node = s.nodes[arguments[1]]
        write_trace!(s,"CRASH n$(node.number) $(node.role) term $(node.term)")
        node.role=="LEADER" && end_leadership!(s,node,"CRASH")
        crash!(node)
    elseif kind=="RESTART"
        node = s.nodes[arguments[1]]
        node.up = true
        set_election_timer!(s,node)
        write_trace!(
            s,
            "RESTART n$(node.number) term $(node.term) length $(last_index(node)) deadline $(node.election_deadline)"
        )
    elseif kind=="PARTITION"
        for (i,group) in enumerate(arguments),node in group
            s.network.groups[node] = i
        end
        write_trace!(s,"PARTITION "*join(node_set.(arguments),' '))
    elseif kind=="HEAL"
        fill!(s.network.groups,0)
        write_trace!(s,"HEAL")
    else
        start_transfer!(s,s.nodes[arguments[1]],arguments[2])
    end
end
function attempt!(s,request)
    request.attempts += 1
    destination,redirected = request.destination,0
    reason = ""
    while true
        node = s.nodes[destination]
        if !node.up
            reason = "down"
            break
        elseif node.role=="LEADER"
            if node.transfer_target!=0
                reason = "transfer"
                break
            end
            push!(node.log,LogEntry(node.term,request.command,request.number))
            s.leaders[node.term].appended += 1
            request.accepted_index,request.accepted_term,request.scheduled = last_index(node),node.term,-1
            write_trace!(
                s,
                "ACCEPT r$(request.number) n$(node.number) index $(last_index(node)) term $(node.term)"
            )
            return
        elseif node.known_leader==0 || redirected>=s.settings.nodes-1
            reason = "noleader"
            break
        end
        destination = node.known_leader
        write_trace!(s,"REDIRECT r$(request.number) n$(node.number) n$destination")
        redirected += 1
        request.redirects += 1
    end
    node = s.nodes[destination]
    prefix = "REJECT r$(request.number) n$(node.number) $reason"
    if request.attempts<s.settings.attempts
        request.destination = node.number%s.settings.nodes+1
        request.scheduled = s.time+s.settings.retry
        write_trace!(s,"$prefix retry n$(request.destination) at $(request.scheduled)")
    else
        request.abandoned,request.scheduled = true,-1
        write_trace!(s,prefix*" giveup")
    end
end
function start_election!(s,node,trigger)
    node.term += 1
    node.role,node.voted_for,node.votes,node.known_leader = "CANDIDATE",node.number,Set([node.number]),0
    set_election_timer!(s,node)
    node.stats["elections"] += 1
    push!(
        s.elections,
        ElectionRecord(time=s.time,node=node.number,term=node.term,trigger=trigger,votes=node.votes)
    )
    node.election_record = length(s.elections)
    write_trace!(
        s,
        "ELECTION n$(node.number) term $(node.term) last $(last_index(node))/$(last_term(node)) deadline $(node.election_deadline)"
    )
    for other in s.nodes
        other.number!=node.number && send_message!(
            s,
            node,
            other.number,
            "RV",
            (last_index=last_index(node),last_term=last_term(node))
        )
    end
end
function vote_request!(s,node,message)
    reason = message.term<node.term ? "term" : node.voted_for!=0 && node.voted_for!=message.source ? "voted" :
        !accepts_log(node,message.data.last_index,message.data.last_term) ? "log" : ""
    if isempty(reason)
        node.voted_for = message.source
        node.stats["votes_granted"] += 1
        set_election_timer!(s,node)
        write_trace!(
            s,
            "VOTE n$(node.number) n$(message.source) term $(node.term) deadline $(node.election_deadline)"
        )
    else
        write_trace!(s,"DENY n$(node.number) n$(message.source) term $(node.term) $reason")
    end
    send_message!(s,node,message.source,"RVR",(granted=isempty(reason),))
end
function vote_response!(s,node,message)
    (node.role!="CANDIDATE" || message.term!=node.term || !message.data.granted) && return
    push!(node.votes,message.source)
    majority(s,length(node.votes)) && become_leader!(s,node)
end
function become_leader!(s,node)
    node.role,node.known_leader = "LEADER",node.number
    node.next,node.match = fill(last_index(node)+1,s.settings.nodes),zeros(Int,s.settings.nodes)
    push!(node.log,LogEntry(node.term,("NOOP",),0))
    node.stats["leader_terms"] += 1
    s.elections[node.election_record].won = s.time
    check_leader!(s.checker,node)
    s.leaders[node.term] = LeaderRecord(node=node.number,elected=s.time,votes=copy(node.votes))
    write_trace!(
        s,
        "LEADER n$(node.number) term $(node.term) votes $(node_set(node.votes)) noop $(last_index(node))"
    )
    broadcast_append!(s,node)
    node.heartbeat_deadline,node.quorum_deadline,node.heard = s.time+s.settings.heartbeat,s.time+s.settings.quorum,Set{Int}()
end
function truncate_log!(s,node,first)
    removed = node.log[first:end]
    resize!(node.log,first-1)
    node.stats["truncated"] += length(removed)
    check_truncate!(s.checker,first,removed)
    write_trace!(s,"TRUNCATE n$(node.number) from $first removed $(length(removed))")
end
function append_request!(s,node,message)
    if message.term<node.term
        send_message!(s,node,message.source,"AER",(success=false,matched=0))
        return
    end
    if node.role=="CANDIDATE"
        node.role = "FOLLOWER"
        write_trace!(s,"YIELD n$(node.number) term $(node.term) n$(message.source)")
    end
    node.known_leader = message.source
    set_election_timer!(s,node)
    previous = message.data.previous
    if previous>last_index(node) || term_at(node,previous)!=message.data.previous_term
        node.stats["ae_fail"] += 1
        hint = previous>last_index(node) ? last_index(node) : previous-1
        send_message!(s,node,message.source,"AER",(success=false,matched=hint))
        return
    end
    node.stats["ae_ok"] += 1
    for (offset,entry) in enumerate(message.data.entries)
        index = previous+offset
        index<=last_index(node) && term_at(node,index)!=entry.term && truncate_log!(s,node,index)
        if index>last_index(node)
            push!(node.log,entry)
            node.stats["appended"] += 1
        end
    end
    confirmed = previous+length(message.data.entries)
    commit = min(message.data.commit,confirmed)
    commit>node.commit && advance_commit!(s,node,commit)
    send_message!(s,node,message.source,"AER",(success=true,matched=confirmed))
end
function append_response!(s,node,message)
    (node.role!="LEADER" || message.term!=node.term) && return
    source,confirmed = message.source,message.data.matched
    push!(node.heard,source)
    if message.data.success
        node.match[source],node.next[source] = max(node.match[source],confirmed),max(
            node.next[source],
            confirmed+1
        )
        check_commit!(s,node)
        if source==node.transfer_target && !node.transfer_sent && node.match[source]==last_index(node)
            send_timeout_now!(s,node)
        elseif node.next[source]<=last_index(node)
            send_append!(s,node,source)
        end
    else
        node.next[source] = max(node.match[source]+1,min(node.next[source]-1,confirmed+1))
        write_trace!(s,"BACKTRACK n$(node.number) n$source next $(node.next[source])")
        send_append!(s,node,source)
    end
end
function check_commit!(s,node)
    for index in last_index(node):-1:node.commit+1
        term_at(node,index)!=node.term && return
        replicated = 1+count(>=(index),node.match)
        if majority(s,replicated)
            write_trace!(s,"COMMIT n$(node.number) $(node.commit+1)-$index term $(node.term)")
            advance_commit!(s,node,index)
            return
        end
    end
end
function advance_commit!(s,node,index)
    for position in node.commit+1:index
        record_commit!(s.checker,position,term_at(node,position),s.time)
    end
    node.commit = index
    first = node.applied+1
    for position in first:index
        entry = node.log[position]
        result = apply_command!(node.store,entry.command)
        node.stats["applies"] += 1
        record_apply!(s.checker,position,entry,result)
    end
    node.applied = index
    write_trace!(s,"APPLY n$(node.number) $first-$index")
end
function receive_message!(s,message)
    node = s.nodes[message.destination]
    if message.term>node.term
        role = node.role
        write_trace!(
            s,
            "TERM n$(node.number) $(node.term)->$(message.term) $(message.kind) n$(message.source) $role"
        )
        role=="LEADER" && end_leadership!(s,node,"STEPDOWN")
        node.term,node.voted_for,node.known_leader,node.role = message.term,0,0,"FOLLOWER"
        role=="LEADER" && set_election_timer!(s,node)
    end
    if message.kind=="RV"
        vote_request!(s,node,message)
    elseif message.kind=="RVR"
        vote_response!(s,node,message)
    elseif message.kind=="AE"
        append_request!(s,node,message)
    elseif message.kind=="AER"
        append_response!(s,node,message)
    elseif message.term!=node.term || node.role!="FOLLOWER"
        write_trace!(s,"IGNORE n$(node.number) TN n$(message.source) term $(message.term)")
    else
        start_election!(s,node,"transfer")
    end
end
function start_transfer!(s,node,destination)
    prefix = "TRANSFER n$(node.number) n$destination"
    if !node.up || node.role!="LEADER" || node.transfer_target!=0 || node.number==destination
        write_trace!(s,prefix*" ignored")
        return
    end
    write_trace!(s,"$prefix start match $(node.match[destination])/$(last_index(node))")
    node.transfer_target,node.transfer_sent,node.transfer_deadline = destination,false,s.time+s.settings.election_min
    node.match[destination]==last_index(node) ? send_timeout_now!(s,node) : send_append!(s,node,destination)
end
function send_timeout_now!(s,node)
    write_trace!(
        s,
        "TIMEOUTNOW n$(node.number) n$(node.transfer_target) term $(node.term) index $(last_index(node))"
    )
    node.transfer_sent = true
    send_message!(s,node,node.transfer_target,"TN",NamedTuple())
end
function timers!(s,node)
    if node.role=="LEADER"
        if node.quorum_deadline==s.time
            if !majority(s,1+length(node.heard))
                write_trace!(s,"STEPDOWN n$(node.number) term $(node.term) heard $(node_set(node.heard))")
                end_leadership!(s,node,"QUORUM")
                node.role,node.known_leader = "FOLLOWER",0
                set_election_timer!(s,node)
                return
            end
            node.heard,node.quorum_deadline = Set{Int}(),s.time+s.settings.quorum
        end
        if node.transfer_target!=0 && node.transfer_deadline==s.time
            write_trace!(s,"TRANSFER n$(node.number) n$(node.transfer_target) abort")
            cancel_transfer!(node)
        end
        if node.heartbeat_deadline==s.time
            broadcast_append!(s,node)
            node.heartbeat_deadline = s.time+s.settings.heartbeat
        end
    elseif node.election_deadline==s.time
        start_election!(s,node,"timeout")
    end
end
function end_of_tick!(s)
    check_logs!(s.checker,s.nodes)
    leaders = [node for node in s.nodes if node.up && node.role=="LEADER"]
    for node in leaders
        node.stats["leader_ticks"] += 1
    end
    if !isempty(leaders)
        s.leader_ticks += 1
        s.multi_ticks += length(leaders)>=2
        if s.gap_start!=-1
            push!(s.gaps,(s.gap_start,s.time-1))
            s.gap_start = -1
        end
    elseif s.gap_start==-1
        s.gap_start = s.time
    end
    if s.time%s.settings.sample==0
        fields = [string(node.up ? node.role[1] : 'D',node.term) for node in s.nodes]
        push!(s.timelines,words("TIMELINE",s.time,join(fields,' ')))
    end
end
function finish_statistics!(s)
    s.maximum_term = maximum(node.term for node in s.nodes)
    s.committed_count = length(s.checker.committed)
    needed = Set(node.applied for node in s.nodes)
    s.reference_states[0] = Dict{String,Int}()
    for index in 1:s.committed_count
        entry,_ = s.checker.applied[index]
        apply_command!(s.reference_state,entry.command)
        index in needed && (s.reference_states[index]=copy(s.reference_state))
    end
    for request in s.requests
        key = request.command[2]
        s.key_requests[key] = get(s.key_requests,key,0)+1
        if request.accepted_index!=0
            index,term = request.accepted_index,request.accepted_term
            committed = get(s.checker.committed,index,nothing)
            if !isnothing(committed) && committed[1]==term
                request.status = "COMMITTED"
                request.latency = committed[2]-request.time
                request.result = s.checker.applied[index][2]
                push!(s.latencies,request.latency)
                s.key_committed[key] = get(s.key_committed,key,0)+1
            elseif any(node->last_index(node)>=index && term_at(node,index)==term,s.nodes)
                request.status = "UNCOMMITTED"
            else
                request.status = "LOST"
            end
        else
            request.status = request.abandoned ? "FAILED" : "WAITING"
        end
        s.status_counts[request.status] = get(s.status_counts,request.status,0)+1
    end
end
function run_simulation!(s)
    for node in s.nodes
        set_election_timer!(s,node)
        write_trace!(s,"START n$(node.number) deadline $(node.election_deadline)")
    end
    controls = Dict{Int,Vector{NamedTuple}}()
    for event in s.controls
        push!(get!(controls,event.time,NamedTuple[]),event)
    end
    for time in 0:s.settings.finish
        s.time = time
        for event in get(controls,time,NamedTuple[])
            control!(s,event)
        end
        for request in s.requests
            request.scheduled==time && attempt!(s,request)
        end
        for message in network_arrivals!(s.network,time)
            network_deliver!(s.network,message,s.nodes[message.destination].up) && receive_message!(s,message)
        end
        for node in s.nodes
            node.up && timers!(s,node)
        end
        end_of_tick!(s)
    end
    s.gap_start!=-1 && push!(s.gaps,(s.gap_start,s.settings.finish))
    finish_statistics!(s)
end
function leader_lines(s)
    lines = String[]
    for r in s.elections
        outcome = r.won==-1 ? "LOST" : "WON $(r.won)"
        push!(
            lines,
            words(
                "ELECTION",
                r.time,
                "n$(r.node)",
                "term",
                r.term,
                "trigger",
                r.trigger,
                "votes",
                length(r.votes),
                outcome
            )
        )
    end
    for term in 1:s.maximum_term
        elections = [r for r in s.elections if r.term==term]
        candidates = node_set(Set(r.node for r in elections))
        if !haskey(s.leaders,term)
            push!(lines,"TERM $term NONE candidates $candidates")
            continue
        end
        r = s.leaders[term]
        finish,reason,commit = r.ended==-1 ? (
            "-",
            "ACTIVE",
            s.nodes[r.node].commit
        ) : (string(r.ended),r.reason,r.commit)
        start = elections[1].time
        push!(lines,words("TERM",term,"LEADER","n$(r.node)","elected",r.elected,"votes",node_set(r.votes),"ended",finish,reason,
            "appended",r.appended,"commit",commit,"candidates",candidates,"started",start,"wait",r.elected-start))
    end
    for n in s.nodes
        push!(
            lines,
            words(
                "NODE",
                "n$(n.number)",
                "elections",
                n.stats["elections"],
                "leader_terms",
                n.stats["leader_terms"],
                "leader_ticks",
                n.stats["leader_ticks"],
                "votes_granted",
                n.stats["votes_granted"]
            )
        )
    end
    append!(lines,s.timelines)
    for (first,last) in s.gaps
        push!(lines,words("GAP","$first-$last","length",last-first+1))
    end
    longest = maximum((last-first+1 for (first,last) in s.gaps);init=0)
    push!(lines,words("SUMMARY terms",s.maximum_term,"leaders",length(s.leaders),"elections",length(s.elections),"leader_ticks",s.leader_ticks,
        "multi_ticks",s.multi_ticks,"ticks",s.settings.finish+1,"gaps",length(s.gaps),"longest",longest))
    lines
end
function log_lines(s)
    lines = String[]
    for node in s.nodes
        status,voted = node.up ? node.role : "DOWN",node.voted_for==0 ? "-" : "n$(node.voted_for)"
        push!(
            lines,
            words(
                "NODE",
                "n$(node.number)",
                status,
                "term",
                node.term,
                "voted",
                voted,
                "commit",
                node.commit,
                "applied",
                node.applied,
                "length",
                last_index(node)
            )
        )
        for (i,e) in enumerate(node.log)
            line = words(i,e.term,command_text(e.command))
            e.request!=0 && (line*=" r$(e.request)")
            push!(lines,line)
        end
    end
    prefix = 0
    for i in 1:minimum(last_index,s.nodes)
        all(node->node.log[i]==s.nodes[1].log[i],s.nodes[2:end]) || break
        prefix += 1
    end
    push!(lines,words("AGREE prefix",prefix,"committed",s.committed_count))
    for n in s.nodes
        common = 0
        for i in 1:min(last_index(n),s.committed_count)
            term_at(n,i)!=s.checker.committed[i][1] && break
            common = i
        end
        push!(lines,words("DIFF","n$(n.number)","common",common,"behind",s.committed_count-common,"extra",last_index(n)-common,
            "ae_ok",n.stats["ae_ok"],"ae_fail",n.stats["ae_fail"],"appended",n.stats["appended"],"truncated",n.stats["truncated"],"applies",n.stats["applies"]))
    end
    lines
end
function request_line(request)
    line = words(
        "REQUEST",
        "r$(request.number)",
        "at",
        request.time,
        "n$(request.initial_destination)",
        command_text(request.command),
        "attempts",
        request.attempts,
        "redirects",
        request.redirects
    )
    if request.accepted_index!=0
        line *= " "*words(request.status,"index",request.accepted_index,"term",request.accepted_term)
        request.status=="COMMITTED" && (line*=" "*words("latency",request.latency,"result",request.result))
    elseif request.status=="FAILED"
        line *= " FAILED"
    else
        line *= " WAITING next $(request.scheduled)"
    end
    line
end
function state_lines(s)
    lines = String[]
    for n in s.nodes
        status,replay = n.up ? "UP" : "DOWN",n.store==s.reference_states[n.applied] ? "match" : "mismatch"
        push!(
            lines,
            words("NODE","n$(n.number)",status,"applied",n.applied,"keys",length(n.store),"replay",replay)
        )
        for key in sort!(collect(keys(n.store)))
            push!(lines,words(key,n.store[key]))
        end
    end
    append!(lines,request_line.(s.requests))
    for key in sort!(collect(keys(s.key_requests)))
        push!(
            lines,
            words(
                "KEY",
                key,
                "requests",
                s.key_requests[key],
                "committed",
                get(s.key_committed,key,0),
                "final",
                get(s.reference_state,key,"missing")
            )
        )
    end
    statuses = join(
        [words(lowercase(name),get(s.status_counts,name,0)) for name in (
            "COMMITTED",
            "UNCOMMITTED",
            "LOST",
            "FAILED",
            "WAITING"
        )],
        ' '
    )
    push!(lines,words("REQUESTS total",length(s.requests),statuses))
    push!(
        lines,
        words(
            "LATENCY count",
            length(s.latencies),
            "total",
            sum(s.latencies),
            "min",
            isempty(s.latencies) ? 0 : minimum(s.latencies),
            "max",
            maximum(s.latencies;init=0)
        )
    )
    lines
end
function safety_lines(s)
    lines = checker_lines(s.checker,s.maximum_term)
    statistics(entries) = join([words(field,entries[i]) for (i,field) in enumerate(MESSAGE_FIELDS)],' ')
    push!(lines,"MESSAGES "*statistics(s.network.total))
    for kind in MESSAGE_TYPES
        push!(lines,"TYPE $kind "*statistics(s.network.by_type[kind]))
    end
    for a in 1:s.settings.nodes,b in 1:s.settings.nodes
        a==b && continue
        link = s.network.links[(a,b)]
        push!(
            lines,
            words(
                "LINK",
                "n$a->n$b",
                "delay",
                link.delay,
                "loss",
                link.loss,
                "sent",
                link.stats[1],
                "delivered",
                link.stats[2],
                "dropped",
                sum(link.stats[4:7])
            )
        )
    end
    append!(
        lines,
        ["DRAWS $(s.random.draws)",any(!=(0),s.checker.violations) ? "RESULT UNSAFE" : "RESULT SAFE"]
    )
    lines
end
function main()
    settings = read_settings()
    controls,requests = read_script()
    s = RaftSimulation(
        settings=settings,
        nodes=[RaftNode(number=i) for i in 1:settings.nodes],
        network=read_network(settings.nodes),
        random=Minstd(settings.seed),
        controls=controls,
        requests=requests
    )
    run_simulation!(s)
    outputs = [
        ("trace.txt",s.trace),
        ("leaders.txt",leader_lines(s)),
        ("logs.txt",log_lines(s)),
        ("state.txt",state_lines(s)),
        ("safety.txt",safety_lines(s))
    ]
    mkpath("output")
    for (name,lines) in outputs
        write(joinpath("output",name),join(lines,"\n")*"\n")
    end
end
main()
