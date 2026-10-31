using Printf
include("rational.jl")
include("intersections.jl")
include("rings.jl")
include("greiner_hormann.jl")
include("render.jl")
const KINDS = [
    "UNION",
    "INTERSECTION",
    "DIFFERENCE",
    "XOR",
    "CLIP",
    "AREA",
    "MOVE",
    "ROTATE",
    "MIRROR",
    "SNAP",
    "LOCATE",
    "RENDER"
]
const BINARY = KINDS[1:5]
const DEFINITIONS = ["MOVE","ROTATE","MIRROR","SNAP"]
const WORD_COUNTS = Dict(zip(KINDS,[3,3,3,3,3,2,5,6,5,3,4,8]))
struct Rejected <: Exception
    reason::String
end
reject(reason) = throw(Rejected(reason))
line(parts...) = join(string.(parts)," ")
fixed3(value) = @sprintf("%.3f",value)
fixed6(value) = @sprintf("%.6f",value)
digits_word(word) = occursin(r"^[0-9]{1,9}$",word)
integer_word(word) = occursin(r"^-?[0-9]{1,9}$",word)
valid_name(word) = occursin(r"^[a-z0-9_]{1,16}$",word)
function records(name)
    return [(
        number=i,
        text=text
    ) for (i,text) in enumerate(readlines(joinpath("input",name))) if !isempty(text) && !startswith(text,"#")]
end
function canonical_polygon(name,input_rings)
    holes = [normalize_ring(r,false) for r in input_rings[2:end]]
    sort!(holes;by=r -> point_key(r[1]))
    return (name=name,input_rings=input_rings,rings=[[normalize_ring(input_rings[1],true)];holes])
end
function parse_rings(content,end_line)
    result = Vector{Point}[]
    position = 1
    while position <= length(content)
        record = content[position]
        words = split(record.text)
        if length(words) != 2 || !(words[1] in (
            "OUTER",
            "HOLE"
        )) || !digits_word(words[2]) || parse(Int,words[2]) < 1
            return nothing,record.number
        end
        if (words[1] == "OUTER" && !isempty(result)) || (words[1] == "HOLE" && isempty(result))
            return nothing,record.number
        end
        n = parse(Int,words[2])
        position += 1
        vertices = Point[]
        for _ in 1:n
            position > length(content) && return nothing,end_line
            record = content[position]
            words = split(record.text)
            (length(words) != 2 || !all(integer_word,words)) && return nothing,record.number
            push!(vertices,point(parse(Int,words[1]),parse(Int,words[2])))
            position += 1
        end
        push!(result,vertices)
    end
    return isempty(result) ? (nothing,end_line) : (result,0)
end
function check_polygon(sequence)
    for (k,ring) in enumerate(sequence)
        n = length(ring)
        n < 3 && return line("too_few_vertices ring",k)
        for p in ring
            !(0 <= p[1] <= 1000 && 0 <= p[2] <= 1000) && return line("out_of_range ring",k,point_text(p))
        end
        seen = Set{Point}()
        for p in ring
            p in seen && return line("duplicate_vertex ring",k,point_text(p))
            push!(seen,p)
        end
        for i in eachindex(ring)
            cross(
                ring[mod1(i-1,n)],
                ring[i],
                ring[mod1(i+1,n)]
            ) == 0 && return line("collinear ring",k,point_text(ring[i]))
        end
        edges = ring_edges(ring)
        for i in 1:n, j in (i+2):n
            i == 1 && j == n && continue
            a,b = edges[i]
            c,d = edges[j]
            segments_touch(a,b,c,d) && return line(
                "self_intersection ring",
                k,
                segment_text(a,b),
                segment_text(c,d)
            )
        end
    end
    for i in eachindex(sequence), j in (i+1):length(sequence)
        for (a,b) in ring_edges(sequence[i]), (c,d) in ring_edges(sequence[j])
            segments_touch(a,b,c,d) && return line(
                "rings_touch rings",
                i,
                j,
                segment_text(a,b),
                segment_text(c,d)
            )
        end
    end
    for k in 2:length(sequence)
        !inside_ring(sequence[1],sequence[k][1]) && return line(
            "hole_outside ring",
            k,
            point_text(sequence[k][1])
        )
    end
    for i in 2:length(sequence), j in (i+1):length(sequence)
        p = inside_ring(sequence[i],sequence[j][1]) ? sequence[j][1] : inside_ring(
            sequence[j],
            sequence[i][1]
        ) ? sequence[i][1] : nothing
        p !== nothing && return line("hole_in_hole rings",i,j,point_text(p))
    end
    return ""
end
function read_registry()
    used, polygons, invalid = Set{String}(),Dict{String,Any}(),String[]
    lines = records("polygons.txt")
    position, blocks, valid = 1,0,0
    while position <= length(lines)
        start = lines[position]
        name = String(split(start.text)[2])
        position += 1
        content = Any[]
        while lines[position].text != "END"
            push!(content,lines[position])
            position += 1
        end
        end_line = lines[position].number
        position += 1
        blocks += 1
        reason = ""
        if name in used
            reason = line("duplicate_name line",start.number)
        else
            push!(used,name)
            sequence,error_line = parse_rings(content,end_line)
            reason = error_line != 0 ? line("format line",error_line) : check_polygon(sequence)
            if isempty(reason)
                polygons[name] = canonical_polygon(name,sequence)
                valid += 1
            end
        end
        isempty(reason) || push!(invalid,line("polygon",name,reason))
    end
    return (used=used,polygons=polygons,invalid=invalid,blocks=blocks,valid=valid)
end
function resolve_polygon(registry,name)
    name in registry.used || reject("unknown_polygon " * name)
    haskey(registry.polygons,name) || reject("invalid_polygon " * name)
    return registry.polygons[name]
end
function arguments_valid(words)
    kind = words[1]
    length(words) == WORD_COUNTS[kind] || return false
    (kind in BINARY || kind == "AREA") && return true
    kind == "SNAP" && return valid_name(words[3])
    if kind == "MIRROR"
        return valid_name(words[5]) && words[3] in ("x","y") && integer_word(words[4]) && 0 <= parse(
            Int,
            words[4]
        ) <= 1000
    end
    selected = kind == "MOVE" ? words[3:4] : kind == "ROTATE" ? words[3:5] : words[3:end]
    all(integer_word,selected) || return false
    v = parse.(Int,selected)
    kind == "LOCATE" && return all(x -> 0 <= x <= 1000,v)
    kind == "MOVE" && return valid_name(words[5]) && all(x -> -1000 <= x <= 1000,v)
    kind == "ROTATE" && return valid_name(words[6]) && 0 <= v[1] <= 1000 && 0 <= v[2] <= 1000 && 1 <= v[3] <= 3
    x0,y0,cw,ch,cols,rows = v
    return x0 >= 0 && y0 >= 0 && 1 <= cw <= 100 && 1 <= ch <= 100 && 1 <= cols <= 100 && 1 <= rows <= 60 && x0+cw*cols <= 1000 && y0+ch*rows <= 1000
end
function general_position(first,second)
    av = [p for r in first.rings for p in r]
    bv = Set(p for r in second.rings for p in r)
    for p in av
        p in bv && return "shared_vertex " * point_text(p)
    end
    ae = [e for r in first.rings for e in ring_edges(r)]
    be = [e for r in second.rings for e in ring_edges(r)]
    for (a,b) in ae, (c,d) in be
        segments_overlap(a,b,c,d) && return line("overlapping_edges",segment_text(a,b),segment_text(c,d))
    end
    for (source,other,edges) in [(first,second,be),(second,first,ae)]
        for ring in source.rings, p in ring, (a,b) in edges
            on_segment(p,a,b) && return line(
                "vertex_on_edge",
                source.name,
                point_text(p),
                other.name,
                segment_text(a,b)
            )
        end
    end
    return ""
end
function transformed_rings(polygon,words)
    result = Vector{Point}[]
    for ring in polygon.input_rings
        transformed = Point[]
        for (x,y) in ring
            if words[1] == "MOVE"
                x,y = x+parse(Int,words[3]),y+parse(Int,words[4])
            elseif words[1] == "ROTATE"
                cx,cy,turns = parse.(Int,words[3:5])
                for _ in 1:turns
                    x,y = cx-(y-cy),cy+(x-cx)
                end
            elseif words[3] == "x"
                x = 2*parse(Int,words[4])-x
            else
                y = 2*parse(Int,words[4])-y
            end
            push!(transformed,(x,y))
        end
        push!(result,transformed)
    end
    return result
end
function resolve_target(registry,regions,word)
    if startswith(word,"@")
        suffix = word[2:end]
        (!digits_word(suffix) || !haskey(regions,parse(Int,suffix))) && reject("bad_target " * word)
        return regions[parse(Int,suffix)]
    end
    polygon = resolve_polygon(registry,word)
    return (polygons=[polygon.rings],operands=nothing)
end
function check_operation(registry,regions,words)
    kind = words[1]
    kind in KINDS || reject("unknown_operation " * kind)
    arguments_valid(words) || reject("bad_arguments")
    first,second,target,defined = nothing,nothing,nothing,nothing
    if kind in BINARY
        first,second = resolve_polygon(registry,words[2]),resolve_polygon(registry,words[3])
    elseif kind in ["AREA","MOVE","ROTATE","MIRROR"]
        first = resolve_polygon(registry,words[2])
    else
        target = resolve_target(registry,regions,words[2])
    end
    kind in DEFINITIONS && words[end] in registry.used && reject("duplicate_name " * words[end])
    kind == "SNAP" && length(target.polygons) != 1 && reject("not_single " * words[2])
    if kind == "CLIP"
        window = second.rings
        length(window) != 1 && reject("not_convex " * words[3])
        ring = window[1]
        any(cross(
            ring[mod1(i-1,length(ring))],
            ring[i],
            ring[mod1(i+1,length(ring))]
        ) <= 0 for i in eachindex(ring)) && reject("not_convex " * words[3])
    end
    if kind in BINARY
        error = general_position(first,second)
        isempty(error) || reject(error)
    end
    if kind in ["MOVE","ROTATE","MIRROR"]
        sequence = transformed_rings(first,words)
        any(!(0 <= p[1] <= 1000 && 0 <= p[2] <= 1000) for ring in sequence for p in ring) && reject("out_of_range " * words[end])
        defined = canonical_polygon(String(words[end]),sequence)
    elseif kind == "SNAP"
        sequence = [[point(
            floor(BigInt,p[1]+1//2),
            floor(BigInt,p[2]+1//2)
        ) for p in ring] for ring in target.polygons[1]]
        error = check_polygon(sequence)
        isempty(error) || reject("invalid_result " * error)
        defined = canonical_polygon(String(words[end]),sequence)
    end
    return (first=first,second=second,target=target,defined=defined)
end
function total_area(polygons)
    total = 0.0
    for polygon in polygons, ring in polygon
        total += ring_area(ring)
    end
    return total
end
function binary_result(kind,first,second)
    graph = build_graph(first.rings,second.rings)
    intersection = assemble_rings(traverse_graph(graph,false,false))
    union_result = assemble_rings(traverse_graph(graph,true,true))
    polygons = kind == "UNION" ? union_result : kind in [
        "INTERSECTION",
        "CLIP"
    ] ? intersection : assemble_rings(traverse_graph(graph,true,false))
    if kind == "XOR"
        other = build_graph(second.rings,first.rings)
        append!(polygons,assemble_rings(traverse_graph(other,true,false)))
        sort!(polygons;by=p -> point_key(p[1][1]))
    end
    relation = !isempty(graph.crossings) ? "overlap" : graph.n_a == length(first.rings) && graph.n_b == 0 ? "within" : graph.n_b == length(second.rings) && graph.n_a == 0 ? "contains" : graph.n_a == 0 && graph.n_b == 0 ? "disjoint" : "overlap"
    return (
        polygons=polygons,
        operands=(first,second)
    ),graph,relation,total_area(intersection)/total_area(union_result)
end
function cyclic_equal(a,b)
    length(a) == length(b) || return false
    return any(all(a[i] == b[mod1(start+i-1,length(b))] for i in eachindex(a)) for start in eachindex(b))
end
function crosscheck_clip(first,window,polygons)
    clipped = Vector{Point}[]
    for ring in first.rings
        points = copy(ring)
        for (c,d) in ring_edges(window.rings[1])
            replacement = Point[]
            for i in eachindex(points)
                previous,current = points[mod1(i-1,length(points))],points[i]
                a,b = cross(c,d,previous),cross(c,d,current)
                (a > 0) != (b > 0) && push!(replacement,clipping_point(previous,current,a,b))
                b > 0 && push!(replacement,current)
            end
            points = replacement
        end
        deduplicated = [points[i] for i in eachindex(points) if points[i] != points[mod1(i-1,length(points))]]
        length(deduplicated) >= 3 && push!(clipped,deduplicated)
    end
    result_rings = [r for p in polygons for r in p]
    matches = length(result_rings) == length(clipped) && all(any(cyclic_equal(
        r,
        s
    ) for s in clipped) for r in result_rings)
    return line(
        "crosscheck",
        matches ? "match" : "mismatch",
        "rings",
        length(clipped),
        "vertices",
        sum(length,clipped;init=0)
    )
end
function result_values(polygons,first,second)
    lines = String[]
    av = Set(p for r in first.rings for p in r)
    bv = second === nothing ? Set{Point}() : Set(p for r in second.rings for p in r)
    origins = zeros(Int,3)
    vertices = Point[]
    ring_count,hole_count,total,perimeter,sx,sy = 0,0,0.0,0.0,0.0,0.0
    for (k,polygon) in enumerate(polygons), (j,ring) in enumerate(polygon)
        ring_count += 1
        hole_count += j > 1
        area = ring_area(ring)
        total += area
        perimeter += ring_perimeter(ring)
        prefix = j == 1 ? line("outer",k) : line("hole",k,j-1)
        push!(lines,line(prefix,length(ring),fixed3(area),join(point_text.(ring)," ")))
        append!(vertices,ring)
        for (a,b) in ring_edges(ring)
            origins[a in av ? 1 : a in bv ? 2 : 3] += 1
            x1,y1,x2,y2 = coordinate_real(a[1]),coordinate_real(a[2]),coordinate_real(b[1]),coordinate_real(b[2])
            c = x1*y2-x2*y1
            sx += (x1+x2)*c
            sy += (y1+y2)*c
        end
    end
    pushfirst!(
        lines,
        line(
            "polygons",
            length(polygons),
            "rings",
            ring_count,
            "holes",
            hole_count,
            "vertices",
            length(vertices),
            "area",
            fixed3(total)
        )
    )
    if isempty(vertices)
        append!(lines,["bbox none","centroid none"])
    else
        low = (minimum(p[1] for p in vertices),minimum(p[2] for p in vertices))
        high = (maximum(p[1] for p in vertices),maximum(p[2] for p in vertices))
        push!(lines,line("bbox",point_text(low),point_text(high)))
        push!(lines,string("centroid (",fixed3(sx/(6.0*total)),",",fixed3(sy/(6.0*total)),")"))
    end
    push!(lines,line("perimeter",fixed3(perimeter)))
    push!(lines,line("origins a",origins[1],"b",origins[2],"crossing",origins[3]))
    return (lines=lines,rings=ring_count,holes=hole_count,vertices=length(vertices),area=total)
end
function property_lines(polygon,area)
    orientations = [sum((a[1]*b[2]-b[1]*a[2] for (
        a,
        b
    ) in ring_edges(r));init=BigInt(0)//BigInt(1)) > 0 ? "ccw" : "cw" for r in polygon.input_rings]
    reflex = sum((count(
        i -> cross(r[mod1(i-1,length(r))],r[i],r[mod1(i+1,length(r))]) < 0,
        eachindex(r)
    ) for r in polygon.rings);init=0)
    ordered = sort(polygon.rings[1];by=p -> (p[1],p[2]))
    chains = Vector{Point}[]
    for sequence in [ordered,reverse(ordered)]
        chain = Point[]
        for p in sequence
            while length(chain) >= 2 && cross(chain[end-1],chain[end],p) <= 0
                pop!(chain)
            end
            push!(chain,p)
        end
        push!(chains,chain)
    end
    hull = [chains[1][1:end-1];chains[2][1:end-1]]
    hull_area = coordinate_real(sum((a[1]*b[2]-b[1]*a[2] for (
        a,
        b
    ) in ring_edges(hull));init=BigInt(0)//BigInt(1))/2)
    return [
        line("input",join(orientations," ")),
        line("reflex",reflex),
        line("hull",length(hull),fixed3(hull_area),"solidity",fixed6(area/hull_area))
    ]
end
function locate(polygons,p)
    for (k,polygon) in enumerate(polygons)
        boundary(polygon[1],p) && return line("boundary outer",k)
        for j in 2:length(polygon)
            boundary(polygon[j],p) && return line("boundary hole",k,j-1)
        end
    end
    for (k,polygon) in enumerate(polygons)
        inside_ring(polygon[1],p) && !any(inside_ring(r,p) for r in polygon[2:end]) && return line(
            "inside polygon",
            k
        )
    end
    return "outside"
end
operand_location(polygon,p) = any(boundary(r,p) for r in polygon.rings) ? "boundary" : interior(
    polygon.rings,
    p
) ? "inside" : "outside"
function main()
    registry = read_registry()
    operations = records("operations.txt")
    regions = Dict{Int,Any}()
    results,areas,drawings,rejected = String[],["operation,rings,holes,vertices,area"],String[],String[]
    kind_totals,kind_succeeded = Dict(k=>0 for k in KINDS),Dict(k=>0 for k in KINDS)
    succeeded,defined,crossings = 0,0,0
    for (number,record) in enumerate(operations)
        words = String.(split(record.text))
        kind = words[1]
        haskey(kind_totals,kind) && (kind_totals[kind] += 1)
        checked = try
            check_operation(registry,regions,words)
        catch error
            error isa Rejected || rethrow()
            push!(rejected,line("op",number,error.reason))
            continue
        end
        succeeded += 1
        kind_succeeded[kind] += 1
        if kind in DEFINITIONS
            registry.polygons[checked.defined.name] = checked.defined
            push!(registry.used,checked.defined.name)
            defined += 1
        end
        if kind == "RENDER"
            parameters = parse.(Int,words[3:end])
            grid,counts = render_grid(checked.target.polygons,checked.target.operands,parameters...)
            push!(
                drawings,
                line(
                    "render",
                    number,
                    words[2],
                    "cols",
                    parameters[5],
                    "rows",
                    parameters[6],
                    "result",
                    counts['#'],
                    "a",
                    counts['a'],
                    "b",
                    counts['b'],
                    "both",
                    counts['+']
                )
            )
            append!(drawings,grid)
        elseif kind == "LOCATE"
            p = point(parse(Int,words[3]),parse(Int,words[4]))
            push!(results,line("op",number,record.text))
            push!(results,line("location",locate(checked.target.polygons,p)))
            if checked.target.operands !== nothing
                a,b = checked.target.operands
                push!(results,line("operands a",operand_location(a,p),"b",operand_location(b,p)))
            end
        else
            push!(results,line("op",number,record.text))
            first,second = checked.first,checked.second
            if kind in BINARY
                region,graph,relation,iou = binary_result(kind,first,second)
                push!(results,line("relation",relation,"iou",fixed6(iou)))
                push!(results,line("crossings",length(graph.crossings)))
                crossings += length(graph.crossings)
                for id in graph.crossings
                    node = graph.nodes[id]
                    push!(results,line("crossing",point_text(node.point),node.entering ? "in" : "out"))
                end
            else
                first = kind in DEFINITIONS ? checked.defined : first
                second = nothing
                region = (polygons=[first.rings],operands=nothing)
            end
            regions[number] = region
            values = result_values(region.polygons,first,second)
            append!(results,values.lines)
            kind in BINARY || append!(results,property_lines(first,values.area))
            kind == "CLIP" && push!(results,crosscheck_clip(first,second,region.polygons))
            push!(
                areas,
                string(
                    number,
                    ":",
                    join(words,":"),
                    ",",
                    values.rings,
                    ",",
                    values.holes,
                    ",",
                    values.vertices,
                    ",",
                    fixed3(values.area)
                )
            )
        end
    end
    push!(
        results,
        line(
            "summary polygons",
            registry.blocks,
            "valid",
            registry.valid,
            "invalid",
            length(registry.invalid),
            "defined",
            defined
        )
    )
    push!(
        results,
        line("summary operations",length(operations),"succeeded",succeeded,"rejected",length(rejected))
    )
    push!(results,line("summary crossings",crossings))
    append!(results,[line("kind",kind,kind_totals[kind],kind_succeeded[kind]) for kind in KINDS])
    rejections = [line("rejections",length(registry.invalid)+length(rejected));registry.invalid;rejected]
    mkpath("output")
    for (name,lines) in [
        ("results.txt",results),
        ("areas.csv",areas),
        ("render.txt",drawings),
        ("rejections.txt",rejections)
    ]
        open(joinpath("output",name),"w") do stream
            for text in lines
                println(stream,text)
            end
        end
    end
end
main()
