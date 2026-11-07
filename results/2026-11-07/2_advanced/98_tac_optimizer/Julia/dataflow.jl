const TACDefinition = Tuple{String,Int}
const TACCopy = Tuple{String,String}
function reaching_transfer(entry,number,state)
    entry.destination === nothing && return copy(state)
    result = Set{TACDefinition}(definition for definition in state if definition[1] != entry.destination)
    push!(result,(entry.destination,number))
    result
end
function live_transfer(entry,state)
    result = copy(state)
    entry.destination !== nothing && delete!(result,entry.destination)
    union!(result,used_variables(entry))
end
function expression_transfer(entry,number,state)
    result = copy(state)
    value = expression(entry)
    value !== nothing && push!(result,value)
    entry.kind == "store" && filter!(value->!(value[1] == "load" && value[2] == entry.name),result)
    entry.kind == "call" && filter!(value->value[1] != "load",result)
    entry.destination !== nothing && filter!(value->!(entry.destination in value[3:4]),result)
    result
end
function copy_transfer(entry,number,state)
    result = Set{TACCopy}(pair for pair in state if !(entry.destination in pair))
    entry.kind == "copy" && entry.a isa String && entry.destination != entry.a && push!(result,(entry.destination,entry.a))
    result
end
function forward_flow(graph,kind,transfer,universe::Set{T}) where T
    incoming = Dict{Int,Set{T}}()
    outgoing = Dict(number=>copy(universe) for number in graph.reachable)
    iterations = 0
    while true
        changed = false
        iterations += 1
        for number in graph.reverse_postorder
            predecessors = graph.reachable_predecessors[number]
            if kind == "reaching"
                state = Set{T}()
                for predecessor in predecessors
                    union!(state,outgoing[predecessor])
                end
                number == 1 && union!(state,((parameter,0) for parameter in graph.function_node.parameters))
            elseif number == 1
                state = Set{T}()
            else
                state = copy(outgoing[predecessors[1]])
                for predecessor in predecessors[2:end]
                    intersect!(state,outgoing[predecessor])
                end
            end
            incoming[number] = copy(state)
            for instruction_number in graph.blocks[number].instructions
                state = transfer(graph.instructions[instruction_number],instruction_number,state)
            end
            if state != outgoing[number]
                outgoing[number] = state
                changed = true
            end
        end
        !changed && return incoming,outgoing,iterations
    end
end
function liveness(graph)
    incoming = Dict(number=>Set{String}() for number in graph.reachable)
    outgoing = Dict{Int,Set{String}}()
    iterations = 0
    while true
        changed = false
        iterations += 1
        for number in graph.postorder
            state = Set{String}()
            for successor in graph.blocks[number].successors
                union!(state,incoming[successor])
            end
            outgoing[number] = copy(state)
            for instruction_number in reverse(graph.blocks[number].instructions)
                state = live_transfer(graph.instructions[instruction_number],state)
            end
            if state != incoming[number]
                incoming[number] = state
                changed = true
            end
        end
        !changed && return incoming,outgoing,iterations
    end
end
function boundaries(graph,incoming,transfer)
    result = empty(incoming)
    for block in graph.reachable
        state = copy(incoming[block])
        for number in graph.blocks[block].instructions
            result[number] = copy(state)
            state = transfer(graph.instructions[number],number,state)
        end
    end
    result
end
struct TACDataFlow
    iterations::Dict{String,Int}
    reaching_in::Dict{Int,Set{TACDefinition}}
    reaching_out::Dict{Int,Set{TACDefinition}}
    live_in::Dict{Int,Set{String}}
    live_out::Dict{Int,Set{String}}
    expression_in::Dict{Int,Set{TACExpression}}
    expression_out::Dict{Int,Set{TACExpression}}
    copy_in::Dict{Int,Set{TACCopy}}
    copy_out::Dict{Int,Set{TACCopy}}
    reaching_before::Dict{Int,Set{TACDefinition}}
    expression_before::Dict{Int,Set{TACExpression}}
    copy_before::Dict{Int,Set{TACCopy}}
    live_before::Dict{Int,Set{String}}
    live_after::Dict{Int,Set{String}}
end
function TACDataFlow(graph)
    expressions,copies = Set{TACExpression}(),Set{TACCopy}()
    for (number,entry) in enumerate(graph.instructions)
        graph.block_of[number] in graph.reachable || continue
        value = expression(entry)
        value !== nothing && push!(expressions,value)
        entry.kind == "copy" && entry.a isa String && entry.destination != entry.a && push!(copies,(entry.destination,entry.a))
    end
    reaching_in,reaching_out,reaching_iterations = forward_flow(graph,"reaching",reaching_transfer,Set{TACDefinition}())
    live_in,live_out,live_iterations = liveness(graph)
    expression_in,expression_out,expression_iterations = forward_flow(graph,"expressions",expression_transfer,expressions)
    copy_in,copy_out,copy_iterations = forward_flow(graph,"copies",copy_transfer,copies)
    live_before,live_after = Dict{Int,Set{String}}(),Dict{Int,Set{String}}()
    for block in graph.reachable
        state = copy(live_out[block])
        for number in reverse(graph.blocks[block].instructions)
            live_after[number] = copy(state)
            state = live_transfer(graph.instructions[number],state)
            live_before[number] = copy(state)
        end
    end
    TACDataFlow(Dict("reaching"=>reaching_iterations,"liveness"=>live_iterations,"expressions"=>expression_iterations,"copies"=>copy_iterations),
        reaching_in,reaching_out,live_in,live_out,expression_in,expression_out,copy_in,copy_out,
        boundaries(graph,reaching_in,reaching_transfer),boundaries(graph,expression_in,expression_transfer),
        boundaries(graph,copy_in,copy_transfer),live_before,live_after)
end
