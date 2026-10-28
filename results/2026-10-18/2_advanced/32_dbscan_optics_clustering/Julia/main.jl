include("dataset.jl")
include("grid_index.jl")
include("dbscan.jl")
include("optics.jl")
include("report.jl")

const LABEL_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
label_char(label) = label == NOISE ? '.' : label < 52 ? LABEL_LETTERS[label+1] : '#'
value_text(value) = value == INF ? "-" : string(value)
optional_root(value) = value == INF ? "-" : root_text(value)
check_text(passed) = passed ? "ok" : "mismatch"
condition_text(passed) = passed ? "ok" : "fail"
optional_label(value) = value < 0 ? "-" : string(value)
pair_count(n) = n*(n-1)÷2
function suggested_radius(value)
    radius = isqrt(value)
    max(radius+(radius*radius < value),1)
end
function make_curve(points,values)
    n = length(points)
    order = sortperm(eachindex(points),by=i->(-values[i],points[i].id))
    ordered = values[order]
    first,last = ordered[1],ordered[end]
    crosses = [abs((n-1)*(value-first)-(last-first)*(rank-1)) for (rank,value) in enumerate(ordered)]
    knee = argmax(crosses)
    (order=order,values=ordered,cross=crosses[knee],knee=knee,eps=suggested_radius(ordered[knee]))
end
function grid_summary(points,eps)
    grid = GridIndex(points,eps)
    neighborhoods = Vector{Int}[]
    candidates = 0
    for i in eachindex(points)
        neighbors,number = neighborhood(grid,i)
        push!(neighborhoods,neighbors)
        candidates += number
    end
    brute = brute_force_counts(points,eps)
    sizes = length.(values(grid.cells))
    occupancy = [(size,count(==(size),sizes)) for size in sort(unique(sizes))]
    (
        eps=eps,
        neighborhoods=neighborhoods,
        candidates=candidates,
        cells=length(grid.cells),
        busiest=busiest_cell(grid),
        pairs=(sum(length.(neighborhoods))-length(points))÷2,
        brute_pairs=(sum(brute)-length(points))÷2,
        consistent=all(length(neighbors) == count for (neighbors,count) in zip(neighborhoods,brute)),
        occupancy=occupancy
    )
end
struct Setting
    name::String
    kind::Symbol
    radius::Int
    labels::Vector{Int}
    core::BitVector
    count::Int
    members::Vector{Vector{Int}}
    noise::Int
    core_count::Int
    border_count::Int
end
function Setting(name,kind,radius,labels,core)
    groups = maximum(labels)+1
    members = [findall(==(label),labels) for label in 0:(groups-1)]
    noise = count(==(NOISE),labels)
    core_count = count(i->labels[i] != NOISE && core[i],eachindex(labels))
    Setting(
        name,
        kind,
        radius,
        labels,
        BitVector(core),
        groups,
        members,
        noise,
        core_count,
        length(labels)-noise-core_count
    )
end
function extract_clusters(ordering,reach,core,radius)
    limit = radius*radius
    labels = fill(NOISE,length(ordering))
    cluster = -1
    for index in ordering
        if reach[index] > limit
            if core[index] <= limit
                cluster += 1
                labels[index] = cluster
            end
        else
            labels[index] = cluster
        end
    end
    labels,core .<= limit
end
function xi_method(reach,params)
    n = length(reach)-1
    alpha,beta = (params.xi_v-params.xi_u)^2,params.xi_v^2
    xle(a,b) = b == INF ? true : a == INF ? false : beta*a <= alpha*b
    steep_up = [!(reach[i] == INF && reach[i+1] == INF) && xle(reach[i],reach[i+1]) for i in 1:n]
    steep_down = [!(reach[i] == INF && reach[i+1] == INF) && xle(reach[i+1],reach[i]) for i in 1:n]
    up,down = [reach[i] < reach[i+1] for i in 1:n],[reach[i] > reach[i+1] for i in 1:n]
    function region_end(start,steep,reverse_direction)
        stop,flat = start,0
        for i in start:n
            if steep[i]
                stop,flat = i,0
            elseif reverse_direction[i]
                break
            else
                flat += 1
                flat > params.min_pts && break
            end
        end
        stop
    end
    areas = NamedTuple[]
    clusters = Tuple{Int,Int}[]
    down_areas = NamedTuple[]
    index,mib = 1,0
    for start in 1:n
        (start < index || !(steep_up[start] || steep_down[start])) && continue
        mib = max(mib,maximum(reach[index:start]))
        if mib == INF
            empty!(down_areas)
        else
            down_areas = [merge(
                area,
                (high=max(area.high,mib),)
            ) for area in down_areas if xle(mib,reach[area.start])]
        end
        if steep_down[start]
            stop = region_end(start,steep_down,up)
            push!(areas,(kind="down",start=start,stop=stop))
            push!(down_areas,(start=start,stop=stop,high=0))
            index = stop+1
            mib = reach[index]
        else
            stop = region_end(start,steep_up,down)
            push!(areas,(kind="up",start=start,stop=stop))
            index = stop+1
            mib = reach[index]
            candidates = Tuple{Int,Int}[]
            for area in down_areas
                cs,ce = area.start,stop
                xle(area.high,reach[ce+1]) || continue
                top = reach[area.start]
                if xle(reach[ce+1],top)
                    while cs < area.stop && reach[cs+1] > reach[ce+1]
                        cs += 1
                    end
                elseif xle(top,reach[ce+1])
                    while ce > start && reach[ce-1] > top
                        ce -= 1
                    end
                end
                if ce-cs+1 >= params.xi_min_size && cs <= area.stop && ce >= start
                    push!(candidates,(cs,ce))
                end
            end
            append!(clusters,reverse(candidates))
        end
    end
    position_labels = fill(NOISE,n)
    cluster_labels = Int[]
    next_label = 0
    for (start,stop) in clusters
        if all(==(NOISE),position_labels[start:stop])
            position_labels[start:stop] .= next_label
            push!(cluster_labels,next_label)
            next_label += 1
        else
            push!(cluster_labels,-1)
        end
    end
    parents = zeros(Int,length(clusters))
    for (number,(start,stop)) in enumerate(clusters)
        size = stop-start+1
        best_size = typemax(Int)
        for (other,(first,last)) in enumerate(clusters)
            other_size = last-first+1
            if other == number || first > start || stop > last || other_size < size || (other_size == size && other < number)
                continue
            end
            if other_size < best_size
                parents[number],best_size = other,other_size
            end
        end
    end
    (
        areas=areas,
        clusters=clusters,
        position_labels=position_labels,
        cluster_labels=cluster_labels,
        parents=parents
    )
end
function make_analysis(points,params)
    n,k = length(points),params.min_pts-1
    neighbors = [[value for value in sort([squared_distance(
        p,
        q
    ) for q in points if q.id != p.id])[1:(2*params.min_pts)]] for p in points]
    curves = [make_curve(points,[row[j] for row in neighbors]) for j in 1:(2*params.min_pts)]
    curve,kdist = curves[k],[row[k] for row in neighbors]
    radii = sort(unique(vcat(params.eps_list,[curve.eps,params.max_eps])))
    grids = [grid_summary(points,eps) for eps in radii]
    neighborhoods = Dict(grid.eps=>grid.neighborhoods for grid in grids)
    settings = Setting[]
    for eps in params.eps_list
        labels,core = dbscan(neighborhoods[eps],params.min_pts)
        push!(settings,Setting("db$eps",:dbscan,eps,labels,core))
    end
    labels,core = dbscan(neighborhoods[curve.eps],params.min_pts)
    knee = Setting("knee$(curve.eps)",:dbscan,curve.eps,labels,core)
    push!(settings,knee)
    core_distance = core_distances(points,neighborhoods[params.max_eps],params.min_pts)
    ordering,reach,predecessor = optics_ordering(points,neighborhoods[params.max_eps],core_distance)
    for eps in params.extract_eps
        labels,core = extract_clusters(ordering,reach,core_distance,eps)
        push!(settings,Setting("op$eps",:extract,eps,labels,core))
    end
    positions = vcat(reach[ordering],[INF])
    xi = xi_method(positions,params)
    labels = fill(NOISE,n)
    labels[ordering] = xi.position_labels
    xi_setting = Setting("xi",:xi,params.max_eps,labels,core_distance .!= INF)
    push!(settings,xi_setting)
    x0,x1 = minimum(p.x for p in points),maximum(p.x for p in points)
    y0,y1 = minimum(p.y for p in points),maximum(p.y for p in points)
    map_cells = [(
        (p.x-x0)*params.map_width÷(x1-x0+1)+1,
        (y1-p.y)*params.map_height÷(y1-y0+1)+1
    ) for p in points]
    (
        points=points,
        params=params,
        min_pts=params.min_pts,
        k=k,
        curves=curves,
        curve=curve,
        kdist=kdist,
        grids=grids,
        neighborhoods=neighborhoods,
        settings=settings,
        knee=knee,
        core_distance=core_distance,
        ordering=ordering,
        reach=reach,
        predecessor=predecessor,
        positions=positions,
        xi=xi,
        xi_setting=xi_setting,
        map_cells=map_cells
    )
end
turn(o,a,b) = (a.x-o.x)*(b.y-o.y)-(a.y-o.y)*(b.x-o.x)
function half_hull(ordered)
    chain = Point[]
    for point in ordered
        while length(chain) >= 2 && turn(chain[end-1],chain[end],point) <= 0
            pop!(chain)
        end
        push!(chain,point)
    end
    chain
end
function convex_hull(members)
    ordered = sort(members,by=p->(p.x,p.y))
    length(ordered) <= 2 && return ordered
    lower,upper = half_hull(ordered),half_hull(reverse(ordered))
    vcat(lower[1:end-1],upper[1:end-1])
end
function cluster_lines(points,setting,label)
    indices = setting.members[label+1]
    members = points[indices]
    size = length(members)
    core = count(setting.core[indices])
    sx,sy = sum(p.x for p in members),sum(p.y for p in members)
    medoid = members[argmin([((size*p.x-sx)^2+(size*p.y-sy)^2,p.id) for p in members])]
    xmin,xmax = minimum(p.x for p in members),maximum(p.x for p in members)
    ymin,ymax = minimum(p.y for p in members),maximum(p.y for p in members)
    area = (xmax-xmin+1)*(ymax-ymin+1)
    hull = convex_hull(members)
    doubled = abs(sum(p.x*hull[i%length(hull)+1].y-hull[i%length(hull)+1].x*p.y for (i,p) in enumerate(hull)))
    hull_area = "$(doubled÷2).$(isodd(doubled) ? 5 : 0)"
    diameter = maximum(squared_distance(p,q) for p in hull for q in hull)
    [
        "cluster $label $(label_char(label)) size $size core $core border $(size-core) centroid $(fraction_text(sx,size)) $(fraction_text(sy,size)) medoid $(medoid.id)",
        "  bbox $xmin $ymin $xmax $ymax area $area density $(fraction_text(size,area))",
        "  hull $(length(hull)) hull_area $hull_area diameter_sq $diameter diameter $(root_text(diameter))"
    ]
end
function frequencies(values)
    result = Dict{eltype(values),Int}()
    for value in values
        result[value] = get(result,value,0)+1
    end
    result
end
function adjusted_rand(first,second)
    pairs = sum(pair_count(n) for n in values(frequencies(zip(first,second))))
    a = sum(pair_count(n) for n in values(frequencies(first)))
    b = sum(pair_count(n) for n in values(frequencies(second)))
    z = pair_count(length(first))
    numerator,denominator = 2*(z*pairs-a*b),z*(a+b)-2*a*b
    denominator == 0 ? (1,1) : (numerator,denominator)
end
function labels_lines(a)
    lines = ["id,"*join((s.name for s in a.settings),',')]
    for (i,point) in enumerate(a.points)
        push!(lines,join((point.id,(s.labels[i] for s in a.settings)...),','))
    end
    lines
end
function optics_lines(a)
    lines = ["order,id,core_sq,reach_sq,reach,predecessor"]
    for (position,index) in enumerate(a.ordering)
        reach,predecessor = a.reach[index],a.predecessor[index]
        previous = predecessor == 0 ? "-" : string(a.points[predecessor].id)
        push!(
            lines,
            "$position,$(a.points[index].id),$(value_text(a.core_distance[index])),$(value_text(reach)),$(optional_root(reach)),$previous"
        )
    end
    lines
end
function kdist_lines(a)
    c = a.curve
    lines = ["k_distance k $(a.k) points $(length(a.points))","rank id kdist_sq kdist"]
    for (rank,(index,value)) in enumerate(zip(c.order,c.values))
        push!(lines,"$rank $(a.points[index].id) $value $(root_text(value))")
    end
    value = c.values[c.knee]
    push!(
        lines,
        "",
        "knee rank $(c.knee) id $(a.points[c.order[c.knee]].id) kdist_sq $value kdist $(root_text(value)) cross $(c.cross)",
        "suggested_eps $(c.eps)",
        "",
        "knee_table"
    )
    for (j,row) in enumerate(a.curves)
        push!(
            lines,
            "k $j rank $(row.knee) id $(a.points[row.order[row.knee]].id) kdist_sq $(row.values[row.knee]) eps $(row.eps)"
        )
    end
    push!(lines,"","core_check")
    for s in a.settings
        s.kind == :dbscan || continue
        core = count(v->v <= s.radius*s.radius,a.kdist)
        grid_core = count(s.core)
        push!(
            lines,
            "eps $(s.radius) core $core non_core $(length(a.points)-core) grid_core $grid_core $(check_text(core == grid_core))"
        )
    end
    defined = findall(!=(INF),a.core_distance)
    consistent = all(a.core_distance[i] == a.kdist[i] for i in defined)
    push!(lines,"optics max_eps $(a.params.max_eps) core $(length(defined)) $(check_text(consistent))")
    lines
end
function check_lines(a,s)
    linked,supported,separated = true,true,true
    isolated = 0
    ambiguous = String[]
    for (i,neighbors) in enumerate(a.neighborhoods[s.radius])
        label = s.labels[i]
        core_labels = [s.labels[j] for j in neighbors if s.core[j]]
        if s.core[i]
            any(!=(label),core_labels) && (linked=false)
        elseif label != NOISE
            !(label in core_labels) && (supported=false)
            others = sort(unique(filter(!=(label),core_labels)))
            !isempty(others) && push!(ambiguous,"  $(a.points[i].id) cluster $label also "*join(others,' '))
        else
            !isempty(core_labels) && (separated=false)
            isolated += length(neighbors) == 1
        end
    end
    vcat(
        [
            "check $(condition_text(linked)) $(condition_text(supported)) $(condition_text(separated))",
            "isolated $isolated",
            "ambiguous $(length(ambiguous))"
        ],
        ambiguous
    )
end
function setting_lines(a,s)
    lines = ["setting $(s.name) eps $(s.radius) clusters $(s.count) noise $(s.noise) core $(s.core_count) border $(s.border_count)"]
    for label in 0:(s.count-1)
        append!(lines,cluster_lines(a.points,s,label))
    end
    s.kind == :dbscan && append!(lines,check_lines(a,s))
    lines
end
function hierarchy_lines(a)
    settings = filter(s->s.kind == :dbscan,a.settings)
    ordered = sortperm(eachindex(settings),by=i->(settings[i].radius,i))
    settings = settings[ordered]
    lines = ["hierarchy"]
    for i in 2:length(settings)
        small,large = settings[i-1],settings[i]
        push!(lines,"$(small.name) -> $(large.name)")
        sources = [Int[] for _ in 1:large.count]
        for (label,members) in enumerate(small.members)
            first_core = first(filter(j->small.core[j],members))
            push!(sources[large.labels[first_core]+1],label-1)
        end
        for (label,clusters) in enumerate(sources)
            text = isempty(clusters) ? "-" : join(clusters,' ')
            push!(lines,"  $(label-1) <- $text")
        end
    end
    lines
end
function comparison_lines(a)
    lines = ["optics_vs_dbscan"]
    for x in a.settings
        x.kind == :extract || continue
        matches = filter(s->s.kind == :dbscan && s.radius == x.radius,a.settings)
        isempty(matches) && continue
        y = first(matches)
        pairs = Set((x.labels[i],y.labels[i]) for i in eachindex(x.labels) if x.core[i])
        same = length(pairs) == length(Set(first(pair) for pair in pairs)) == length(Set(last(pair) for pair in pairs))
        border_as_noise = count(i->x.labels[i] == NOISE && y.labels[i] != NOISE,eachindex(x.labels))
        moved = "-"
        if same
            mapping = Dict(pairs)
            moved = string(count(
                i->x.labels[i] != NOISE && mapping[x.labels[i]] != y.labels[i],
                eachindex(x.labels)
            ))
        end
        push!(
            lines,
            "$(x.name) $(y.name) core_partition $(same ? "same" : "different") border_as_noise $border_as_noise moved $moved"
        )
    end
    lines
end
function optics_summary_lines(a)
    components = Int[]
    for index in a.ordering
        a.reach[index] == INF && push!(components,0)
        components[end] += 1
    end
    ["optics max_eps $(a.params.max_eps) core $(count(!=(INF),a.core_distance)) components $(length(components)) singletons $(count(==(1),components)) largest $(maximum(components))"]
end
function sweep_lines(a)
    lines = ["sweep max_eps $(a.params.max_eps)","eps clusters noise largest"]
    counts = Int[]
    for eps in 1:a.params.max_eps
        labels,_ = extract_clusters(a.ordering,a.reach,a.core_distance,eps)
        sizes = collect(values(frequencies(filter(!=(NOISE),labels))))
        push!(counts,maximum(labels)+1)
        push!(lines,"$eps $(counts[end]) $(count(==(NOISE),labels)) $(maximum(sizes;init=0))")
    end
    stable = nothing
    start = 1
    for eps in 1:a.params.max_eps
        eps < a.params.max_eps && counts[eps+1] == counts[start] && continue
        run_length = eps-start+1
        if counts[start] >= 2 && (isnothing(stable) || run_length > stable.length)
            stable = (clusters=counts[start],first=start,last=eps,length=run_length)
        end
        start = eps+1
    end
    push!(
        lines,
        isnothing(stable) ? "stable -" : "stable clusters $(stable.clusters) eps $(stable.first) $(stable.last) length $(stable.length)"
    )
    lines
end
function xi_lines(a)
    xi = a.xi
    lines = ["xi $(a.params.xi_text) min_size $(a.params.xi_min_size) steep_areas $(length(xi.areas))"]
    append!(lines,["$(area.kind) $(area.start) $(area.stop)" for area in xi.areas])
    push!(lines,"xi_clusters $(length(xi.clusters))")
    for (j,(start,stop)) in enumerate(xi.clusters)
        inner = filter(!=(INF),a.positions[(start+1):stop])
        valley = minimum(inner;init=INF)
        parent = xi.parents[j] == 0 ? "-" : string(xi.parents[j]-1)
        push!(
            lines,
            "$(j-1) start $start end $stop size $(stop-start+1) label $(optional_label(xi.cluster_labels[j])) parent $parent walls $(optional_root(a.positions[start])) $(optional_root(a.positions[stop+1])) valley $(optional_root(valley))"
        )
    end
    lines
end
function outlier_lines(a)
    knee = a.knee
    core = findall(knee.core)
    rows = Tuple{Int,Int,Int}[]
    for i in findall(==(NOISE),knee.labels)
        q = core[argmin([(squared_distance(a.points[i],a.points[j]),a.points[j].id) for j in core])]
        push!(rows,(squared_distance(a.points[i],a.points[q]),i,q))
    end
    sort!(rows,by=row->(-row[1],a.points[row[2]].id))
    lines = ["outliers $(knee.name) count $(length(rows))"]
    for (distance,i,q) in rows
        push!(
            lines,
            "$(a.points[i].id) nearest_core $(a.points[q].id) cluster $(knee.labels[q]) dist_sq $distance dist $(root_text(distance))"
        )
    end
    lines
end
function gap_lines(a)
    knee = a.knee
    lines = ["gaps $(knee.name)"]
    for first in 1:knee.count,second in (first+1):knee.count
        best = nothing
        for i in knee.members[first],j in knee.members[second]
            candidate = (squared_distance(a.points[i],a.points[j]),a.points[i].id,a.points[j].id)
            (isnothing(best) || candidate < best) && (best=candidate)
        end
        distance,p,q = best
        push!(lines,"$(first-1) $(second-1) dist_sq $distance dist $(root_text(distance)) between $p $q")
    end
    lines
end
function contingency_lines(a)
    knee,xi = a.knee,a.xi_setting
    table = zeros(Int,knee.count+1,xi.count+1)
    for (r,c) in zip(knee.labels,xi.labels)
        table[r+2,c+2] += 1
    end
    lines = ["contingency $(knee.name) xi","columns "*join(-1:(xi.count-1),' ')]
    for r in -1:(knee.count-1)
        push!(lines,"$r "*join(table[r+2,:],' '))
    end
    for c in 0:(xi.count-1)
        shared_counts = table[2:end,c+2]
        r = argmax(shared_counts)
        shared = shared_counts[r]
        union = length(knee.members[r])+length(xi.members[c+1])-shared
        push!(lines,"match $c $(r-1) shared $shared jaccard $(fraction_text(shared,union))")
    end
    lines
end
function ari_lines(a)
    lines = ["ari"]
    for i in eachindex(a.settings),j in (i+1):length(a.settings)
        first,second = a.settings[i],a.settings[j]
        numerator,denominator = adjusted_rand(first.labels,second.labels)
        push!(lines,"$(first.name) $(second.name) $(ari_text(numerator,denominator))")
    end
    lines
end
function join_parts(parts)
    lines = String[]
    for part in parts
        !isempty(lines) && push!(lines,"")
        append!(lines,part)
    end
    lines
end
function clusters_lines(a)
    parts = [[
        "points $(length(a.points)) min_pts $(a.min_pts)",
        "settings "*join((s.name for s in a.settings),' ')
    ]]
    grid_lines = ["grid"]
    for grid in a.grids
        gx,gy,size = grid.busiest
        push!(
            grid_lines,
            "eps $(grid.eps) cells $(grid.cells) busiest $gx $gy $size candidates $(grid.candidates) pairs $(grid.pairs) brute_pairs $(grid.brute_pairs) $(check_text(grid.consistent))",
            "  occupancy "*join(("$size:$count" for (size,count) in grid.occupancy),' ')
        )
    end
    push!(parts,grid_lines)
    append!(parts,[setting_lines(a,s) for s in a.settings])
    append!(
        parts,
        [
            hierarchy_lines(a),
            comparison_lines(a),
            optics_summary_lines(a),
            sweep_lines(a),
            xi_lines(a),
            outlier_lines(a),
            gap_lines(a),
            contingency_lines(a),
            ari_lines(a)
        ]
    )
    join_parts(parts)
end
function map_rows(a,s;kind=false)
    cells = [Int[] for _ in 1:a.params.map_height,_ in 1:a.params.map_width]
    for (i,(column,row)) in enumerate(a.map_cells)
        push!(cells[row,column],i)
    end
    rows = String[]
    for row in axes(cells,1)
        characters = Char[]
        for column in axes(cells,2)
            indices = cells[row,column]
            if isempty(indices)
                character = ' '
            elseif kind
                character = any(s.core[indices]) ? '#' : any(!=(NOISE),s.labels[indices]) ? '+' : '.'
            else
                clusters = unique(filter(!=(NOISE),s.labels[indices]))
                character = isempty(clusters) ? '.' : length(clusters) == 1 ? label_char(only(clusters)) : '*'
            end
            push!(characters,character)
        end
        push!(rows,String(characters))
    end
    rows
end
function kdist_plot(a)
    c = a.curve
    width,height,n = a.params.kdist_width,a.params.kdist_height,length(a.points)
    top = c.values[1]
    heights = Int[]
    knee_column = 1
    for column in 0:(width-1)
        first,last = column*n÷width+1,(column+1)*n÷width
        push!(heights,isqrt(height*height*c.values[first]÷top))
        first <= c.knee <= last && (knee_column=column+1)
    end
    rows = [String([height-row+1 <= heights[column] ? '#' : column == knee_column ? ':' : ' ' for column in 1:width]) for row in 1:height]
    rows,knee_column
end
function maps_lines(a)
    lines = String[]
    for s in a.settings
        push!(lines,"map $(s.name) clusters $(s.count) noise $(s.noise)")
        append!(lines,framed(map_rows(a,s),a.params.map_width))
        legend = isempty(s.members) ? "-" : join(
            ("$(label_char(label-1))=$(length(members))" for (label,members) in enumerate(s.members)),
            ' '
        )
        push!(lines,"legend $legend","")
    end
    push!(lines,"kinds $(a.knee.name)")
    append!(lines,framed(map_rows(a,a.knee;kind=true),a.params.map_width))
    rows,knee_column = kdist_plot(a)
    push!(lines,"","kdist_plot k $(a.k) max $(root_text(a.curve.values[1])) knee_column $knee_column")
    append!(lines,framed(rows,a.params.kdist_width))
    top = maximum(filter(!=(INF),a.positions))
    columns = vcat(filter(s->s.kind == :extract,a.settings),[a.xi_setting])
    push!(
        lines,
        "",
        "reachability width $(a.params.plot_width) max_reach $(root_text(top)) columns "*join(
            (s.name for s in columns),
            ' '
        )
    )
    for (position,index) in enumerate(a.ordering)
        reach = a.reach[index]
        bar = reach == INF ? repeat("-",a.params.plot_width) : repeat(
            "#",
            isqrt(a.params.plot_width*a.params.plot_width*reach÷top)
        )
        characters = join(label_char(s.labels[index]) for s in columns)
        push!(
            lines,
            "$(lpad(string(position),4)) $(lpad(string(a.points[index].id),5)) $(lpad(optional_root(reach),7)) $characters |$bar"
        )
    end
    lines
end
function main()
    analysis = make_analysis(read_points(),read_params())
    outputs = (
        ("labels.csv",labels_lines(analysis)),
        ("optics_order.csv",optics_lines(analysis)),
        ("kdist.txt",kdist_lines(analysis)),
        ("clusters.txt",clusters_lines(analysis)),
        ("maps.txt",maps_lines(analysis))
    )
    for (name,lines) in outputs
        write_lines(name,lines)
    end
end
main()
