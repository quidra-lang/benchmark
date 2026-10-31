include("network.jl")
include("clocks.jl")
include("processes.jl")
include("snapshot.jl")
include("analysis.jl")
Base.@kwdef mutable struct Simulation
    names::Vector{String}
    params::Dict{String,Any}
    raw::Bool
    processes::Vector{ProcessState}
    channels::Dict{Tuple{Int,Int},NetworkChannel}
    channel_order::Vector{Tuple{Int,Int}}
    random::MINSTD
    queue::Vector{NamedTuple} = NamedTuple[]
    creation::Int = 0
    current_time::Int = 0
    messages::Vector{Message} = Message[]
    packets::Vector{Packet} = Packet[]
    copies::Vector{Int} = Int[]
    events::Vector{CausalEvent} = CausalEvent[]
    snapshots::Vector{Snapshot} = Snapshot[]
    snapshot_by_name::Dict{String,Int} = Dict{String,Int}()
    timeline::Vector{NamedTuple} = NamedTuple[]
end
function load_params()
    params = Dict{String,Any}("compare"=>Tuple{String,String}[],"cuts"=>Vector{Int}[],"predicates"=>Int[])
    for line in readlines(joinpath("input","params.txt"))
        words = String.(split(line))
        key = words[1]
        if key in ("SEED","END","CUTCOUNT")
            params[lowercase(key)] = parse(Int,words[2])
        elseif key=="COMPARE"
            push!(params["compare"],Tuple(words[2:end]))
        elseif key=="CUT"
            push!(params["cuts"],parse.(Int,words[2:end]))
        else
            push!(params["predicates"],parse(Int,words[2]))
        end
    end
    params
end
queue_key(item) = (item.time,item.process,item.creation)
function enqueue!(sim,time,process,kind,payload)
    sim.creation += 1
    item = (time=time,process=process,creation=sim.creation,kind=kind,payload=payload)
    push!(sim.queue,item)
    index = length(sim.queue)
    while index>1
        parent = index÷2
        queue_key(sim.queue[parent])<=queue_key(item) && break
        sim.queue[index] = sim.queue[parent]
        index = parent
    end
    sim.queue[index] = item
end
function dequeue!(sim)
    first = sim.queue[1]
    last = pop!(sim.queue)
    if !isempty(sim.queue)
        index = 1
        while 2index<=length(sim.queue)
            child = 2index
            child<length(sim.queue) && queue_key(sim.queue[child+1])<queue_key(sim.queue[child]) && (child+=1)
            queue_key(last)<=queue_key(sim.queue[child]) && break
            sim.queue[index] = sim.queue[child]
            index = child
        end
        sim.queue[index] = last
    end
    first
end
function make_simulation(names,channels,order,scripts,params,raw=false)
    sim = Simulation(
        names=names,
        params=params,
        raw=raw,
        processes=initialize_processes(names,scripts),
        channels=deepcopy(channels),
        channel_order=order,
        random=MINSTD(params["seed"],0)
    )
    schedule_actions(sim.processes,params["end"],(time,p,action)->enqueue!(sim,time,p,:action,action))
    sim
end
function record_event!(sim,p,kind,details,sender=0)
    process = sim.processes[p]
    if kind=="RECV"
        receive_event!(process,p,sim.events[sender])
    else
        nonreceive_event!(process,p)
    end
    event = CausalEvent(
        length(sim.events)+1,
        length(process.events)+1,
        p,
        kind,
        details,
        sim.current_time,
        process.lamport,
        copy(process.vector),
        process.balance
    )
    push!(process.events,event.number)
    process.types[kind] = get(process.types,kind,0)+1
    process.min_balance = min(process.min_balance,process.balance)
    push!(sim.events,event)
    push!(sim.timeline,(kind=:event,index=event.number))
    event.number
end
function dispatch_packet!(sim,source,destination,packet)
    push!(sim.packets,packet)
    index = length(sim.packets)
    vector = packet.packet_type==:copy ? sim.events[sim.messages[packet.message].send_event].vector : Int[]
    dispatch!(
        sim.channels[(source,destination)],
        packet,
        sim.current_time,
        sim.random,
        vector,
        (time,p)->enqueue!(sim,time,p,:arrival,index)
    )
    index
end
function send_message!(sim,p,action,sender)
    process = sim.processes[p]
    kind = action.kind
    destination = action.destination==0 ? sender : action.destination
    amount,tag,event_type,message_kind = 0,action.text,"SEND","P2P"
    if kind=="TRANSFER"
        amount = action.amount
        if amount>process.balance
            process.refused += 1
            record_event!(sim,p,"NOFUNDS",(destination=destination,amount=amount,balance=process.balance))
            return
        end
        process.balance -= amount
        process.outgoing += amount
        tag = "transfer"
    elseif kind=="BROADCAST"
        event_type,message_kind = "BCAST","BCAST"
        process.broadcast[p] += 1
    end
    id = length(sim.messages)+1
    message = Message(
        id=id,
        kind=message_kind,
        source=p,
        tag=tag,
        amount=amount,
        stamp=message_kind=="BCAST" ? copy(process.broadcast) : Int[]
    )
    push!(sim.messages,message)
    message.send_event = record_event!(sim,p,event_type,(message=id,destination=destination))
    message.send_time = sim.current_time
    destinations = message_kind=="BCAST" ? [q for q in eachindex(sim.names) if q!=p] : [destination]
    for q in destinations
        index = dispatch_packet!(sim,p,q,Packet(packet_type=:copy,message=id))
        push!(message.copies,index)
        push!(sim.copies,index)
    end
end
function process_action!(sim,p,action,sender=0)
    if action.kind=="LOCAL"
        record_event!(sim,p,"LOCAL",(label=action.text,))
    elseif action.kind=="SNAPSHOT"
        initiate_snapshot!(sim,p,action.text)
    else
        send_message!(sim,p,action,sender)
    end
end
function start_snapshot!(sim,name)
    if !haskey(sim.snapshot_by_name,name)
        push!(sim.snapshots,new_snapshot(name,sim.current_time,length(sim.names)))
        sim.snapshot_by_name[name] = length(sim.snapshots)
    end
    sim.snapshot_by_name[name]
end
function record_snapshot!(sim,index,p,reason)
    snapshot = sim.snapshots[index]
    record_state!(snapshot,sim.processes[p],p,sim.current_time,reason)
    push!(sim.timeline,(kind=:snapshot,index=index,process=p,time=sim.current_time))
    for q in eachindex(sim.names)
        p==q && continue
        dispatch_packet!(sim,p,q,Packet(packet_type=:marker,snapshot=index))
        snapshot.markers[(p,q)] = (sent=sim.current_time,accepted=0)
    end
end
function initiate_snapshot!(sim,p,name)
    index = start_snapshot!(sim,name)
    snapshot = sim.snapshots[index]
    if !isnothing(snapshot.records[p])
        push!(snapshot.ignored,(p,sim.current_time))
    else
        record_snapshot!(sim,index,p,"initiate")
    end
end
function accept_marker!(sim,p,packet)
    snapshot = sim.snapshots[packet.snapshot]
    if isnothing(snapshot.records[p])
        record_snapshot!(sim,packet.snapshot,p,"marker $(sim.names[packet.source])")
    end
    accepted_marker!(snapshot,packet.source,p,sim.current_time,length(sim.names))
end
function deliver!(sim,p,index)
    packet,process = sim.packets[index],sim.processes[p]
    message = sim.messages[packet.message]
    message.kind=="BCAST" && (process.broadcast[packet.source]+=1)
    process.balance += message.amount
    process.incoming += message.amount
    packet.recv_event = record_event!(sim,p,"RECV",(copy=index,),message.send_event)
    packet.delivery_time = sim.current_time
    push!(process.delivered,index)
    for action in reaction_actions(process,message.tag)
        process_action!(sim,p,action,packet.source)
    end
end
function can_deliver(sim,p,index)
    packet = sim.packets[index]
    broadcast_deliverable(sim.messages[packet.message].stamp,sim.processes[p].broadcast,packet.source)
end
function release_causal_waits!(sim,p)
    process = sim.processes[p]
    while true
        position = findfirst(index->can_deliver(sim,p,index),process.holdback)
        isnothing(position) && break
        index = process.holdback[position]
        deleteat!(process.holdback,position)
        deliver!(sim,p,index)
    end
end
function accept_packet!(sim,p,index)
    packet,process = sim.packets[index],sim.processes[p]
    source = packet.source
    process.next_sequence[source] += 1
    if packet.packet_type==:marker
        accept_marker!(sim,p,packet)
        return
    end
    for snapshot in sim.snapshots
        if !isnothing(snapshot.records[p]) && !((source,p) in snapshot.accepted)
            push!(snapshot.channel_states[(source,p)],index)
        end
    end
    message = sim.messages[packet.message]
    if message.kind=="P2P" || sim.raw
        deliver!(sim,p,index)
    elseif can_deliver(sim,p,index)
        deliver!(sim,p,index)
        release_causal_waits!(sim,p)
    else
        packet.causal_wait = true
        packet.missing = missing_indices(message.stamp,process.broadcast,source)
        push!(process.holdback,index)
    end
end
function receive_packet!(sim,p,index)
    packet,process = sim.packets[index],sim.processes[p]
    source = packet.source
    if sim.raw
        accept_packet!(sim,p,index)
    elseif packet.sequence!=process.next_sequence[source]
        packet.fifo_wait = true
        process.reorder[source][packet.sequence] = index
        sim.channels[(source,p)].buffered += 1
    else
        accept_packet!(sim,p,index)
        buffer = process.reorder[source]
        while haskey(buffer,process.next_sequence[source])
            following = pop!(buffer,process.next_sequence[source])
            accept_packet!(sim,p,following)
        end
    end
    process.max_held = max(process.max_held,held_count(process))
end
function run_simulation!(sim)
    while !isempty(sim.queue) && sim.queue[1].time<=sim.params["end"]
        item = dequeue!(sim)
        sim.current_time = item.time
        if item.kind==:action
            process_action!(sim,item.process,item.payload)
        else
            receive_packet!(sim,item.process,item.payload)
        end
    end
    sim
end
yes(value) = value ? "yes" : "no"
msg_name(id) = "m$id"
event_name(sim,event) = "$(sim.names[event.process]).$(event.local_number)"
initial_total(sim) = sum(process.initial for process in sim.processes)
cut_details(sim,cut) = cut_details(cut,sim.processes,sim.packets,sim.copies,sim.messages,sim.events)
copy_label(sim,index) = copy_label(sim.packets[index],sim.messages,sim.names)
function trace_lines(sim)
    lines = String[]
    for event in sim.events
        kind,detail = event.kind,event.details
        info = if kind=="LOCAL"
            detail.label
        elseif kind=="NOFUNDS"
            "to $(sim.names[detail.destination]) amount $(detail.amount) balance $(detail.balance)"
        elseif kind in ("SEND","BCAST")
            message = sim.messages[detail.message]
            text = kind=="BCAST" ? "m$(message.id) tag $(message.tag)" : "m$(message.id) to $(sim.names[detail.destination]) tag $(message.tag)"
            message.amount>0 && (text*=" amount $(message.amount) balance $(event.balance)")
            text
        else
            packet = sim.packets[detail.copy]
            message = sim.messages[packet.message]
            text = "m$(message.id) from $(sim.names[packet.source]) tag $(message.tag)"
            message.amount>0 && (text*=" amount $(message.amount) balance $(event.balance)")
            text
        end
        push!(
            lines,
            "$(event.number) t=$(event.time) $(event_name(sim,event)) $kind $info L=$(event.lamport) V=$(vector_text(event.vector))"
        )
    end
    delivered = count(i->sim.packets[i].recv_event!=0,sim.copies)
    push!(
        lines,
        "SUMMARY events $(length(sim.events)) messages $(length(sim.messages)) copies $(length(sim.copies)) delivered $delivered undelivered $(length(sim.copies)-delivered) draws $(sim.random.draws)"
    )
    for (p,process) in enumerate(sim.processes)
        push!(
            lines,
            "FINAL $(sim.names[p]) events $(length(process.events)) L=$(process.lamport) V=$(vector_text(process.vector)) B=$(vector_text(process.broadcast)) balance $(process.balance) in $(process.incoming) out $(process.outgoing) refused $(process.refused) min $(process.min_balance)"
        )
    end
    for (p,process) in enumerate(sim.processes)
        counts = join(
            ("$(lowercase(kind)) $(get(process.types,kind,0))" for kind in (
                "LOCAL",
                "NOFUNDS",
                "SEND",
                "BCAST",
                "RECV"
            )),
            " "
        )
        push!(lines,"COUNTS $(sim.names[p]) $counts")
    end
    lines
end
function wait_mode(sim,packet)
    !packet.causal_wait && return packet.fifo_wait ? "fifo" : "direct"
    missing = join(sim.names[packet.missing],",")
    (packet.fifo_wait ? "fifo+causal " : "causal ")*missing
end
function broadcast_history(sim,p)
    history = Int[]
    for index in sim.processes[p].events
        event = sim.events[index]
        if event.kind=="BCAST"
            push!(history,event.details.message)
        elseif event.kind=="RECV"
            message = sim.messages[sim.packets[event.details.copy].message]
            message.kind=="BCAST" && push!(history,message.id)
        end
    end
    history
end
function deliveries_lines(sim)
    lines = String[]
    for (p,process) in enumerate(sim.processes)
        push!(lines,"PROCESS $(sim.names[p])")
        modes,total_wait,max_wait = zeros(Int,4),0,0
        for (number,index) in enumerate(process.delivered)
            packet = sim.packets[index]
            message = sim.messages[packet.message]
            wait = packet.delivery_time-packet.arrival_time
            total_wait += wait
            max_wait = max(max_wait,wait)
            mode = packet.fifo_wait ? (packet.causal_wait ? 4 : 2) : (packet.causal_wait ? 3 : 1)
            modes[mode] += 1
            push!(
                lines,
                "$number m$(message.id) from $(sim.names[packet.source]) $(message.kind) tag $(message.tag) sent $(message.send_time) arrived $(packet.arrival_time) delivered $(packet.delivery_time) wait $wait $(wait_mode(sim,packet))"
            )
        end
        for index in sim.copies
            packet = sim.packets[index]
            packet.destination==p && packet.arrival_time<=sim.params["end"] && packet.recv_event==0 || continue
            message = sim.messages[packet.message]
            place = haskey(
                process.reorder[packet.source],
                packet.sequence
            ) ? "fifo" : "causal "*join(sim.names[packet.missing],",")
            push!(
                lines,
                "HELD m$(message.id) from $(sim.names[packet.source]) $(message.kind) tag $(message.tag) sent $(message.send_time) arrived $(packet.arrival_time) $place"
            )
        end
        for index in sim.copies
            packet = sim.packets[index]
            packet.destination==p && packet.arrival_time>sim.params["end"] || continue
            message = sim.messages[packet.message]
            push!(
                lines,
                "TRANSIT m$(message.id) from $(sim.names[packet.source]) $(message.kind) tag $(message.tag) sent $(message.send_time) arrival $(packet.arrival_time)"
            )
        end
        push!(
            lines,
            "TOTAL delivered $(length(process.delivered)) direct $(modes[1]) fifo $(modes[2]) causal $(modes[3]) both $(modes[4]) wait $total_wait max_wait $max_wait max_held $(process.max_held)"
        )
        history = broadcast_history(sim,p)
        push!(lines,"BCASTS "*(isempty(history) ? "none" : join(msg_name.(history)," ")))
    end
    for pair in sim.channel_order
        c = sim.channels[pair]
        push!(
            lines,
            "CHANNEL $(sim.names[pair[1]])->$(sim.names[pair[2]]) $(c.kind) $(delay_notation(c)) messages $(c.messages) markers $(c.markers) buffered $(c.buffered) max_delay $(c.max_delay) entries $(c.entries)"
        )
    end
    tags = sort(unique([sim.messages[sim.packets[i].message].tag for i in sim.copies]))
    for tag in tags
        tagged = [i for i in sim.copies if sim.messages[sim.packets[i].message].tag==tag]
        completed = [i for i in tagged if sim.packets[i].recv_event!=0]
        latencies = [sim.packets[i].delivery_time-sim.messages[sim.packets[i].message].send_time for i in completed]
        push!(
            lines,
            "TAG $tag copies $(length(tagged)) delivered $(length(completed)) latency $(sum(latencies)) max $(maximum(latencies;init=0))"
        )
    end
    broadcasts = [message for message in sim.messages if message.kind=="BCAST"]
    for message in broadcasts
        completed = [sim.packets[i].delivery_time for i in message.copies if sim.packets[i].recv_event!=0]
        stable = length(completed)==length(message.copies) ? string(maximum(completed)) : "none"
        push!(
            lines,
            "STABLE m$(message.id) $(sim.names[message.source]) tag $(message.tag) sent $(message.send_time) stable $stable"
        )
    end
    disagreements = 0
    for a in 1:length(broadcasts),b in a+1:length(broadcasts)
        first,second = broadcasts[a].id,broadcasts[b].id
        earlier,later = Int[],Int[]
        for p in eachindex(sim.names)
            history = broadcast_history(sim,p)
            i,j = findfirst(==(first),history),findfirst(==(second),history)
            if !isnothing(i) && !isnothing(j)
                push!(i<j ? earlier : later,p)
            end
        end
        if !isempty(earlier) && !isempty(later)
            disagreements += 1
            push!(
                lines,
                "DISAGREE m$first m$second $(join(sim.names[earlier],",")) $(join(sim.names[later],","))"
            )
        end
    end
    push!(lines,"DISAGREEMENTS $disagreements")
    lines
end
consistent_verdict(sim,details) = details.consistent ? "yes" : "no "*join(
    (copy_label(sim,i) for i in details.orphans),
    " "
)
function snapshots_lines(normal,raw)
    lines = String[]
    for sim in (normal,raw),snapshot in sim.snapshots
        cut = snapshot_cut(snapshot)
        details = cut_details(sim,cut)
        entries,pending = recorded_copies(snapshot,sim.channel_order)
        channel_money = sum((sim.messages[sim.packets[i].message].amount for i in entries);init=0)
        balances = sum(record.balance for record in snapshot.records)
        money = balances+channel_money
        initial = initial_total(sim)
        if sim.raw
            push!(
                lines,
                "RAW $(snapshot.name) completed $(snapshot.complete) cut $(vector_text(cut)) consistent $(consistent_verdict(sim,details)) money $money conserved $(yes(money==initial))"
            )
            continue
        end
        push!(lines,"SNAPSHOT $(snapshot.name) started $(snapshot.start) completed $(snapshot.complete)")
        for (p,record) in enumerate(snapshot.records)
            pending_text = isempty(record.pending) ? "none" : join(
                (msg_name(sim.packets[i].message) for i in record.pending),
                " "
            )
            push!(
                lines,
                "RECORD $(sim.names[p]) t=$(record.time) $(record.reason) balance $(record.balance) L=$(record.lamport) V=$(vector_text(record.vector)) pending $pending_text"
            )
        end
        for pair in sim.channel_order
            state = snapshot.channel_states[pair]
            marker = snapshot.markers[pair]
            values = String[]
            for i in state
                message = sim.messages[sim.packets[i].message]
                push!(values,"m$(message.id)"*(message.amount==0 ? "" : ":$(message.amount)"))
            end
            text = isempty(values) ? "empty" : join(values," ")
            push!(
                lines,
                "CHANNEL $(sim.names[pair[1]])->$(sim.names[pair[2]]) marker $(marker.sent) $(marker.accepted) state $text"
            )
        end
        append!(lines,["IGNORED $(sim.names[p]) t=$time" for (p,time) in snapshot.ignored])
        push!(lines,"CUT $(vector_text(cut)) consistent $(consistent_verdict(sim,details)) vector $(yes(vector_consistent(snapshot,cut)))",
            "TRANSIT channels $(length(entries)) pending $(length(pending)) cut $(length(details.transit)) match $(yes(transit_match(entries,pending,details.transit)))",
            "MONEY balances $balances channels $channel_money total $money initial $initial conserved $(yes(money==initial))")
    end
    lines
end
function range_notation(sim,path)
    isempty(path) && return "-"
    parts = String[]
    first,last = sim.events[path[1]],sim.events[path[1]]
    function append_part(a,b)
        push!(
            parts,
            a.number==b.number ? event_name(
                sim,
                a
            ) : "$(sim.names[a.process]).$(a.local_number)-$(b.local_number)"
        )
    end
    for index in path[2:end]
        event = sim.events[index]
        if event.process==last.process && event.local_number==last.local_number+1
            last = event
        else
            append_part(first,last)
            first,last = event,event
        end
    end
    append_part(first,last)
    join(parts," ")
end
function causal_longest_chain(sim)
    current = sim.events[argmax([event.lamport for event in sim.events])]
    chain = [current.number]
    while current.lamport>1
        previous = 0
        if current.kind=="RECV"
            candidate = sim.messages[sim.packets[current.details.copy].message].send_event
            sim.events[candidate].lamport==current.lamport-1 && (previous=candidate)
        end
        previous==0 && (previous=sim.processes[current.process].events[current.local_number-1])
        push!(chain,previous)
        current = sim.events[previous]
    end
    reverse(chain)
end
function analysis_lines(sim,raw)
    lines = String[]
    edges = graph_edges(sim.events,sim.processes,sim.packets,sim.copies,sim.messages)
    indexed = Dict(event_name(sim,event)=>event.number for event in sim.events)
    for (first_name,second_name) in sim.params["compare"]
        first,second = sim.events[indexed[first_name]],sim.events[indexed[second_name]]
        vector_relation = relation(first.vector,second.vector)
        forward = graph_path(first.number,second.number,edges)
        reverse_path = isnothing(forward) ? graph_path(second.number,first.number,edges) : nothing
        graph_relation = !isnothing(forward) ? "->" : !isnothing(reverse_path) ? "<-" : "||"
        push!(
            lines,
            "COMPARE $first_name $vector_relation $second_name L=$(first.lamport),$(second.lamport) graph $graph_relation agree $(yes(vector_relation==graph_relation))"
        )
        path = isnothing(forward) ? reverse_path : forward
        if !isnothing(path)
            messages = count(
                pair->sim.events[pair[1]].process!=sim.events[pair[2]].process,
                zip(path,path[2:end])
            )
            push!(lines,"PATH length $(length(path)) messages $messages $(range_notation(sim,path))")
        end
        for event in (first,second)
            future = [count(
                i->sim.events[i].vector[event.process]<event.local_number,
                process.events
            ) for process in sim.processes]
            push!(
                lines,
                "WINDOW $(event_name(sim,event)) past $(vector_text(event.vector)) future $(vector_text(future))"
            )
        end
    end
    summary = concurrency_statistics(sim.events,length(sim.names))
    push!(
        lines,
        "CONCURRENCY events $(length(sim.events)) pairs $(summary.pairs) ordered $(summary.ordered) concurrent $(summary.concurrent) same_lamport $(summary.same_lamport) inversions $(summary.inversions)"
    )
    for p in eachindex(sim.names),q in p+1:length(sim.names)
        push!(lines,"PAIR $(sim.names[p]) $(sim.names[q]) $(summary.by_pair[p,q])")
    end
    chain = causal_longest_chain(sim)
    push!(lines,"CHAIN length $(length(chain)) $(range_notation(sim,chain))")
    races,violations = races_and_violations(sim.processes,sim.packets,sim.messages,sim.events)
    for item in races
        a,b = sim.packets[item.a],sim.packets[item.b]
        push!(
            lines,
            "RACE $(sim.names[item.process]) m$(a.message) $(sim.names[a.source]) m$(b.message) $(sim.names[b.source])"
        )
    end
    push!(lines,"RACES $(length(races))")
    for item in violations
        a,b = sim.packets[item.a],sim.packets[item.b]
        push!(
            lines,
            "VIOLATION $(sim.names[item.process]) m$(a.message) $(sim.names[a.source]) overtook m$(b.message) $(sim.names[b.source])"
        )
    end
    fifo_count(items,model) = count(item->model.packets[item.a].source==model.packets[item.b].source,items)
    push!(lines,"VIOLATIONS causal $(length(violations)) fifo $(fifo_count(violations,sim))")
    _,raw_violations = races_and_violations(raw.processes,raw.packets,raw.messages,raw.events)
    raw_delivered = count(i->raw.packets[i].recv_event!=0,raw.copies)
    push!(
        lines,
        "RAW events $(length(raw.events)) delivered $raw_delivered causal $(length(raw_violations)) fifo $(fifo_count(raw_violations,raw))"
    )
    for cut in sim.params["cuts"]
        details = cut_details(sim,cut)
        verdict = details.consistent ? "consistent" : "inconsistent orphans "*join(
            (copy_label(sim,i) for i in details.orphans),
            " "
        )
        push!(
            lines,
            "CUT $(vector_text(cut)) $verdict transit $(length(details.transit)) money $(details.money) initial $(initial_total(sim))"
        )
    end
    enumeration = enumerate_cuts(sim.processes,sim.events,sim.params["cutcount"],sim.params["predicates"])
    push!(
        lines,
        "CUTCOUNT t=$(sim.params["cutcount"]) events $(vector_text(enumeration.limits)) product $(enumeration.product) consistent $(enumeration.consistent)",
        "LEVELS "*join(enumeration.levels," ")
    )
    for (threshold,record) in zip(sim.params["predicates"],enumeration.predicates)
        push!(
            lines,
            "PREDICATE transit>=$threshold cuts $(record.cuts) possibly $(yes(record.possibly)) definitely $(yes(record.definitely))"
        )
    end
    lines
end
function write_at!(line,position,text)
    required = position+length(text)
    required>length(line) && append!(line,fill(' ',required-length(line)))
    for (offset,char) in enumerate(text)
        line[position+offset] = char
    end
end
function diagram_header(letter,names)
    line = fill(' ',8length(names)-1)
    write_at!(line,0,"    $letter ")
    for (p,name) in enumerate(names)
        write_at!(line,8p-2,name)
    end
    rstrip(join(line))
end
function diagram_entry(sim,value,p,kind,detail)
    columns = [8q-2 for q in eachindex(sim.names)]
    line = fill(' ',columns[end]+1)
    write_at!(line,0,lpad(value,5)*" ")
    for column in columns
        line[column+1] = '|'
    end
    own = columns[p]
    symbols = Dict("LOCAL"=>'*',"NOFUNDS"=>'x',"SEND"=>'S',"BCAST"=>'B',"RECV"=>'R',"snapshot"=>'#')
    line[own+1] = symbols[kind]
    if kind=="snapshot"
        write_at!(line,own+1,sim.snapshots[detail.snapshot].name)
    elseif kind in ("SEND","BCAST")
        write_at!(line,own+1,msg_name(detail.message))
    elseif kind=="RECV"
        packet = sim.packets[detail.copy]
        other = columns[packet.source]
        low,high = minmax(own,other)
        for position in low+1:high-1
            line[position+1] = position in columns ? '+' : '-'
        end
        line[(other<own ? high-1 : low+1)+1] = other<own ? '>' : '<'
        write_at!(line,low+2,msg_name(packet.message))
        line[own+1] = 'R'
    end
    rstrip(join(line))
end
function diagram_lines(sim)
    lines = [diagram_header("t",sim.names)]
    for item in sim.timeline
        if item.kind==:snapshot
            push!(lines,diagram_entry(sim,item.time,item.process,"snapshot",(snapshot=item.index,)))
        else
            event = sim.events[item.index]
            push!(lines,diagram_entry(sim,event.time,event.process,event.kind,event.details))
        end
    end
    push!(lines,diagram_header("L",sim.names))
    for event in sort(sim.events;by=event->(event.lamport,event.process))
        push!(lines,diagram_entry(sim,event.lamport,event.process,event.kind,event.details))
    end
    lines
end
function save_output(name,lines)
    mkpath("output")
    open(joinpath("output",name),"w") do io
        for line in lines
            println(io,line)
        end
    end
end
function main()
    names,channels,order = read_topology()
    scripts,params = read_scripts(names),load_params()
    normal = run_simulation!(make_simulation(names,channels,order,scripts,params))
    raw = run_simulation!(make_simulation(names,channels,order,scripts,params,true))
    save_output("trace.txt",trace_lines(normal))
    save_output("deliveries.txt",deliveries_lines(normal))
    save_output("snapshots.txt",snapshots_lines(normal,raw))
    save_output("analysis.txt",analysis_lines(normal,raw))
    save_output("diagram.txt",diagram_lines(normal))
end
main()
