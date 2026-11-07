include("predicates.jl")
include("triangulation.jl")
include("voronoi.jl")
include("proximity.jl")
include("plot.jl")
using Printf
number(x) = @sprintf("%.3f",x==0 ? 0.0 : x)
words(sequence) = join(sequence," ")
edge_id(a,b) = minmax(a,b)
function read_inputs()
    lines = readlines("input/points.txt")
    points, rejected = Tuple{Int,Int}[],String[]
    accepted = Dict{Tuple{Int,Int},Int}()
    for (i,line) in enumerate(lines)
        (isempty(line) || startswith(line,"#")) && continue
        fields = split(line,' ')
        if length(fields)!=2 || any(w->isnothing(match(r"^-?[0-9]+$",w)),fields)
            push!(rejected,"reject $i format")
            continue
        end
        point = Tuple(parse.(Int,fields))
        if any(x->x<0 || x>1000,point)
            push!(rejected,"reject $i range")
        elseif haskey(accepted,point)
            push!(rejected,"reject $i duplicate $(accepted[point])")
        else
            push!(points,point)
            accepted[point] = length(points)
        end
    end
    params = Dict{String,Any}(
        "plot"=>[61,31],
        "plot_layers"=>["edges","hull","sites"],
        "sections"=>["summary"],
        "alpha"=>Int[],
        "queries"=>String[]
    )
    for line in readlines("input/params.txt")
        (isempty(line) || startswith(line,"#")) && continue
        fields = split(line,' ')
        name = fields[1]
        if name=="query"
            push!(params["queries"],line[7:end])
        else
            params[name] = name in ("plot","alpha") ? parse.(Int,fields[2:end]) : String.(fields[2:end])
        end
    end
    points,length(lines),rejected,params
end
function convex_layers(points)
    remaining = collect(eachindex(points))
    layers = Vector{Int}[]
    depth = zeros(Int,length(points))
    while !isempty(remaining)
        if length(remaining)<=2
            layer = sort(remaining)
        else
            ordered = sort(remaining;by=s->points[s])
            lower,upper = Int[],Int[]
            for (order,chain) in ((ordered,lower),(reverse(ordered),upper))
                for s in order
                    while length(chain)>=2 && orient(points[chain[end-1]],points[chain[end]],points[s])<=0
                        pop!(chain)
                    end
                    push!(chain,s)
                end
            end
            layer = vcat(lower[1:end-1],upper[1:end-1])
            start = argmin(layer)
            layer = vcat(layer[start:end],layer[1:start-1])
        end
        push!(layers,layer)
        depth[layer] .= length(layers)
        remaining = setdiff(remaining,layer)
    end
    layers,depth
end
function circle_order(points,a,b,c)
    orient(points[a],points[b],points[c])>0 ? (a,b,c) : (a,c,b)
end
function circle_relation(points,support,s)
    length(support)==1 && return support[1]==s ? 0 : -1
    length(support)==2 && return -dot_at(points[s],points[support[1]],points[support[2]])
    incircle(points[support[1]],points[support[2]],points[support[3]],points[s])
end
function enclosing_circle(points,hull)
    support = nothing
    for (i,a) in enumerate(hull)
        !isnothing(support) && circle_relation(points,support,a)>=0 && continue
        support = (a,)
        for j in 1:i-1
            b = hull[j]
            circle_relation(points,support,b)>=0 && continue
            support = (a,b)
            for k in 1:j-1
                c = hull[k]
                circle_relation(points,support,c)<0 && (support=circle_order(points,a,b,c))
            end
        end
    end
    boundary = [s for s in eachindex(points) if circle_relation(points,support,s)==0]
    diameter = nothing
    for i in 1:length(boundary)-1,j in i+1:length(boundary)
        a,b = boundary[i],boundary[j]
        if all(s->dot_at(points[s],points[a],points[b])==0,boundary)
            diameter = (a,b)
            break
        end
    end
    if isnothing(diameter)
        a,b,c = circle_order(points,boundary...)
        center,radius = circumcenter(points[a],points[b],points[c]),squared_radius(
            points[a],
            points[b],
            points[c]
        )
    else
        a,b = points[diameter[1]],points[diameter[2]]
        center,radius = (a[1]+b[1],a[2]+b[2],2),d2(a,b)/4
    end
    center,radius,boundary
end
function query_answer(query,points,ts,edges,edge_triangles,neighbors,degree,duals,gabriel,rng,mst,shortest)
    fields = split(query,' ')
    name,arguments = fields[1],parse.(Int,fields[2:end])
    n = length(points)
    if name in ("route","path","neighbors","edge")
        any(s->s<1 || s>n,arguments) && return "$query error unknown_site"
        name=="edge" && arguments[1]==arguments[2] && return "$query error same_site"
    end
    if name=="locate"
        q = Tuple(arguments)
        nearest = argmin(s->(d2(points[s],q),s),1:n)
        vertex = findfirst(==(q),points)
        position = "outside"
        if !isnothing(vertex)
            position = "vertex $vertex"
        else
            crossing = findfirst(
                e->orient(points[e[1]],points[e[2]],q)==0 && dot_at(q,points[e[1]],points[e[2]])<0,
                edges
            )
            if !isnothing(crossing)
                position = "edge $(words(edges[crossing]))"
            else
                containing = findfirst(
                    t->all(e->orient(points[e[1]],points[e[2]],q)>0,((t[1],t[2]),(t[2],t[3]),(t[3],t[1]))),
                    ts
                )
                !isnothing(containing) && (position="triangle $(words(ts[containing]))")
            end
        end
        answer = "$position nearest $nearest d2 $(d2(points[nearest],q))"
    elseif name=="walk"
        path,outside = visibility_walk(points,Tuple(arguments),ts,edge_triangles)
        stopping = isnothing(outside) ? "triangle $(path[end])" : "outside $(words(outside))"
        answer = "steps $(length(path)-1) $stopping path $(words(path))"
    elseif name=="natural"
        selected = [t for t in ts if incircle(points[t[1]],points[t[2]],points[t[3]],Tuple(arguments))>0]
        sites = sort(unique([s for t in selected for s in t]))
        answer = "triangles $(length(selected)) sites "*(isempty(sites) ? "-" : words(sites))
    elseif name=="route"
        path,total = greedy_route(points,neighbors,arguments...)
        answer = "hops $(length(path)-1) length $(number(total)) path $(words(path))"
    elseif name=="path"
        a,b = arguments
        paths = get!(shortest,a) do
            dijkstra(points,neighbors,a)
        end
        path = [b]
        while path[end]!=a
            push!(path,paths.previous[path[end]])
        end
        reverse!(path)
        total = paths.distances[b]
        stretch = a==b ? "-" : number(total/sqrt(d2(points[a],points[b])))
        answer = "length $(number(total)) stretch $stretch hops $(length(path)-1) sites $(words(path))"
    elseif name=="neighbors"
        s = arguments[1]
        answer = "degree $(degree[s]) sites $(words(neighbors[s]))"
    else
        a,b = arguments
        edge = edge_id(a,b)
        if haskey(duals,edge)
            yesno(set) = edge in set ? "yes" : "no"
            answer = "delaunay len2 $(d2(points[a],points[b])) gabriel $(yesno(gabriel)) rng $(yesno(rng)) mst $(yesno(mst)) dual $(duals[edge])"
        else
            crossings = ["$u-$v" for (u,v) in edges if orient(points[a],points[b],points[u])*orient(points[a],points[b],points[v])<0 && orient(points[u],points[v],points[a])*orient(
                points[u],
                points[v],
                points[b]
            )<0]
            answer = "missing crossings $(length(crossings))"*(isempty(crossings) ? "" : " "*words(crossings))
        end
    end
    "$query $answer"
end
function main()
    points,line_count,rejected,params = read_inputs()
    n = length(points)
    mesh = Triangulation(points)
    insertions = [insert_site!(mesh,s) for s in 4:n]
    ts = triangles(mesh)
    t = length(ts)
    edge_triangles = Dict{Tuple{Int,Int},Int}()
    for (k,(a,b,c)) in enumerate(ts),edge in ((a,b),(b,c),(c,a))
        edge_triangles[edge] = k
    end
    edges = sort(unique([edge_id(a,b) for (a,b) in keys(mesh.directed)]))
    e = length(edges)
    lengths = Dict(edge=>d2(points[edge[1]],points[edge[2]]) for edge in edges)
    hull_next = Dict(hull_edges(mesh))
    hull_prev = Dict(v=>u for (u,v) in hull_next)
    start = minimum(keys(hull_next))
    hull = [start]
    while hull_next[hull[end]]!=start
        push!(hull,hull_next[hull[end]])
    end
    h = length(hull)
    hull_pairs = [(hull[i],hull[mod1(i+1,h)]) for i in 1:h]
    perimeter,area_hull = 0.0,0
    for (a,b) in hull_pairs
        perimeter += sqrt(d2(points[a],points[b]))
        area_hull += points[a][1]*points[b][2]-points[b][1]*points[a][2]
    end
    adjacent = [Int[] for _ in 1:n]
    for (a,b) in edges
        push!(adjacent[a],b)
        push!(adjacent[b],a)
    end
    neighbors = [neighbor_order(s,adjacent[s],mesh.directed,hull_next) for s in 1:n]
    degree = length.(neighbors)
    areas,kinds,min_angles,max_angles = Int[],String[],Float64[],Float64[]
    bins = zeros(Int,6)
    angle_total = 0.0
    for (a,b,c) in ts
        pa,pb,pc = points[a],points[b],points[c]
        area = orient(pa,pb,pc)
        products = (dot_at(pa,pb,pc),dot_at(pb,pc,pa),dot_at(pc,pa,pb))
        sides = (d2(pb,pc),d2(pc,pa),d2(pa,pb))
        kind = 0 in products ? "right" : minimum(products)<0 ? "obtuse" : "acute"
        lo,hi = atan(area,products[argmin(sides)])*180/pi,atan(area,products[argmax(sides)])*180/pi
        push!(areas,area)
        push!(kinds,kind)
        push!(min_angles,lo)
        push!(max_angles,hi)
        angle_total += lo
        bins[floor(Int,lo/10)+1] += 1
    end
    centers = [circumcenter(points[a],points[b],points[c]) for (a,b,c) in ts]
    radii = [squared_radius(points[a],points[b],points[c]) for (a,b,c) in ts]
    positions = [center_position(center,points,hull) for center in centers]
    duals = Dict{Tuple{Int,Int},String}()
    for (a,b) in edges
        left,right = get(edge_triangles,(a,b),0),get(edge_triangles,(b,a),0)
        if left!=0 && right!=0
            duals[(a,b)] = "segment $left $right"
        else
            u,v = left!=0 ? (a,b) : (b,a)
            duals[(a,b)] = "ray $(max(left,right)) $(words(outward(points,u,v)))"
        end
    end
    cells = NamedTuple[]
    cell_total,clip_total,largest = 0.0,0.0,0
    for s in 1:n
        vertices = [edge_triangles[(s,other)] for other in neighbors[s] if haskey(edge_triangles,(s,other))]
        clipped = clipped_area(points,s,neighbors[s])
        bounded = !haskey(hull_next,s)
        area = bounded ? bounded_area(points[s],centers[vertices]) : 0.0
        incoming = bounded ? (0,0) : outward(points,s,hull_next[s])
        outgoing = bounded ? (0,0) : outward(points,hull_prev[s],s)
        push!(
            cells,
            (vertices=vertices,clip=clipped,bounded=bounded,area=area,incoming=incoming,outgoing=outgoing)
        )
        if bounded
            cell_total += area
            (largest==0 || area>cells[largest].area) && (largest=s)
        end
        clip_total += clipped
    end
    nearest = nearest_neighbors(points,neighbors)
    mutual = [(s,nearest[s]) for s in 1:n if s<nearest[s] && nearest[nearest[s]]==s]
    closest = argmin(edge->(lengths[edge],edge...),edges)
    components = nearest_components(nearest)
    component_number = zeros(Int,n)
    component_pairs = Tuple{Int,Int}[]
    for (k,sites) in enumerate(components)
        component_number[sites] .= k
        s = first(s for s in sites if s<nearest[s] && nearest[nearest[s]]==s)
        push!(component_pairs,(s,nearest[s]))
    end
    nn_edges = Set(edge_id(s,nearest[s]) for s in 1:n)
    mst = kruskal(points,edges)
    mst_set = Set(mst)
    mst_length = 0.0
    for edge in mst
        mst_length += sqrt(lengths[edge])
    end
    gabriel = Set(edge for edge in edges if is_gabriel(points,edge,mesh.directed))
    rng = Set(edge for edge in edges if is_relative_neighbor(points,edge))
    graph_degrees = Dict{String,Vector{Int}}()
    for (name,graph) in (("gg",gabriel),("rng",rng),("mst",mst))
        counts = zeros(Int,n)
        for (a,b) in graph
            counts[a] += 1
            counts[b] += 1
        end
        graph_degrees[name] = counts
    end
    candidates = findall(==("inside"),positions)
    empty_vertex = isempty(candidates) ? 0 : argmax(k->radii[k],candidates)
    diameter,diameter2 = (1,2),-1
    for a in 1:n-1,b in a+1:n
        distance = d2(points[a],points[b])
        if distance>diameter2
            diameter,diameter2 = (a,b),distance
        end
    end
    width,width_edge = Inf,hull_pairs[1]
    for (a,b) in hull_pairs
        value = maximum(orient(points[a],points[b],points[s]) for s in hull)/sqrt(d2(points[a],points[b]))
        value<width && ((width,width_edge)=(value,(a,b)))
    end
    enclosing_center,enclosing_radius,enclosing_sites = enclosing_circle(points,hull)
    layers,depth = convex_layers(points)
    shortest = Dict{Int,Any}()
    pair_count = n*(n-1)÷2
    stretch_total,maximum_stretch,stretch_length,stretch_distance = 0.0,-Inf,0.0,0.0
    stretch_pair = (1,2)
    for a in 1:n-1
        paths = get!(shortest,a) do
            dijkstra(points,neighbors,a)
        end
        for b in a+1:n
            total = paths.distances[b]
            distance = sqrt(d2(points[a],points[b]))
            stretch = total/distance
            stretch_total += stretch
            if stretch>maximum_stretch
                maximum_stretch,stretch_pair,stretch_length,stretch_distance = stretch,(a,b),total,distance
            end
        end
    end
    sections = Dict{String,Vector{String}}()
    sections["input"] = vcat(["lines $line_count","accepted $n","rejected $(length(rejected))"],rejected)
    max_flips = isempty(insertions) ? "max_flips none" : let r=insertions[argmax([r.flips for r in insertions])]
        "max_flips $(r.site) $(r.flips)"
    end
    sections["summary"] = ["sites $n","triangles $t","edges $e","hull_vertices $h","interior_sites $(n-h)","euler $(n-e+t)",
        "flips $(sum((r.flips for r in insertions);init=0))","outside_insertions $(count(r->r.kind=="outside",insertions))",max_flips,
        "acute $(count(==("acute"),kinds))","right $(count(==("right"),kinds))","obtuse $(count(==("obtuse"),kinds))"]
    sections["insertions"] = ["init $(words(mesh.initial))"]
    for r in insertions
        description = r.kind=="inside" ? "inside $(words(r.containing))" : "outside $(r.visible)"
        push!(
            sections["insertions"],
            "insert $(r.site) $description flips $(r.flips) triangles $(r.triangles) hull $(r.hull)"
        )
    end
    sections["triangles"] = String[]
    for (k,(a,b,c)) in enumerate(ts)
        adjacent_numbers = [get(
            edge_triangles,
            edge,
            0
        )==0 ? "-" : string(edge_triangles[edge]) for edge in ((c,b),(a,c),(b,a))]
        push!(
            sections["triangles"],
            "tri $k $a $b $c area2 $(areas[k]) $(kinds[k]) adj $(words(adjacent_numbers))"
        )
    end
    sections["edges"] = String[]
    for (a,b) in edges
        left,right = get(edge_triangles,(a,b),0),get(edge_triangles,(b,a),0)
        kind = left!=0 && right!=0 ? "inner" : "hull"
        push!(
            sections["edges"],
            "edge $a $b $kind len2 $(lengths[(a,b)]) left $(left==0 ? "-" : string(left)) right $(right==0 ? "-" : string(right))"
        )
    end
    sections["hull"] = [
        "hull_vertices $h",
        "order $(words(hull))",
        "perimeter $(number(perimeter))",
        "area2 $area_hull"
    ]
    sections["convex_layers"] = vcat(
        ["layers $(length(layers))"],
        ["layer $k size $(length(layer)) sites $(words(layer))" for (k,layer) in enumerate(layers)]
    )
    lo,hi = argmin(min_angles),argmax(max_angles)
    sections["quality"] = vcat(["min_angle $(number(min_angles[lo])) tri $lo","max_angle $(number(max_angles[hi])) tri $hi","mean_min_angle $(number(angle_total/t))"],
        ["bin $(10i) $(10(i+1)) $(bins[i+1])" for i in 0:5])
    sections["vertices"] = ["$name $(count(==(name),positions))" for name in ("inside","on","outside")]
    for (k,(x,y,d)) in enumerate(centers)
        push!(
            sections["vertices"],
            "v $k $(fraction(x,d)) $(fraction(y,d)) r $(number(sqrt(radii[k]))) $(positions[k])"
        )
    end
    sections["voronoi_edges"] = vcat(
        ["segments $(e-h)","rays $h"],
        ["ve $(words(edge)) $(duals[edge])" for edge in edges]
    )
    sections["cells"] = [
        "bounded $(n-h)",
        "unbounded $h",
        "total_area $(number(cell_total))",
        "clip_total $(number(clip_total))",
        largest==0 ? "largest none" : "largest $largest area $(number(cells[largest].area))"
    ]
    for (s,cell) in enumerate(cells)
        if cell.bounded
            line = "cell $s bounded $(length(cell.vertices)) area $(number(cell.area)) clip $(number(cell.clip)) vertices $(words(cell.vertices))"
        else
            line = "cell $s unbounded $(length(cell.vertices)) clip $(number(cell.clip)) from $(words(cell.incoming)) vertices $(words(cell.vertices)) to $(words(cell.outgoing))"
        end
        push!(sections["cells"],line)
    end
    sections["nearest"] = [
        "mutual_pairs $(length(mutual))",
        "closest_pair $(words(closest)) d2 $(lengths[closest])"
    ]
    for s in 1:n
        other = nearest[s]
        push!(
            sections["nearest"],
            "nn $s $other d2 $(d2(points[s],points[other])) $(nearest[other]==s ? "mutual" : "-")"
        )
    end
    sections["components"] = vcat(
        ["components $(length(components))"],
        ["component $k size $(length(sites)) pair $(words(component_pairs[k])) sites $(words(sites))" for (
            k,
            sites
        ) in enumerate(components)]
    )
    sections["mst"] = vcat(
        [
            "edges $(n-1)",
            "total_length $(number(mst_length))",
            "longest $(words(mst[end])) len2 $(lengths[mst[end]])"
        ],
        ["mst $(words(edge)) len2 $(lengths[edge])" for edge in mst]
    )
    sections["proximity"] = vcat(["delaunay $e","gabriel $(length(gabriel))","rng $(length(rng))","mst $(n-1)","nn $(length(nn_edges))"],
        ["rng_extra $(words(edge)) len2 $(lengths[edge])" for edge in edges if edge in rng && !(edge in mst_set)])
    sections["degrees"] = vcat(
        ["min $(minimum(degree))","max $(maximum(degree))"],
        ["degree $d count $(count(==(d),degree))" for d in sort(unique(degree))]
    )
    sections["empty_circle"] = ["candidates $(length(candidates))"]
    if empty_vertex==0
        push!(sections["empty_circle"],"none")
    else
        x,y,d = centers[empty_vertex]
        append!(
            sections["empty_circle"],
            [
                "vertex $empty_vertex",
                "center $(fraction(x,d)) $(fraction(y,d))",
                "radius $(number(sqrt(radii[empty_vertex])))",
                "sites $(words(ts[empty_vertex]))"
            ]
        )
    end
    x,y,d = enclosing_center
    sections["extent"] = ["diameter $(words(diameter)) d2 $diameter2","width $(number(width)) edge $(words(width_edge))",
        "enclosing_center $(fraction(x,d)) $(fraction(y,d))","enclosing_radius $(number(sqrt(enclosing_radius)))","enclosing_sites $(words(enclosing_sites))"]
    sections["spanner"] = [
        "pairs $pair_count",
        "max_stretch $(number(maximum_stretch)) pair $(words(stretch_pair)) length $(number(stretch_length)) distance $(number(stretch_distance))",
        "mean_stretch $(number(stretch_total/pair_count))"
    ]
    sections["alpha"] = String[]
    for alpha in params["alpha"]
        selected = findall(<=(alpha),radii)
        incidence = Dict(edge=>0 for edge in edges)
        area = 0
        for k in selected
            a,b,c = ts[k]
            area += areas[k]
            for edge in ((a,b),(b,c),(c,a))
                incidence[edge_id(edge...)] += 1
            end
        end
        selected_edges = [edge for edge in edges if incidence[edge]>0 || (edge in gabriel && lengths[edge]<=4alpha)]
        sets = DisjointSets(n)
        incident = falses(n)
        for (a,b) in selected_edges
            unite!(sets,a,b)
            incident[a] = incident[b] = true
        end
        boundary,dangling = count(edge->incidence[edge]==1,selected_edges),count(
            edge->incidence[edge]==0,
            selected_edges
        )
        holes = sets.count-(n-length(selected_edges)+length(selected))
        push!(
            sections["alpha"],
            "alpha $alpha triangles $(length(selected)) edges $(length(selected_edges)) boundary $boundary dangling $dangling isolated $(count(!,incident)) components $(sets.count) holes $holes area2 $area"
        )
    end
    sections["sites"] = ["site $s $(words(points[s])) $(haskey(hull_next,s) ? "hull" : "inner") dt $(degree[s]) gg $(graph_degrees["gg"][s]) rng $(graph_degrees["rng"][s]) mst $(graph_degrees["mst"][s]) nn $(nearest[s]) comp $(component_number[s]) depth $(depth[s])" for s in 1:n]
    sections["queries"] = [query_answer(
        query,
        points,
        ts,
        edges,
        edge_triangles,
        neighbors,
        degree,
        duals,
        gabriel,
        rng,
        mst_set,
        shortest
    ) for query in params["queries"]]
    canvas = Canvas(params["plot"]...)
    for layer in params["plot_layers"]
        if layer=="sites"
            for point in points
                mark!(canvas,point,'o')
            end
        elseif layer=="circle"
            empty_vertex!=0 && mark!(canvas,centers[empty_vertex],'@')
        else
            graph,character = layer=="edges" ? (edges,'.') : layer=="mst" ? (mst,'*') : (hull_pairs,'#')
            for (a,b) in graph
                line!(canvas,points[a],points[b],character)
            end
        end
    end
    sections["delaunay_plot"] = framed(canvas)
    canvas = Canvas(params["plot"]...)
    draw_voronoi!(canvas,points)
    sections["voronoi_plot"] = framed(canvas)
    files = [("triangulation.txt",["input","summary","insertions","triangles","edges","hull","convex_layers","quality"]),
        ("voronoi.txt",["vertices","voronoi_edges","cells"]),(
            "derived.txt",
            [
                "nearest",
                "components",
                "mst",
                "proximity",
                "degrees",
                "empty_circle",
                "extent",
                "spanner",
                "alpha",
                "sites",
                "queries"
            ]
        ),("plot.txt",["delaunay_plot","voronoi_plot"])]
    mkpath("output")
    for (name,owned) in files
        open(joinpath("output",name),"w") do io
            for section in params["sections"]
                if section in owned
                    println(io,"[$section]")
                    for line in sections[section]
                        println(io,line)
                    end
                end
            end
        end
    end
end
main()
