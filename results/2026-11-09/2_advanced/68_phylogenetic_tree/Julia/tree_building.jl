Base.@kwdef mutable struct PhyloTree
    size::Int
    adjacent::Dict{Int,Dict{Int,Float64}}
    next_node::Int
    negative::Int = 0
end
PhyloTree(n,taxa) = PhyloTree(size=n,adjacent=Dict(t=>Dict{Int,Float64}() for t in taxa),next_node=n+1)
function internal_node!(tree)
    node = tree.next_node
    tree.next_node += 1
    tree.adjacent[node] = Dict{Int,Float64}()
    node
end
function connect!(tree,a,b,length=0.0)
    tree.adjacent[a][b] = tree.adjacent[b][a] = length
end
function disconnect!(tree,a,b)
    length = pop!(tree.adjacent[a],b)
    delete!(tree.adjacent[b],a)
    length
end
copy_tree(tree) = PhyloTree(
    size=tree.size,
    adjacent=Dict(node=>copy(neighbors) for (node,neighbors) in tree.adjacent),
    next_node=tree.next_node,
    negative=tree.negative
)
tree_taxa(tree) = sort!([node for node in keys(tree.adjacent) if node<=tree.size])
tree_internals(tree) = sort!([node for node in keys(tree.adjacent) if node>tree.size])
tree_edges(tree) = [(
    a,
    b,
    tree.adjacent[a][b]
) for a in sort!(collect(keys(tree.adjacent))) for b in sort!(collect(keys(tree.adjacent[a]))) if a<b]
function root_tree(tree,outgroup)
    root = first(keys(tree.adjacent[outgroup]))
    parents,children,masks,order = Dict{Int,Int}(),Dict{Int,Vector{Int}}(),Dict{Int,Int}(),Int[]
    function visit(node,parent)
        parents[node] = parent
        push!(order,node)
        children[node] = sort!([neighbor for neighbor in keys(tree.adjacent[node]) if neighbor!=parent])
        mask = node<=tree.size ? 1<<(node-1) : 0
        for child in children[node]
            visit(child,node)
            mask |= masks[child]
        end
        masks[node] = mask
    end
    visit(root,0)
    (
        tree=tree,
        outgroup=outgroup,
        root=root,
        parents=parents,
        children=children,
        masks=masks,
        order=order,
        ingroup=xor(masks[root],1<<(outgroup-1))
    )
end
split_set(rooted) = Set(rooted.masks[node] for node in tree_internals(rooted.tree) if node!=rooted.root)
function branch_lengths(rooted)
    Dict((node==rooted.outgroup ? rooted.ingroup : rooted.masks[node])=>rooted.tree.adjacent[node][rooted.parents[node]] for node in rooted.order[2:end])
end
function star_tree(n,taxa)
    tree = PhyloTree(n,taxa)
    root = internal_node!(tree)
    for taxon in taxa
        connect!(tree,root,taxon)
    end
    tree
end
function neighbor_joining(matrix,taxa)
    active = collect(taxa)
    tree = PhyloTree(size(matrix,1),active)
    distances = Dict((a,b)=>matrix[a,b] for a in active for b in active)
    while length(active)>=4
        n = length(active)
        totals = Dict(a=>foldl(+, (distances[(a,b)] for b in active if b!=a);init=0.0) for a in active)
        best,selected = Inf,(0,0)
        for i in 1:n-1,j in i+1:n
            a,b = active[i],active[j]
            value = (n-2)*distances[(a,b)]-totals[a]-totals[b]
            value<best && ((best,selected)=(value,(a,b)))
        end
        a,b = selected
        node = internal_node!(tree)
        distance = distances[(a,b)]
        first_length = distance/2+(totals[a]-totals[b])/(2*(n-2))
        connect!(tree,a,node,first_length)
        connect!(tree,b,node,distance-first_length)
        remaining = filter(x->x!=a && x!=b,active)
        for other in remaining
            value = (distances[(a,other)]+distances[(b,other)]-distance)/2
            distances[(node,other)] = distances[(other,node)] = value
        end
        active = [remaining;node]
    end
    a,b,c = active
    node = internal_node!(tree)
    ab,ac,bc = distances[(a,b)],distances[(a,c)],distances[(b,c)]
    connect!(tree,a,node,(ab+ac-bc)/2)
    connect!(tree,b,node,(ab+bc-ac)/2)
    connect!(tree,c,node,(ac+bc-ab)/2)
    for (a,b,branch_length) in tree_edges(tree)
        if branch_length<0
            connect!(tree,a,b,0.0)
            tree.negative += 1
        end
    end
    tree
end
function path_distances(tree,start;unit=false)
    distances,stack = Dict(start=>0.0),[(start,0)]
    while !isempty(stack)
        node,parent = pop!(stack)
        for neighbor in sort!(collect(keys(tree.adjacent[node])))
            neighbor==parent && continue
            distances[neighbor] = distances[node]+(unit ? 1 : tree.adjacent[node][neighbor])
            push!(stack,(neighbor,node))
        end
    end
    distances
end
function patristic_matrix(tree)
    matrix = zeros(tree.size,tree.size)
    taxa = tree_taxa(tree)
    for (i,a) in enumerate(taxa)
        distances = path_distances(tree,a)
        for b in taxa[i+1:end]
            matrix[a,b] = matrix[b,a] = distances[b]
        end
    end
    matrix
end
