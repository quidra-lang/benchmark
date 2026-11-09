canonical(a,b,c) = min((a,b,c),(b,c,a),(c,a,b))
struct Triangulation
    points::Vector{Tuple{Int,Int}}
    directed::Dict{Tuple{Int,Int},Int}
    initial::Tuple{Int,Int,Int}
end
function add_triangle!(mesh,a,b,c)
    mesh.directed[(a,b)] = c
    mesh.directed[(b,c)] = a
    mesh.directed[(c,a)] = b
end
function remove_triangle!(mesh,a,b,c)
    delete!(mesh.directed,(a,b))
    delete!(mesh.directed,(b,c))
    delete!(mesh.directed,(c,a))
end
function Triangulation(points)
    initial = orient(points[1],points[2],points[3])>0 ? (1,2,3) : (1,3,2)
    mesh = Triangulation(points,Dict{Tuple{Int,Int},Int}(),initial)
    add_triangle!(mesh,initial...)
    mesh
end
triangles(mesh) = sort(collect(Set(canonical(a,b,c) for ((a,b),c) in mesh.directed)))
hull_edges(mesh) = sort([edge for edge in keys(mesh.directed) if !haskey(mesh.directed,reverse(edge))])
function insert_site!(mesh,s)
    points = mesh.points
    containing = nothing
    for (a,b,c) in triangles(mesh)
        if orient(points[a],points[b],points[s])>0 && orient(points[b],points[c],points[s])>0 && orient(
            points[c],
            points[a],
            points[s]
        )>0
            containing = (a,b,c)
            break
        end
    end
    if isnothing(containing)
        check = Set((v,u) for (u,v) in hull_edges(mesh) if orient(points[u],points[v],points[s])<0)
        kind,visible = "outside",length(check)
    else
        a,b,c = containing
        remove_triangle!(mesh,a,b,c)
        check = Set([(a,b),(b,c),(c,a)])
        kind,visible = "inside",0
    end
    for (a,b) in check
        add_triangle!(mesh,a,b,s)
    end
    flips = 0
    while !isempty(check)
        a,b = pop!(check)
        q = get(mesh.directed,(b,a),0)
        if q!=0 && incircle(points[a],points[b],points[s],points[q])>0
            remove_triangle!(mesh,a,b,s)
            remove_triangle!(mesh,b,a,q)
            add_triangle!(mesh,a,q,s)
            add_triangle!(mesh,q,b,s)
            push!(check,(a,q),(q,b))
            flips += 1
        end
    end
    (
        site=s,
        kind=kind,
        containing=containing,
        visible=visible,
        flips=flips,
        triangles=length(mesh.directed)÷3,
        hull=length(hull_edges(mesh))
    )
end
function visibility_walk(points,query,triangles,edge_triangles)
    path = [1]
    while true
        a,b,c = triangles[path[end]]
        crossing = findfirst(edge->orient(points[edge[1]],points[edge[2]],query)<0,[(a,b),(b,c),(c,a)])
        isnothing(crossing) && return path,nothing
        u,v = ((a,b),(b,c),(c,a))[crossing]
        following = get(edge_triangles,(v,u),0)
        following==0 && return path,minmax(u,v)
        push!(path,following)
    end
end
