const MESSAGE_TYPES = ("RV","RVR","AE","AER","TN")
const MESSAGE_FIELDS = ("sent","delivered","inflight","partition","rule","loss","down")
const MESSAGE_REASONS = ("partition","rule","loss","down")
mutable struct NetworkLink
    delay::Int
    loss::Int
    passed::Int
    drops::Vector{Tuple{String,Int,Int}}
    stats::Vector{Int}
end
struct RaftMessage
    kind::String
    source::Int
    destination::Int
    term::Int
    data::NamedTuple
end
mutable struct RaftNetwork
    links::Dict{Tuple{Int,Int},NetworkLink}
    groups::Vector{Int}
    total::Vector{Int}
    by_type::Dict{String,Vector{Int}}
    queue::Vector{Tuple{Int,Int,Int,RaftMessage}}
    serial::Int
end
function read_network(n)
    lines = split.(readlines("input/network.txt"))
    default = parse(Int,lines[1][2])
    links = Dict((a,b)=>NetworkLink(
        default,
        0,
        0,
        Tuple{String,Int,Int}[],
        zeros(Int,7)
    ) for a in 1:n for b in 1:n if a!=b)
    for f in lines[2:end],a in 1:n,b in 1:n
        (a==b || !(f[2]=="*" || parse(Int,f[2])==a) || !(f[3]=="*" || parse(Int,f[3])==b)) && continue
        link = links[(a,b)]
        if f[1]=="DELAY"
            link.delay = parse(Int,f[4])
        elseif f[1]=="LOSS"
            link.loss = parse(Int,f[4])
        else
            push!(link.drops,(String(f[4]),parse(Int,f[5]),parse(Int,f[6])))
        end
    end
    RaftNetwork(
        links,
        zeros(Int,n),
        zeros(Int,7),
        Dict(k=>zeros(Int,7) for k in MESSAGE_TYPES),
        Tuple{Int,Int,Int,RaftMessage}[],
        0
    )
end
function network_count!(network,message,field,amount=1)
    i = findfirst(==(field),MESSAGE_FIELDS)
    network.total[i] += amount
    network.by_type[message.kind][i] += amount
    network.links[(message.source,message.destination)].stats[i] += amount
end
separated(network,a,b) = network.groups[a]!=network.groups[b]
function heap_push!(queue,event)
    push!(queue,event)
    i = length(queue)
    while i>1
        p = i÷2
        queue[p][1:3]<=event[1:3] && break
        queue[i] = queue[p]
        i = p
    end
    queue[i] = event
end
function heap_pop!(queue)
    first,last = queue[1],pop!(queue)
    isempty(queue) && return first
    i,n = 1,length(queue)
    while 2i<=n
        child = 2i
        child<n && queue[child+1][1:3]<queue[child][1:3] && (child+=1)
        last[1:3]<=queue[child][1:3] && break
        queue[i] = queue[child]
        i = child
    end
    queue[i] = last
    first
end
function network_send!(network,time,source,destination,term,kind,data)
    message = RaftMessage(kind,source,destination,term,data)
    network.serial += 1
    network_count!(network,message,"sent")
    link = network.links[(source,destination)]
    if separated(network,source,destination)
        network_count!(network,message,"partition")
        return
    end
    if any(d->d[1] in (kind,"ALL") && d[2]<=time<=d[3],link.drops)
        network_count!(network,message,"rule")
        return
    end
    link.passed += 1
    if link.loss>0 && link.passed%link.loss==0
        network_count!(network,message,"loss")
        return
    end
    network_count!(network,message,"inflight")
    heap_push!(network.queue,(time+link.delay,source,network.serial,message))
end
function network_arrivals!(network,time)
    messages = RaftMessage[]
    while !isempty(network.queue) && network.queue[1][1]==time
        _,_,_,message = heap_pop!(network.queue)
        network_count!(network,message,"inflight",-1)
        push!(messages,message)
    end
    messages
end
function network_deliver!(network,message,up)
    if !up
        network_count!(network,message,"down")
        return false
    elseif separated(network,message.source,message.destination)
        network_count!(network,message,"partition")
        return false
    end
    network_count!(network,message,"delivered")
    true
end
