const VARIANTS = ["ul","ur","dl","dr"]
function mark_conflicts(orders,upper,node_count,position)
    marked = Set{Tuple{Int,Int}}()
    for layer in 1:length(orders)-1
        above,below = orders[layer],orders[layer+1]
        first_bound,start = 0,1
        for (last,v) in enumerate(below)
            inner = v > node_count && upper[v][1] > node_count
            (!inner && last != length(below)) && continue
            last_bound = inner ? position[upper[v][1]] : length(above)-1
            for w in below[start:last], u in upper[w]
                (position[u] < first_bound || position[u] > last_bound) && push!(marked,(u,w))
            end
            start,first_bound = last+1,last_bound
        end
    end
    marked
end
function alignment(variant,orders,upper,lower,marked,vertex_count)
    scan = [variant[2] == 'l' ? copy(layer) : reverse(layer) for layer in orders]
    rank = positions(scan)
    root,align = collect(1:vertex_count),collect(1:vertex_count)
    layers = variant[1] == 'u' ? collect(eachindex(orders)) : reverse(collect(eachindex(orders)))
    reference = variant[1] == 'u' ? upper : lower
    for layer in layers[2:end]
        boundary = -1
        for v in scan[layer]
            neighbors = sort(reference[v];by=u -> rank[u])
            isempty(neighbors) && continue
            for middle in ((length(neighbors)-1)÷2+1,length(neighbors)÷2+1)
                u = neighbors[middle]
                segment = variant[1] == 'u' ? (u,v) : (v,u)
                if align[v] == v && !(segment in marked) && boundary < rank[u]
                    align[u] = v
                    root[v] = root[u]
                    align[v] = root[v]
                    boundary = rank[u]
                end
            end
        end
    end
    root,scan
end
function compact(root,scan,variant,left,right,node_count,settings)
    blocks = sort(unique(root))
    outgoing,incoming = [Dict{Int,Int}() for _ in root],[Dict{Int,Int}() for _ in root]
    for layer in scan, i in 1:length(layer)-1
        first,second = layer[i],layer[i+1]
        a,b = variant[2] == 'l' ? (first,second) : (second,first)
        gap = a <= node_count && b <= node_count ? settings["node_sep"] : settings["dummy_sep"]
        distance = right[a]+left[b]+1+gap
        origin,target = root[first],root[second]
        distance = max(distance,get(outgoing[origin],target,distance))
        outgoing[origin][target] = distance
        incoming[target][origin] = distance
    end
    pending = length.(incoming)
    ready = [b for b in blocks if pending[b] == 0]
    ordered = Int[]
    y1,y2 = zeros(Int,length(root)),zeros(Int,length(root))
    while !isempty(ready)
        block = pop!(ready)
        push!(ordered,block)
        y1[block] = maximum((y1[p]+d for (p,d) in incoming[block]);init=0)
        for following in sort(collect(keys(outgoing[block])))
            pending[following] -= 1
            pending[following] == 0 && push!(ready,following)
        end
    end
    for block in reverse(ordered)
        coordinate = y1[block]
        isempty(outgoing[block]) || (coordinate = max(coordinate,minimum(y2[b]-d for (b,d) in outgoing[block])))
        y2[block] = coordinate
    end
    sign = variant[2] == 'l' ? 1 : -1
    [sign*y2[b] for b in root],length(blocks)
end
function assign_coordinates(orders,upper,lower,widths,node_count,settings)
    vertical = settings["direction"] in ("TB","BT")
    left = vertical ? [(w-1)÷2 for w in widths] : zeros(Int,length(widths))
    right = vertical ? widths .- 1 .- left : zeros(Int,length(widths))
    conflicts = mark_conflicts(orders,upper,node_count,positions(orders))
    layouts,blocks,bounds,spans = Dict{String,Vector{Int}}(),Dict{String,Int}(),Dict{String,Tuple{Int,Int}}(),Dict{String,Int}()
    for variant in VARIANTS
        root,scan = alignment(variant,orders,upper,lower,conflicts,length(widths))
        layout,block_count = compact(root,scan,variant,left,right,node_count,settings)
        low,high = minimum(layout-left),maximum(layout+right)
        layouts[variant],blocks[variant],bounds[variant],spans[variant] = layout,block_count,(low,high),high-low+1
    end
    smallest = VARIANTS[argmin([spans[k] for k in VARIANTS])]
    aligned = Dict{String,Vector{Int}}()
    for variant in VARIANTS
        side = variant[2] == 'l' ? 1 : 2
        shift = bounds[smallest][side]-bounds[variant][side]
        aligned[variant] = layouts[variant] .+ shift
    end
    x = [begin
        values = sort([aligned[k][v] for k in VARIANTS])
        fld(values[2]+values[3],2)
    end for v in eachindex(widths)]
    x .-= minimum(x-left)
    (x=x,left=left,right=right,aligned=aligned,blocks=blocks,widths=spans,smallest=smallest,conflicts=conflicts)
end
