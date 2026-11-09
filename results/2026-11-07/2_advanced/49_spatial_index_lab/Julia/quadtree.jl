const CHILD_NAMES = ["NW","NE","SW","SE"]
mutable struct QuadNode
    x::Int
    y::Int
    size::Int
    points::Vector{Vector{Int}}
    children::Vector{QuadNode}
end
QuadNode(x,y,size) = QuadNode(x,y,size,Vector{Int}[],QuadNode[])
quad_destination(node,p) = 1+Int(p[2]>=node.x+node.size÷2)+2Int(p[3]>=node.y+node.size÷2)
function quad_insert!(root,point,capacity)
    node = root
    while !isempty(node.children)
        node = node.children[quad_destination(node,point)]
    end
    push!(node.points,point)
    sort!(node.points;by=first)
    if length(node.points)>capacity
        half = node.size÷2
        node.children = [
            QuadNode(node.x,node.y,half),
            QuadNode(node.x+half,node.y,half),
            QuadNode(node.x,node.y+half,half),
            QuadNode(node.x+half,node.y+half,half)
        ]
        previous,node.points = node.points,Vector{Int}[]
        for p in previous
            quad_insert!(node,p,capacity)
        end
    end
end
function quad_delete!(root,point,capacity)
    ancestors = QuadNode[]
    node = root
    while !isempty(node.children)
        push!(ancestors,node)
        node = node.children[quad_destination(node,point)]
    end
    filter!(p->p[1]!=point[1],node.points)
    for node in reverse(ancestors)
        any(child->!isempty(child.children),node.children) && break
        points = [p for child in node.children for p in child.points]
        length(points)>capacity && break
        node.points = sort(points;by=first)
        empty!(node.children)
    end
end
function quad_build(points,world,capacity)
    root = QuadNode(0,0,world)
    for point in points
        quad_insert!(root,point,capacity)
    end
    root
end
