mutable struct DisjointSets
    parent::Vector{Int}
    size::Vector{Int}
    count::Int
end
DisjointSets(n) = DisjointSets(collect(1:n),ones(Int,n),n)
function root!(sets,site)
    while sets.parent[site]!=site
        sets.parent[site] = sets.parent[sets.parent[site]]
        site = sets.parent[site]
    end
    site
end
function unite!(sets,a,b)
    a,b = root!(sets,a),root!(sets,b)
    a==b && return false
    sets.size[a]<sets.size[b] && ((a,b)=(b,a))
    sets.parent[b] = a
    sets.size[a] += sets.size[b]
    sets.count -= 1
    true
end
nearest_neighbors(points,neighbors) = [argmin(
    t->(d2(points[s],points[t]),t),
    neighbors[s]
) for s in eachindex(points)]
function nearest_components(nearest)
    sets = DisjointSets(length(nearest))
    for s in eachindex(nearest)
        unite!(sets,s,nearest[s])
    end
    groups = Dict{Int,Vector{Int}}()
    for s in eachindex(nearest)
        push!(get!(groups,root!(sets,s),Int[]),s)
    end
    sort(collect(values(groups));by=first)
end
function kruskal(points,edges)
    sets = DisjointSets(length(points))
    adopted = Tuple{Int,Int}[]
    for (a,b) in sort(edges;by=e->(d2(points[e[1]],points[e[2]]),e...))
        if unite!(sets,a,b)
            push!(adopted,(a,b))
            sets.count==1 && break
        end
    end
    adopted
end
function is_gabriel(points,edge,directed)
    a,b = edge
    for direction in (edge,reverse(edge))
        q = get(directed,direction,0)
        q!=0 && dot_at(points[q],points[a],points[b])<=0 && return false
    end
    true
end
function is_relative_neighbor(points,edge)
    a,b = edge
    length2 = d2(points[a],points[b])
    !any(p->d2(points[a],p)<length2 && d2(points[b],p)<length2,points)
end
function greedy_route(points,neighbors,start,target)
    path = [start]
    total = 0.0
    while path[end]!=target
        current = path[end]
        next_site = argmin(s->(d2(points[s],points[target]),s),neighbors[current])
        total += sqrt(d2(points[current],points[next_site]))
        push!(path,next_site)
    end
    path,total
end
function dijkstra(points,neighbors,start)
    n = length(points)
    distances,previous,done = fill(Inf,n),zeros(Int,n),falses(n)
    distances[start] = 0.0
    for _ in 1:n
        site = 0
        best = Inf
        for s in 1:n
            if !done[s] && distances[s]<best
                site,best = s,distances[s]
            end
        end
        site==0 && break
        done[site] = true
        for other in neighbors[site]
            candidate = distances[site]+sqrt(d2(points[site],points[other]))
            if candidate<distances[other]
                distances[other],previous[other] = candidate,site
            end
        end
    end
    (distances=distances,previous=previous)
end
