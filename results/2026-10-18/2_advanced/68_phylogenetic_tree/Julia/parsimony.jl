function merge_sets(first,second)
    common = first&second
    common!=0 ? (common,0) : (first|second,1)
end
function provisional(rooted,pattern)
    sets,changes = Dict{Int,Int}(),0
    for node in reverse(rooted.order)
        if node<=rooted.tree.size
            sets[node] = pattern[node]
        else
            children = filter(!=(rooted.outgroup),rooted.children[node])
            sets[node],added = merge_sets(sets[children[1]],sets[children[2]])
            changes += added
            if node==rooted.root
                _,added = merge_sets(sets[node],sets[rooted.outgroup])
                changes += added
            end
        end
    end
    sets,changes
end
pattern_scores(tree,patterns,outgroup) = [provisional(
    root_tree(tree,outgroup),
    pattern
)[2] for pattern in patterns.encoded]
parsimony_score(tree,patterns,outgroup) = sum(value*weight for (value,weight) in zip(
    pattern_scores(tree,patterns,outgroup),
    patterns.weights
))
function reconstruct(tree,patterns,outgroup)
    rooted = root_tree(tree,outgroup)
    ancestors = Dict(node=>Char[] for node in tree_internals(tree))
    branch_changes = Dict((a,b)=>0 for (a,b,_) in tree_edges(tree))
    scores = Int[]
    for (pattern,weight) in zip(patterns.encoded,patterns.weights)
        sets,changes = provisional(rooted,pattern)
        push!(scores,changes)
        combined,_ = merge_sets(sets[rooted.root],sets[outgroup])
        first_base = combined&(-combined)
        states = Dict{Int,Int}()
        for node in (rooted.root,outgroup)
            states[node] = sets[node]&first_base!=0 ? first_base : sets[node]&(-sets[node])
        end
        for node in rooted.order[2:end]
            node==outgroup && continue
            parent_state = states[rooted.parents[node]]
            states[node] = sets[node]&parent_state!=0 ? parent_state : sets[node]&(-sets[node])
        end
        for node in keys(ancestors)
            push!(ancestors[node],BASES[trailing_zeros(states[node])+1])
        end
        for (a,b) in keys(branch_changes)
            states[a]!=states[b] && (branch_changes[(a,b)]+=weight)
        end
    end
    sequences = Dict(node=>join(states[index] for index in patterns.columns) for (node,states) in ancestors)
    sequences,branch_changes,[scores[index] for index in patterns.columns]
end
function branches(tree,outgroup)
    rooted = root_tree(tree,outgroup)
    sort!([(
        child==outgroup ? rooted.ingroup : rooted.masks[child],
        rooted.parents[child],
        child
    ) for child in rooted.order[2:end]])
end
function insert_taxon(tree,a,b,taxon)
    result = copy_tree(tree)
    disconnect!(result,a,b)
    node = internal_node!(result)
    result.adjacent[taxon] = Dict{Int,Float64}()
    connect!(result,a,node)
    connect!(result,b,node)
    connect!(result,taxon,node)
    result
end
function nni_candidates(tree,outgroup)
    rooted = root_tree(tree,outgroup)
    candidates = Tuple{Int,Int,PhyloTree}[]
    for (mask,a,b) in branches(tree,outgroup)
        (a<=tree.size || b<=tree.size) && continue
        sibling = first(child for child in rooted.children[a] if child!=b && child!=outgroup)
        children = sort!(copy(rooted.children[b]);by=child->rooted.masks[child])
        for (swap,child) in enumerate(children)
            result = copy_tree(tree)
            sibling_length = disconnect!(result,a,sibling)
            child_length = disconnect!(result,b,child)
            connect!(result,a,child,child_length)
            connect!(result,b,sibling,sibling_length)
            push!(candidates,(mask,swap,result))
        end
    end
    candidates
end
