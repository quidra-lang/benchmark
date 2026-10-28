include("pgm_io.jl")
include("filters.jl")
include("canny.jl")
include("hough.jl")
include("corners.jl")
const POLYGON_KINDS = [
    "equilateral_triangle",
    "right_triangle",
    "triangle",
    "square",
    "rectangle",
    "parallelogram",
    "trapezoid",
    "quadrilateral"
]
cross2(a,b) = a[1]*b[2]-a[2]*b[1]
dot2(a,b) = a[1]*b[1]+a[2]*b[2]
difference(a,b) = (a[1]-b[1],a[2]-b[2])
chebyshev(a,b) = max(abs(a[1]-b[1]),abs(a[2]-b[2]))
angle_difference(a,b) = min(abs(a-b),180-abs(a-b))
function nearest_integer(n,d)
    d<0 && ((n,d)=(-n,-d))
    fld(2n+d,2d)
end
function bresenham(start,ending)
    x,y = start
    x1,y1 = ending
    dx,dy = abs(x1-x),-abs(y1-y)
    sx,sy = x<x1 ? 1 : -1,y<y1 ? 1 : -1
    error = dx+dy
    points = Tuple{Int,Int}[]
    while true
        push!(points,(x,y))
        x==x1 && y==y1 && break
        twice = 2error
        if twice>=dy
            error += dy
            x += sx
        end
        if twice<=dx
            error += dx
            y += sy
        end
    end
    points
end
function circle_gaps(center,outline,edges)
    half(p) = p[2]>0 || (p[2]==0 && p[1]>0) ? 0 : 1
    offsets = sort(collect(outline);lt=(a,b)->half(a)!=half(b) ? half(a)<half(b) : cross2(a,b)>0)
    hits = [(center[1]+dx,center[2]+dy) in edges for (dx,dy) in offsets]
    n = length(hits)
    all(hits) && return 0,1
    any(hits) || return n,0
    arcs = count(i->hits[i] && !hits[mod1(i-1,n)],1:n)
    maximum_gap,run = 0,0
    for hit in vcat(hits,hits)
        run = hit ? 0 : run+1
        maximum_gap = max(maximum_gap,run)
    end
    min(maximum_gap,n),arcs
end
on_circumference(point,circle) = (circle.radius-1)^2<=dot2(
    difference(point,circle.center),
    difference(point,circle.center)
)<=(circle.radius+1)^2
function selected_circles(outlines,peaks,edges,maximum_count)
    circles = NamedTuple[]
    for cell in peaks[1:min(maximum_count,length(peaks))]
        center,outline = (cell.x,cell.y),outlines[cell.radius]
        gap,arcs = circle_gaps(center,outline,edges)
        push!(
            circles,
            (
                type="circle",
                number=length(circles)+1,
                center=center,
                radius=cell.radius,
                votes=cell.votes,
                outline=outline,
                outline_count=length(outline),
                gap=gap,
                arcs=arcs
            )
        )
    end
    circle_edges = Set(p for p in edges if any(c->on_circumference(p,c),circles))
    circles,circle_edges,setdiff(edges,circle_edges)
end
function extract_segments(peaks,line_edges,trig,params)
    used = Set{Tuple{Int,Int}}()
    lines,segments = NamedTuple[],NamedTuple[]
    for peak in peaks
        length(lines)>=params["hough_max_lines"][1] && break
        cosine,sine = trig[peak.theta+1]
        available = [p for p in line_edges if !(p in used) && abs(rho(
            p,
            peak.theta,
            trig,
            params["hough_rho_step"][1]
        )-peak.rho)<=params["segment_tolerance"][1]]
        sort!(available;by=p->(p[2]*cosine-p[1]*sine,p[1],p[2]))
        groups = Vector{Tuple{Int,Int}}[]
        for p in available
            if isempty(groups) || (p[2]*cosine-p[1]*sine)-(groups[end][end][2]*cosine-groups[end][end][1]*sine)>params["segment_max_gap"][1]*16384
                push!(groups,Tuple{Int,Int}[])
            end
            push!(groups[end],p)
        end
        pending = [group for group in groups if chebyshev(
            group[1],
            group[end]
        )+1>=params["segment_min_length"][1]]
        isempty(pending) && continue
        numbers = Int[]
        for group in pending
            number = length(segments)+1
            push!(
                segments,
                (
                    number=number,
                    line=length(lines)+1,
                    start=group[1],
                    ending=group[end],
                    length=chebyshev(group[1],group[end])+1,
                    pixels=length(group),
                    points=group,
                    theta=peak.theta
                )
            )
            push!(numbers,number)
            union!(used,group)
        end
        push!(lines,(;peak...,number=length(lines)+1,segments=numbers))
    end
    lines,segments,used
end
function build_junctions(segments,minimum_angle,maximum_distance)
    joins = Dict{Tuple{Int,Int},Any}()
    for a in 1:length(segments)-1,b in a+1:length(segments)
        sa,sb = segments[a],segments[b]
        angle_difference(sa.theta,sb.theta)<minimum_angle && continue
        da,db = difference(sa.ending,sa.start),difference(sb.ending,sb.start)
        den = cross2(da,db)
        den==0 && continue
        lambda = cross2(difference(sb.start,sa.start),db)
        point = (
            nearest_integer(sa.start[1]*den+lambda*da[1],den),
            nearest_integer(sa.start[2]*den+lambda*da[2],den)
        )
        end_a = chebyshev(sa.start,point)<=chebyshev(sa.ending,point) ? 1 : 2
        end_b = chebyshev(sb.start,point)<=chebyshev(sb.ending,point) ? 1 : 2
        dist_a,dist_b = min(chebyshev(sa.start,point),chebyshev(sa.ending,point)),min(
            chebyshev(sb.start,point),
            chebyshev(sb.ending,point)
        )
        max(dist_a,dist_b)<=maximum_distance && (joins[(a,b)]=(point=point,a=a,b=b,end_a=end_a,end_b=end_b))
    end
    joins
end
joined(a,b,joins) = get(joins,minmax(a,b),nothing)
junction_end(join,s) = join.a==s ? join.end_a : join.end_b
function polygon_cycles(segments,joins)
    graph = [Int[] for _ in segments]
    for (a,b) in keys(joins)
        push!(graph[a],b)
        push!(graph[b],a)
    end
    foreach(sort!,graph)
    polygons = NamedTuple[]
    for k in (3,4)
        found = NamedTuple[]
        for first_segment in eachindex(segments)
            function extend(sequence)
                if length(sequence)==k
                    sequence[2]<sequence[end] || return
                    isnothing(joined(sequence[end],first_segment,joins)) && return
                    vertices = Tuple{Int,Int}[]
                    for i in 1:k
                        previous,current,following = sequence[mod1(i-1,k)],sequence[i],sequence[mod1(i+1,k)]
                        entry,exit = joined(previous,current,joins),joined(current,following,joins)
                        junction_end(entry,current)!=junction_end(exit,current) || return
                        push!(vertices,entry.point)
                    end
                    turns = [cross2(
                        difference(vertices[mod1(i+1,k)],vertices[i]),
                        difference(vertices[mod1(i+2,k)],vertices[mod1(i+1,k)])
                    ) for i in 1:k]
                    (all(>(0),turns) || all(<(0),turns)) || return
                    push!(found,(segments=copy(sequence),vertices=vertices))
                    return
                end
                for candidate in graph[sequence[end]]
                    (candidate<=first_segment || candidate in sequence) && continue
                    extend(vcat(sequence,[candidate]))
                end
            end
            extend([first_segment])
        end
        sort!(found;by=p->Tuple(p.segments))
        for p in found
            push!(polygons,(;p...,type="polygon",number=length(polygons)+1))
        end
    end
    polygons
end
function polygon_properties(p,segments,edges,params)
    k,vertices = length(p.segments),p.vertices
    theta = [segments[s].theta for s in p.segments]
    angles,lengths,supports = Int[],Int[],Int[]
    sigma = 0
    for i in 1:k
        previous,current,following = vertices[mod1(i-1,k)],vertices[i],vertices[mod1(i+1,k)]
        phi = angle_difference(theta[mod1(i-1,k)],theta[i])
        dot2(difference(previous,current),difference(following,current))<0 && (phi=180-phi)
        push!(angles,phi)
        side = difference(following,current)
        push!(lengths,dot2(side,side))
        points = bresenham(current,following)
        hits = count(point->any((point[1]+dx,point[2]+dy) in edges for dx in -1:1 for dy in -1:1),points)
        push!(supports,fld(100hits,length(points)))
        sigma += cross2(current,following)
    end
    tolerance = params["angle_tolerance"][1]
    if k==3
        kind = all(a->abs(a-60)<=tolerance,angles) ? "equilateral_triangle" : any(
            a->abs(a-90)<=tolerance,
            angles
        ) ? "right_triangle" : "triangle"
    else
        first_parallel,second_parallel = angle_difference(theta[1],theta[3])<=tolerance,angle_difference(
            theta[2],
            theta[4]
        )<=tolerance
        kind = !first_parallel && !second_parallel ? "quadrilateral" : first_parallel!=second_parallel ? "trapezoid" : any(
            a->abs(a-90)>tolerance,
            angles
        ) ? "parallelogram" :
            100*(maximum(lengths)-minimum(lengths))<=params["square_tolerance"][1]*maximum(lengths) ? "square" : "rectangle"
    end
    (;p...,angles=angles,lengths=lengths,supports=supports,sigma=sigma,kind=kind,vertex_corners=zeros(Int,k))
end
function representatives(shape)
    shape.type=="polygon" && return shape.vertices
    x,y = shape.center
    r = shape.radius
    [(x+r,y),(x,y+r),(x-r,y),(x,y-r)]
end
function contains_pixel(shape,point)
    if shape.type=="circle"
        offset = difference(point,shape.center)
        return dot2(offset,offset)<=shape.radius^2
    end
    vertices = shape.vertices
    for i in eachindex(vertices)
        value = cross2(
            difference(vertices[mod1(i+1,length(vertices))],vertices[i]),
            difference(point,vertices[i])
        )
        value!=0 && ((value>0)!=(shape.sigma>0)) && return false
    end
    true
end
function measure_shapes!(shapes,image,margin)
    height,width = size(image)
    for i in eachindex(shapes)
        shape = shapes[i]
        points = representatives(shape)
        x0,x1 = max(0,minimum(p[1] for p in points)-margin),min(width-1,maximum(p[1] for p in points)+margin)
        y0,y1 = max(0,minimum(p[2] for p in points)-margin),min(height-1,maximum(p[2] for p in points)+margin)
        inner_count,outer_count,inner_total,outer_total = 0,0,0,0
        for y in y0:y1,x in x0:x1
            if contains_pixel(shape,(x,y))
                inner_count += 1
                inner_total += image[y+1,x+1]
            else
                outer_count += 1
                outer_total += image[y+1,x+1]
            end
        end
        mean = inner_count==0 ? 0 : fld(inner_total,inner_count)
        contrast = mean-(outer_count==0 ? 0 : fld(outer_total,outer_count))
        shapes[i] = (;shape...,pixel_count=inner_count,mean=mean,contrast=contrast,enclosing=0)
    end
    for i in eachindex(shapes)
        shape = shapes[i]
        parents = [j for j in eachindex(shapes) if j!=i && shapes[j].pixel_count>shape.pixel_count && all(
            p->contains_pixel(shapes[j],p),
            representatives(shape)
        )]
        enclosing = isempty(parents) ? 0 : argmin(j->(shapes[j].pixel_count,j),parents)
        shapes[i] = (;shape...,enclosing=enclosing)
    end
end
function match_corners!(corners,polygons,segments,maximum_distance)
    for i in eachindex(corners)
        corner = corners[i]
        point = (corner.x,corner.y)
        vertices = [(
            chebyshev(point,v),
            p.number,
            j
        ) for p in polygons for (j,v) in enumerate(p.vertices) if chebyshev(point,v)<=maximum_distance]
        if !isempty(vertices)
            _,p,j = minimum(vertices)
            match,kind = "polygon $p vertex $j","vertex"
        else
            ends = [(
                chebyshev(point,v),
                s.number,
                j
            ) for s in segments for (j,v) in enumerate((s.start,s.ending)) if chebyshev(point,v)<=maximum_distance]
            if isempty(ends)
                match,kind = "none","none"
            else
                _,s,j = minimum(ends)
                match,kind = "segment $s "*(j==1 ? "start" : "end"),"segment"
            end
        end
        corners[i] = (;corner...,match=match,match_kind=kind)
    end
    matched = 0
    for p in polygons,(i,vertex) in enumerate(p.vertices)
        candidates = [(
            chebyshev((c.x,c.y),vertex),
            c.number
        ) for c in corners if chebyshev((c.x,c.y),vertex)<=maximum_distance]
        if !isempty(candidates)
            p.vertex_corners[i] = minimum(candidates)[2]
            matched += 1
        end
    end
    matched
end
function shape_explanations(shape,edges)
    if shape.type=="circle"
        return Set(p for p in edges if on_circumference(p,shape))
    end
    explained = Set{Tuple{Int,Int}}()
    vertices = shape.vertices
    for i in eachindex(vertices),(x,y) in bresenham(
        vertices[i],
        vertices[mod1(i+1,length(vertices))]
    ),dx in -1:1,dy in -1:1
        (x+dx,y+dy) in edges && push!(explained,(x+dx,y+dy))
    end
    explained
end
function component_attributes(groups,edges,magnitude,direction,shapes)
    explanations = [shape_explanations(shape,edges) for shape in shapes]
    result = NamedTuple[]
    for pixels in groups
        xs,ys = first.(pixels),last.(pixels)
        ends = count(p->count(offset->(p[1]+offset[1],p[2]+offset[2]) in edges,NEIGHBORS)==1,pixels)
        strength = fld(sum(magnitude[y+1,x+1] for (x,y) in pixels),length(pixels))
        main_direction = argmin(d->(-count(p->direction[p[2]+1,p[1]+1]==d,pixels),d),[0,45,90,135])
        counts = [count(p->p in explained,pixels) for explained in explanations]
        maximum_count = maximum(counts;init=0)
        shape = maximum_count==0 ? 0 : argmax(counts)
        push!(
            result,
            (
                number=length(result)+1,
                pixels=length(pixels),
                box=(minimum(xs),minimum(ys),maximum(xs),maximum(ys)),
                ends=ends,
                strength=strength,
                direction=main_direction,
                shape=shape,
                explained=maximum_count
            )
        )
    end
    result
end
function overlay_image(image,segments,circles,corners,divisor)
    output = fld.(image,divisor)
    height,width = size(image)
    function mark!(point)
        x,y = point
        0<=x<width && 0<=y<height && (output[y+1,x+1]=255)
    end
    for s in segments,p in bresenham(s.start,s.ending)
        mark!(p)
    end
    for c in circles,(dx,dy) in c.outline
        mark!((c.center[1]+dx,c.center[2]+dy))
    end
    for c in corners,offset in -2:2
        mark!((c.x+offset,c.y))
        mark!((c.x,c.y+offset))
    end
    output
end
shape_name(index,shapes) = index==0 ? "none" : "$(shapes[index].type) $(shapes[index].number)"
function main()
    image,trig,params = read_inputs()
    height,width = size(image)
    smoothed = smoothing(image,params)
    gx,gy,magnitude = gradient(smoothed)
    direction = directions(gx,gy)
    nonmax = suppress(magnitude,direction)
    edges,strong,weak = hysteresis(nonmax,params["canny_low"][1],params["canny_high"][1])
    groups = components(edges)
    cells,outlines = circle_votes(edges,width,height,params)
    circle_candidates,circle_peak_list = circle_peaks(
        cells,
        outlines,
        width,
        height,
        params["circle_min_percent"][1]
    )
    circles,circle_edges,line_edges = selected_circles(
        outlines,
        circle_peak_list,
        edges,
        params["circle_max_count"][1]
    )
    votes = line_votes(line_edges,trig,params["hough_rho_step"][1])
    peaks = line_peaks(votes,params["hough_threshold"][1])
    lines,segments,used = extract_segments(peaks,line_edges,trig,params)
    joins = build_junctions(segments,params["junction_min_angle"][1],params["junction_distance"][1])
    polygons = NamedTuple[polygon_properties(p,segments,edges,params) for p in polygon_cycles(segments,joins)]
    polygon_count = length(polygons)
    shapes = vcat(polygons,circles)
    measure_shapes!(shapes,image,params["contrast_margin"][1])
    polygons,circles = shapes[1:polygon_count],shapes[polygon_count+1:end]
    _,corner_candidates,corners = harris_corners(
        gx,
        gy,
        params["harris_window"][1],
        params["harris_threshold"][1],
        params["harris_max_count"][1]
    )
    matched_vertices = match_corners!(corners,polygons,segments,params["corner_match_distance"][1])
    component_list = component_attributes(groups,edges,magnitude,direction,shapes)
    overlay = overlay_image(image,segments,circles,corners,params["overlay_divisor"][1])
    limits = [rho(p,t,trig,params["hough_rho_step"][1]) for t in 0:179 for p in (
        (0,0),
        (width-1,0),
        (0,height-1),
        (width-1,height-1)
    )]
    lo,hi = minimum(limits),maximum(limits)
    max_votes = maximum(values(votes);init=0)
    hough_image = zeros(Int,hi-lo+1,180)
    if max_votes>0
        for r in lo:hi,t in 0:179
            hough_image[r-lo+1,t+1] = fld(255get(votes,(t,r),0),max_votes)
        end
    end
    edge_image = zeros(Int,height,width)
    for (x,y) in edges
        edge_image[y+1,x+1] = 255
    end
    write_pgm("edges.pgm",edge_image)
    write_pgm("hough.pgm",hough_image)
    write_pgm("overlay.pgm",overlay)
    line_text = ["lines $(length(lines))"]
    for line in lines
        push!(
            line_text,
            "line $(line.number) theta $(line.theta) rho $(line.rho) votes $(line.votes) segments $(length(line.segments))"
        )
        for number in line.segments
            s = segments[number]
            push!(
                line_text,
                "segment $number start $(s.start[1]) $(s.start[2]) end $(s.ending[1]) $(s.ending[2]) length $(s.length) pixels $(s.pixels)"
            )
        end
    end
    circle_text = ["circles $(length(circles))"]
    for c in circles
        push!(
            circle_text,
            "circle $(c.number) center $(c.center[1]) $(c.center[2]) radius $(c.radius) votes $(c.votes) points $(c.outline_count) gap $(c.gap) arcs $(c.arcs) pixels $(c.pixel_count) mean $(c.mean) contrast $(c.contrast) inside $(shape_name(c.enclosing,shapes))"
        )
    end
    polygon_text = ["polygons $(length(polygons))"]
    for p in polygons
        amount = abs(p.sigma)
        area = "$(amount÷2).$(isodd(amount) ? "5" : "0")"
        push!(
            polygon_text,
            "polygon $(p.number) $(p.kind) segments $(join(p.segments," ")) area $area pixels $(p.pixel_count) mean $(p.mean) contrast $(p.contrast) inside $(shape_name(p.enclosing,shapes))"
        )
        for (i,(x,y)) in enumerate(p.vertices)
            corner = p.vertex_corners[i]==0 ? "none" : string(p.vertex_corners[i])
            push!(polygon_text,"vertex $i $x $y angle $(p.angles[i]) corner $corner")
        end
        for (i,s) in enumerate(p.segments)
            push!(polygon_text,"side $i segment $s length2 $(p.lengths[i]) support $(p.supports[i])")
        end
    end
    corner_text = vcat(
        ["corners $(length(corners))"],
        ["corner $(c.number) $(c.x) $(c.y) response $(c.response) match $(c.match)" for c in corners]
    )
    component_text = vcat(
        ["components $(length(component_list))"],
        ["component $(c.number) pixels $(c.pixels) box $(join(c.box," ")) ends $(c.ends) strength $(c.strength) direction $(c.direction) shape $(shape_name(c.shape,shapes)) explained $(c.explained)" for c in component_list]
    )
    report = ["image $width $height","gradient_nonzero $(count(>(0),magnitude))","gradient_max $(maximum(magnitude))","nms_kept $(count(>(0),nonmax))",
        "strong $(length(strong))","weak $(length(weak))","edges $(length(edges))","weak_kept $(length(intersect(weak,edges)))","weak_dropped $(length(setdiff(weak,edges)))","edge_components $(length(groups))"]
    append!(report,["direction_$d $(count(p->direction[p[2]+1,p[1]+1]==d,edges))" for d in (0,45,90,135)])
    append!(report,["circle_candidates $(length(circle_candidates))","circle_peaks $(length(circle_peak_list))","circles $(length(circles))","circle_edge_pixels $(length(circle_edges))",
        "line_edge_pixels $(length(line_edges))","hough_max_votes $max_votes","hough_peaks $(length(peaks))","lines $(length(lines))","segments $(length(segments))","claimed_pixels $(length(used))","junctions $(length(joins))","polygons $(length(polygons))"])
    append!(report,["$kind $(count(p->p.kind==kind,polygons))" for kind in POLYGON_KINDS])
    append!(report,["corner_candidates $(length(corner_candidates))","corners $(length(corners))","corners_on_vertices $(count(c->c.match_kind=="vertex",corners))",
        "corners_on_segments $(count(c->c.match_kind=="segment",corners))","corners_unmatched $(count(c->c.match_kind=="none",corners))","vertices_with_corner $matched_vertices"])
    for (name,text) in (
        ("lines.txt",line_text),
        ("circles.txt",circle_text),
        ("polygons.txt",polygon_text),
        ("corners.txt",corner_text),
        ("components.txt",component_text),
        ("report.txt",report)
    )
        write_lines(name,text)
    end
end
main()
