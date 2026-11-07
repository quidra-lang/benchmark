include("graph_io.jl")
include("acyclic_layering.jl")
include("crossing.jl")
include("coordinates.jl")
include("canvas.jl")
mutable struct LayoutEdge
    number::Int
    source::Int
    target::Int
    upper::Int
    lower::Int
    reversed::Bool
    transitive::Bool
    chain::Vector{Int}
    span::Int
    crossings::Int
    route::Vector{Tuple{Int,Int}}
    bends::Int
    length::Int
    upper_endpoint::Tuple{Int,Int}
    lower_endpoint::Tuple{Int,Int}
end
function new_edge(number,source,target)
    LayoutEdge(number,source,target,source,target,false,false,Int[],0,0,Tuple{Int,Int}[],0,0,(0,0),(0,0))
end
words(parts...) = join(string.(parts)," ")
function reachable(start,neighbors)
    found,pending = Set([start]),[start]
    while !isempty(pending)
        v = pop!(pending)
        for w in neighbors[v]
            if !(w in found)
                push!(found,w)
                push!(pending,w)
            end
        end
    end
    found
end
copy_order(orders) = copy.(orders)
function reorder_layer!(orders,layer,reference,method)
    position = positions(orders)
    current = orders[layer]
    movable = [v for v in current if !isempty(reference[v])]
    keys = Dict{Int,Tuple{Int,Int}}()
    for v in movable
        neighbors = sort(position[reference[v]])
        size = length(neighbors)
        keys[v] = method == "barycenter" ? (sum(neighbors),size) :
            (neighbors[(size-1)÷2+1]+neighbors[size÷2+1],1)
    end
    sort!(movable;alg=MergeSort,lt=(a,b) -> keys[a][1]*keys[b][2] < keys[b][1]*keys[a][2])
    index = 1
    for (i,v) in enumerate(current)
        if !isempty(reference[v])
            current[i] = movable[index]
            index += 1
        end
    end
end
function adjacent_exchanges!(orders,upper,lower)
    swaps = 0
    position = positions(orders)
    while true
        changed = false
        for layer in orders, i in 1:length(layer)-1
            a,b = layer[i],layer[i+1]
            if adjacent_cost(a,b,upper,lower,position) > adjacent_cost(b,a,upper,lower,position)
                layer[i],layer[i+1] = b,a
                position[a],position[b] = i,i-1
                swaps += 1
                changed = true
            end
        end
        changed || return swaps
    end
end
function reduce_crossings(initial,gaps,upper,lower,vertex_layer,settings)
    records,sift_records = Any[],Tuple{Int,Int,Int}[]
    random_state = settings["seed"]
    best_run,best_sweep,best_crossings = 0,0,typemax(Int)
    adopted = copy_order(initial)
    for run in 0:settings["restarts"]
        orders = copy_order(initial)
        if run > 0
            for layer in orders, j in length(layer):-1:2
                random_state = 48271*random_state % 2147483647
                k = random_state % j+1
                layer[j],layer[k] = layer[k],layer[j]
            end
        end
        crossings = total_crossings(gaps,orders)
        push!(records,(run=run,sweep=0,direction="initial",moved=0,swaps=0,crossings=crossings))
        history = [copy_order(orders)]
        local_best,local_sweep,local_order = crossings,0,copy_order(orders)
        sweep = 1
        while crossings != 0 && sweep-1 != settings["sweeps"]
            sweep-1 >= 2 && history[end] == history[end-2] && break
            before = positions(orders)
            layers = isodd(sweep) ? collect(2:length(orders)) : collect((length(orders)-1):-1:1)
            reference = isodd(sweep) ? upper : lower
            for layer in layers
                reorder_layer!(orders,layer,reference,settings["heuristic"])
            end
            after = positions(orders)
            moved = count(before .!= after)
            swaps = adjacent_exchanges!(orders,upper,lower)
            crossings = total_crossings(gaps,orders)
            push!(records,(run=run,sweep=sweep,direction=isodd(sweep) ? "down" : "up",moved=moved,swaps=swaps,crossings=crossings))
            push!(history,copy_order(orders))
            if crossings < local_best
                local_best,local_sweep,local_order = crossings,sweep,copy_order(orders)
            end
            sweep += 1
        end
        if local_best < best_crossings
            best_crossings,best_run,best_sweep,adopted = local_best,run,local_sweep,copy_order(local_order)
        end
    end
    if settings["sifting"] == "on"
        round = 0
        while true
            round += 1
            moves = 0
            for v in eachindex(vertex_layer)
                layer = vertex_layer[v]
                original = findfirst(==(v),adopted[layer])
                remaining = [w for w in adopted[layer] if w != v]
                costs = Int[]
                for position in 0:length(remaining)
                    adopted[layer] = [remaining[1:position];v;remaining[position+1:end]]
                    push!(costs,local_crossings(gaps,adopted,layer))
                end
                lowest = minimum(costs)
                chosen = costs[original] == lowest ? original : argmin(costs)
                adopted[layer] = [remaining[1:chosen-1];v;remaining[chosen:end]]
                moves += chosen != original
            end
            push!(sift_records,(round,moves,total_crossings(gaps,adopted)))
            moves == 0 && break
        end
    end
    (orders=adopted,records=records,sift=sift_records,best_run=best_run,best_sweep=best_sweep,best_crossings=best_crossings)
end
function assign_tracks(segments,x,settings)
    bent = [s for s in segments if x[s[1]] != x[s[2]]]
    upper_counts = Dict{Int,Int}()
    for (p,_,_) in bent
        upper_counts[p] = get(upper_counts,p,0)+1
    end
    buses = Dict{Tuple{Int,Int},Vector{NTuple{3,Int}}}()
    for segment in bent
        p,q,_ = segment
        key = upper_counts[p] >= 2 ? (0,p) : (1,q)
        push!(get!(buses,key,NTuple{3,Int}[]),segment)
    end
    details = Any[]
    for ((kind,v),members) in buses
        values = [x[endpoint] for (p,q,_) in members for endpoint in (p,q)]
        push!(details,(low=minimum(values),high=maximum(values),kind=kind,coordinate=x[v],members=members))
    end
    sort!(details;by=b -> (b.low,b.high,b.kind,b.coordinate))
    ends = Int[]
    tracks = Dict{Tuple{Int,Int},Int}()
    for bus in details
        chosen = findfirst(e -> e+1 < bus.low,ends)
        if chosen === nothing
            push!(ends,bus.high)
            chosen = length(ends)
        else
            ends[chosen] = bus.high
        end
        for (p,q,_) in bus.members
            tracks[(p,q)] = chosen
        end
    end
    total = length(ends)
    gap = max(settings["layer_gap"],total+2)
    offsets = Dict(segment => track+fld(gap-2-total,2) for (segment,track) in tracks)
    total,gap,offsets
end
function layout_graph(graph)
    settings = graph.settings
    ids = sort(collect(keys(graph.nodes)))
    node_count = length(ids)
    node_numbers = Dict(id => i for (i,id) in enumerate(ids))
    labels = [graph.nodes[id] for id in ids]
    edges = [new_edge(i,node_numbers[a],node_numbers[b]) for (i,(a,b)) in enumerate(graph.edges)]
    names,widths = string.(ids),length.(labels) .+ 2
    original = [(e.source,e.target) for e in edges]
    upper_original,lower_original = graph_neighbors(node_count,original)
    sources = count(v -> isempty(upper_original[v]) && !isempty(lower_original[v]),1:node_count)
    sinks = count(v -> isempty(lower_original[v]) && !isempty(upper_original[v]),1:node_count)
    isolated = count(v -> isempty(lower_original[v]) && isempty(upper_original[v]),1:node_count)
    undirected = [union(upper_original[v],lower_original[v]) for v in 1:node_count]
    remaining,components = Set(1:node_count),0
    while !isempty(remaining)
        setdiff!(remaining,reachable(minimum(remaining),undirected))
        components += 1
    end
    closure = [reachable(v,lower_original) for v in 1:node_count]
    remaining,strong = Set(1:node_count),Vector{Int}[]
    while !isempty(remaining)
        first = minimum(remaining)
        component = sort([v for v in remaining if v in closure[first] && first in closure[v]])
        setdiff!(remaining,component)
        length(component) >= 2 && push!(strong,component)
    end
    acyclic = acyclic_order(node_count,original)
    acyclic_position = invperm(acyclic)
    for e in edges
        if acyclic_position[e.source] > acyclic_position[e.target]
            e.reversed = true
            e.upper,e.lower = e.target,e.source
        end
    end
    _,dag_lower = graph_neighbors(node_count,[(e.upper,e.lower) for e in edges])
    if settings["reduce"] == "on"
        closure = [reachable(v,dag_lower) for v in 1:node_count]
        for e in edges
            e.transitive = !e.reversed && any(w != e.lower && e.lower in closure[w] for w in dag_lower[e.upper])
        end
    end
    drawn = [e for e in edges if !e.transitive]
    heights,coffman_labels,dummies_before,promotion_rounds,promotions = assign_heights(node_count,[(e.upper,e.lower) for e in drawn],settings)
    levels = maximum(heights) .- heights
    used = Set(levels)
    for e in drawn
        union!(used,(levels[e.upper]+1):(levels[e.lower]-1))
    end
    normalized = Dict(level => i for (i,level) in enumerate(sort(collect(used))))
    vertex_layer = [normalized[level] for level in levels]
    layer_count = length(used)
    for e in drawn
        first,last = vertex_layer[e.upper],vertex_layer[e.lower]
        e.span = last-first
        e.chain = [e.upper]
        for layer in (first+1):(last-1)
            push!(vertex_layer,layer)
            push!(names,"d$(length(vertex_layer)-node_count)")
            push!(widths,1)
            push!(e.chain,length(vertex_layer))
        end
        push!(e.chain,e.lower)
    end
    vertex_count = length(vertex_layer)
    upper,lower = [Int[] for _ in 1:vertex_count],[Int[] for _ in 1:vertex_count]
    gaps = [NTuple{3,Int}[] for _ in 1:layer_count-1]
    for e in drawn, j in 1:length(e.chain)-1
        p,q = e.chain[j],e.chain[j+1]
        push!(gaps[vertex_layer[p]],(p,q,e.number))
        push!(lower[p],q)
        push!(upper[q],p)
    end
    initial_order = [Int[] for _ in 1:layer_count]
    visited = falses(vertex_count)
    function visit(v)
        visited[v] && return
        visited[v] = true
        push!(initial_order[vertex_layer[v]],v)
        for w in lower[v]
            visit(w)
        end
    end
    for v in 1:node_count
        visit(v)
    end
    initial_crossings = total_crossings(gaps,initial_order)
    reduction = reduce_crossings(initial_order,gaps,upper,lower,vertex_layer,settings)
    orders = reduction.orders
    position = positions(orders)
    crossings_by_gap = gap_counts(gaps,orders)
    final_crossings = sum(crossings_by_gap;init=0)
    brute = sum((brute_crossings(s,position) for s in gaps);init=0)
    for segments in gaps, i in eachindex(segments), j in (i+1):length(segments)
        p,q,a = segments[i]
        u,v,b = segments[j]
        if (position[p]-position[u])*(position[q]-position[v]) < 0
            edges[a].crossings += 1
            edges[b].crossings += 1
        end
    end
    coordinates = assign_coordinates(orders,upper,lower,widths,node_count,settings)
    x = coordinates.x
    track_counts,gap_widths = Int[],Int[]
    offsets = Dict{Tuple{Int,Int},Int}()
    for segments in gaps
        tracks,gap,local_offsets = assign_tracks(segments,x,settings)
        push!(track_counts,tracks)
        push!(gap_widths,gap)
        merge!(offsets,local_offsets)
    end
    vertical = settings["direction"] in ("TB","BT")
    thickness = [vertical ? 1 : maximum(widths[layer]) for layer in orders]
    bands = [0]
    for layer in 1:layer_count-1
        push!(bands,bands[end]+thickness[layer]+gap_widths[layer])
    end
    main_length = bands[end]+thickness[end]
    secondary_length = maximum(x+coordinates.right)+1
    canvas = new_canvas(settings["direction"],main_length,secondary_length)
    for e in drawn
        size = vertical ? 1 : widths[e.upper]
        e.upper_endpoint = (bands[vertex_layer[e.upper]]+size,x[e.upper])
        e.lower_endpoint = (bands[vertex_layer[e.lower]]-1,x[e.lower])
    end
    for v in 1:vertex_count
        layer = vertex_layer[v]
        beginning,ending = bands[layer],bands[layer]+thickness[layer]-1
        if v > node_count
            main_line!(canvas,beginning,ending,x[v])
        elseif !vertical && !isempty(lower[v])
            main_line!(canvas,beginning+widths[v],ending,x[v])
        end
    end
    for (layer,segments) in enumerate(gaps), (p,q,_) in segments
        draw_segment!(canvas,bands[layer]+thickness[layer],gap_widths[layer],x[p],x[q],get(offsets,(p,q),0))
    end
    for e in drawn
        draw_arrow!(canvas,e.reversed ? e.upper_endpoint : e.lower_endpoint,e.reversed)
        points = [e.upper_endpoint]
        bent = 0
        for j in 1:length(e.chain)-1
            p,q = e.chain[j],e.chain[j+1]
            x[p] == x[q] && continue
            layer = vertex_layer[p]
            main = bands[layer]+thickness[layer]+offsets[(p,q)]
            append!(points,[(main,x[p]),(main,x[q])])
            bent += 1
        end
        push!(points,e.lower_endpoint)
        e.route = [canvas_cell(canvas,p...) for p in points]
        e.reversed && reverse!(e.route)
        e.bends = 2*bent
        e.length = 1+sum((abs(e.route[i+1][1]-e.route[i][1])+abs(e.route[i+1][2]-e.route[i][2]) for i in 1:length(e.route)-1);init=0)
    end
    path = nothing
    if graph.path !== nothing
        start,stop = node_numbers[graph.path[1]],node_numbers[graph.path[2]]
        following = [sort([e.target for e in drawn if e.source == v]) for v in 1:node_count]
        parent = fill(-1,node_count)
        parent[start] = 0
        queue,head = [start],1
        while head <= length(queue)
            v = queue[head]
            head += 1
            for w in following[v]
                parent[w] != -1 && continue
                parent[w] = v
                push!(queue,w)
            end
        end
        if parent[stop] != -1
            path,v = Int[],stop
            while v != 0
                push!(path,v)
                v = parent[v]
            end
            reverse!(path)
        end
    end
    if path !== nothing
        by_endpoints = Dict((e.source,e.target) => e for e in drawn)
        for i in 1:length(path)-1
            highlight_route!(canvas,by_endpoints[(path[i],path[i+1])].route)
        end
    end
    for v in 1:node_count
        draw_box!(canvas,labels[v],bands[vertex_layer[v]],x[v],coordinates.left[v],path !== nothing && v in path)
    end
    layout = ["graph $(graph.name)","settings " * join(["$key=$(settings[key])" for key in SETTING_NAMES]," "),
        "acyclic " * join(names[acyclic]," ")]
    coffman_labels === nothing || push!(layout,"labels " * join(["$(names[v]):$(coffman_labels[v])" for v in 1:node_count]," "))
    for (round,v,difference) in promotions
        push!(layout,"promote $round $(names[v]) $difference")
    end
    for r in reduction.records
        text = "sweep $(r.run) $(r.sweep) $(r.direction)"
        r.sweep > 0 && (text *= " moved $(r.moved) swaps $(r.swaps)")
        push!(layout,text * " crossings $(r.crossings)")
    end
    push!(layout,"best run $(reduction.best_run) sweep $(reduction.best_sweep) crossings $(reduction.best_crossings)")
    append!(layout,["sift $round moves $moves crossings $count" for (round,moves,count) in reduction.sift])
    for (layer,vertices) in enumerate(orders)
        first,last = bands[layer],bands[layer]+thickness[layer]-1
        if settings["direction"] in ("BT","RL")
            first,last = main_length-1-last,main_length-1-first
        end
        low,high = minimum(x[vertices]-coordinates.left[vertices]),maximum(x[vertices]+coordinates.right[vertices])
        push!(layout,"layer $(layer-1) band $first $last extent $low $high : " * join(["$(names[v])@$(x[v])" for v in vertices]," "))
    end
    for (gap,segments) in enumerate(gaps)
        push!(layout,"between $(gap-1) $gap segments $(length(segments)) crossings $(crossings_by_gap[gap]) tracks $(track_counts[gap]) gap $(gap_widths[gap])")
    end
    variants = join(["$k=$(coordinates.blocks[k])/$(coordinates.widths[k])" for k in VARIANTS]," ")
    push!(layout,"bk conflicts $(length(coordinates.conflicts)) $variants smallest $(coordinates.smallest)")
    for vertices in orders, v in vertices
        aligned = join(["$k $(coordinates.aligned[k][v])" for k in VARIANTS]," ")
        push!(layout,"vertex $(names[v]) layer $(vertex_layer[v]-1) pos $(position[v]) $aligned x $(x[v])")
    end
    for e in edges
        text = "edge $(ids[e.source]) $(ids[e.target])"
        if e.transitive
            push!(layout,text * " transitive")
        else
            e.reversed && (text *= " reversed")
            chain = e.reversed ? reverse(e.chain) : e.chain
            route = join(["$row,$column" for (row,column) in e.route]," ")
            push!(layout,text * " span $(e.span) crossings $(e.crossings) bends $(e.bends) path " * join(x[chain]," ") * " route " * route)
        end
    end
    push!(layout,"end")
    statistics = ["graph $(graph.name)","nodes $node_count edges $(length(edges)) self_loops $(graph.self_loops) duplicates $(graph.duplicates)",
        "sources $sources sinks $sinks isolated $isolated components $components"]
    append!(statistics,["scc " * join(names[c]," ") for c in strong])
    edge_name(e) = "$(ids[e.source])->$(ids[e.target])"
    for (label,selected) in [("reversed",[e for e in edges if e.reversed]),("transitive",[e for e in edges if e.transitive])]
        push!(statistics,"$label $(length(selected))" * (isempty(selected) ? "" : " " * join(edge_name.(selected)," ")))
    end
    max_nodes = maximum(count(v -> v <= node_count,layer) for layer in orders)
    push!(statistics,"layers $layer_count max_nodes $max_nodes max_vertices $(maximum(length.(orders)))")
    push!(statistics,settings["promotion"] == "on" ? "promotion rounds $promotion_rounds accepted $(length(promotions)) dummies_before $dummies_before" : "promotion off")
    spans = sort(unique([e.span for e in drawn]))
    push!(statistics,"dummies $(vertex_count-node_count) span_total $(sum((e.span for e in drawn);init=0)) span_max $(maximum(spans;init=0))")
    push!(statistics,isempty(spans) ? "spans none" : "spans " * join(["$span:$(count(e -> e.span == span,drawn))" for span in spans]," "))
    long_edges = [e for e in drawn if e.span >= 2]
    vertical_edges = count(e -> length(unique(x[e.chain[2:end-1]])) == 1,long_edges)
    push!(statistics,"long_edges $(length(long_edges)) vertical $vertical_edges")
    push!(statistics,"crossings initial $initial_crossings swept $(reduction.best_crossings) best_run $(reduction.best_run) best_sweep $(reduction.best_sweep) final $final_crossings brute $brute")
    segments = [s for gap in gaps for s in gap]
    straight = count(s -> x[s[1]] == x[s[2]],segments)
    offset = sum((abs(x[p]-x[q]) for (p,q,_) in segments);init=0)
    push!(statistics,"segments $(length(segments)) straight $straight bent $(length(segments)-straight) offset $offset")
    text = "routes length $(sum((e.length for e in drawn);init=0)) bends $(sum((e.bends for e in drawn);init=0))"
    if !isempty(drawn)
        longest = drawn[argmax([e.length for e in drawn])]
        text *= " longest $(edge_name(longest)) $(longest.length)"
    end
    push!(statistics,text)
    push!(statistics,"canvas width $(canvas.columns) height $(canvas.rows) crossing_cells $(crossing_cells(canvas))")
    if graph.path !== nothing
        start,stop = graph.path
        text = "path $start $stop"
        text *= path === nothing ? " none" : " hops $(length(path)-1) : " * join(names[path]," ")
        push!(statistics,text)
    end
    push!(statistics,"end")
    csv = ["$(graph.name),$(r.run),$(r.sweep),$(r.crossings)" for r in reduction.records]
    drawing = ["graph $(graph.name) $(canvas.columns)x$(canvas.rows)";drawing_lines(canvas)]
    (layout=layout,statistics=statistics,csv=csv,drawing=drawing,nodes=node_count,edges=length(edges),
        dummies=vertex_count-node_count,initial_crossings=initial_crossings,final_crossings=final_crossings)
end
function main()
    graphs = read_graphs(read_defaults())
    layouts,statistics,crossings,drawings = String[],String[],["graph,run,sweep,crossings"],Vector{String}[]
    total_names = ["graphs","laid_out","errors","nodes","edges","dummies","crossings_initial","crossings_final"]
    totals = Dict(key => 0 for key in total_names)
    for graph in graphs
        totals["graphs"] += 1
        if graph.error !== nothing
            kind,number = graph.error
            error = ["graph $(graph.name)","error $kind line $number","end"]
            append!(layouts,error)
            append!(statistics,error)
            push!(drawings,["graph $(graph.name) error $kind"])
            totals["errors"] += 1
            continue
        end
        result = layout_graph(graph)
        append!(layouts,result.layout)
        append!(statistics,result.statistics)
        append!(crossings,result.csv)
        push!(drawings,result.drawing)
        totals["laid_out"] += 1
        totals["nodes"] += result.nodes
        totals["edges"] += result.edges
        totals["dummies"] += result.dummies
        totals["crossings_initial"] += result.initial_crossings
        totals["crossings_final"] += result.final_crossings
    end
    push!(statistics,"summary " * join(["$key $(totals[key])" for key in total_names]," "))
    mkpath("output")
    for (name,lines) in [("layout.txt",layouts),("stats.txt",statistics),("crossings.csv",crossings)]
        write(joinpath("output",name),join(lines,"\n") * (isempty(lines) ? "" : "\n"))
    end
    write("output/drawings.txt",join([join(block,"\n") for block in drawings],"\n\n") * (isempty(drawings) ? "" : "\n"))
end
main()
