function positions(orders)
    result = zeros(Int,sum(length,orders))
    for layer in orders, (i,v) in enumerate(layer)
        result[v] = i-1
    end
    result
end
function accumulator(segments,position,lower_size)
    capacity = 1
    while capacity < lower_size
        capacity *= 2
    end
    tree = zeros(Int,2*capacity-1)
    total = 0
    pairs = sort([(position[p],position[q]) for (p,q,_) in segments])
    for (_,lower) in pairs
        index = lower+capacity
        tree[index] += 1
        while index > 1
            iseven(index) && (total += tree[index+1])
            index ÷= 2
            tree[index] += 1
        end
    end
    total
end
function brute_crossings(segments,position)
    total = 0
    for i in eachindex(segments), j in (i+1):length(segments)
        p,q,_ = segments[i]
        u,v,_ = segments[j]
        total += (position[p]-position[u])*(position[q]-position[v]) < 0
    end
    total
end
gap_counts(gaps,orders) = [accumulator(segments,positions(orders),length(orders[i+1])) for (i,segments) in enumerate(gaps)]
total_crossings(gaps,orders) = sum(gap_counts(gaps,orders);init=0)
function local_crossings(gaps,orders,layer)
    position = positions(orders)
    sum((accumulator(gaps[i],position,length(orders[i+1])) for i in (layer-1,layer) if 1 <= i <= length(gaps));init=0)
end
function adjacent_cost(a,b,upper,lower,position)
    total = 0
    for neighbors in (upper,lower), u in neighbors[a], v in neighbors[b]
        total += position[u] > position[v]
    end
    total
end
