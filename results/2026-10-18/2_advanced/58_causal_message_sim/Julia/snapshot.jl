Base.@kwdef mutable struct Snapshot
    name::String
    start::Int
    complete::Int = 0
    records::Vector{Any}
    channel_states::Dict{Tuple{Int,Int},Vector{Int}}
    markers::Dict{Tuple{Int,Int},NamedTuple} = Dict{Tuple{Int,Int},NamedTuple}()
    accepted::Set{Tuple{Int,Int}} = Set{Tuple{Int,Int}}()
    ignored::Vector{Tuple{Int,Int}} = Tuple{Int,Int}[]
end
function new_snapshot(name,time,n)
    Snapshot(
        name=name,
        start=time,
        records=Any[nothing for _ in 1:n],
        channel_states=Dict((p,q)=>Int[] for p in 1:n for q in 1:n if p!=q)
    )
end
function record_state!(snapshot,process,p,time,reason)
    snapshot.records[p] = (
        time=time,
        reason=reason,
        balance=process.balance,
        lamport=process.lamport,
        vector=copy(process.vector),
        pending=copy(process.holdback)
    )
end
function accepted_marker!(snapshot,source,destination,time,n)
    pair = (source,destination)
    push!(snapshot.accepted,pair)
    snapshot.markers[pair] = (;snapshot.markers[pair]...,accepted=time)
    length(snapshot.accepted)==n*(n-1) && (snapshot.complete=time)
end
snapshot_cut(snapshot) = [record.vector[p] for (p,record) in enumerate(snapshot.records)]
function cut_details(cut,processes,packets,copies,messages,events)
    orphans,transit = Int[],Int[]
    for index in copies
        packet = packets[index]
        sending = events[messages[packet.message].send_event]
        sent = sending.local_number<=cut[packet.source]
        received = packet.recv_event!=0 && events[packet.recv_event].local_number<=cut[packet.destination]
        received && !sent && push!(orphans,index)
        sent && !received && push!(transit,index)
    end
    balances = sum(balance_at_cut(process,cut[p],events) for (p,process) in enumerate(processes))
    money = balances+sum((messages[packets[i].message].amount for i in transit);init=0)
    (orphans=orphans,transit=transit,balances=balances,money=money,consistent=isempty(orphans))
end
function recorded_copies(snapshot,channel_order)
    entries = Int[]
    for pair in channel_order
        append!(entries,snapshot.channel_states[pair])
    end
    pending = Int[]
    for record in snapshot.records
        append!(pending,record.pending)
    end
    entries,pending
end
transit_match(entries,pending,transit) = sort(vcat(entries,pending))==sort(transit)
vector_consistent(snapshot,cut) = all(record->less_equal(record.vector,cut),snapshot.records)
copy_label(packet,messages,names) = "m$(messages[packet.message].id)->$(names[packet.destination])"
