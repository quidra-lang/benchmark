include("fixed_point.jl")
include("vector3.jl")
include("scene.jl")
include("intersect.jl")
include("shading.jl")
const RAY_KINDS = ("primary","reflection","refraction","shadow")
const LIGHT_COUNTS = ("pixels","shadow_rays","blocked","attenuated","backfacing","outside")
const BLACK = (0,0,0)
mutable struct BVHNode
    bounds::Tuple{NTuple{3,Int},NTuple{3,Int}}
    depth::Int
    visits::Int
    objects::Vector{Int}
    left::Int
    right::Int
end
Base.@kwdef mutable struct Pixel
    x::Int
    y::Int
    rays::Int = 0
    depth::Int = 0
    samples::Int = 1
    label::String = "."
    center::NTuple{3,Int} = BLACK
    color::NTuple{3,Int} = BLACK
    hit::Any = nothing
end
Base.@kwdef mutable struct Renderer
    scene::Any
    width::Int
    height::Int
    contrast::Int
    max_depth::Int
    far::Int
    epsilon::Int
    objects::Vector{NamedTuple}
    planes::Vector{Int}
    nodes::Vector{BVHNode} = BVHNode[]
    root::Int = 0
    leaf_depth::Vector{Int}
    rays::Vector{Int} = zeros(Int,4)
    misses::Vector{Int} = zeros(Int,3)
    depth_counts::Vector{Int}
    tests::Matrix{Int} = zeros(Int,4,2)
    object_counts::Matrix{Int}
    light_counts::Matrix{Int}
    total_internal_reflections::Int = 0
    clamped::Int = 0
    supersampled::Int = 0
    pixels::Vector{Pixel} = Pixel[]
end
vector_text(vector) = join(vector," ")
function write_lines(name,lines)
    mkpath("output")
    open(joinpath("output",name),"w") do io
        for line in lines
            println(io,line)
        end
    end
end
function read_settings()
    Dict(String(row[1])=>parse.(Int,row[2:end]) for row in split.(readlines(joinpath("input","render.txt"))))
end
function union_box(renderer,ids)
    objects = renderer.objects
    ntuple(a->minimum(objects[i].bounds[1][a] for i in ids),3),ntuple(
        a->maximum(objects[i].bounds[2][a] for i in ids),
        3
    )
end
function surface_cost(renderer,ids)
    lo,hi = union_box(renderer,ids)
    dx,dy,dz = sub(hi,lo)
    (dx*dy+dy*dz+dz*dx)*length(ids)
end
function build_bvh!(renderer,ids,depth)
    node = BVHNode(union_box(renderer,ids),depth,0,Int[],0,0)
    push!(renderer.nodes,node)
    index = length(renderer.nodes)
    if length(ids)<=2
        node.objects = sort(ids)
        renderer.leaf_depth[ids] .= depth
        return index
    end
    best_key,best_groups = nothing,nothing
    for axis in 1:3
        ordered = sort(ids;by=i->(
            fld(renderer.objects[i].bounds[1][axis]+renderer.objects[i].bounds[2][axis],2),
            i
        ))
        for split in 1:length(ordered)-1
            left,right = ordered[1:split],ordered[split+1:end]
            key = (surface_cost(renderer,left)+surface_cost(renderer,right),axis,split)
            if isnothing(best_key) || key<best_key
                best_key,best_groups = key,(left,right)
            end
        end
    end
    node.left = build_bvh!(renderer,best_groups[1],depth+1)
    node.right = build_bvh!(renderer,best_groups[2],depth+1)
    index
end
function make_renderer(scene,settings)
    objects = NamedTuple[(
        ;object...,
        bounds=object_bounds(object,settings["pad"][1])
    ) for object in scene.objects]
    planes = [i for (i,object) in enumerate(objects) if object.kind=="plane"]
    bounded = [i for (i,object) in enumerate(objects) if !isnothing(object.bounds)]
    depth = settings["depth"][1]
    renderer = Renderer(scene=scene,width=settings["size"][1],height=settings["size"][2],contrast=settings["contrast"][1],max_depth=depth,
        far=settings["far"][1],epsilon=settings["epsilon"][1],objects=objects,planes=planes,leaf_depth=fill(
            -1,
            length(objects)
        ),
        depth_counts=zeros(Int,depth+1),object_counts=zeros(Int,length(objects),3),light_counts=zeros(
            Int,
            length(scene.lights),
            6
        ))
    isempty(bounded) || (renderer.root=build_bvh!(renderer,bounded,0))
    renderer
end
function test_node!(renderer,index,origin,direction,kind,counted)
    node = renderer.nodes[index]
    if counted
        renderer.tests[kind,1] += 1
        node.visits += 1
    end
    interval = slab(node.bounds...,origin,direction)
    (isnothing(interval) || interval.far<=renderer.epsilon) ? nothing : interval.near
end
function test_object!(renderer,index,origin,direction,kind,counted)
    counted && (renderer.tests[kind,2]+=1)
    candidate(renderer.objects[index],origin,direction,renderer.epsilon)
end
function nearest(renderer,origin,direction,kind=1,counted=false)
    best = nothing
    function consider(index)
        intersection = test_object!(renderer,index,origin,direction,kind,counted)
        (isnothing(intersection) || intersection.distance>renderer.far) && return
        if isnothing(best) || (intersection.distance,index)<(best.intersection.distance,best.index)
            best = (index=index,intersection=intersection)
        end
    end
    function visit(index)
        entry = test_node!(renderer,index,origin,direction,kind,counted)
        (isnothing(entry) || entry>renderer.far || (!isnothing(best) && entry>best.intersection.distance)) && return
        node = renderer.nodes[index]
        if isempty(node.objects)
            visit(node.left)
            visit(node.right)
        else
            foreach(consider,node.objects)
        end
    end
    foreach(consider,renderer.planes)
    renderer.root!=0 && visit(renderer.root)
    best
end
function occluders(renderer,origin,direction,distance,counted=false)
    found = Int[]
    function consider(index)
        intersection = test_object!(renderer,index,origin,direction,4,counted)
        if !isnothing(intersection) && intersection.distance<distance
            push!(found,index)
            counted && (renderer.object_counts[index,3]+=1)
        end
    end
    function visit(index)
        entry = test_node!(renderer,index,origin,direction,4,counted)
        (isnothing(entry) || entry>=distance) && return
        node = renderer.nodes[index]
        if isempty(node.objects)
            visit(node.left)
            visit(node.right)
        else
            foreach(consider,node.objects)
        end
    end
    foreach(consider,renderer.planes)
    renderer.root!=0 && visit(renderer.root)
    sort!(found)
end
function camera_ray(renderer,qx,qy)
    scene = renderer.scene
    hw,hh = scene.view
    u = fld((qx-2renderer.width)*hw,2renderer.width)
    v = fld((2renderer.height-qy)*hh,2renderer.height)
    scene.eye,norm(add(add(scene.forward,sc(scene.right,u)),sc(scene.up,v)))
end
function intersection_info(renderer,nearest_hit,origin,direction)
    object = renderer.objects[nearest_hit.index]
    distance = nearest_hit.intersection.distance
    point = add(origin,sc(direction,distance))
    outward = outward_normal(object,point,direction,nearest_hit.intersection)
    front = dot(outward,direction)<=0
    normal = front ? outward : neg(outward)
    (
        index=nearest_hit.index,
        object=object,
        distance=distance,
        point=point,
        normal=normal,
        front=front,
        base=base_color(object.material,point)
    )
end
function light_samples(renderer,light,point)
    light.kind=="sun" && return [(light.direction,renderer.far,light.intensity)]
    positions = NTuple{3,Int}[]
    if light.kind=="area"
        k = light.divisions
        for j in 0:k-1,i in 0:k-1
            push!(
                positions,
                ntuple(a->light.position[a]+fld((2i+1)*light.u[a],2k)+fld((2j+1)*light.v[a],2k),3)
            )
        end
    else
        push!(positions,light.position)
    end
    intensity = fld(light.intensity,light.samples)
    [(norm(sub(position,point)),vector_length(sub(position,point)),intensity) for position in positions]
end
function cone_factor(light,direction)
    light.kind!="spot" && return S
    cosine = -dot(direction,light.direction)
    cosine<=light.outer && return 0
    cosine>=light.inner && return S
    fld((cosine-light.outer)*S,light.inner-light.outer)
end
function sample_contribution!(renderer,light,sample,info,view,pixel)
    direction,distance,intensity = sample
    j = light.number
    counted = !isnothing(pixel)
    ndl = dot(info.normal,direction)
    if ndl<=0
        counted && (renderer.light_counts[j,5]+=1)
        return (0,0,0)
    end
    factor = cone_factor(light,direction)
    if factor==0
        counted && (renderer.light_counts[j,6]+=1)
        return (0,0,0)
    end
    if counted
        renderer.rays[4] += 1
        pixel.rays += 1
        renderer.light_counts[j,2] += 1
    end
    blockers = occluders(renderer,info.point,direction,distance,counted)
    for index in blockers
        factor = mul(factor,renderer.objects[index].material.kt)
    end
    if factor==0
        counted && (renderer.light_counts[j,3]+=1)
        return (0,0,0)
    end
    counted && !isempty(blockers) && (renderer.light_counts[j,4]+=1)
    diffuse,specular = phong(info.object.material,info.normal,direction,view,ndl,intensity,factor)
    1,diffuse,specular
end
function local_color!(renderer,info,direction,pixel)
    lighting = NTuple{3,Int}[]
    for light in renderer.scene.lights
        lit,diffuse,specular = 0,0,0
        for sample in light_samples(renderer,light,info.point)
            lit_count,dif,spe = sample_contribution!(renderer,light,sample,info,neg(direction),pixel)
            lit += lit_count
            diffuse += dif
            specular += spe
        end
        push!(lighting,(lit,diffuse,specular))
    end
    diffuse,specular = sum(item[2] for item in lighting),sum(item[3] for item in lighting)
    raw = ntuple(a->fld(info.base[a]*(renderer.scene.ambient+diffuse),S)+fld(255specular,S),3)
    isnothing(pixel) || (renderer.clamped+=count(>(255),raw))
    ntuple(a->min(raw[a],255),3),(;info...,lighting=lighting,illumination=count(item->item[1]>0,lighting))
end
function apply_fog(renderer,color,distance)
    fog = renderer.scene.fog
    isnothing(fog) && return color
    r,g,b,start,ending = fog
    factor = distance<=start ? 0 : distance>=ending ? S : fld((distance-start)*S,ending-start)
    mix((color,S-factor),((r,g,b),factor))
end
function trace!(renderer,origin,direction,kind=1,depth=0,pixel=nothing,record=nothing)
    counted = !isnothing(pixel)
    if counted
        renderer.rays[kind] += 1
        renderer.depth_counts[depth+1] += 1
        pixel.rays += 1
        pixel.depth = max(pixel.depth,depth)
    end
    isnothing(record) || push!(
        record,
        "ray $(RAY_KINDS[kind]) $depth origin $(vector_text(origin)) direction $(vector_text(direction))"
    )
    nearest_hit = nearest(renderer,origin,direction,kind,counted)
    if isnothing(nearest_hit)
        counted && (renderer.misses[kind]+=1)
        color = renderer.scene.background
        isnothing(record) || append!(record,["miss","color $(vector_text(color))"])
        return (color=color,hit=nothing)
    end
    info = intersection_info(renderer,nearest_hit,origin,direction)
    counted && (renderer.object_counts[info.index,kind==1 ? 1 : 2]+=1)
    local_color,info = local_color!(renderer,info,direction,pixel)
    if !isnothing(record)
        push!(
            record,
            "hit $(info.object.label) t $(info.distance) point $(vector_text(info.point)) normal $(vector_text(info.normal)) base $(vector_text(info.base))"
        )
        for (light,(lit,diffuse,specular)) in zip(renderer.scene.lights,info.lighting)
            push!(
                record,
                "light $(light.number) lit $lit of $(light.samples) diffuse $diffuse specular $specular"
            )
        end
        push!(record,"local $(vector_text(local_color))")
    end
    material = info.object.material
    color = local_color
    if depth<renderer.max_depth && (material.kr>0 || material.kt>0)
        wr,wt,transmitted,internal = refraction(material,direction,info.normal,info.front)
        if internal
            counted && (renderer.total_internal_reflections+=1)
            isnothing(record) || push!(record,"total_internal_reflection")
        end
        weight = S-material.kr-material.kt
        isnothing(record) || push!(record,"weights $weight $wr $wt")
        reflected_color = wr>0 ? trace!(
            renderer,
            info.point,
            reflected(direction,info.normal),
            2,
            depth+1,
            pixel,
            record
        ).color : BLACK
        refracted_color = wt>0 ? trace!(renderer,info.point,transmitted,3,depth+1,pixel,record).color : BLACK
        color = mix((local_color,weight),(reflected_color,wr),(refracted_color,wt))
    end
    color = apply_fog(renderer,color,info.distance)
    isnothing(record) || push!(record,"color $(vector_text(color))")
    (color=color,hit=info)
end
function render!(renderer)
    for y in 0:renderer.height-1,x in 0:renderer.width-1
        pixel = Pixel(x=x,y=y)
        origin,direction = camera_ray(renderer,4x+2,4y+2)
        result = trace!(renderer,origin,direction,1,0,pixel)
        pixel.center = pixel.color = result.color
        pixel.hit = result.hit
        if !isnothing(result.hit)
            pixel.label = result.hit.object.label
            for (j,lighting) in enumerate(result.hit.lighting)
                lighting[1]>0 && (renderer.light_counts[j,1]+=1)
            end
        end
        push!(renderer.pixels,pixel)
    end
    for pixel in renderer.pixels
        x,y = pixel.x,pixel.y
        boundary = false
        for (nx,ny) in ((x,y-1),(x,y+1),(x-1,y),(x+1,y))
            0<=nx<renderer.width && 0<=ny<renderer.height || continue
            other = renderer.pixels[ny*renderer.width+nx+1]
            if other.label!=pixel.label || maximum(abs(other.center[a]-pixel.center[a]) for a in 1:3)>renderer.contrast
                boundary = true
                break
            end
        end
        boundary || continue
        renderer.supersampled += 1
        pixel.samples = 4
        colors = NTuple{3,Int}[]
        for (dx,dy) in ((1,1),(3,1),(1,3),(3,3))
            origin,direction = camera_ray(renderer,4x+dx,4y+dy)
            push!(colors,trace!(renderer,origin,direction,1,0,pixel).color)
        end
        pixel.color = ntuple(a->fld(sum(color[a] for color in colors),4),3)
    end
end
function write_netpbm(renderer,name,magic,values)
    lines = [magic,"$(renderer.width) $(renderer.height)","255"]
    for y in 0:renderer.height-1
        row = values[y*renderer.width+1:(y+1)*renderer.width]
        push!(lines,join(magic=="P3" ? vector_text.(row) : string.(row)," "))
    end
    write_lines(name,lines)
end
function write_map(renderer,name,values)
    write_lines(name,[join(values[y*renderer.width+1:(y+1)*renderer.width]) for y in 0:renderer.height-1])
end
function distance_range(renderer)
    distances = [pixel.hit.distance for pixel in renderer.pixels if !isnothing(pixel.hit)]
    isempty(distances) ? nothing : extrema(distances)
end
mean_color(pixels) = ntuple(a->fld(sum(pixel.color[a] for pixel in pixels),length(pixels)),3)
function write_images(renderer)
    distances = distance_range(renderer)
    max_cost = maximum(pixel.rays for pixel in renderer.pixels)
    depth_values,normal_values,albedo_values,light_values = Int[],NTuple{3,Int}[],NTuple{3,Int}[],String[]
    for pixel in renderer.pixels
        hit = pixel.hit
        if isnothing(hit)
            push!(depth_values,0)
            push!(normal_values,BLACK)
            push!(albedo_values,BLACK)
            push!(light_values,".")
            continue
        end
        low,high = distances
        push!(depth_values,low==high ? 255 : 255-fld(235*(hit.distance-low),high-low))
        push!(normal_values,ntuple(a->clamp(fld((hit.normal[a]+S)*255,2S),0,255),3))
        push!(albedo_values,hit.base)
        push!(light_values,string(hit.illumination))
    end
    for (
        name,
        magic,
        values
    ) in (("image.ppm","P3",[p.color for p in renderer.pixels]),("depth.pgm","P2",depth_values),
        ("normal.ppm","P3",normal_values),("albedo.ppm","P3",albedo_values),(
            "cost.pgm",
            "P2",
            [fld(255p.rays,max_cost) for p in renderer.pixels]
        ))
        write_netpbm(renderer,name,magic,values)
    end
    write_map(renderer,"object_map.txt",[p.label for p in renderer.pixels])
    write_map(renderer,"light_map.txt",light_values)
    write_map(renderer,"ray_depth.txt",[string(p.depth) for p in renderer.pixels])
end
function statistics(renderer)
    lines = ["image $(renderer.width) $(renderer.height)","supersampled $(renderer.supersampled)",
        "rays "*join(
            ("$kind $count" for (kind,count) in zip(RAY_KINDS,renderer.rays)),
            " "
        )*" total $(sum(renderer.rays))",
        "misses "*join(
            ("$kind $count" for (kind,count) in zip(RAY_KINDS[1:3],renderer.misses)),
            " "
        ),"depth "*vector_text(renderer.depth_counts)]
    for (i,kind) in enumerate(RAY_KINDS)
        push!(lines,"tests $kind nodes $(renderer.tests[i,1]) objects $(renderer.tests[i,2])")
    end
    distances = distance_range(renderer)
    push!(lines,"total_internal_reflection $(renderer.total_internal_reflections)","clamped $(renderer.clamped)","distance "*(isnothing(distances) ? "none" : vector_text(distances)),
        "max_pixel_rays $(maximum(p.rays for p in renderer.pixels))","mean "*vector_text(mean_color(renderer.pixels)))
    histogram = zeros(Int,8)
    for pixel in renderer.pixels
        r,g,b = pixel.color
        brightness = fld(299r+587g+114b,1000)
        histogram[fld(brightness,32)+1] += 1
    end
    push!(lines,"histogram "*vector_text(histogram))
    for node in renderer.nodes
        role = isempty(node.objects) ? "inner" : "leaf "*join(renderer.objects[i].label for i in node.objects)
        push!(
            lines,
            "node $(node.depth) $role box $(vector_text(node.bounds[1])) $(vector_text(node.bounds[2])) visits $(node.visits)"
        )
    end
    for (i,object) in enumerate(renderer.objects)
        pixels = [p for p in renderer.pixels if p.label==object.label]
        box,color = "none","none"
        if !isempty(pixels)
            box = vector_text((
                minimum(p.x for p in pixels),
                minimum(p.y for p in pixels),
                maximum(p.x for p in pixels),
                maximum(p.y for p in pixels)
            ))
            color = vector_text(mean_color(pixels))
        end
        primary,secondary,shadow = renderer.object_counts[i,:]
        push!(
            lines,
            "object $(object.label) $(object.kind) primary $primary secondary $secondary shadow $shadow pixels $(length(pixels)) box $box color $color"
        )
    end
    for (i,light) in enumerate(renderer.scene.lights)
        counts = join(("$name $value" for (name,value) in zip(LIGHT_COUNTS,renderer.light_counts[i,:]))," ")
        push!(lines,"light $i $(light.kind) samples $(light.samples) $counts")
    end
    lines
end
function process_queries(renderer)
    lines = String[]
    for (number,line) in enumerate(readlines(joinpath("input","queries.txt")))
        push!(lines,"query $number $line")
        words = String.(split(line))
        kind = words[1]
        if kind=="object"
            i = findfirst(object->object.label==words[2],renderer.objects)
            object = renderer.objects[i]
            suffix = isnothing(object.bounds) ? "bounds none leaf none" : "bounds $(vector_text(object.bounds[1])) $(vector_text(object.bounds[2])) leaf $(renderer.leaf_depth[i])"
            push!(lines,"$(object.kind) material $(object.material.name) $suffix")
            continue
        end
        values = parse.(Int,words[2:end])
        if kind=="pixel"
            x,y = values
            pixel = renderer.pixels[y*renderer.width+x+1]
            distance = isnothing(pixel.hit) ? "none" : string(pixel.hit.distance)
            push!(
                lines,
                "label $(pixel.label) distance $distance color $(vector_text(pixel.color)) samples $(pixel.samples) rays $(pixel.rays)"
            )
        elseif kind=="trace"
            x,y = values
            origin,direction = camera_ray(renderer,4x+2,4y+2)
            trace!(renderer,origin,direction,1,0,nothing,lines)
        elseif kind=="ray"
            trace!(renderer,Tuple(values[1:3]),norm(values[4:6]),1,0,nothing,lines)
        elseif kind=="visible"
            relative = sub(values,renderer.scene.eye)
            direction = norm(relative)
            blockers = occluders(
                renderer,
                renderer.scene.eye,
                direction,
                vector_length(relative)-renderer.epsilon
            )
            visible = isempty(blockers) ? "yes" : "no"
            first_hit = nearest(renderer,renderer.scene.eye,direction)
            suffix = isnothing(first_hit) ? "first none" : "first $(renderer.objects[first_hit.index].label) t $(first_hit.intersection.distance)"
            push!(lines,"$visible $suffix")
        elseif kind=="shadow"
            for light in renderer.scene.lights
                total,numbers = 0,Set{Int}()
                for (direction,distance,_) in light_samples(renderer,light,values)
                    factor = cone_factor(light,direction)
                    for i in occluders(renderer,values,direction,distance)
                        push!(numbers,i)
                        factor = mul(factor,renderer.objects[i].material.kt)
                    end
                    total += factor
                end
                labels = join(object.label for object in renderer.objects if object.number in numbers)
                push!(
                    lines,
                    "light $(light.number) factor $total occluders $(isempty(labels) ? "none" : labels)"
                )
            end
        elseif kind=="region"
            x0,y0,x1,y1 = values
            pixels = [renderer.pixels[y*renderer.width+x+1] for y in y0:y1 for x in x0:x1]
            push!(lines,"pixels $(length(pixels)) mean $(vector_text(mean_color(pixels)))")
            for label in vcat([object.label for object in renderer.objects],["."])
                total = count(pixel->pixel.label==label,pixels)
                total>0 && push!(lines,"label $label $total")
            end
        end
    end
    lines
end
function main()
    renderer = make_renderer(read_scene(),read_settings())
    render!(renderer)
    write_images(renderer)
    write_lines("stats.txt",statistics(renderer))
    write_lines("queries.txt",process_queries(renderer))
end
main()
