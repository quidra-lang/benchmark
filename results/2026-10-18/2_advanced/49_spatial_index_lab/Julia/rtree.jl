point_box(p) = (p[2],p[3],p[2],p[3])
area(b) = (b[3]-b[1])*(b[4]-b[2])
mbr(a,b) = (min(a[1],b[1]),min(a[2],b[2]),max(a[3],b[3]),max(a[4],b[4]))
enlargement(a,b) = area(mbr(a,b))-area(a)
box_contains(a,b) = a[1]<=b[1] && b[3]<=a[3] && a[2]<=b[2] && b[4]<=a[4]
intersects(a,b) = a[1]<=b[3] && b[1]<=a[3] && a[2]<=b[4] && b[2]<=a[4]
function overlap(a,b)
    w,h = min(a[3],b[3])-max(a[1],b[1]),min(a[4],b[4])-max(a[2],b[2])
    w>0 && h>0 ? w*h : 0
end
mutable struct REntry
    box::NTuple{4,Int}
    id::Int
    child::Any
end
mutable struct RNode
    level::Int
    entries::Vector{REntry}
    parent::Any
end
function rnode(level,entries=REntry[],parent=nothing)
    node = RNode(level,entries,parent)
    adopt_children!(node)
    node
end
function adopt_children!(node)
    if node.level>0
        for entry in node.entries
            entry.child.parent = node
        end
    end
end
node_box(node) = foldl(mbr,(entry.box for entry in node.entries))
mutable struct RTree
    root::RNode
    maximum::Int
    minimum::Int
end
function quadratic_split!(tree,node)
    entries = node.entries
    seeds,best = (1,2),typemin(Int)
    for i in 1:length(entries)-1,j in i+1:length(entries)
        a,b = entries[i].box,entries[j].box
        waste = area(mbr(a,b))-area(a)-area(b)
        waste>best && ((seeds,best)=((i,j),waste))
    end
    a,b = seeds
    group1,group2 = [entries[a]],[entries[b]]
    box1,box2 = entries[a].box,entries[b].box
    rest = [entry for (i,entry) in enumerate(entries) if !(i in seeds)]
    while !isempty(rest)
        if length(group1)+length(rest)==tree.minimum
            append!(group1,rest)
            break
        elseif length(group2)+length(rest)==tree.minimum
            append!(group2,rest)
            break
        end
        selected = argmax([abs(enlargement(box1,e.box)-enlargement(box2,e.box)) for e in rest])
        entry = popat!(rest,selected)
        key1,key2 = (enlargement(box1,entry.box),area(box1),length(group1),1),(
            enlargement(box2,entry.box),
            area(box2),
            length(group2),
            2
        )
        if key1<key2
            push!(group1,entry)
            box1 = mbr(box1,entry.box)
        else
            push!(group2,entry)
            box2 = mbr(box2,entry.box)
        end
    end
    node.entries = group1
    adopt_children!(node)
    rnode(node.level,group2,node.parent)
end
function rtree_insert!(tree,entry,level=0)
    node = tree.root
    while node.level>level
        chosen = argmin(
            i->(enlargement(node.entries[i].box,entry.box),area(node.entries[i].box),i),
            eachindex(node.entries)
        )
        node = node.entries[chosen].child
    end
    push!(node.entries,entry)
    level>0 && (entry.child.parent=node)
    while true
        sibling = length(node.entries)>tree.maximum ? quadratic_split!(tree,node) : nothing
        parent = node.parent
        if isnothing(parent)
            if !isnothing(sibling)
                tree.root = rnode(
                    node.level+1,
                    [REntry(node_box(node),0,node),REntry(node_box(sibling),0,sibling)]
                )
            end
            return
        end
        i = findfirst(e->e.child===node,parent.entries)
        parent.entries[i].box = node_box(node)
        if !isnothing(sibling)
            push!(parent.entries,REntry(node_box(sibling),0,sibling))
            sibling.parent = parent
        end
        node = parent
    end
end
function find_leaf(tree,id,box)
    pending = [tree.root]
    while !isempty(pending)
        node = pop!(pending)
        if node.level==0
            i = findfirst(e->e.id==id,node.entries)
            isnothing(i) || return node,i
        else
            for entry in reverse(node.entries)
                box_contains(entry.box,box) && push!(pending,entry.child)
            end
        end
    end
    nothing
end
function rtree_delete!(tree,point)
    node,index = find_leaf(tree,point[1],point_box(point))
    deleteat!(node.entries,index)
    removed = RNode[]
    while node!==tree.root
        parent = node.parent
        i = findfirst(e->e.child===node,parent.entries)
        if length(node.entries)<tree.minimum
            deleteat!(parent.entries,i)
            push!(removed,node)
            node.parent = nothing
        else
            parent.entries[i].box = node_box(node)
        end
        node = parent
    end
    for node in removed,entry in node.entries
        rtree_insert!(tree,entry,node.level)
    end
    while tree.root.level>0 && length(tree.root.entries)==1
        tree.root = tree.root.entries[1].child
        tree.root.parent = nothing
    end
end
function str_root(entries,maximum)
    numbered = [(e.id,e) for e in entries]
    level = 0
    while true
        pages = cld(length(numbered),maximum)
        slabs = 1
        while slabs*slabs<pages
            slabs += 1
        end
        sort!(numbered;by=item->(item[2].box[1]+item[2].box[3],item[2].box[2]+item[2].box[4],item[1]))
        nodes = RNode[]
        slab_size = slabs*maximum
        for start in 1:slab_size:length(numbered)
            slab = numbered[start:min(start+slab_size-1,length(numbered))]
            sort!(slab;by=item->(item[2].box[2]+item[2].box[4],item[2].box[1]+item[2].box[3],item[1]))
            for offset in 1:maximum:length(slab)
                push!(
                    nodes,
                    rnode(level,[item[2] for item in slab[offset:min(offset+maximum-1,length(slab))]])
                )
            end
        end
        length(nodes)==1 && return nodes[1]
        numbered = [(i-1,REntry(node_box(node),0,node)) for (i,node) in enumerate(nodes)]
        level += 1
    end
end
function rtree_build(objects,maximum,minimum;bulk=false)
    entries = [REntry(length(obj)==3 ? point_box(obj) : Tuple(obj[2:end]),obj[1],nothing) for obj in objects]
    tree = RTree(rnode(0),maximum,minimum)
    if bulk
        tree.root = str_root(entries,maximum)
    else
        for entry in entries
            rtree_insert!(tree,entry)
        end
    end
    tree
end
