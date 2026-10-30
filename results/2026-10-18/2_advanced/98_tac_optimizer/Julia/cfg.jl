mutable struct TACBlock
    number::Int
    labels::Vector{String}
    start::Int
    finish::Int
    instructions::Vector{Int}
    predecessors::Vector{Int}
    successors::Vector{Int}
end
TACBlock(number,labels,start) = TACBlock(number,copy(labels),start,0,Int[],Int[],Int[])
mutable struct TACLoop
    header::Int
    latches::Vector{Int}
    blocks::BitSet
    depth::Int
    exits::BitSet
    outside::BitSet
end
Base.@kwdef mutable struct TACCFG
    function_node::TACFunction
    blocks::Vector{TACBlock} = TACBlock[]
    instructions::Vector{TACInstruction} = TACInstruction[]
    positions::Vector{Int} = Int[]
    block_of::Vector{Int} = Int[]
    reachable::BitSet = BitSet()
    postorder::Vector{Int} = Int[]
    reverse_postorder::Vector{Int} = Int[]
    reachable_predecessors::Vector{Vector{Int}} = Vector{Int}[]
    dominators::Vector{BitSet} = BitSet[]
    immediate::Vector{Int} = Int[]
    loops::Vector{TACLoop} = TACLoop[]
    depth::Vector{Int} = Int[]
end
function TACCFG(function_node)
    graph = TACCFG(function_node=function_node)
    pending,first_label = String[],0
    current,previous_kind = nothing,""
    for (index,line) in enumerate(function_node.code)
        if line isa String
            isempty(pending) && (first_label = index)
            push!(pending,line)
            continue
        end
        number = length(graph.instructions)+1
        if current === nothing || !isempty(pending) || previous_kind in ("goto","if","return")
            start = isempty(pending) ? index : first_label
            current !== nothing && (current.finish = start)
            current = TACBlock(length(graph.blocks)+1,pending,start)
            push!(graph.blocks,current)
            pending = String[]
        end
        push!(graph.instructions,line)
        push!(graph.positions,index)
        push!(graph.block_of,current.number)
        push!(current.instructions,number)
        previous_kind = line.kind
    end
    current.finish = length(function_node.code)+1
    labels = Dict(label=>block.number for block in graph.blocks for label in block.labels)
    for block in graph.blocks
        last = graph.instructions[block.instructions[end]]
        if last.kind == "goto"
            block.successors = [labels[last.name]]
        elseif last.kind == "if"
            block.successors = unique([block.number+1,labels[last.name]])
        elseif last.kind != "return"
            block.successors = [block.number+1]
        end
        for successor in block.successors
            push!(graph.blocks[successor].predecessors,block.number)
        end
    end
    push!(graph.reachable,1)
    stack = [(1,1)]
    while !isempty(stack)
        number,index = stack[end]
        successors = graph.blocks[number].successors
        if index > length(successors)
            push!(graph.postorder,number)
            pop!(stack)
        else
            stack[end] = (number,index+1)
            successor = successors[index]
            if !(successor in graph.reachable)
                push!(graph.reachable,successor)
                push!(stack,(successor,1))
            end
        end
    end
    graph.reverse_postorder = reverse(graph.postorder)
    graph.reachable_predecessors = [filter(number->number in graph.reachable,block.predecessors) for block in graph.blocks]
    graph.dominators = [number in graph.reachable ? copy(graph.reachable) : BitSet() for number in eachindex(graph.blocks)]
    graph.dominators[1] = BitSet([1])
    changed = true
    while changed
        changed = false
        for number in graph.reverse_postorder[2:end]
            predecessors = graph.reachable_predecessors[number]
            value = copy(graph.dominators[predecessors[1]])
            for predecessor in predecessors[2:end]
                intersect!(value,graph.dominators[predecessor])
            end
            push!(value,number)
            if value != graph.dominators[number]
                graph.dominators[number] = value
                changed = true
            end
        end
    end
    graph.immediate = zeros(Int,length(graph.blocks))
    for number in sort(collect(setdiff(graph.reachable,BitSet([1]))))
        graph.immediate[number] = argmax(parent->length(graph.dominators[parent]),setdiff(graph.dominators[number],BitSet([number])))
    end
    for header in graph.reachable
        latches = filter(number->header in graph.dominators[number],graph.reachable_predecessors[header])
        isempty(latches) && continue
        members = BitSet([header;latches])
        pending = filter(!=(header),latches)
        while !isempty(pending)
            number = pop!(pending)
            for predecessor in graph.reachable_predecessors[number]
                if !(predecessor in members)
                    push!(members,predecessor)
                    push!(pending,predecessor)
                end
            end
        end
        push!(graph.loops,TACLoop(header,latches,members,0,BitSet(),BitSet()))
    end
    graph.depth = [count(loop->number in loop.blocks,graph.loops) for number in eachindex(graph.blocks)]
    for loop in graph.loops
        loop.depth = count(other->loop.header in other.blocks,graph.loops)
        for number in loop.blocks
            block = graph.blocks[number]
            outside = setdiff(BitSet(block.successors),loop.blocks)
            union!(loop.outside,outside)
            (!isempty(outside) || graph.instructions[block.instructions[end]].kind == "return") && push!(loop.exits,number)
        end
    end
    graph
end
