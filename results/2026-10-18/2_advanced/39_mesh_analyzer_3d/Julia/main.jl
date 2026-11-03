include("obj_io.jl")
include("measure.jl")
include("topology.jl")
include("orientation.jl")
include("repair.jl")

function read_parameters()
    settings = record(
        snap=1,
        merge=true,
        degenerate=true,
        duplicates=true,
        orient=true,
        outward=true,
        fill_holes=0,
        keep_unused=true,
        sections=["summary","components"],
        queries=Any[]
    )
    for line in readlines(joinpath("input","params.txt"))
        (isempty(line) || startswith(line,"#")) && continue
        parts = split(line)
        key,args = parts[1],parts[2:end]
        if key == "query"
            push!(settings[:queries],(String(args[1]),parse.(Int,args[2:end])))
        elseif key == "sections"
            settings[:sections] = String.(args)
        elseif key in ("snap","fill_holes")
            settings[Symbol(key)] = parse(Int,only(args))
        else
            settings[Symbol(key)] = only(args) == "on"
        end
    end
    settings
end
function polygon_is_nonplanar(polygon,snapped)
    corners = polygon[:vertices]
    origin = snapped[corners[1]]
    total = (0,0,0)
    for i in 2:length(corners)-1
        n = cross(subtract(snapped[corners[i]],origin),subtract(snapped[corners[i+1]],origin))
        total = ntuple(axis->total[axis]+n[axis],3)
    end
    any(dot(subtract(snapped[v],origin),total) != 0 for v in corners)
end
function edge_shape(edge,faces,points,adjacent)
    length(adjacent) != 2 && return "-"
    a,b = edge
    first_face,second_face = faces[adjacent[1]],faces[adjacent[2]]
    has_directed(first_face.vertices,a,b) == has_directed(second_face.vertices,a,b) && return "inconsistent"
    third = first(v for v in second_face.vertices if v != a && v != b)
    signed = dot(subtract(points[third],points[first_face.vertices[1]]),normal(first_face,points))
    signed < 0 ? "convex" : signed > 0 ? "concave" : "flat"
end
function shape_counts(component,mesh,faces,points)
    shapes = Dict{String,Int}()
    for edge in component[:edges]
        shape = edge_shape(edge,faces,points,mesh.edges[edge])
        shapes[shape] = get(shapes,shape,0)+1
    end
    shapes
end
function descriptors(faces,points,mesh,loops,orientability,inside)
    result = Dict{Symbol,Any}[]
    violations = Set(inconsistent_edges(faces,mesh.edges))
    for comp in mesh.components
        component = copy(comp)
        ids,vertices,edges = comp[:faces],comp[:vertices],comp[:edges]
        closed = isempty(comp[:boundary])
        manifold = isempty(comp[:nonmanifold]) && isempty(comp[:nonmanifold_vertices])
        consistent = !any(edge in violations for edge in edges)
        solid = closed && manifold && consistent
        orientable = orientability[comp[:number]]
        loop_count = count(loop->loop[:component] == comp[:number],loops)
        chi = length(vertices)-length(edges)+length(ids)
        signed = volume6(ids,faces,points)
        total_normal = (0,0,0)
        for id in ids
            n = normal(faces[id],points)
            total_normal = ntuple(axis->total_normal[axis]+n[axis],3)
        end
        degrees = [count(edge->v in edge,edges) for v in vertices]
        lengths = [edge_length_squared(edge,points) for edge in edges]
        angles = [triangle_angle(faces[id],points) for id in ids]
        merge!(component,record(closed=closed,manifold=manifold,consistent=consistent,solid=solid,orientable=orientable,loops=loop_count,euler=chi,
            genus=manifold && orientable ? fld(
                2-chi-loop_count,
                2
            ) : nothing,crosscaps=manifold && !orientable ? 2-chi-loop_count : nothing,
            volume6=signed,centroid=solid && signed != 0 ? centroid(
                ids,
                faces,
                points,
                signed
            ) : nothing,area=area(faces[ids],points),normal_sum=total_normal,
            bbox=bbox(vertices,points),inside=solid ? get(inside,comp[:number],Int[]) : Int[],angles=angles,
            edge_min=minimum(lengths),edge_max=maximum(lengths),valence_min=minimum(degrees),valence_max=maximum(degrees)))
        push!(result,component)
    end
    result
end
function analyze_source(source,settings)
    snapped,snapped_list = snapped_vertices(source.vertices,settings[:snap])
    representative = representatives(snapped,settings[:merge])
    triangles = split_polygons(source.polygons)
    kept,removed = cleaned_faces(triangles,snapped,representative,settings[:degenerate],settings[:duplicates])
    points,cleaned,renumber = remap_vertices(
        source.vertices,
        snapped,
        representative,
        kept,
        settings[:keep_unused]
    )
    initial = [face.vertices for face in cleaned]
    before = analyze_mesh(cleaned)
    initial_inconsistent = inconsistent_edges(cleaned,before.edges)
    settings[:orient] && repair_orientation!(cleaned,before.edges)
    after = inconsistent_edges(cleaned,before.edges)
    loops = boundary_loops(cleaned,before,has_directed)
    permitted = Set(component[:number] for component in before.components if isempty(component[:nonmanifold]) && !any(edge in after for edge in component[:edges]))
    faces,added = fill_loops(cleaned,loops,settings[:fill_holes],permitted)
    mesh = analyze_mesh(faces)
    violations = Set(inconsistent_edges(faces,mesh.edges))
    solids = [comp for comp in mesh.components if isempty(comp[:boundary]) && isempty(comp[:nonmanifold]) && isempty(comp[:nonmanifold_vertices]) && !any(edge in violations for edge in comp[:edges])]
    inside = Dict{Int,Vector{Int}}()
    for comp in solids
        containers = Int[]
        for other in solids
            comp === other && continue
            sample = findfirst(v->!(v in other[:vertices]),comp[:vertices])
            if !isnothing(sample) && winding_number(
                other[:faces],
                faces,
                points,
                points[comp[:vertices][sample]]
            ) != 0
                push!(containers,other[:number])
            end
        end
        inside[comp[:number]] = sort(containers)
    end
    outward_components = 0
    if settings[:outward]
        for comp in solids
            signed = volume6(comp[:faces],faces,points)
            depth = length(inside[comp[:number]])
            if signed != 0 && ((iseven(depth) && signed < 0) || (isodd(depth) && signed > 0))
                foreach(flip!,faces[comp[:faces]])
                outward_components += 1
            end
        end
    end
    flipped = sum(faces[i].vertices != initial[i] for i in eachindex(initial);init=0)
    final_loops = boundary_loops(faces,mesh,has_directed)
    components = descriptors(faces,points,mesh,final_loops,orientable_components(faces,mesh),inside)
    nonplanar = Set(polygon[:number] for polygon in source.polygons if polygon_is_nonplanar(polygon,snapped))
    groups = unique([polygon[:group] for polygon in source.polygons])
    !isempty(added) && push!(groups,"fill")
    original_to_reps = Dict{Int,Vector{Int}}()
    for (number,rep) in enumerate(representative)
        push!(get!(()->Int[],original_to_reps,rep),number)
    end
    record(source=source,settings=settings,snapped_list=snapped_list,representative=representative,original_to_reps=original_to_reps,triangles=triangles,removed=removed,
        points=points,faces=faces,renumber=renumber,initial_faces=length(cleaned),mesh_before=before,initial_inconsistent=initial_inconsistent,inconsistent_after=after,
        loops_before=loops,added=added,mesh=mesh,components=components,outward_components=outward_components,flipped_faces=flipped,nonplanar=nonplanar,group_order=groups)
end
yes(value) = value ? "yes" : "no"
listing(items) = isempty(items) ? "-" : join(items,' ')
optional(value) = isnothing(value) ? "-" : string(value)
function section_summary(data)
    source = data[:source]
    sizes = [length(p[:vertices]) for p in source.polygons]
    removals = [reason for (_,reason) in data[:removed]]
    lines = [
        "[summary]",
        "lines $(source.lines)",
        "vertices $(length(source.vertices))",
        "polygons $(length(source.polygons))",
        "errors $(length(source.errors))",
        "ignored $(source.ignored)",
        "nonplanar_polygons $(length(data[:nonplanar]))"
    ]
    for size in sort(unique(sizes))
        push!(lines,"polygon_size $size $(count(==(size),sizes))")
    end
    append!(lines,[
        "triangles $(length(data[:triangles]))","snapped $(length(data[:snapped_list]))","merged $(count(i->i != data[:representative][i],eachindex(data[:representative])))",
        "removed_repeated $(count(==("repeated"),removals))","removed_zero_area $(count(==("zero_area"),removals))","removed_duplicate $(count(==("duplicate"),removals))",
        "faces $(data[:initial_faces])","inconsistent_before $(length(data[:initial_inconsistent]))","flipped_faces $(data[:flipped_faces])","outward_components $(data[:outward_components])",
        "boundary_loops $(length(data[:loops_before]))","holes_filled $(count(loop->loop[:filled],data[:loops_before]))","fill_faces $(length(data[:added]))","final_vertices $(length(data[:points]))",
        "final_faces $(length(data[:faces]))","components $(length(data[:components]))","solids $(count(c->c[:solid],data[:components]))","total_area $(format_real(area(data[:faces],data[:points])))",
        "total_volume $(format_fraction(sum(comp[:volume6] for comp in data[:components] if comp[:solid];init=0),6))"
    ])
    lines
end
section_warnings(data) = vcat(["[warnings]"],["line $number $kind" for (number,kind) in data[:source].errors])
function section_cleanup(data)
    lines = ["[cleanup]","snapped $(length(data[:snapped_list]))"]
    for (number,before,after) in data[:snapped_list]
        push!(lines,"snap $number $(listing(before)) to $(listing(after))")
    end
    push!(lines,"merged $(count(i->data[:representative][i] != i,eachindex(data[:representative])))")
    for original in sort(collect(keys(data[:original_to_reps])))
        members = data[:original_to_reps][original]
        length(members) > 1 && push!(lines,"merge $(get(data[:renumber],original,"-")) $(listing(members))")
    end
    push!(lines,"removed $(length(data[:removed]))")
    for (face,reason) in data[:removed]
        push!(lines,"remove $(face.triangle) polygon $(face.polygon) line $(face.line) $reason")
    end
    lines
end
function section_components(data)
    lines = String[]
    for comp in data[:components]
        n = comp[:number]
        face_groups = Set(data[:faces][i].group for i in comp[:faces])
        groups = [group for group in data[:group_order] if group in face_groups]
        shapes = shape_counts(comp,data[:mesh],data[:faces],data[:points])
        append!(lines,["[component $n]","groups $(listing(groups))","faces $(length(comp[:faces]))","vertices $(length(comp[:vertices]))","edges $(length(comp[:edges]))",
            "boundary_edges $(length(comp[:boundary]))","nonmanifold_edges $(length(comp[:nonmanifold]))","nonmanifold_vertices $(length(comp[:nonmanifold_vertices]))","boundary_loops $(comp[:loops])"])
        for key in (:closed,:manifold,:orientable,:consistent,:solid)
            push!(lines,"$key $(yes(comp[key]))")
        end
        push!(lines,"euler $(comp[:euler])")
        push!(
            lines,
            !isnothing(comp[:genus]) ? "genus $(comp[:genus])" : !isnothing(comp[:crosscaps]) ? "crosscaps $(comp[:crosscaps])" : "genus -"
        )
        volume = comp[:solid] ? format_fraction(comp[:volume6],6) : "-"
        center = isnothing(comp[:centroid]) ? "-" : listing(format_fraction.(comp[:centroid]))
        append!(
            lines,
            [
                "volume $volume",
                "area $(format_real(comp[:area]))",
                "normal_sum $(listing(comp[:normal_sum]))",
                "bbox $(listing(comp[:bbox]))",
                "inside $(listing(comp[:inside]))",
                "centroid $center"
            ]
        )
        for shape in ("convex","concave","flat")
            push!(lines,"$shape $(get(shapes,shape,0))")
        end
        for angle in ("acute","right","obtuse")
            push!(lines,"$angle $(count(==(angle),comp[:angles]))")
        end
        append!(
            lines,
            [
                "edge_len2 $(comp[:edge_min]) $(comp[:edge_max])",
                "valence $(comp[:valence_min]) $(comp[:valence_max])"
            ]
        )
    end
    lines
end
function section_groups(data)
    lines = String[]
    mesh = data[:mesh]
    for group in data[:group_order]
        polygons = filter(p->p[:group] == group,data[:source].polygons)
        assigned = findall(face->face.group == group,data[:faces])
        components = sort(unique(mesh.face_components[assigned]))
        append!(lines,["[group $group]","polygons $(length(polygons))","triangles $(count(t->t.group == group,data[:triangles]))","nonplanar $(count(p->p[:number] in data[:nonplanar],polygons))",
            "faces $(length(assigned))","area $(format_real(area(data[:faces][assigned],data[:points])))","components $(listing(components))"])
    end
    lines
end
function section_contacts(data)
    lines = ["[contacts]"]
    comps,points = data[:components],data[:points]
    for i in eachindex(comps), j in i+1:length(comps)
        first_comp,second_comp = comps[i],comps[j]
        first_box,second_box = first_comp[:bbox],second_comp[:bbox]
        all(first_box[axis] <= second_box[axis+3] && second_box[axis] <= first_box[axis+3] for axis in 1:3) || continue
        shared = length(intersect(Set(first_comp[:vertices]),Set(second_comp[:vertices])))
        gap = minimum(dot(
            subtract(points[a],points[b]),
            subtract(points[a],points[b])
        ) for a in first_comp[:vertices] for b in second_comp[:vertices] if a != b)
        push!(lines,"contact $i $j shared $shared gap2 $gap")
    end
    lines
end
function section_edges(data)
    mesh,faces,points = data[:mesh],data[:faces],data[:points]
    lengths = [edge_length_squared(edge,points) for edge in mesh.edge_order]
    shapes = [edge_shape(edge,faces,points,mesh.edges[edge]) for edge in mesh.edge_order]
    adjacent_counts = [length(mesh.edges[edge]) for edge in mesh.edge_order]
    shortest,longest = argmin(lengths),argmax(lengths)
    lines = [
        "[edges]",
        "edges $(length(mesh.edges))",
        "boundary $(count(==(1),adjacent_counts))",
        "manifold $(count(==(2),adjacent_counts))",
        "nonmanifold $(count(>=(3),adjacent_counts))",
        "max_faces $(maximum(adjacent_counts))"
    ]
    for shape in ("convex","concave","flat","inconsistent")
        push!(lines,"$shape $(count(==(shape),shapes))")
    end
    append!(
        lines,
        [
            "shortest $(listing(mesh.edge_order[shortest])) len2 $(lengths[shortest])",
            "longest $(listing(mesh.edge_order[longest])) len2 $(lengths[longest])"
        ]
    )
    lines
end
function degrees(mesh,n)
    values = zeros(Int,n)
    for (a,b) in mesh.edge_order
        values[a] += 1
        values[b] += 1
    end
    values
end
function section_valence(data)
    degree = filter(>(0),degrees(data[:mesh],length(data[:points])))
    lines = [
        "[valence]",
        "used $(length(degree))",
        "isolated $(length(data[:points])-length(degree))",
        "min $(minimum(degree))",
        "max $(maximum(degree))",
        "mean $(format_fraction(sum(degree),length(degree)))"
    ]
    for value in sort(unique(degree))
        push!(lines,"degree $value $(count(==(value),degree))")
    end
    lines
end
function find_vertex_path(start,stop,mesh,n)
    graph = [Int[] for _ in 1:n]
    for (a,b) in mesh.edge_order
        push!(graph[a],b)
        push!(graph[b],a)
    end
    parent = fill(-1,n)
    parent[start] = 0
    queue = [start]
    index = 1
    while index <= length(queue)
        current = queue[index]
        index += 1
        for neighbor in sort(graph[current])
            if parent[neighbor] == -1
                parent[neighbor] = current
                push!(queue,neighbor)
            end
        end
    end
    parent[stop] == -1 && return nothing
    path = Int[]
    current = stop
    while current != 0
        push!(path,current)
        current = parent[current]
    end
    reverse(path)
end
function answer_query(kind,args,data)
    points,faces,mesh = data[:points],data[:faces],data[:mesh]
    if kind == "vertex"
        number = only(args)
        !(1 <= number <= length(points)) && return "vertex $number invalid"
        containing = findall(face->number in face.vertices,faces)
        degree = count(edge->number in edge,mesh.edge_order)
        fans = get(mesh.fans,number,Vector{Int}[])
        boundary = any(number in edge && length(mesh.edges[edge]) == 1 for edge in mesh.edge_order)
        components = sort(unique(mesh.face_components[containing]))
        return "vertex $number at $(listing(points[number])) faces $(length(containing)) valence $degree fans $(length(fans)) boundary $(yes(boundary)) components $(listing(components))"
    elseif kind == "face"
        number = only(args)
        !(1 <= number <= length(faces)) && return "face $number invalid"
        face = faces[number]
        neighbors = String[]
        for (a,b) in triangle_edges(face.vertices)
            participants = mesh.edges[key_edge(a,b)]
            push!(
                neighbors,
                length(participants) == 1 ? "-" : length(participants) >= 3 ? "*" : string(first(i for i in participants if i != number))
            )
        end
        polygon,line = face.polygon == 0 ? "-" : string(face.polygon),face.line == 0 ? "-" : string(face.line)
        return "face $number vertices $(listing(face.vertices)) group $(face.group) polygon $polygon line $line component $(mesh.face_components[number]) normal $(listing(normal(face,points))) area $(format_real(area([face],points))) neighbors $(listing(neighbors))"
    elseif kind == "edge"
        a,b = key_edge(args...)
        !haskey(mesh.edges,(a,b)) && return "edge $a $b none"
        adjacent = mesh.edges[(a,b)]
        category = length(adjacent) == 1 ? "boundary" : length(adjacent) == 2 ? "manifold" : "nonmanifold"
        return "edge $a $b faces $(listing(adjacent)) kind $category shape $(edge_shape((a,b),faces,points,adjacent)) len2 $(edge_length_squared((a,b),points))"
    elseif kind == "point"
        inside = Int[]
        total = 0
        for component in data[:components]
            component[:solid] || continue
            winding = winding_number(component[:faces],faces,points,Tuple(args))
            if winding != 0
                push!(inside,component[:number])
                total += winding
            end
        end
        return "point $(listing(args)) inside $(listing(inside)) winding $total"
    elseif kind == "path"
        start,stop = args
        !(1 <= start <= length(points) && 1 <= stop <= length(points)) && return "path $start $stop invalid"
        path = find_vertex_path(start,stop,mesh,length(points))
        return isnothing(path) ? "path $start $stop none" : "path $start $stop hops $(length(path)-1) vertices $(listing(path))"
    end
    scores = [dot(normal(face,points),args) for face in faces]
    silhouette = count(mesh.edge_order) do edge
        adjacent = mesh.edges[edge]
        length(adjacent) == 2 && ((scores[adjacent[1]] > 0 && scores[adjacent[2]] < 0) || (scores[adjacent[1]] < 0 && scores[adjacent[2]] > 0))
    end
    "view $(listing(args)) front $(count(>(0),scores)) back $(count(<(0),scores)) side $(count(==(0),scores)) silhouette $silhouette"
end
function section_queries(data)
    vcat(["[queries]"],[answer_query(kind,args,data) for (kind,args) in data[:settings][:queries]])
end
function boundaries_report(data)
    mesh = data[:mesh_before]
    lines = ["loops $(length(data[:loops_before]))"]
    for loop in data[:loops_before]
        push!(
            lines,
            "loop $(loop[:number]) component $(loop[:component]) length $(loop[:length]) $(loop[:kind]) $(loop[:filled] ? "filled" : "kept") vertices $(listing(loop[:vertices]))"
        )
    end
    nonmanifold = filter(edge->length(mesh.edges[edge]) >= 3,mesh.edge_order)
    push!(lines,"nonmanifold_edges $(length(nonmanifold))")
    for edge in nonmanifold
        push!(lines,"edge $(listing(edge)) faces $(listing(mesh.edges[edge]))")
    end
    push!(lines,"nonmanifold_vertices $(length(mesh.nonmanifold_vertices))")
    for vertex in mesh.nonmanifold_vertices
        components = sort(unique([mesh.face_components[face] for fan in mesh.fans[vertex] for face in fan]))
        push!(lines,"vertex $vertex fans $(length(mesh.fans[vertex])) components $(listing(components))")
    end
    push!(lines,"inconsistent_edges $(length(data[:inconsistent_after]))")
    for edge in data[:inconsistent_after]
        push!(lines,"edge $(listing(edge)) faces $(listing(mesh.edges[edge]))")
    end
    lines
end
function csv_components(data)
    lines = ["component,faces,vertices,closed,euler,genus,volume6,area"]
    for comp in data[:components]
        row = (
            comp[:number],
            length(comp[:faces]),
            length(comp[:vertices]),
            yes(comp[:closed]),
            comp[:euler],
            optional(comp[:genus]),
            comp[:solid] ? string(comp[:volume6]) : "-",
            format_real(comp[:area])
        )
        push!(lines,join(row,','))
    end
    lines
end
function main()
    source,settings = read_obj(),read_parameters()
    data = analyze_source(source,settings)
    actions = Dict(
        "summary"=>section_summary,
        "warnings"=>section_warnings,
        "cleanup"=>section_cleanup,
        "components"=>section_components,
        "groups"=>section_groups,
        "contacts"=>section_contacts,
        "edges"=>section_edges,
        "valence"=>section_valence,
        "queries"=>section_queries
    )
    report = String[]
    for section in settings[:sections]
        append!(report,actions[section](data))
    end
    outputs = (
        "report.txt"=>report,
        "components.csv"=>csv_components(data),
        "boundaries.txt"=>boundaries_report(data),
        "repaired.obj"=>write_repaired_obj(data[:points],data[:faces])
    )
    mkpath("output")
    for (name,lines) in outputs
        open(joinpath("output",name),"w") do handle
            foreach(line->println(handle,line),lines)
        end
    end
end
main()
