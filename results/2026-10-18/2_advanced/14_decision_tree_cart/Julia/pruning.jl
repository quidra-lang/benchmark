struct Decision
    node::Node
    rows::Int
    leaf_error::Int
    subtree_error::Int
    pruned::Bool
end

struct SequenceTree
    alpha::Tuple{Int,Int}
    tree::PrunedTree
end

function reduced_error_pruning(root, rows)
    reached = Dict{Int,Vector{Row}}()
    for row in rows
        for node in first(route(PrunedTree(root), row))
            push!(get!(reached, node.number, Row[]), row)
        end
    end
    decisions, cut = Decision[], Set{Int}()
    function decide(node)
        visiting = get(reached, node.number, Row[])
        leaf_error = count(row -> row.label != node.prediction, visiting)
        isnothing(node.split) && return leaf_error
        subtree_error = decide(node.left) + decide(node.right)
        pruned = leaf_error <= subtree_error
        push!(decisions, Decision(node, length(visiting), leaf_error, subtree_error, pruned))
        pruned && push!(cut, node.number)
        pruned ? leaf_error : subtree_error
    end
    decide(root)
    PrunedTree(root, cut), decisions
end

function cost_complexity_sequence(root)
    tree = PrunedTree(root)
    sequence = [SequenceTree((0, 1), tree)]
    while !is_leaf(tree, root)
        alpha = nothing
        weakest = Set{Int}()
        for node in internal_nodes(tree)
            descendants = leaves(tree, node)
            strength = (node.errors - sum(leaf.errors for leaf in descendants), length(descendants) - 1)
            if isnothing(alpha) || is_greater(alpha, strength)
                alpha = strength
                weakest = Set([node.number])
            elseif !is_greater(strength, alpha)
                push!(weakest, node.number)
            end
        end
        tree = PrunedTree(root, union(tree.cut, weakest))
        push!(sequence, SequenceTree(alpha, tree))
    end
    sequence
end
