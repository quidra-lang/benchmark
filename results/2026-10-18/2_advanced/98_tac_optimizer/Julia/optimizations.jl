function rewrite_code!(function_node,replacements,insertions=Dict{Int,Vector{TACCode}}())
    result = TACCode[]
    number = 0
    for (index,line) in enumerate(function_node.code)
        append!(result,get(insertions,index,TACCode[]))
        if line isa String
            push!(result,line)
        else
            number += 1
            append!(result,get(replacements,number,TACCode[line]))
        end
    end
    append!(result,get(insertions,length(function_node.code)+1,TACCode[]))
    function_node.code = result
end
function fold_instruction(entry)
    entry.kind in ("bin","if") || return entry,false
    a,b = entry.a,entry.b
    first_constant,second_constant = a isa Int,b isa Int
    if first_constant && second_constant
        entry.operation in ("/","%") && b == 0 && return entry,false
        result = calculate(entry.operation,a,b)
        if entry.kind == "if"
            return (result != 0 ? TACInstruction(kind="goto",name=entry.name) : nothing),true
        elseif -2147483648 <= result <= 2147483647
            return TACInstruction(kind="copy",destination=entry.destination,a=result),true
        end
        return entry,false
    end
    (entry.kind != "bin" || first_constant == second_constant) && return entry,false
    op,replacement = entry.operation,nothing
    if op == "+" && (a == 0 || b == 0)
        replacement = first_constant ? b : a
    elseif op == "-" && b == 0
        replacement = a
    elseif op == "*" && (a == 1 || b == 1)
        replacement = first_constant ? b : a
    elseif op == "/" && b == 1
        replacement = a
    elseif op == "*" && (a == 0 || b == 0)
        replacement = 0
    end
    replacement === nothing ? (entry,false) : (TACInstruction(kind="copy",destination=entry.destination,a=replacement),true)
end
function cse_replacements!(function_node,graph,sources,candidates)
    function_node.temporary_serial += 1
    temporary = "_t$(function_node.temporary_serial)"
    replacements = Dict{Int,Vector{TACCode}}()
    for number in sources
        entry = graph.instructions[number]
        replacements[number] = TACCode[replace_instruction(entry;destination=temporary),TACInstruction(kind="copy",destination=entry.destination,a=temporary)]
    end
    for number in candidates
        replacements[number] = TACCode[TACInstruction(kind="copy",destination=graph.instructions[number].destination,a=temporary)]
    end
    temporary,replacements
end
function hoist!(function_node,graph,loop,moves)
    header = graph.blocks[loop.header]
    outside = filter(number->!(number in loop.blocks),header.predecessors)
    replacements = Dict(number=>TACCode[] for number in moves)
    moved = TACCode[graph.instructions[number] for number in moves]
    if loop.header != 1 && length(outside) == 1 && graph.blocks[outside[1]].successors == [loop.header]
        preheader = graph.blocks[outside[1]]
        last = preheader.instructions[end]
        position = graph.positions[last]
        !(graph.instructions[last].kind in ("goto","if")) && (position += 1)
        insertion = moved
        destination = "B$(preheader.number)"
    else
        function_node.preheader_serial += 1
        label = "_p$(function_node.preheader_serial)"
        position = header.start
        insertion = TACCode[label;moved]
        destination = "new " * label
        for number in outside
            last = graph.blocks[number].instructions[end]
            entry = graph.instructions[last]
            if entry.kind in ("goto","if") && entry.name in header.labels
                replacements[last] = TACCode[replace_instruction(entry;name=label)]
            end
        end
    end
    rewrite_code!(function_node,replacements,Dict(position=>insertion))
    destination
end
function remove_unreachable!(function_node,graph)
    blocks = [number for number in eachindex(graph.blocks) if !(number in graph.reachable)]
    deleted = BitSet()
    for number in blocks
        block = graph.blocks[number]
        union!(deleted,block.start:block.finish-1)
    end
    numbers = Dict(position=>number for (number,position) in enumerate(graph.positions))
    remaining = Tuple{TACCode,Int}[(line,get(numbers,index,0)) for (index,line) in enumerate(function_node.code) if !(index in deleted)]
    jumps = Int[]
    for (index,(line,number)) in enumerate(remaining)
        (line isa String || !(line.kind in ("goto","if"))) && continue
        labels = String[]
        following = index+1
        while following <= length(remaining) && remaining[following][1] isa String
            push!(labels,remaining[following][1])
            following += 1
        end
        line.name in labels && push!(jumps,number)
    end
    filter!(pair->!(pair[2] in jumps),remaining)
    targets = Set(line.name for (line,number) in remaining if line isa TACInstruction && line.kind in ("goto","if"))
    labels = String[line for (line,number) in remaining if line isa String && !(line in targets)]
    function_node.code = TACCode[line for (line,number) in remaining if line isa TACInstruction || line in targets]
    blocks,jumps,labels
end
