include("tac_parser.jl")
include("cfg.jl")
include("dataflow.jl")
include("optimizations.jl")
include("regalloc.jl")

const PASS_ORDER = ["constprop","copyprop","cse","dce","licm","unreachable"]
const VERSIONS = ["original","optimized","allocated"]
comma_list(values) = isempty(values) ? "-" : join(string.(collect(values)),",")
block_list(numbers) = comma_list(["B$number" for number in numbers])
instruction_list(numbers) = comma_list(["#$number" for number in numbers])
function read_settings()
    lines = readlines("input/params.txt")
    registers = parse(Int,split(lines[1])[2])
    enabled = Set(split(lines[2])[2:end])
    maximum_rounds = parse(Int,split(lines[3])[2])
    registers,filter(name->name in enabled,PASS_ORDER),maximum_rounds
end
function read_runs()
    lines = readlines("input/input.txt")
    runs = Vector{Int}[]
    for line in lines[2:parse(Int,lines[1])+1]
        values = parse.(Int,split(line))
        push!(runs,values[2:values[1]+1])
    end
    runs
end
reachable_numbers(graph) = [number for number in eachindex(graph.instructions) if graph.block_of[number] in graph.reachable]
reaching_numbers(flow,number,variable) = Set(definition for (name,definition) in flow.reaching_before[number] if name == variable)
function constant_value(graph,definitions)
    (isempty(definitions) || 0 in definitions) && return nothing
    value = nothing
    for number in definitions
        entry = graph.instructions[number]
        (entry.kind != "copy" || !(entry.a isa Int)) && return nothing
        value !== nothing && value != entry.a && return nothing
        value = entry.a
    end
    value
end
function constant_propagation!(function_node,graph,flow)
    replacements,records = Dict{Int,Vector{TACCode}}(),String[]
    for number in reachable_numbers(graph)
        original = graph.instructions[number]
        entry = original
        for field in operand_fields(original)
            variable = getproperty(original,field)
            variable isa String || continue
            value = constant_value(graph,reaching_numbers(flow,number,variable))
            if value !== nothing
                entry = field == :a ? replace_instruction(entry;a=value) : replace_instruction(entry;b=value)
                push!(records,"#$number: $variable -> $value")
            end
        end
        result,folded = fold_instruction(entry)
        if result === nothing
            push!(records,"#$number: delete " * instruction_string(entry))
            replacements[number] = TACCode[]
        else
            folded && push!(records,"#$number: fold " * instruction_string(result))
            replacements[number] = TACCode[result]
        end
    end
    rewrite_code!(function_node,replacements)
    length(records),records
end
function copy_propagation!(function_node,graph,flow)
    replacements,records = Dict{Int,Vector{TACCode}}(),String[]
    for number in reachable_numbers(graph)
        original = graph.instructions[number]
        entry = original
        available = Dict(flow.copy_before[number])
        for field in operand_fields(original)
            variable = getproperty(original,field)
            if variable isa String && haskey(available,variable)
                replacement = available[variable]
                entry = field == :a ? replace_instruction(entry;a=replacement) : replace_instruction(entry;b=replacement)
                push!(records,"#$number: $variable -> $replacement")
            end
        end
        replacements[number] = TACCode[entry]
    end
    rewrite_code!(function_node,replacements)
    length(records),records
end
function expression_sources(graph,value,candidate)
    block_number = graph.block_of[candidate]
    for number in reverse(graph.blocks[block_number].instructions)
        number < candidate && expression(graph.instructions[number]) == value && return BitSet([number])
    end
    sources,examined = BitSet(),BitSet()
    pending = copy(graph.reachable_predecessors[block_number])
    while !isempty(pending)
        number = pop!(pending)
        number in examined && continue
        push!(examined,number)
        found = false
        for instruction_number in reverse(graph.blocks[number].instructions)
            if expression(graph.instructions[instruction_number]) == value
                push!(sources,instruction_number)
                found = true
                break
            end
        end
        !found && append!(pending,graph.reachable_predecessors[number])
    end
    sources
end
function common_subexpressions!(function_node,graph,flow)
    candidates = Dict{TACExpression,Vector{Int}}()
    for number in reachable_numbers(graph)
        value = expression(graph.instructions[number])
        if value !== nothing && value in flow.expression_before[number]
            push!(get!(candidates,value,Int[]),number)
        end
    end
    replacements,records,changes = Dict{Int,Vector{TACCode}}(),String[],0
    for (value,numbers) in sort(collect(candidates);by=pair->pair.second[1])
        sources = BitSet()
        for number in numbers
            union!(sources,expression_sources(graph,value,number))
        end
        setdiff!(sources,numbers)
        temporary,edits = cse_replacements!(function_node,graph,sources,numbers)
        merge!(replacements,edits)
        push!(records,"$(expression_string(value)): $temporary sources=$(instruction_list(sources)) replaced=$(instruction_list(numbers))")
        changes += length(numbers)
    end
    rewrite_code!(function_node,replacements)
    changes,records
end
function dead_code!(function_node,graph,flow)
    replacements,records = Dict{Int,Vector{TACCode}}(),Tuple{Int,String}[]
    for block_number in graph.reachable
        state = copy(flow.live_out[block_number])
        for number in reverse(graph.blocks[block_number].instructions)
            entry = graph.instructions[number]
            destination = entry.destination
            self_copy = entry.kind == "copy" && destination == entry.a
            dead_assignment = entry.kind in ("copy","bin","load") && !(destination in state)
            if self_copy || dead_assignment
                replacements[number] = TACCode[]
                push!(records,(number,"#$number: delete " * instruction_string(entry)))
                continue
            end
            if entry.kind == "call" && destination !== nothing && !(destination in state)
                push!(records,(number,"#$number: unused result " * instruction_string(entry)))
                entry = replace_instruction(entry;destination=nothing)
                replacements[number] = TACCode[entry]
            end
            state = live_transfer(entry,state)
        end
    end
    rewrite_code!(function_node,replacements)
    ordered = [record for (number,record) in sort(records;by=first)]
    length(ordered),ordered
end
inside_definitions(graph,loop,definitions) = BitSet(number for number in definitions if number != 0 && graph.block_of[number] in loop.blocks)
function invariant_operand(graph,flow,loop,number,variable,marked)
    definitions = reaching_numbers(flow,number,variable)
    inside = inside_definitions(graph,loop,definitions)
    isempty(inside) || (length(definitions) == 1 && issubset(inside,marked))
end
function marked_invariants(graph,flow,loop,numbers)
    stores = Set(graph.instructions[number].name for number in numbers if graph.instructions[number].kind == "store")
    calls = any(number->graph.instructions[number].kind == "call",numbers)
    marked,order = BitSet(),Int[]
    while true
        changed = false
        for number in numbers
            entry = graph.instructions[number]
            (number in marked || !(entry.kind in ("copy","bin","load"))) && continue
            entry.kind == "load" && (calls || entry.name in stores) && continue
            if all(variable->invariant_operand(graph,flow,loop,number,variable,marked),used_variables(entry))
                push!(marked,number)
                push!(order,number)
                changed = true
            end
        end
        !changed && return order
    end
end
function movable_invariants(graph,flow,loop,numbers,marked_order)
    definitions = Dict{String,Int}()
    for number in numbers
        destination = graph.instructions[number].destination
        destination !== nothing && (definitions[destination] = get(definitions,destination,0)+1)
    end
    moved,order = BitSet(),Int[]
    for number in marked_order
        entry = graph.instructions[number]
        destination = entry.destination
        (definitions[destination] != 1 || destination in flow.live_in[loop.header]) && continue
        block_number = graph.block_of[number]
        dominates_exits = all(exit_block->block_number in graph.dominators[exit_block],loop.exits)
        dangerous = entry.kind == "load" || (entry.kind == "bin" && entry.operation in ("/","%") && (entry.b isa String || entry.b == 0))
        dead_outside = all(successor->!(destination in flow.live_in[successor]),loop.outside)
        !dominates_exits && (dangerous || !dead_outside) && continue
        ready = all(variable->issubset(inside_definitions(graph,loop,reaching_numbers(flow,number,variable)),moved),used_variables(entry))
        if ready
            push!(moved,number)
            push!(order,number)
        end
    end
    order
end
function loop_invariant_motion!(function_node,graph,flow)
    for loop in sort(graph.loops;by=loop->(length(loop.blocks),loop.header))
        numbers = sort([number for block in loop.blocks for number in graph.blocks[block].instructions])
        moves = movable_invariants(graph,flow,loop,numbers,marked_invariants(graph,flow,loop,numbers))
        if !isempty(moves)
            destination = hoist!(function_node,graph,loop,moves)
            return length(moves),["B$(loop.header): hoist $(instruction_list(moves)) to $destination"]
        end
    end
    0,String[]
end
function unreachable_code!(function_node,graph,flow)
    blocks,jumps,labels = remove_unreachable!(function_node,graph)
    records = [["remove block B$number" for number in blocks];["remove jump #$number" for number in jumps];["remove label $label" for label in labels]]
    length(records),records
end
const PASSES = Dict("constprop"=>constant_propagation!,"copyprop"=>copy_propagation!,"cse"=>common_subexpressions!,
    "dce"=>dead_code!,"licm"=>loop_invariant_motion!,"unreachable"=>unreachable_code!)
function optimize_function!(function_node,enabled,maximum_rounds,totals)
    original_count = length(instructions(function_node))
    lines = ["== $(function_node.name) =="]
    rounds = 0
    for round_number in 1:maximum_rounds
        rounds = round_number
        counts,records = Int[],String[]
        for name in enabled
            graph = TACCFG(function_node)
            flow = TACDataFlow(graph)
            count,pass_records = PASSES[name](function_node,graph,flow)
            push!(counts,count)
            totals[name] += count
            append!(records,["  $name $record" for record in pass_records])
        end
        push!(lines,"round $round_number: " * join(("$name=$count" for (name,count) in zip(enabled,counts))," "))
        append!(lines,records)
        all(==(0),counts) && break
    end
    push!(lines,"result: rounds=$rounds instructions=$original_count->$(length(instructions(function_node)))")
    lines
end
function reachable_names(callees,starts)
    reached = Set{String}()
    pending = collect(starts)
    while !isempty(pending)
        name = pop!(pending)
        if !(name in reached)
            push!(reached,name)
            append!(pending,callees[name])
        end
    end
    reached
end
function call_graph(program)
    names = [function_node.name for function_node in program.functions]
    callees = Dict{String,Vector{String}}()
    for function_node in program.functions
        called = Set(entry.name for entry in instructions(function_node) if entry.kind == "call")
        callees[function_node.name] = filter(name->name in called,names)
    end
    recursive = Set(name for name in names if name in reachable_names(callees,callees[name]))
    callees,reachable_names(callees,["main"]),recursive
end
function call_graph_lines(program,heading)
    callees,reachable,recursive = call_graph(program)
    lines = ["== call graph ($heading) =="]
    for function_node in program.functions
        name = function_node.name
        push!(lines,"$name -> $(comma_list(callees[name]))" * (name in recursive ? " (recursive)" : ""))
    end
    push!(lines,"unreachable functions: " * comma_list([f.name for f in program.functions if !(f.name in reachable)]))
    lines,reachable
end
definition_list(definitions) = comma_list(["$variable:$number" for (variable,number) in sort(collect(definitions);by=pair->(pair[2],pair[1]))])
function function_analysis(function_node,heading)
    graph = TACCFG(function_node)
    flow = TACDataFlow(graph)
    lines = ["== $(function_node.name) ($heading) ==","code:"]
    number = 0
    for line in function_node.code
        if line isa String
            push!(lines,line * ":")
            continue
        end
        number += 1
        text = "  #$number " * instruction_string(line)
        if graph.block_of[number] in graph.reachable
            variables = unique(used_variables(line))
            if !isempty(variables)
                chains = ["$variable:$(comma_list(sort(collect(reaching_numbers(flow,number,variable)))))" for variable in variables]
                text *= " | " * join(chains," ")
            end
        end
        push!(lines,text)
    end
    push!(lines,"blocks: $(length(graph.blocks))")
    for block in graph.blocks
        push!(lines,"B$(block.number) $(block.instructions[1])-$(block.instructions[end]) labels=$(comma_list(block.labels)) preds=$(block_list(block.predecessors)) succs=$(block_list(block.successors))")
    end
    push!(lines,"unreachable: " * block_list([number for number in eachindex(graph.blocks) if !(number in graph.reachable)]))
    push!(lines,"order: " * block_list(graph.reverse_postorder),"dominators:")
    for number in graph.reachable
        parent = graph.immediate[number]
        push!(lines,"B$number idom=$(parent == 0 ? "-" : "B$parent") dom=$(block_list(graph.dominators[number]))")
    end
    push!(lines,"dominator tree:")
    stack = [(1,0)]
    while !isempty(stack)
        number,depth = pop!(stack)
        push!(lines,"  "^depth * "B$number")
        children = [child for child in eachindex(graph.immediate) if graph.immediate[child] == number]
        append!(stack,[(child,depth+1) for child in reverse(children)])
    end
    push!(lines,"loops: $(length(graph.loops))")
    for loop in graph.loops
        push!(lines,"header=B$(loop.header) latches=$(block_list(loop.latches)) depth=$(loop.depth) blocks=$(block_list(loop.blocks)) exits=$(block_list(loop.exits))")
    end
    analyses = (("reaching definitions","reaching",flow.reaching_in,flow.reaching_out,definition_list),
        ("liveness","liveness",flow.live_in,flow.live_out,state->comma_list(sort(collect(state)))),
        ("available expressions","expressions",flow.expression_in,flow.expression_out,state->comma_list(sort(expression_string.(collect(state))))))
    for (title,key,incoming,outgoing,render) in analyses
        push!(lines,"$title: iterations=$(flow.iterations[key])")
        for number in graph.reachable
            push!(lines,"B$number in=$(render(incoming[number])) out=$(render(outgoing[number]))")
        end
    end
    lines
end
function rewrite_registers(function_node,colors)
    names = Dict(variable=>"R$color" for (variable,color) in colors if color >= 0)
    code,moves = TACCode[],0
    for line in function_node.code
        if line isa String
            push!(code,line)
            continue
        end
        destination = line.destination === nothing ? nothing : get(names,line.destination,line.destination)
        a = line.a isa String ? get(names,line.a,line.a) : line.a
        b = line.b isa String ? get(names,line.b,line.b) : line.b
        entry = replace_instruction(line;destination=destination,a=a,b=b)
        if entry.kind == "copy" && entry.destination == entry.a
            moves += 1
        else
            push!(code,entry)
        end
    end
    parameters = [get(names,parameter,parameter) for parameter in function_node.parameters]
    TACFunction(function_node.name,parameters,code),moves
end
function allocation_report(function_node,registers)
    graph = TACCFG(function_node)
    flow = TACDataFlow(graph)
    allocation = TACAllocation(function_node,graph,flow,registers)
    allocated,moves = rewrite_registers(function_node,allocation.colors)
    nodes = sort(collect(keys(allocation.neighbors)))
    edges = div(sum(length,values(allocation.neighbors);init=0),2)
    lines = ["== $(function_node.name) ==","nodes=$(length(nodes)) edges=$edges registers=$registers"]
    for node in nodes
        neighbors = allocation.neighbors[node]
        push!(lines,"$node degree=$(length(neighbors)) cost=$(allocation.costs[node]) neighbors=$(comma_list(sort(collect(neighbors))))")
    end
    push!(lines,"simplify: " * comma_list(allocation.order))
    push!(lines,"potential spills: " * comma_list(["$node($(allocation.costs[node])/$degree)" for (node,degree) in allocation.potential]))
    for node in nodes
        color = allocation.colors[node]
        push!(lines,"$node -> " * (color < 0 ? "spill" : "R$color"))
    end
    pressure = maximum([0;length.(collect(values(flow.live_before)));length.(collect(values(flow.live_after)))])
    used = length(Set(color for color in values(allocation.colors) if color >= 0))
    spills = allocation.spills
    spill_uses = sum((count(variable->variable in spills,used_variables(entry)) for entry in instructions(function_node));init=0)
    spill_defs = count(entry->entry.destination in spills,instructions(function_node))+count(parameter->parameter in spills,function_node.parameters)
    push!(lines,"summary: pressure=$pressure used=$used spilled=$(length(spills)) moves=$moves spill_uses=$spill_uses spill_defs=$spill_defs")
    append!(lines,function_lines(allocated))
    allocated,lines
end
struct ExecutableTACFunction
    parameters::Vector{String}
    instructions::Vector{TACInstruction}
    labels::Dict{String,Int}
end
mutable struct TACInterpreter
    functions::Dict{String,ExecutableTACFunction}
    arrays::Dict{String,Vector{Int}}
    inputs::Vector{Int}
    input_position::Int
    output::Vector{Int}
    steps::Dict{String,Int}
    calls::Dict{String,Int}
    kinds::Dict{String,Int}
end
function TACInterpreter(program,inputs)
    functions = Dict{String,ExecutableTACFunction}()
    for function_node in program.functions
        labels,code = Dict{String,Int}(),TACInstruction[]
        for line in function_node.code
            line isa String ? (labels[line] = length(code)+1) : push!(code,line)
        end
        functions[function_node.name] = ExecutableTACFunction(function_node.parameters,code,labels)
    end
    TACInterpreter(functions,Dict(name=>zeros(Int,size) for (name,size) in program.arrays),inputs,1,Int[],
        Dict(name=>0 for name in keys(functions)),Dict(name=>0 for name in keys(functions)),Dict(kind=>0 for kind in KINDS))
end
value_of(operand,variables) = operand isa String ? variables[operand] : operand
function call_tac!(interpreter,name,arguments)
    function_node = interpreter.functions[name]
    variables = Dict{String,Int}(zip(function_node.parameters,arguments))
    pushed,position = Int[],1
    interpreter.calls[name] += 1
    while true
        entry = function_node.instructions[position]
        position += 1
        interpreter.steps[name] += 1
        interpreter.kinds[entry.kind] += 1
        kind = entry.kind
        if kind == "copy"
            variables[entry.destination] = value_of(entry.a,variables)
        elseif kind == "bin"
            variables[entry.destination] = calculate(entry.operation,value_of(entry.a,variables),value_of(entry.b,variables))
        elseif kind == "load"
            variables[entry.destination] = interpreter.arrays[entry.name][value_of(entry.a,variables)+1]
        elseif kind == "store"
            interpreter.arrays[entry.name][value_of(entry.a,variables)+1] = value_of(entry.b,variables)
        elseif kind == "goto"
            position = function_node.labels[entry.name]
        elseif kind == "if"
            calculate(entry.operation,value_of(entry.a,variables),value_of(entry.b,variables)) != 0 && (position = function_node.labels[entry.name])
        elseif kind == "param"
            push!(pushed,value_of(entry.a,variables))
        elseif kind == "call"
            arguments = entry.count == 0 ? Int[] : pushed[end-entry.count+1:end]
            entry.count != 0 && resize!(pushed,length(pushed)-entry.count)
            result = call_tac!(interpreter,entry.name,arguments)
            entry.destination !== nothing && (variables[entry.destination] = result)
        elseif kind == "return"
            return value_of(entry.a,variables)
        elseif kind == "read"
            variables[entry.destination] = interpreter.inputs[interpreter.input_position]
            interpreter.input_position += 1
        else
            push!(interpreter.output,value_of(entry.a,variables))
        end
    end
end
function static_kinds(program)
    counts = Dict(kind=>0 for kind in KINDS)
    for function_node in program.functions,entry in instructions(function_node)
        counts[entry.kind] += 1
    end
    counts
end
function comparison_report(original,optimized,allocated,runs)
    programs = [original,optimized,allocated]
    profiles = Dict(version=>Dict(function_node.name=>0 for function_node in original.functions) for version in VERSIONS)
    dynamic = Dict(version=>Dict(kind=>0 for kind in KINDS) for version in VERSIONS)
    total_steps = Dict(version=>0 for version in VERSIONS)
    original_calls = Dict(function_node.name=>0 for function_node in original.functions)
    lines,same = String[],0
    for (run_number,inputs) in enumerate(runs)
        push!(lines,"run $run_number: inputs=$(length(inputs))")
        outputs = Vector{Int}[]
        for (version,program) in zip(VERSIONS,programs)
            interpreter = TACInterpreter(program,inputs)
            call_tac!(interpreter,"main",Int[])
            steps,calls = sum(values(interpreter.steps);init=0),sum(values(interpreter.calls);init=0)
            push!(lines,"  $version: steps=$steps calls=$calls output=$(comma_list(interpreter.output))")
            for (name,count) in interpreter.steps
                profiles[version][name] += count
            end
            for kind in KINDS
                dynamic[version][kind] += interpreter.kinds[kind]
            end
            total_steps[version] += steps
            if version == "original"
                for (name,count) in interpreter.calls
                    original_calls[name] += count
                end
            end
            push!(outputs,interpreter.output)
        end
        equal = outputs[1] == outputs[2] == outputs[3]
        same += Int(equal)
        push!(lines,"  result: " * (equal ? "same" : "different"))
    end
    push!(lines,"== profile ==")
    for function_node in original.functions
        name = function_node.name
        push!(lines,"$name: calls=$(original_calls[name]) original=$(profiles["original"][name]) optimized=$(profiles["optimized"][name]) allocated=$(profiles["allocated"][name])")
    end
    original_kinds,optimized_kinds = static_kinds(original),static_kinds(optimized)
    push!(lines,"== summary ==","runs=$(length(runs)) same=$same different=$(length(runs)-same)")
    push!(lines,"instructions: original=$(sum(values(original_kinds))) optimized=$(sum(values(optimized_kinds)))")
    push!(lines,"kinds: " * join(("$kind=$(original_kinds[kind])->$(optimized_kinds[kind])" for kind in KINDS)," "))
    push!(lines,"steps: " * join(("$version=$(total_steps[version])" for version in VERSIONS)," "))
    for version in VERSIONS
        push!(lines,"dynamic $version: " * join(("$kind=$(dynamic[version][kind])" for kind in KINDS)," "))
    end
    lines
end
function main()
    registers,enabled,maximum_rounds = read_settings()
    runs = read_runs()
    original = read_program("input/program.tac")
    analysis,_ = call_graph_lines(original,"original")
    for function_node in original.functions
        append!(analysis,function_analysis(function_node,"original"))
    end
    working = TACProgram(copy(original.arrays),[TACFunction(f.name,copy(f.parameters),copy(f.code)) for f in original.functions])
    pass_lines,totals = String[],Dict(name=>0 for name in enabled)
    for function_node in working.functions
        append!(pass_lines,optimize_function!(function_node,enabled,maximum_rounds,totals))
    end
    graph_lines,reachable = call_graph_lines(working,"optimized")
    append!(analysis,graph_lines)
    removed = [f.name for f in working.functions if "unreachable" in enabled && !(f.name in reachable)]
    optimized = TACProgram(working.arrays,filter(f->!(f.name in removed),working.functions))
    append!(pass_lines,["== program ==","removed functions: " * comma_list(removed),"== total ==",join(("$name=$(totals[name])" for name in enabled)," ")])
    allocated_functions,allocation_lines = TACFunction[],String[]
    for function_node in optimized.functions
        append!(analysis,function_analysis(function_node,"optimized"))
        allocated_function,lines = allocation_report(function_node,registers)
        push!(allocated_functions,allocated_function)
        append!(allocation_lines,lines)
    end
    allocated = TACProgram(optimized.arrays,allocated_functions)
    reports = (("optimized.tac",program_lines(optimized)),("analysis.txt",analysis),("passes.txt",pass_lines),
        ("regalloc.txt",allocation_lines),("comparison.txt",comparison_report(original,optimized,allocated,runs)))
    for (filename,lines) in reports
        write(joinpath("output",filename),join(lines,"\n") * "\n")
    end
end
main()
