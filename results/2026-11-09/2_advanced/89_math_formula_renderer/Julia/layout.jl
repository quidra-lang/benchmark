const ELEMENT_TYPES = ["ordinary","operator","binary","relation","open","close","punctuation"]
const SPACING = [Any[0,1,"B","R",0,0,0],Any[1,1,nothing,"R",0,0,0],
    Any["B","B",nothing,nothing,"B",nothing,nothing],Any["R","R",nothing,0,"R",0,0],
    Any[0,0,nothing,0,0,0,0],Any[0,1,"B","R",0,0,0],Any["P","P",nothing,"P","P","P","P"]]
function element_types(node)
    if node.kind == "symbol"
        kind = get(SYMBOL_TYPES,node.value,"ordinary")
    elseif node.kind == "command"
        kind = COMMAND_TYPES[node.value]
    elseif node.kind == "delim"
        return "open","close"
    elseif node.kind == "script"
        return element_types(node.children[1])
    elseif node.kind in ("overset","underset")
        return element_types(node.children[2])
    else
        kind = "ordinary"
    end
    kind,kind
end
function converted_types(nodes)
    result = [collect(element_types(node)) for node in nodes]
    for (i,current) in enumerate(result)
        if current[1] == "binary" && (i == 1 || result[i-1][2] in ("binary","operator","relation","open","punctuation"))
            current .= "ordinary"
        end
        if current[1] in ("relation","close","punctuation") && i > 1 && result[i-1][2] == "binary"
            result[i-1] .= "ordinary"
        end
    end
    !isempty(result) && result[end][2] == "binary" && (result[end] .= "ordinary")
    result
end
function word_element(node)
    node.kind == "script" && return word_element(node.children[1])
    node.kind == "command" && (node.value[2:end] in GREEK || node.value == "\\infty")
end
function alphanumeric(node)
    (node.kind in ("identifier","number") || word_element(node)) && return true
    node.kind == "script" && return alphanumeric(node.children[1])
    node.kind == "accent" && node.value in ("overline","hat","vec","dot","tilde") && alphanumeric(node.children[1])
end
function spacing(nodes,style,parameters)
    types = converted_types(nodes)
    values = Dict("B"=>(style == "normal" ? parameters["bin_space"] : 0),
        "R"=>(style == "normal" ? parameters["rel_space"] : 0),"P"=>(style == "normal" ? parameters["punct_space"] : 0))
    gaps = Int[]
    for i in 1:length(nodes)-1
        first,second = nodes[i],nodes[i+1]
        if alphanumeric(first) && alphanumeric(second) && (word_element(first) || word_element(second))
            push!(gaps,1)
        else
            row,column = findfirst(==(types[i][2]),ELEMENT_TYPES),findfirst(==(types[i+1][1]),ELEMENT_TYPES)
            entry = SPACING[row][column]
            push!(gaps,entry isa String ? values[entry] : entry)
        end
    end
    types,gaps
end
function row_box(children,gaps,description="row",roles=fill("",length(children)))
    ascent = maximum((child.baseline for child in children);init=0)
    depth = maximum((descent(child) for child in children);init=0)
    width = sum((child.width for child in children);init=0)+sum(gaps;init=0)
    result = new_box(width,ascent+depth+1,ascent,description)
    x = 0
    for (i,child) in enumerate(children)
        add_child!(result,child,x,ascent-child.baseline,roles[i])
        x += child.width
        i <= length(gaps) && (x += gaps[i])
    end
    result
end
