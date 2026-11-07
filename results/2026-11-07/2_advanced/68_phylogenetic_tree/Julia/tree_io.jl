using Printf
function real_text(value,places)
    text = Printf.format(Printf.Format("%.$(places)f"),value)
    startswith(text,"-") && parse(Float64,text)==0 ? text[2:end] : text
end
symbols(mask,n) = join(mask&(1<<(taxon-1))!=0 ? '*' : '.' for taxon in 1:n)
function child_order(rooted,names)
    minima,children = Dict{Int,String}(),Dict{Int,Vector{Int}}()
    for node in reverse(rooted.order)
        if node<=rooted.tree.size
            minima[node],children[node] = names[node],Int[]
        else
            children[node] = sort!(copy(rooted.children[node]);by=child->minima[child])
            minima[node] = minima[children[node][1]]
        end
    end
    children
end
function newick(tree,names,outgroup;lengths=false,support=nothing)
    rooted = root_tree(tree,outgroup)
    children = child_order(rooted,names)
    function node_text(node)
        if node<=tree.size
            text = names[node]
        else
            text = "("*join(node_text.(children[node]),",")*")"
            !isnothing(support) && node!=rooted.root && (text*=string(get(support,rooted.masks[node],0)))
        end
        lengths && node!=rooted.root && (text*=":"*real_text(tree.adjacent[node][rooted.parents[node]],5))
        text
    end
    node_text(rooted.root)*";"
end
function cladogram(tree,names,outgroup,support)
    rooted = root_tree(tree,outgroup)
    children = child_order(rooted,names)
    lines = ["*"]
    function descend(node,prefix)
        for (i,child) in enumerate(children[node])
            last_child = i==length(children[node])
            connector = last_child ? "`-- " : "|-- "
            label = child<=tree.size ? names[child] : "[$(get(support,rooted.masks[child],0))]"
            push!(lines,prefix*connector*label)
            descend(child,prefix*(last_child ? "    " : "|   "))
        end
    end
    descend(rooted.root,"")
    lines
end
function write_lines(filename,lines)
    mkpath("output")
    open(joinpath("output",filename),"w") do io
        for line in lines
            println(io,line)
        end
    end
end
