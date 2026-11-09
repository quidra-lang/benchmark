include("dataset.jl")
include("kdtree.jl")
include("quadtree.jl")
include("rtree.jl")
include("grid.jl")
include("report.jl")
const POINT_STRUCTURES = ["kdtree","quadtree","rtree","str","grid"]
const RECTANGLE_STRUCTURES = ["rtree_rect","str_rect"]
const RTREE_STRUCTURES = ["rtree","str","rtree_rect","str_rect"]
const SEARCH_COMMANDS = ["RANGE","RADIUS","KNN","WINDOWCOUNT","CONTAINS","NEAREST","JOIN"]
struct NodeView
    region::NTuple{4,Int}
    held::Vector{Vector{Int}}
    children::Vector{NodeView}
    source::Any
    mark::String
    depth::Int
    count::Int
end
function node_view(region,held,children,source,mark="root",depth=0)
    NodeView(
        region,
        held,
        children,
        source,
        mark,
        depth,
        length(held)+sum((child.count for child in children);init=0)
    )
end
function kd_view(node,region,mark="root",depth=0)
    x1,y1,x2,y2 = region
    split = node.point[node.axis+2]
    left,right = node.axis==0 ? ((x1,y1,split,y2),(split,y1,x2,y2)) : ((x1,y1,x2,split),(x1,split,x2,y2))
    children = NodeView[]
    isnothing(node.left) || push!(children,kd_view(node.left,left,"L",depth+1))
    isnothing(node.right) || push!(children,kd_view(node.right,right,"R",depth+1))
    node_view(region,[node.point],children,node,mark,depth)
end
function quad_view(node,mark="root",depth=0)
    children = [quad_view(child,CHILD_NAMES[i],depth+1) for (i,child) in enumerate(node.children)]
    node_view(
        (node.x,node.y,node.x+node.size-1,node.y+node.size-1),
        copy(node.points),
        children,
        node,
        mark,
        depth
    )
end
function rtree_view(node,objects,depth=0)
    held = node.level==0 ? [objects[entry.id] for entry in node.entries] : Vector{Int}[]
    children = node.level==0 ? NodeView[] : [rtree_view(
        entry.child,
        objects,
        depth+1
    ) for entry in node.entries]
    node_view(node_box(node),held,children,node,"root",depth)
end
function grid_view(grid)
    cells = [node_view(cell.box,copy(cell.points),NodeView[],cell,"root",1) for cell in grid.cells]
    node_view((0,0,grid.world-1,grid.world-1),Vector{Int}[],cells,grid)
end
function preorder(root)
    result,pending = NodeView[],[root]
    while !isempty(pending)
        node = pop!(pending)
        push!(result,node)
        append!(pending,reverse(node.children))
    end
    result
end
object_box(obj) = length(obj)==3 ? point_box(obj) : Tuple(obj[2:end])
point_distance(q,p) = (p[2]-q[1])^2+(p[3]-q[2])^2
function minimum_distance(q,b)
    dx = q[1]<b[1] ? b[1]-q[1] : q[1]>b[3] ? q[1]-b[3] : 0
    dy = q[2]<b[2] ? b[2]-q[2] : q[2]>b[4] ? q[2]-b[4] : 0
    dx*dx+dy*dy
end
object_distance(q,obj) = length(obj)==3 ? point_distance(q,obj) : minimum_distance(q,object_box(obj))
function search_conditions(command,values)
    if command=="RANGE"
        box = Tuple(values)
        return region->intersects(region,box),point->box_contains(box,point_box(point))
    elseif command=="RADIUS"
        q,limit = values[1:2],values[3]^2
        return region->minimum_distance(q,region)<=limit,point->point_distance(q,point)<=limit
    end
    x,y = values
    box = (x,y,x,y)
    region->box_contains(region,box),rectangle->box_contains(object_box(rectangle),box)
end
function condition_search(root,region_condition,object_condition)
    answer,pending = Int[],[root]
    nodes = tests = 0
    while !isempty(pending)
        node = pop!(pending)
        nodes += 1
        tests += length(node.held)
        append!(answer,[obj[1] for obj in node.held if object_condition(obj)])
        append!(pending,reverse([child for child in node.children if region_condition(child.region)]))
    end
    (answer=sort(answer),nodes=nodes,tests=tests)
end
function window_count(root,window)
    answer = nodes = tests = 0
    pending = [root]
    while !isempty(pending)
        node = pop!(pending)
        nodes += 1
        if box_contains(window,node.region)
            answer += node.count
        else
            tests += length(node.held)
            answer += count(point->box_contains(window,point_box(point)),node.held)
            append!(pending,reverse([child for child in node.children if intersects(child.region,window)]))
        end
    end
    (answer=answer,nodes=nodes,tests=tests)
end
function heap_push!(heap,item)
    push!(heap,item)
    i = length(heap)
    while i>1
        parent = i÷2
        heap[parent][1]<=heap[i][1] && break
        heap[parent],heap[i] = heap[i],heap[parent]
        i = parent
    end
end
function heap_pop!(heap)
    result = heap[1]
    tail = pop!(heap)
    if !isempty(heap)
        heap[1] = tail
        i = 1
        while 2i<=length(heap)
            child = 2i
            child<length(heap) && heap[child+1][1]<heap[child][1] && (child+=1)
            heap[i][1]<=heap[child][1] && break
            heap[i],heap[child] = heap[child],heap[i]
            i = child
        end
    end
    result
end
function best_first(root,q,k)
    heap = Tuple{NTuple{3,Int},Any}[]
    heap_push!(heap,((minimum_distance(q,root.region),0,0),root))
    serial = 1
    answer = Tuple{Int,Int}[]
    nodes = tests = 0
    while !isempty(heap)
        key,element = heap_pop!(heap)
        distance,kind,tie = key
        if kind==1
            push!(answer,(element[1],distance))
            length(answer)==k && break
        else
            nodes += 1
            tests += length(element.held)
            for obj in element.held
                heap_push!(heap,((object_distance(q,obj),1,obj[1]),obj))
            end
            for child in element.children
                heap_push!(heap,((minimum_distance(q,child.region),0,serial),child))
                serial += 1
            end
        end
    end
    (answer=answer,nodes=nodes,tests=tests)
end
function spatial_join(point_root,rectangle_root)
    answer = Tuple{Int,Int}[]
    nodes = tests = 0
    pending = [(point_root,rectangle_root)]
    while !isempty(pending)
        a,b = pop!(pending)
        nodes += 1
        if isempty(a.children) && isempty(b.children)
            tests += length(a.held)*length(b.held)
            for p in a.held,r in b.held
                box_contains(object_box(r),point_box(p)) && push!(answer,(r[1],p[1]))
            end
        else
            left = isempty(a.children) ? [a] : a.children
            right = isempty(b.children) ? [b] : b.children
            children = [(u,v) for u in left for v in right if intersects(u.region,v.region)]
            append!(pending,reverse(children))
        end
    end
    (answer=sort(answer),nodes=nodes,tests=tests)
end
function brute_force(command,values,points,rectangles)
    if command in ("RANGE","RADIUS","CONTAINS")
        _,condition = search_conditions(command,values)
        objects = command=="CONTAINS" ? rectangles : points
        return sort([obj[1] for obj in objects if condition(obj)])
    elseif command=="WINDOWCOUNT"
        return count(p->box_contains(Tuple(values),point_box(p)),points)
    elseif command in ("KNN","NEAREST")
        q,k = values[1:2],values[3]
        objects = command=="NEAREST" ? rectangles : points
        ordered = sort([(object_distance(q,obj),obj[1]) for obj in objects])
        return [(id,distance) for (distance,id) in ordered[1:k]]
    end
    sort([(r[1],p[1]) for r in rectangles for p in points if box_contains(object_box(r),point_box(p))])
end
structures_for(command) = command=="JOIN" ? ["rtree","str"] : command in (
    "CONTAINS",
    "NEAREST"
) ? RECTANGLE_STRUCTURES : POINT_STRUCTURES
function locate_kd(node,p)
    path = ""
    while node.point[1]!=p[1]
        left = kd_key(p,node.axis)<kd_key(node.point,node.axis)
        path *= left ? "L" : "R"
        node = left ? node.left : node.right
    end
    isempty(path) ? "-" : path
end
function locate_quad(node,p)
    path = String[]
    while !isempty(node.children)
        destination = quad_destination(node,p)
        push!(path,CHILD_NAMES[destination])
        node = node.children[destination]
    end
    isempty(path) ? "-" : join(path,"/")
end
function locate_rtree(root,p)
    pending = [(root,Int[])]
    while !isempty(pending)
        node,path = pop!(pending)
        if node.level==0
            index = findfirst(entry->entry.id==p[1],node.entries)
            isnothing(index) || return join(vcat(path,[index]),"/")
        else
            for (i,entry) in reverse(collect(enumerate(node.entries)))
                box_contains(entry.box,point_box(p)) && push!(pending,(entry.child,vcat(path,[i])))
            end
        end
    end
    "-"
end
function dump_tree(name,root)
    lines = String[]
    for v in preorder(root)
        prefix = repeat("  ",v.depth+1)
        if name=="kdtree"
            axis = v.source.axis==0 ? "x" : "y"
            line = "$(v.mark) $axis $(ids(v.held[1])) box $(ids(v.region))"
        elseif name=="quadtree"
            node = v.source
            contents = isempty(v.children) ? "leaf $(ids(p[1] for p in v.held))" : "node count $(v.count)"
            line = "$(v.mark) $(node.x) $(node.y) $(node.size) $contents"
        elseif v.source.level==0
            line = "leaf $(ids(v.region)) ids $(ids(p[1] for p in v.held))"
        else
            line = "node $(v.source.level) $(ids(v.region)) entries $(length(v.source.entries))"
        end
        push!(lines,prefix*line)
    end
    lines
end
function kd_statistics(root)
    nodes = preorder(root)
    height = maximum(v.depth for v in nodes)+1
    n,leaves,one,depth_sum = length(nodes),count(v->isempty(v.children),nodes),count(
        v->length(v.children)==1,
        nodes
    ),sum(v.depth for v in nodes)
    ideal = 0
    while 2^ideal-1<n
        ideal += 1
    end
    lines = ["kdtree height $height ideal $ideal nodes $n leaves $leaves one_child $one depth_sum $depth_sum avg_depth $(fraction(depth_sum,n))"]
    for depth in 0:height-1
        group = [v for v in nodes if v.depth==depth]
        push!(
            lines,
            "  depth $depth nodes $(length(group)) leaves $(count(v->isempty(v.children),group)) one_child $(count(v->length(v.children)==1,group))"
        )
    end
    lines
end
function quad_statistics(root,capacity)
    nodes = preorder(root)
    height = maximum(v.depth for v in nodes)+1
    leaves = [v for v in nodes if isempty(v.children)]
    lines = ["quadtree height $height internal $(length(nodes)-length(leaves)) leaves $(length(leaves)) empty $(count(v->isempty(v.held),leaves)) max_leaf $(maximum(length(v.held) for v in leaves)) fill $(fraction(root.count,length(leaves)*capacity))"]
    for depth in 0:height-1
        group = [v for v in nodes if v.depth==depth]
        local_leaves = [v for v in group if isempty(v.children)]
        push!(
            lines,
            "  depth $depth internal $(length(group)-length(local_leaves)) leaves $(length(local_leaves)) points $(sum((length(v.held) for v in local_leaves);init=0))"
        )
    end
    lines
end
function rtree_statistics(name,root,maximum_entries,minimum_entries)
    nodes = preorder(root)
    height = root.source.level+1
    entries = sum(length(v.source.entries) for v in nodes)
    lines = ["$name height $height nodes $(length(nodes)) leaves $(count(v->v.source.level==0,nodes)) entries $entries fill $(fraction(entries,length(nodes)*maximum_entries))"]
    for level in height-1:-1:0
        group = [v for v in nodes if v.source.level==level]
        sizes = [length(v.source.entries) for v in group]
        area_sum,overlap_sum = sum(area(v.region) for v in group),0
        for i in 1:length(group)-1,j in i+1:length(group)
            overlap_sum += overlap(group[i].region,group[j].region)
        end
        push!(
            lines,
            "  level $level nodes $(length(group)) entries $(sum(sizes)) min $(minimum(sizes)) max $(maximum(sizes)) under $(count(<(minimum_entries),sizes)) area $area_sum overlap $overlap_sum"
        )
    end
    lines
end
function grid_statistics(root)
    counts = [length(v.held) for v in root.children]
    sequence = join(("$k:$(count(==(k),counts))" for k in sort(unique(counts)))," ")
    ["grid cells $(length(counts)) used $(count(>(0),counts)) max $(maximum(counts))","  occupancy $sequence"]
end
function snapshot(views,number,query,point_count,rectangle_count,params)
    header = "snapshot $number query $query points $point_count rects $rectangle_count"
    structures = [header]
    stats = vcat([header],kd_statistics(views["kdtree"]),quad_statistics(views["quadtree"],params.bucket))
    for name in vcat(["kdtree","quadtree"],RTREE_STRUCTURES)
        push!(structures,name)
        append!(structures,dump_tree(name,views[name]))
        name in RTREE_STRUCTURES && append!(
            stats,
            rtree_statistics(name,views[name],params.maximum,params.minimum)
        )
    end
    append!(stats,grid_statistics(views["grid"]))
    structures,stats
end
function visits_summary(totals)
    lines = ["visits"]
    for command in SEARCH_COMMANDS
        haskey(totals,command) || continue
        names = structures_for(command)
        rows = totals[command]
        for name in names
            q,n,t,m = rows[name]
            push!(
                lines,
                "$command $name queries $q nodes $n tests $t max_nodes $m mean_nodes $(fraction(n,q))"
            )
        end
        ranked = sort(collect(eachindex(names));by=i->(rows[names[i]][2],rows[names[i]][3],i))
        push!(lines,"rank $command "*join(names[ranked]," "))
    end
    lines
end
function main()
    initial,rectangle_rows,params,commands = read_dataset()
    points = Dict(p[1]=>p for p in initial)
    rectangles = Dict(r[1]=>r for r in rectangle_rows)
    kd,quad = kd_build(initial),quad_build(initial,params.world,params.bucket)
    grid = UniformGrid(params.world,params.cell_size,initial)
    trees = Dict(name=>rtree_build(
        name in RECTANGLE_STRUCTURES ? rectangle_rows : initial,
        params.maximum,
        params.minimum;bulk=name in ("str","str_rect")
    ) for name in RTREE_STRUCTURES)
    views = Dict{String,NodeView}()
    function refresh_views!()
        views["kdtree"] = kd_view(kd,(0,0,params.world-1,params.world-1))
        views["quadtree"] = quad_view(quad)
        views["grid"] = grid_view(grid)
        for name in RTREE_STRUCTURES
            views[name] = rtree_view(trees[name].root,name in RECTANGLE_STRUCTURES ? rectangles : points)
        end
    end
    refresh_views!()
    structures,stats = snapshot(views,0,0,length(points),length(rectangles),params)
    answers,visits,join_rows = String[],["query,command,structure,nodes,tests"],["query,rect,point"]
    totals = Dict{String,Dict{String,Vector{Int}}}()
    snapshot_number = 0
    for (q,command) in enumerate(commands)
        name,values = command.name,command.values
        if name in SEARCH_COMMANDS
            expected = brute_force(name,values,collect(Base.values(points)),collect(Base.values(rectangles)))
            mismatches = String[]
            for structure in structures_for(name)
                root = views[structure]
                if name in ("RANGE","RADIUS","CONTAINS")
                    result = condition_search(root,search_conditions(name,values)...)
                elseif name=="WINDOWCOUNT"
                    result = window_count(root,Tuple(values))
                elseif name=="JOIN"
                    result = spatial_join(root,views[structure*"_rect"])
                else
                    result = best_first(root,values[1:2],values[3])
                end
                result.answer==expected || push!(mismatches,structure)
                push!(visits,"$q,$name,$structure,$(result.nodes),$(result.tests)")
                rows = get!(totals,name,Dict{String,Vector{Int}}())
                row = get!(rows,structure,zeros(Int,4))
                row[1] += 1
                row[2] += result.nodes
                row[3] += result.tests
                row[4] = max(row[4],result.nodes)
            end
            check = isempty(mismatches) ? "ok" : "mismatch "*join(mismatches," ")
            if name=="WINDOWCOUNT"
                line = "$q $name count $expected check $check"
            elseif name=="JOIN"
                line = "$q $name count $(length(expected)) check $check"
                append!(join_rows,["$q,$r,$p" for (r,p) in expected])
            else
                sequence = name in ("KNN","NEAREST") ? distances(expected) : ids(expected)
                line = "$q $name count $(length(expected)) ids $sequence check $check"
            end
            push!(answers,line)
        elseif name=="LOCATE"
            id = values[1]
            if !haskey(points,id)
                push!(answers,"$q LOCATE $id missing")
            else
                p = points[id]
                c,r = grid_position(grid,p)
                push!(
                    answers,
                    "$q LOCATE $id kdtree $(locate_kd(kd,p)) quadtree $(locate_quad(quad,p)) rtree $(locate_rtree(trees["rtree"].root,p)) str $(locate_rtree(trees["str"].root,p)) grid $c $r"
                )
            end
        elseif name=="INSERT"
            p = values
            points[p[1]] = p
            kd = kd_insert!(kd,p)
            quad_insert!(quad,p,params.bucket)
            for structure in ("rtree","str")
                rtree_insert!(trees[structure],REntry(point_box(p),p[1],nothing))
            end
            grid_insert!(grid,p)
            refresh_views!()
            push!(answers,"$q INSERT $(p[1]) inserted points $(length(points))")
        elseif name=="DELETE"
            id = values[1]
            status = "missing"
            if haskey(points,id)
                p = points[id]
                kd = kd_delete!(kd,p)
                quad_delete!(quad,p,params.bucket)
                for structure in ("rtree","str")
                    rtree_delete!(trees[structure],p)
                end
                grid_delete!(grid,p)
                delete!(points,id)
                refresh_views!()
                status = "deleted"
            end
            push!(answers,"$q DELETE $id $status points $(length(points))")
        else
            snapshot_number += 1
            a,b = snapshot(views,snapshot_number,q,length(points),length(rectangles),params)
            push!(structures,"")
            append!(structures,a)
            push!(stats,"")
            append!(stats,b)
            push!(answers,"$q DUMP snapshot $snapshot_number")
        end
    end
    push!(stats,"")
    append!(stats,visits_summary(totals))
    for (name,lines) in (
        ("answers.txt",answers),
        ("visits.csv",visits),
        ("join.csv",join_rows),
        ("structures.txt",structures),
        ("stats.txt",stats)
    )
        write_lines(name,lines)
    end
end
main()
