include("lexer.jl")
include("parser.jl")
include("values_fields.jl")
include("builtins.jl")
include("streams.jl")

const SPECIAL_NAMES = Set(["FILENAME","FNR","FS","NF","NR","OFS","ORS","SUBSEP"])
const AwkBinding = Tuple{Int,String}

struct StaticIssue <: Exception
    position::Tuple{Int,Int}
    message::String
end
struct Transfer <: Exception
    kind::String
    value::AwkValue
end
Transfer(kind) = Transfer(kind,UNINITIALIZED)

mutable struct AwkAnalysis
    items::Vector{AwkNode}
    functions::Vector{AwkNode}
    rules::Vector{AwkNode}
    function_table::Dict{String,AwkNode}
    global_names::Set{String}
    bindings::Set{AwkBinding}
    array_names::Set{AwkBinding}
    statement_lines::Set{Int}
    nodes::Vector{AwkNode}
    errors::Vector{Tuple{Int,Int,Int,String}}
end
function AwkAnalysis(items)
    AwkAnalysis(items,filter(item->item.kind == "function",items),filter(item->item.kind == "rule",items),
        Dict{String,AwkNode}(),copy(SPECIAL_NAMES),Set{AwkBinding}((0,name) for name in SPECIAL_NAMES),
        Set{AwkBinding}(),Set{Int}(),AwkNode[],Tuple{Int,Int,Int,String}[])
end
function static_error!(analysis,position,priority,message)
    push!(analysis.errors,(position[1],position[2],priority,message))
end
function resolve_name!(analysis,node,function_node)
    local_name = function_node !== nothing && node.name in function_node.parameter_names
    node.binding = (local_name ? function_node.function_id : 0,node.name)
    push!(analysis.bindings,node.binding)
    !local_name && push!(analysis.global_names,node.name)
    haskey(analysis.function_table,node.name) && static_error!(analysis,node.position,3,"function $(node.name) used as variable")
end
function prepare!(analysis)
    for (identifier,function_node) in enumerate(analysis.functions)
        function_node.function_id = identifier
        if haskey(analysis.function_table,function_node.name)
            static_error!(analysis,function_node.name_position,1,"function $(function_node.name) redefined")
        else
            analysis.function_table[function_node.name] = function_node
        end
        names = Set{String}()
        function_node.parameter_names = names
        for parameter in function_node.parameters
            parameter.name in names && static_error!(analysis,parameter.position,2,"duplicate parameter $(parameter.name)")
            push!(names,parameter.name)
        end
    end
    for item in analysis.items
        function_node = item.kind == "function" ? item : nothing
        pending = [item]
        while !isempty(pending)
            node = pop!(pending)
            push!(analysis.nodes,node)
            node.kind in STATEMENTS && push!(analysis.statement_lines,node.position[1])
            if node.kind in ("name","array","parameter")
                resolve_name!(analysis,node,function_node)
            elseif node.kind == "call"
                target = get(analysis.function_table,node.name,nothing)
                if target === nothing
                    static_error!(analysis,node.position,4,"undefined function $(node.name)")
                else
                    node.target_function = target
                    length(node.arguments) > length(target.parameters) && static_error!(analysis,node.position,5,"too many arguments to $(node.name)")
                end
            end
            append!(pending,reverse(node.children))
        end
    end
    if !isempty(analysis.errors)
        line,column,_,message = minimum(analysis.errors)
        throw(StaticIssue((line,column),message))
    end
    links = Tuple{AwkBinding,AwkBinding}[]
    for node in analysis.nodes
        if node.kind == "array"
            push!(analysis.array_names,node.binding)
        elseif node.kind in ("membership","delete","for_in")
            push!(analysis.array_names,node.array.binding)
        elseif node.kind == "builtin" && node.name == "split"
            push!(analysis.array_names,node.arguments[2].binding)
        elseif node.kind == "call"
            for (argument,parameter) in zip(node.arguments,node.target_function.parameters)
                argument.kind == "name" && push!(links,(argument.binding,parameter.binding))
            end
        end
    end
    changed = true
    while changed
        previous = length(analysis.array_names)
        for (first,second) in links
            if first in analysis.array_names || second in analysis.array_names
                push!(analysis.array_names,first,second)
            end
        end
        changed = length(analysis.array_names) != previous
    end
    analysis
end
function arithmetic(operator,first,second,position)
    a,b = to_number(first),to_number(second)
    if operator in ("/","%")
        b == 0 && throw(RuntimeIssue(position,"division by zero"))
        quotient = div(a,b)
        result = operator == "/" ? quotient : a-quotient*b
    elseif operator == "^"
        b < 0 && throw(RuntimeIssue(position,"negative exponent"))
        result = a^b
    elseif operator == "+"
        result = a+b
    elseif operator == "-"
        result = a-b
    else
        result = a*b
    end
    number(result)
end

Base.@kwdef struct AwkLocation
    kind::Symbol
    binding::AwkBinding = (0,"")
    array::Union{Nothing,AwkArray} = nothing
    key::String = ""
    index::Int = 0
end
Base.@kwdef mutable struct AwkEngine
    analysis::AwkAnalysis
    options::Vector{Tuple{String,String}}
    operands::Vector{AwkOperand}
    globals::Dict{String,AwkVariable}
    global_names::Set{String}
    local_frames::Vector{Dict{String,AwkVariable}} = Dict{String,AwkVariable}[]
    record::AwkRecord
    streams::AwkStreams = AwkStreams()
    lines::Dict{Int,Int}
    phase::String = "BEGIN"
    exit_status::Int = 0
    error::Union{Nothing,RuntimeIssue} = nothing
    operand_position::Int = 1
    current_operand::Union{Nothing,AwkOperand} = nothing
    input_lines::Vector{String} = String[]
    input_position::Int = 1
end
function AwkEngine(analysis,options,operands)
    globals = Dict{String,AwkVariable}(name=>((0,name) in analysis.array_names ? AwkArray() : UNINITIALIZED) for name in analysis.global_names)
    merge!(globals,Dict("FILENAME"=>string_value(""),"FNR"=>number(0),"FS"=>string_value(" "),"NF"=>number(0),
        "NR"=>number(0),"OFS"=>string_value(" "),"ORS"=>string_value("\n"),"SUBSEP"=>string_value(string(Char(28)))))
    for rule in analysis.rules
        rule.count,rule.inside = 0,false
    end
    for function_node in analysis.functions
        function_node.call_count,function_node.active_calls,function_node.max_depth = 0,0,0
    end
    AwkEngine(analysis=analysis,options=options,operands=operands,globals=globals,
        global_names=copy(analysis.global_names),record=AwkRecord(name->globals[name]),
        lines=Dict{Int,Int}(line=>0 for line in analysis.statement_lines))
end
function variable(engine,binding)
    scope,name = binding
    scope != 0 && return engine.local_frames[end][name]
    name == "NF" ? number(length(engine.record.fields)) : engine.globals[name]
end
global_value(engine,name) = variable(engine,(0,name))
function assign_global_input!(engine,name,text)
    push!(engine.global_names,name)
    engine.globals[name] = input_value(text)
end
function subscript(engine,expressions)
    values = String[]
    for expression in expressions
        push!(values,to_string(evaluate(engine,expression)))
    end
    join(values,to_string(global_value(engine,"SUBSEP")))
end
function location(engine,node)
    node.kind == "name" && return AwkLocation(kind=:variable,binding=node.binding)
    if node.kind == "array"
        key = subscript(engine,node.indexes)
        return AwkLocation(kind=:array,array=variable(engine,node.binding),key=key)
    end
    index = to_number(evaluate(engine,node.index))
    index < 0 && throw(RuntimeIssue(node.position,"negative field index"))
    AwkLocation(kind=:field,index=index)
end
function read_location(engine,place)
    place.kind == :variable && return variable(engine,place.binding)
    place.kind == :field && return read_field(engine.record,place.index)
    get!(place.array,place.key,UNINITIALIZED)
end
function store!(engine,place,value,position)
    if place.kind == :field
        write_field!(engine.record,place.index,value)
    elseif place.kind == :array
        place.array[place.key] = value
    else
        scope,name = place.binding
        if scope != 0
            engine.local_frames[end][name] = value
        elseif name == "NF"
            size = to_number(value)
            size < 0 && throw(RuntimeIssue(position,"negative NF"))
            resize_fields!(engine.record,size)
        else
            engine.globals[name] = value
        end
    end
end
function evaluate(engine,node)
    kind = node.kind
    kind == "number" && return number(node.value)
    kind == "string" && return string_value(node.value)
    kind in LVALUE_KINDS && return read_location(engine,location(engine,node))
    kind == "paren" && return evaluate(engine,node.expression)
    if kind == "assignment"
        place = location(engine,node.location)
        value = evaluate(engine,node.value)
        node.operator != "=" && (value = arithmetic(node.operator[1:end-1],read_location(engine,place),value,node.position))
        store!(engine,place,value,node.position)
        return read_location(engine,place)
    elseif kind == "increment"
        place = location(engine,node.location)
        old = to_number(read_location(engine,place))
        value = old+node.delta
        store!(engine,place,number(value),node.position)
        return number(node.prefix ? value : old)
    elseif kind == "conditional"
        return evaluate(engine,truth(evaluate(engine,node.condition)) ? node.first : node.second)
    elseif kind == "unary"
        value = evaluate(engine,node.operand)
        node.operator == "!" && return number(!truth(value))
        integer = to_number(value)
        return number(node.operator == "-" ? -integer : integer)
    elseif kind == "membership"
        key = subscript(engine,node.indexes)
        return number(haskey(variable(engine,node.array.binding),key))
    elseif kind == "binary"
        first = evaluate(engine,node.left)
        operator = node.operator
        operator == "||" && truth(first) && return number(1)
        operator == "&&" && !truth(first) && return number(0)
        second = evaluate(engine,node.right)
        operator in ("&&","||") && return number(truth(second))
        operator == "concat" && return string_value(to_string(first) * to_string(second))
        if operator in COMPARISONS
            order = compare_values(first,second)
            result = operator == "<" ? order < 0 : operator == "<=" ? order <= 0 : operator == "==" ? order == 0 : operator == "!=" ? order != 0 : operator == ">=" ? order >= 0 : order > 0
            return number(result)
        end
        return arithmetic(operator,first,second,node.position)
    elseif kind == "call"
        return call_function(engine,node)
    elseif kind == "builtin"
        return evaluate_builtin(engine,node)
    end
    evaluate_getline(engine,node)
end
function call_function(engine,node)
    function_node = node.target_function
    frame = Dict{String,AwkVariable}()
    for (index,parameter) in enumerate(function_node.parameters)
        is_array = parameter.binding in engine.analysis.array_names
        if index <= length(node.arguments)
            argument = node.arguments[index]
            value = is_array ? variable(engine,argument.binding) : evaluate(engine,argument)
        else
            value = is_array ? AwkArray() : UNINITIALIZED
        end
        frame[parameter.name] = value
    end
    function_node.call_count += 1
    function_node.active_calls += 1
    function_node.max_depth = max(function_node.max_depth,function_node.active_calls)
    push!(engine.local_frames,frame)
    try
        execute_statement!(engine,function_node.body)
    catch transfer
        transfer isa Transfer && transfer.kind == "return" && return transfer.value
        rethrow()
    finally
        pop!(engine.local_frames)
        function_node.active_calls -= 1
    end
    UNINITIALIZED
end
function evaluate_builtin(engine,node)
    name,arguments = node.name,node.arguments
    if name == "length"
        isempty(arguments) && return number(length(to_string(engine.record.zero)))
        argument = arguments[1]
        argument.kind == "name" && argument.binding in engine.analysis.array_names && return number(length(variable(engine,argument.binding)))
        return number(length(to_string(evaluate(engine,argument))))
    elseif name == "split"
        text = to_string(evaluate(engine,arguments[1]))
        separator = length(arguments) == 3 ? to_string(evaluate(engine,arguments[3])) : to_string(global_value(engine,"FS"))
        array = variable(engine,arguments[2].binding)
        empty!(array)
        pieces = split_pieces(text,separator)
        for (index,piece) in enumerate(pieces)
            array[string(index)] = input_value(piece)
        end
        return number(length(pieces))
    elseif name == "close"
        filename = to_string(evaluate(engine,arguments[1]))
        return number(close_streams!(engine.streams,filename))
    end
    values = AwkValue[evaluate(engine,argument) for argument in arguments]
    invoke_builtin(name,values,node.position)
end
function evaluate_getline(engine,node)
    if node.filename !== nothing
        filename = to_string(evaluate(engine,node.filename))
        status,line = getline_input!(engine.streams,filename)
    elseif engine.phase == "END"
        return number(0)
    else
        line = next_record!(engine)
        status = line === nothing ? 0 : 1
    end
    if status == 1
        if node.target === nothing
            set_record!(engine.record,line)
        else
            place = location(engine,node.target)
            store!(engine,place,input_value(line),node.position)
        end
    end
    number(status)
end
function execute_output!(engine,node)
    arguments = AwkValue[evaluate(engine,argument) for argument in node.arguments]
    if node.kind == "print"
        isempty(arguments) && push!(arguments,engine.record.zero)
        text = join(to_string.(arguments),to_string(global_value(engine,"OFS"))) * to_string(global_value(engine,"ORS"))
    else
        text = format_output(arguments,node.position)
    end
    filename = node.filename === nothing ? nothing : to_string(evaluate(engine,node.filename))
    write_output!(engine.streams,text,filename,node.redirect,node.redirect_position)
end
function execute_loop_body!(engine,body)
    try
        execute_statement!(engine,body)
    catch transfer
        transfer isa Transfer || rethrow()
        transfer.kind == "break" && return false
        transfer.kind == "continue" || rethrow()
    end
    true
end
function execute_statement!(engine,node)
    kind = node.kind
    if kind == "block"
        for child in node.statements
            execute_statement!(engine,child)
        end
        return
    end
    kind == "empty" && return
    engine.lines[node.position[1]] += 1
    if kind == "expression_statement"
        evaluate(engine,node.expression)
    elseif kind in ("print","printf")
        execute_output!(engine,node)
    elseif kind == "if"
        branch = truth(evaluate(engine,node.condition)) ? node.first : node.second
        branch !== nothing && execute_statement!(engine,branch)
    elseif kind == "while"
        while truth(evaluate(engine,node.condition))
            execute_loop_body!(engine,node.body) || break
        end
    elseif kind == "do"
        while true
            execute_loop_body!(engine,node.body) || break
            truth(evaluate(engine,node.condition)) || break
        end
    elseif kind == "for"
        node.initial !== nothing && evaluate(engine,node.initial)
        while node.condition === nothing || truth(evaluate(engine,node.condition))
            execute_loop_body!(engine,node.body) || break
            node.update !== nothing && evaluate(engine,node.update)
        end
    elseif kind == "for_in"
        subscripts = sort(collect(keys(variable(engine,node.array.binding)));by=subscript_order)
        for key in subscripts
            store!(engine,AwkLocation(kind=:variable,binding=node.variable.binding),input_value(key),node.variable.position)
            execute_loop_body!(engine,node.body) || break
        end
    elseif kind == "delete"
        array = variable(engine,node.array.binding)
        if node.indexes === nothing
            empty!(array)
        else
            key = subscript(engine,node.indexes)
            pop!(array,key,nothing)
        end
    elseif kind == "next"
        engine.phase in ("BEGIN","END") && throw(RuntimeIssue(node.position,"next used in BEGIN or END"))
        throw(Transfer("next"))
    elseif kind == "exit"
        node.value !== nothing && (engine.exit_status = to_number(evaluate(engine,node.value)))
        throw(Transfer("exit"))
    elseif kind == "return"
        throw(Transfer("return",node.value === nothing ? UNINITIALIZED : evaluate(engine,node.value)))
    else
        throw(Transfer(kind))
    end
end
function next_record!(engine)
    while true
        if engine.input_position <= length(engine.input_lines)
            line = engine.input_lines[engine.input_position]
            engine.input_position += 1
            engine.current_operand.records += 1
            engine.globals["NR"] = number(to_number(global_value(engine,"NR"))+1)
            engine.globals["FNR"] = number(to_number(global_value(engine,"FNR"))+1)
            return line
        end
        engine.operand_position > length(engine.operands) && return nothing
        operand = engine.operands[engine.operand_position]
        engine.operand_position += 1
        if operand.kind == "assignment"
            assign_global_input!(engine,operand.name,operand.value)
        else
            engine.current_operand = operand
            engine.input_lines = read_records(operand.name)
            engine.input_position = 1
            engine.globals["FILENAME"] = string_value(operand.name)
            engine.globals["FNR"] = number(0)
        end
    end
end
function run_actions!(engine,phase)
    engine.phase = phase
    for rule in engine.analysis.rules
        if rule.flavor == phase
            rule.count += 1
            execute_statement!(engine,rule.action)
        end
    end
end
function rule_matches(engine,rule)
    rule.flavor == "all" && return true
    rule.flavor == "pattern" && return truth(evaluate(engine,rule.patterns[1]))
    !rule.inside && truth(evaluate(engine,rule.patterns[1])) && (rule.inside = true)
    rule.inside || return false
    truth(evaluate(engine,rule.patterns[2])) && (rule.inside = false)
    true
end
function run_records!(engine)
    any(rule->rule.flavor != "BEGIN",engine.analysis.rules) || return
    engine.phase = "records"
    rules = filter(rule->!(rule.flavor in ("BEGIN","END")),engine.analysis.rules)
    while true
        line = next_record!(engine)
        line === nothing && return
        set_record!(engine.record,line)
        try
            for rule in rules
                if rule_matches(engine,rule)
                    rule.count += 1
                    if rule.action === nothing
                        write_output!(engine.streams,to_string(engine.record.zero) * to_string(global_value(engine,"ORS")))
                    else
                        execute_statement!(engine,rule.action)
                    end
                end
            end
        catch transfer
            transfer isa Transfer && transfer.kind == "next" || rethrow()
        end
    end
end
function execute!(engine)
    try
        for (name,text) in engine.options
            assign_global_input!(engine,name,text)
        end
        try
            run_actions!(engine,"BEGIN")
            run_records!(engine)
        catch transfer
            transfer isa Transfer && transfer.kind == "exit" || rethrow()
        end
        try
            run_actions!(engine,"END")
        catch transfer
            transfer isa Transfer && transfer.kind == "exit" || rethrow()
        end
    catch error
        error isa RuntimeIssue || rethrow()
        engine.error = error
    end
end
function statistics(engine)
    if engine.error === nothing
        status = "status: exit $(engine.exit_status)"
    else
        line,column = engine.error.position
        status = "status: runtime error at $line:$column: $(engine.error.message)"
    end
    lines = [status,"[inputs]"]
    for operand in engine.operands
        operand.kind == "file" && push!(lines,"$(operand.name) records=$(operand.records)")
    end
    push!(lines,"[getline]")
    for name in engine.streams.input_order
        source = engine.streams.inputs[name]
        push!(lines,name * " " * (source.ever_opened ? "reads=$(source.reads)" : "missing"))
    end
    push!(lines,"[rules]")
    for rule in engine.analysis.rules
        line,column = rule.position
        push!(lines,"$line:$column $(rule.flavor) count=$(rule.count)")
    end
    push!(lines,"[functions]")
    for function_node in engine.analysis.functions
        push!(lines,"$(function_node.name) calls=$(function_node.call_count) depth=$(function_node.max_depth)")
    end
    push!(lines,"[outputs]")
    stdout = engine.streams.stdout
    push!(lines,"stdout.txt writes=$(stdout.writes) bytes=$(length(content(stdout)))")
    for name in engine.streams.output_order
        output = engine.streams.outputs[name]
        push!(lines,"$name writes=$(output.writes) bytes=$(length(content(output)))")
    end
    push!(lines,"[lines]")
    for line in sort(collect(keys(engine.lines)))
        push!(lines,"$line count=$(engine.lines[line])")
    end
    push!(lines,"[globals]")
    for name in sort(collect(engine.global_names))
        value = global_value(engine,name)
        text = (0,name) in engine.analysis.array_names ? "array ($(length(value)))" : describe_value(value)
        push!(lines,"$name = $text")
    end
    lines
end
function main()
    options,operands = parse_arguments(readlines("input/args.txt"))
    source = read("input/program.awk",String)
    try
        items = parse_program!(AwkParser(tokenize(source)))
        analysis = prepare!(AwkAnalysis(items))
        engine = AwkEngine(analysis,options,operands)
        execute!(engine)
        lines,streams = statistics(engine),engine.streams
    catch error
        if error isa SyntaxIssue
            line,column = error.position
            lines = ["status: syntax error at $line:$column"]
        elseif error isa StaticIssue
            line,column = error.position
            lines = ["status: error at $line:$column: $(error.message)"]
        else
            rethrow()
        end
        streams = AwkStreams()
    end
    save_streams(streams)
    write("output/stats.txt",join(lines,"\n") * "\n")
end
main()
