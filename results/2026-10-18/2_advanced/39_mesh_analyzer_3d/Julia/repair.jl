function split_polygons(polygons)
    triangles = Face[]
    for polygon in polygons
        corners = polygon[:vertices]
        for i in 2:length(corners)-1
            push!(
                triangles,
                Face(
                    length(triangles)+1,
                    polygon[:number],
                    polygon[:line],
                    polygon[:group],
                    (corners[1],corners[i],corners[i+1])
                )
            )
        end
    end
    triangles
end
function snapped_vertices(vertices,spacing)
    points = Point3[]
    changed = Tuple{Int,Point3,Point3}[]
    for (i,point) in enumerate(vertices)
        rounded = ntuple(axis->spacing*fld(2*point[axis]+spacing,2*spacing),3)
        push!(points,rounded)
        rounded != point && push!(changed,(i,point,rounded))
    end
    points,changed
end
function representatives(points,merge)
    owner = Dict{Point3,Int}()
    [merge ? get!(owner,point,i) : i for (i,point) in enumerate(points)]
end
function cleaned_faces(triangles,points,representative,remove_zero,remove_duplicate)
    faces = Face[]
    removed = Tuple{Face,String}[]
    seen = Set{Point3}()
    for triangle in triangles
        a,b,c = (representative[v] for v in triangle.vertices)
        reason = length(Set((a,b,c))) < 3 ? "repeated" : remove_zero && cross(
            subtract(points[b],points[a]),
            subtract(points[c],points[a])
        ) == (0,0,0) ? "zero_area" : nothing
        if isnothing(reason)
            identifier = Tuple(sort([a,b,c]))
            if remove_duplicate && identifier in seen
                reason = "duplicate"
            else
                push!(seen,identifier)
            end
        end
        if isnothing(reason)
            push!(faces,Face(triangle.triangle,triangle.polygon,triangle.line,triangle.group,(a,b,c)))
        else
            push!(removed,(triangle,reason))
        end
    end
    faces,removed
end
function remap_vertices(original,snapped,representative,faces,keep_unused)
    present = keep_unused ? [i for i in eachindex(original) if representative[i] == i] : sort(unique([v for face in faces for v in face.vertices]))
    numbers = Dict(old=>index for (index,old) in enumerate(present))
    points = snapped[present]
    mapped = [Face(
        face.triangle,
        face.polygon,
        face.line,
        face.group,
        Tuple(numbers[v] for v in face.vertices)
    ) for face in faces]
    points,mapped,numbers
end
function fill_loops(faces,loops,max_length,permitted)
    added = Face[]
    for loop in loops
        corners,count = loop[:vertices],loop[:length]
        loop[:filled] = false
        if loop[:kind] != "coherent" || !(3 <= count <= max_length) || length(unique(corners)) != count || !(loop[:component] in permitted)
            continue
        end
        for i in 3:count
            push!(added,Face(0,0,0,"fill",(corners[1],corners[i],corners[i-1])))
        end
        loop[:filled] = true
    end
    vcat(faces,added),added
end
