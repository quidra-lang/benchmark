function graph_edges(events,processes,packets,copies,messages)
    outgoing = [Int[] for _ in events]
    for process in processes
        for i in 1:length(process.events)-1
            push!(outgoing[process.events[i]],process.events[i+1])
        end
    end
    for i in copies
        packet = packets[i]
        packet.recv_event!=0 && push!(outgoing[messages[packet.message].send_event],packet.recv_event)
    end
    outgoing
end
function graph_path(source,target,edges)
    parent = zeros(Int,length(edges))
    parent[source] = -1
    queue,head = [source],1
    while head<=length(queue) && parent[target]==0
        current = queue[head]
        head += 1
        for next in edges[current]
            if parent[next]==0
                parent[next] = current
                push!(queue,next)
            end
        end
    end
    parent[target]==0 && return nothing
    path,cursor = Int[],target
    while cursor!=-1
        push!(path,cursor)
        cursor = parent[cursor]
    end
    reverse(path)
end
function concurrency_statistics(events,n)
    ordered,concurrent,same_lamport,inversions = 0,0,0,0
    by_pair = zeros(Int,n,n)
    for i in 1:length(events),j in i+1:length(events)
        a,b = events[i],events[j]
        if relation(a.vector,b.vector)=="||"
            concurrent += 1
            same_lamport += a.lamport==b.lamport
            if a.process!=b.process
                p,q = minmax(a.process,b.process)
                by_pair[p,q] += 1
            end
        else
            ordered += 1
        end
        (a.time-b.time)*(a.lamport-b.lamport)<0 && (inversions+=1)
    end
    (
        pairs=length(events)*(length(events)-1)÷2,
        ordered=ordered,
        concurrent=concurrent,
        same_lamport=same_lamport,
        inversions=inversions,
        by_pair=by_pair
    )
end
function races_and_violations(processes,packets,messages,events)
    races,violations = NamedTuple[],NamedTuple[]
    for (p,process) in enumerate(processes)
        delivered = process.delivered
        for j in 1:length(delivered)-1
            a,b = delivered[j],delivered[j+1]
            relation(
                events[messages[packets[a].message].send_event].vector,
                events[messages[packets[b].message].send_event].vector
            )=="||" && push!(races,(process=p,a=a,b=b))
        end
        for i in 1:length(delivered),j in i+1:length(delivered)
            a,b = delivered[i],delivered[j]
            relation(
                events[messages[packets[b].message].send_event].vector,
                events[messages[packets[a].message].send_event].vector
            )=="->" && push!(violations,(process=p,a=a,b=b))
        end
    end
    races,violations
end
function consistent_cut(cut,processes,events)
    all(p->cut[p]==0 || less_equal(events[processes[p].events[cut[p]]].vector,cut),eachindex(cut))
end
function enumerate_cuts(processes,events,time_limit,thresholds)
    limits = [count(i->events[i].time<=time_limit,process.events) for process in processes]
    strides = ones(Int,length(limits))
    for p in 2:length(limits)
        strides[p] = strides[p-1]*(limits[p-1]+1)
    end
    product_size = prod(limits.+1)
    cuts = [[(code÷strides[p])%(limits[p]+1) for p in eachindex(limits)] for code in 0:product_size-1]
    consistent,transit = falses(product_size),zeros(Int,product_size)
    levels = zeros(Int,sum(limits)+1)
    initial = sum(process.initial for process in processes)
    for (index,cut) in enumerate(cuts)
        consistent_cut(cut,processes,events) || continue
        consistent[index] = true
        levels[sum(cut)+1] += 1
        transit[index] = initial-sum(balance_at_cut(
            process,
            cut[p],
            events
        ) for (p,process) in enumerate(processes))
    end
    predicates = NamedTuple[]
    for threshold in thresholds
        reached = falses(product_size)
        for (index,cut) in enumerate(cuts)
            consistent[index] && transit[index]<threshold || continue
            if index==1 || any(p->cut[p]>0 && reached[index-strides[p]],eachindex(limits))
                reached[index] = true
            end
        end
        total = count(i->consistent[i] && transit[i]>=threshold,eachindex(cuts))
        push!(predicates,(cuts=total,possibly=total>0,definitely=!reached[end]))
    end
    (limits=limits,product=product_size,consistent=count(consistent),levels=levels,predicates=predicates)
end
