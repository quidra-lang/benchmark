module FPGrowth
using ..Baskets
export growth
mutable struct Node
    item::Int
    parent::Int
    count::Int
    children::Dict{Int,Int}
end
struct Tree
    header::Vector{Int}
    nodes::Vector{Node}
end
function tree(base,minimum)
    supports = Dict{Int,Int}()
    for (mask,weight) in base, code in members(mask)
        supports[code] = get(supports,code,0)+weight
    end
    header = sort!([code for (code,count) in supports if count >= minimum],by=code -> (-supports[code],code))
    nodes = [Node(0,0,0,Dict{Int,Int}())]
    for (mask,weight) in base
        current = 1
        for code in header
            hasitems(mask,bit(code)) || continue
            child = get(nodes[current].children,code,0)
            if child == 0
                push!(nodes,Node(code,current,0,Dict{Int,Int}()))
                child = length(nodes)
                nodes[current].children[code] = child
            end
            nodes[child].count += weight
            current = child
        end
    end
    Tree(header,nodes)
end
function conditional(current,item)
    result = Tuple{UInt128,Int}[]
    for node in current.nodes[2:end]
        node.item == item || continue
        mask = UInt128(0)
        parent = node.parent
        while parent != 1
            mask |= bit(current.nodes[parent].item)
            parent = current.nodes[parent].parent
        end
        push!(result,(mask,node.count))
    end
    result
end
function growth(baskets,minimum,maxsize)
    whole = tree([(mask,1) for mask in baskets],minimum)
    header,nodes = length(whole.header),length(whole.nodes)-1
    trees,conditionalnodes = 0,0
    result = Dict{UInt128,Int}()
    stack = [(whole,UInt128(0))]
    while !isempty(stack)
        current,suffix = pop!(stack)
        for item in reverse(current.header)
            mask = suffix | bit(item)
            result[mask] = sum((node.count for node in current.nodes if node.item == item);init=0)
            if count_ones(mask) < maxsize
                child = tree(conditional(current,item),minimum)
                if length(child.nodes) > 1
                    push!(stack,(child,mask))
                    trees += 1
                    conditionalnodes += length(child.nodes)-1
                end
            end
        end
    end
    (header=header,nodes=nodes,trees=trees,conditionalnodes=conditionalnodes,supports=result)
end
end
