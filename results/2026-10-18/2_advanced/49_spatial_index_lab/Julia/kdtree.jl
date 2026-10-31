mutable struct KDNode
    point::Vector{Int}
    axis::Int
    left::Union{Nothing,KDNode}
    right::Union{Nothing,KDNode}
end
kd_key(p,axis) = axis==0 ? (p[2],p[3],p[1]) : (p[3],p[2],p[1])
function kd_build(points,depth=0)
    isempty(points) && return nothing
    axis = depth%2
    ordered = sort(points;by=p->kd_key(p,axis))
    middle = length(points)÷2+1
    KDNode(ordered[middle],axis,kd_build(ordered[1:middle-1],depth+1),kd_build(ordered[middle+1:end],depth+1))
end
function kd_insert!(root,point)
    isnothing(root) && return KDNode(point,0,nothing,nothing)
    node = root
    while true
        left = kd_key(point,node.axis)<kd_key(node.point,node.axis)
        child = left ? node.left : node.right
        if isnothing(child)
            child = KDNode(point,1-node.axis,nothing,nothing)
            if left
                node.left = child
            else
                node.right = child
            end
            return root
        end
        node = child
    end
end
function kd_minimum(root,axis)
    best = root.point
    pending = [root]
    while !isempty(pending)
        node = pop!(pending)
        if node.axis==axis && !isnothing(node.left)
            push!(pending,node.left)
            continue
        end
        kd_key(node.point,axis)<kd_key(best,axis) && (best=node.point)
        if node.axis!=axis
            isnothing(node.left) || push!(pending,node.left)
            isnothing(node.right) || push!(pending,node.right)
        end
    end
    best
end
function kd_delete!(root,point)
    parent,node,left = nothing,root,false
    while !isnothing(node)
        if node.point[1]!=point[1]
            parent = node
            left = kd_key(point,node.axis)<kd_key(node.point,node.axis)
            node = left ? node.left : node.right
        elseif !isnothing(node.right)
            point = kd_minimum(node.right,node.axis)
            node.point = point
            parent,node,left = node,node.right,false
        elseif !isnothing(node.left)
            point = kd_minimum(node.left,node.axis)
            node.point = point
            node.right,node.left = node.left,nothing
            parent,node,left = node,node.right,false
        else
            isnothing(parent) && return nothing
            if left
                parent.left = nothing
            else
                parent.right = nothing
            end
            return root
        end
    end
    root
end
