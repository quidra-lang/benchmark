include("lexer.jl")
include("parser.jl")
include("semantic.jl")
include("codegen.jl")
include("vm.jl")
const RULES = ["const-jump","not-compare","not-jump","invert-branch","thread","jump-next","unreachable"]
const PUSHING = Set(["PUSH","LOADG","LOADL","READ"])
const POPPING = Set(["POP","STOREG","STOREL","JUMPF","JUMPT","RETV","ADD","SUB","MUL","DIV","MOD","LT","LE","GT","GE","EQ","NE"])
const REPORTS = ["listing.txt","output.txt","diagnostics.txt","stats.txt"]
mutable struct ToyProgram
    name::String
    lines::Vector{Tuple{Int,String}}
    inputs::Vector{Int64}
    error::Union{Nothing,CompileError}
    warnings::Vector{Tuple{ToyPosition,String}}
    folds::Int
    peephole::Vector{Int}
    fields::Dict{Symbol,Any}
end
ToyProgram(name) = ToyProgram(name,Tuple{Int,String}[],Int64[],nothing,Tuple{ToyPosition,String}[],0,zeros(Int,length(RULES)),Dict{Symbol,Any}())
const PROGRAM_FIELDS = (:name,:lines,:inputs,:error,:warnings,:folds,:peephole,:fields)
function Base.getproperty(program::ToyProgram,name::Symbol)
    name in PROGRAM_FIELDS ? getfield(program,name) : getfield(program,:fields)[name]
end
function Base.setproperty!(program::ToyProgram,name::Symbol,value)
    name in PROGRAM_FIELDS ? setfield!(program,name,value) : (getfield(program,:fields)[name] = value)
end
function collect_warnings(analysis)
    warnings = Tuple{ToyPosition,String}[]
    for variable in analysis.variables
        if variable.read_accesses == 0
            role = variable.kind == "parameter" ? "parameter" : "variable"
            push!(warnings,(variable.name_position,"unused $role '$(variable.name)'"))
        end
    end
    for function_node in analysis.functions
        pending = [function_node.body]
        while !isempty(pending)
            statement = pop!(pending)
            if statement.kind == "block"
                for index in 1:length(statement.statements)-1
                    if !can_complete(statement.statements[index])
                        push!(warnings,(statement.statements[index+1].position,"unreachable statement"))
                        break
                    end
                end
            end
            append!(pending,statement_children(statement))
        end
    end
    reachable,pending = Set{ToyNode}(),[analysis.globals["main"]]
    while !isempty(pending)
        function_node = pop!(pending)
        if !(function_node in reachable)
            push!(reachable,function_node)
            append!(pending,collect(function_node.calls))
        end
    end
    for function_node in analysis.functions
        function_node in reachable || push!(warnings,(function_node.name_position,"function '$(function_node.name)' is never called"))
    end
    sort!(warnings;by=first)
    warnings,reachable
end
function is_recursive(function_node)
    visited,pending = Set{ToyNode}(),collect(function_node.calls)
    while !isempty(pending)
        current = pop!(pending)
        current === function_node && return true
        if !(current in visited)
            push!(visited,current)
            append!(pending,collect(current.calls))
        end
    end
    false
end
literal_value(node,kind,value) = node.kind == kind && node.value == value
mutable struct Folder
    count::Int
end
Folder() = Folder(0)
function folded_literal!(folder,node,value)
    folder.count += 1
    kind = node.type == "bool" ? "boolean" : "integer"
    toy_node(kind,node.position;value=kind == "boolean" ? Bool(value) : Int64(value),type=node.type)
end
function folded_identity!(folder,expression)
    folder.count += 1
    expression
end
function fold_expression!(folder,node)
    if node.kind == "unary"
        node.operand = fold_expression!(folder,node.operand)
        if node.operand.kind in ("integer","boolean")
            try
                return folded_literal!(folder,node,calculate(node.operator == "-" ? "NEG" : "NOT",Int64(node.operand.value)))
            catch error
                error isa RuntimeFault || rethrow()
            end
        end
    elseif node.kind == "binary"
        node.left = fold_expression!(folder,node.left)
        node.right = fold_expression!(folder,node.right)
        left,right,operator = node.left,node.right,node.operator
        if left.kind in ("integer","boolean") && right.kind in ("integer","boolean")
            a,b = Int64(left.value),Int64(right.value)
            try
                value = operator == "&&" ? a != 0 && b != 0 : operator == "||" ? a != 0 || b != 0 : calculate(BINARY[operator],a,b)
                return folded_literal!(folder,node,value)
            catch error
                error isa RuntimeFault || rethrow()
            end
        end
        operator == "&&" && literal_value(left,"boolean",false) && return folded_literal!(folder,node,false)
        operator == "||" && literal_value(left,"boolean",true) && return folded_literal!(folder,node,true)
        operator == "&&" && literal_value(left,"boolean",true) && return folded_identity!(folder,right)
        operator == "||" && literal_value(left,"boolean",false) && return folded_identity!(folder,right)
        operator == "+" && literal_value(left,"integer",0) && return folded_identity!(folder,right)
        operator == "*" && literal_value(left,"integer",1) && return folded_identity!(folder,right)
        operator in ("+","-") && literal_value(right,"integer",0) && return folded_identity!(folder,left)
        operator in ("*","/") && literal_value(right,"integer",1) && return folded_identity!(folder,left)
        operator == "&&" && literal_value(right,"boolean",true) && return folded_identity!(folder,left)
        operator == "||" && literal_value(right,"boolean",false) && return folded_identity!(folder,left)
    elseif node.kind == "array"
        node.index = fold_expression!(folder,node.index)
    elseif node.kind == "call"
        node.arguments = [fold_expression!(folder,argument) for argument in node.arguments]
    end
    node
end
function fold_statement!(folder,node)
    kind = node.kind
    if kind == "declaration"
        node.initializer === nothing || (node.initializer = fold_expression!(folder,node.initializer))
    elseif kind == "assignment"
        node.index === nothing || (node.index = fold_expression!(folder,node.index))
        node.value = fold_expression!(folder,node.value)
    elseif kind == "call_statement"
        node.expression = fold_expression!(folder,node.expression)
    elseif kind == "print"
        node.arguments = [fold_expression!(folder,argument) for argument in node.arguments]
    elseif kind == "return"
        node.value === nothing || (node.value = fold_expression!(folder,node.value))
    elseif kind == "block"
        node.statements = [fold_statement!(folder,child) for child in node.statements]
    elseif kind == "if"
        node.condition = fold_expression!(folder,node.condition)
        if node.condition.kind == "boolean"
            selected = node.condition.value ? node.then : node.otherwise
            replacement = selected === nothing ? toy_node("empty",node.position) : fold_statement!(folder,selected)
            folder.count += 1
            return replacement
        end
        node.then = fold_statement!(folder,node.then)
        node.otherwise === nothing || (node.otherwise = fold_statement!(folder,node.otherwise))
    elseif kind == "while"
        node.condition = fold_expression!(folder,node.condition)
        if literal_value(node.condition,"boolean",false)
            folder.count += 1
            return toy_node("empty",node.position)
        end
        node.body = fold_statement!(folder,node.body)
    elseif kind == "for"
        node.initial === nothing || (node.initial = fold_statement!(folder,node.initial))
        node.condition === nothing || (node.condition = fold_expression!(folder,node.condition))
        node.update === nothing || (node.update = fold_statement!(folder,node.update))
        node.body = fold_statement!(folder,node.body)
    end
    node
end
jumps_on(op,value) = (value == 0) == (op == "JUMPF")
function delete_instruction!(code,index)
    deleteat!(code,index+1)
    for (position,entry) in enumerate(code)
        if entry.op in JUMPS && entry.args[1] > index
            code[position] = instruction(entry.op,entry.position,entry.args[1]-1)
        end
    end
end
function rewrite_at!(code,index,targets)
    first = code[index+1]
    second = index+1 < length(code) ? code[index+2] : nothing
    free = second !== nothing && !(index+1 in targets)
    if free && first.op == "PUSH" && second.op in CONDITIONAL
        if jumps_on(second.op,first.args[1])
            code[index+1] = instruction("JUMP",second.position,second.args...)
            delete_instruction!(code,index+1)
        else
            delete_instruction!(code,index+1)
            delete_instruction!(code,index)
        end
        return 1
    elseif free && haskey(NEGATED,first.op) && second.op == "NOT"
        code[index+1] = instruction(NEGATED[first.op],first.position,first.args...)
        delete_instruction!(code,index+1)
        return 2
    elseif free && first.op == "NOT" && second.op in CONDITIONAL
        code[index+1] = instruction(INVERSE[second.op],second.position,second.args...)
        delete_instruction!(code,index+1)
        return 3
    elseif free && first.op in CONDITIONAL && first.args[1] == index+2 && second.op == "JUMP"
        code[index+1] = instruction(INVERSE[first.op],first.position,second.args...)
        delete_instruction!(code,index+1)
        return 4
    end
    if first.op in JUMPS
        target = first.args[1]
        if target < length(code)
            destination = code[target+1]
            new_target = nothing
            if destination.op == "JUMP"
                new_target = destination.args[1]
            elseif destination.op == "PUSH" && target+1 < length(code)
                following = code[target+2]
                following.op in CONDITIONAL && (new_target = jumps_on(following.op,destination.args[1]) ? following.args[1] : target+2)
            end
            if new_target !== nothing && new_target != target
                code[index+1] = instruction(first.op,first.position,new_target)
                return 5
            end
        end
        if target == index+1
            if first.op == "JUMP"
                delete_instruction!(code,index)
            else
                code[index+1] = instruction("POP",first.position)
            end
            return 6
        end
    end
    if free && first.op in TRANSFERS
        delete_instruction!(code,index+1)
        return 7
    end
    0
end
function optimize(original)
    code,counts = copy(original),zeros(Int,length(RULES))
    while true
        targets = Set{Int}(entry.args[1] for entry in code if entry.op in JUMPS)
        changed = false
        for index in 0:length(code)-1
            rule = rewrite_at!(code,index,targets)
            if rule > 0
                counts[rule] += 1
                changed = true
                break
            end
        end
        changed || return code,counts
    end
end
function successors(code,index)
    entry = code[index+1]
    result = Int[]
    !(entry.op in TRANSFERS) && index+1 < length(code) && push!(result,index+1)
    if entry.op in JUMPS
        target = entry.args[1]
        target < length(code) && !(target in result) && push!(result,target)
    end
    result
end
function stack_effect(entry,functions)
    entry.op in PUSHING && return 1
    entry.op in POPPING && return -1
    entry.op == "STOREA" && return -2
    entry.op == "CALL" && return -entry.args[2]+Int(functions[entry.args[1]].type != "void")
    entry.op == "PRINT" && return -entry.args[1]
    0
end
function analyze_flow!(unit,functions)
    code = unit.after
    leaders = Set([0])
    for (position,entry) in enumerate(code)
        index = position-1
        entry.op in JUMPS && entry.args[1] < length(code) && push!(leaders,entry.args[1])
        (entry.op in JUMPS || entry.op in TRANSFERS) && index+1 < length(code) && push!(leaders,index+1)
    end
    starts = sort(collect(leaders))
    block_numbers = Dict(start=>number-1 for (number,start) in enumerate(starts))
    empty!(unit.blocks)
    for (number,start) in enumerate(starts)
        last = number < length(starts) ? starts[number+1]-1 : length(code)-1
        following = [block_numbers[target] for target in successors(code,last)]
        push!(unit.blocks,(start,last,following))
    end
    depths,pending,maximum_depth = Dict(0=>0),[0],0
    while !isempty(pending)
        index = pop!(pending)
        after = depths[index]+stack_effect(code[index+1],functions)
        maximum_depth = max(maximum_depth,after)
        for target in successors(code,index)
            if !haskey(depths,target)
                depths[target] = after
                push!(pending,target)
            end
        end
    end
    unit.depth = maximum_depth
end
function link_units!(units,version)
    addresses,offset = Dict{String,Int}(),0
    for unit in units
        addresses[unit.name] = offset
        setproperty!(unit,Symbol(string(version) * "_start"),offset)
        offset += length(getproperty(unit,version))
    end
    code,owners = Instruction[],String[]
    for unit in units
        start = addresses[unit.name]
        for entry in getproperty(unit,version)
            args = entry.args
            if entry.op in JUMPS
                args = Any[start+args[1]]
            elseif entry.op == "CALL"
                args = Any[addresses[args[1]],args[2]]
            end
            push!(code,instruction(entry.op,entry.position,args...))
            push!(owners,unit.name)
        end
    end
    code,owners,Dict(address=>name for (name,address) in addresses)
end
function compile_program!(program)
    program.source_text = Dict(program.lines)
    declarations = ToyNode[]
    try
        tokens = tokenize(program.lines)
        declarations = parse_program!(ToyParser(tokens))
        program.analysis = analyze!(Analyzer(declarations,tokens[end].position))
    catch error
        error isa CompileError || rethrow()
        program.error = error
        return
    end
    program.warnings,reachable = collect_warnings(program.analysis)
    program.globals = [node for node in declarations if node.kind == "global"]
    functions = [node for node in program.analysis.functions if node in reachable]
    folder = Folder()
    for variable in program.globals
        variable.initializer === nothing || (variable.initializer = fold_expression!(folder,variable.initializer))
    end
    for function_node in functions
        function_node.body = fold_statement!(folder,function_node.body)
    end
    program.folds = folder.count
    program.units,program.global_size = generate(program.globals,functions,program.analysis.globals["main"])
    function_table = Dict{String,ToyNode}(node.name=>node for node in functions)
    for unit in program.units
        unit.after,counts = optimize(unit.before)
        program.peephole .+= counts
        analyze_flow!(unit,function_table)
        unit.recursive = unit.function_node !== nothing && is_recursive(unit.function_node)
    end
    program.before,before_owners,before_starts = link_units!(program.units,:before)
    program.after,program.owners,after_starts = link_units!(program.units,:after)
    program.execution = run_vm!(Execution(program.after,program.owners,after_starts,program.global_size,program.inputs))
    program.comparison = run_vm!(Execution(program.before,before_owners,before_starts,program.global_size,program.inputs))
end
spelling(entry) = join([entry.op;string.(entry.args)]," ")
format_position(position) = "$(position[1]):$(position[2])"
position_display(program,position) = ["  " * program.source_text[position[1]],repeat(" ",position[2]+1) * "^"]
function listing(program)
    lines = String[]
    if isempty(program.globals)
        push!(lines,"globals: none")
    else
        push!(lines,"globals:")
        for variable in program.globals
            type_name = variable.size === nothing ? variable.type : "int[$(variable.size)]"
            push!(lines,"  $(variable.address) $(variable.name) $type_name")
        end
    end
    push!(lines,"functions:")
    for unit in program.units
        signature,callees = "","main"
        if unit.function_node !== nothing
            parameter_types = join([parameter.type for parameter in unit.function_node.parameters],",")
            signature = " $(unit.function_node.type)($parameter_types)"
            names = sort([node.name for node in unit.function_node.calls])
            callees = isempty(names) ? "-" : join(names,",")
        end
        line = "  $(unit.name)$signature address=$(unit.before_start)->$(unit.after_start) size=$(length(unit.before))->$(length(unit.after)) slots=$(length(unit.slots)) stack=$(unit.depth) blocks=$(length(unit.blocks)) calls=$callees"
        unit.recursive && (line *= " recursive")
        push!(lines,line)
        for (number,slot) in enumerate(unit.slots)
            push!(lines,"    slot $(number-1) $(slot.name) $(slot.type)")
        end
    end
    push!(lines,"references:")
    for declaration in [program.globals;program.analysis.functions]
        used_lines = sort(unique([position[1] for position in declaration.references]))
        used = isempty(used_lines) ? "-" : join(used_lines," ")
        push!(lines,"  $(declaration.name) defined $(declaration.name_position[1]) used $used")
    end
    for version in (:before,:after)
        code = getproperty(program,version)
        push!(lines,"$version peephole: $(length(code)) instructions")
        for unit in program.units
            push!(lines,unit.name * ":")
            start = getproperty(unit,Symbol(string(version) * "_start"))
            for address in start:start+length(getproperty(unit,version))-1
                push!(lines,lpad(string(address),5) * "  " * spelling(code[address+1]))
            end
        end
    end
    push!(lines,"control flow:")
    for unit in program.units
        push!(lines,"  " * unit.name)
        for (number,(start,last,following)) in enumerate(unit.blocks)
            line = "    B$(number-1) $(unit.after_start+start)-$(unit.after_start+last)"
            isempty(following) || (line *= " -> " * join(["B$target" for target in following]," "))
            push!(lines,line)
        end
    end
    lines
end
function diagnostics(program)
    if program.error !== nothing
        error = program.error
        return ["$(error.kind) error $(format_position(error.position)): $(error.message)";position_display(program,error.position);"status: compile error"]
    end
    lines = ["warning $(format_position(position)): $message" for (position,message) in program.warnings]
    execution = program.execution
    if execution.error === nothing
        push!(lines,"status: ok")
        return lines
    end
    entry = program.after[execution.error_pc+1]
    owner = program.owners[execution.error_pc+1]
    push!(lines,"runtime error $(format_position(entry.position)): $(execution.error) in $owner")
    append!(lines,position_display(program,entry.position))
    callers = reverse(execution.frames[2:end])
    for frame in callers[1:min(5,length(callers))]
        address = frame.return_address-1
        push!(lines,"  called from $(program.owners[address+1]) at $(format_position(program.after[address+1].position))")
    end
    length(callers) > 5 && push!(lines,"  ... $(length(callers)-5) more")
    push!(lines,"status: runtime error")
    lines
end
function statistics(program)
    execution,comparison = program.execution,program.comparison
    same = execution.output == comparison.output && execution.error == comparison.error
    lines = ["code: $(length(program.before)) -> $(length(program.after))","folds: $(program.folds)","peephole: $(sum(program.peephole))"]
    append!(lines,["  $rule $count" for (rule,count) in zip(RULES,program.peephole)])
    append!(lines,["executed: $(execution.executed)","executed before peephole: $(comparison.executed)","behaviour: $(same ? "same" : "different")",
        "max call depth: $(execution.max_depth)","max stack: $(execution.max_stack)"])
    opcodes,functions,source_lines = Dict{String,Int}(),Dict{String,Int}(),Dict{Int,Int}()
    for (address,(entry,count)) in enumerate(zip(program.after,execution.counts))
        opcodes[entry.op] = get(opcodes,entry.op,0)+count
        owner = program.owners[address]
        functions[owner] = get(functions,owner,0)+count
        source_line = entry.position[1]
        source_lines[source_line] = get(source_lines,source_line,0)+count
    end
    push!(lines,"opcodes:")
    for (op,count) in sort(collect(opcodes);by=pair -> (-pair.second,pair.first))
        count > 0 && push!(lines,"  $op $count")
    end
    push!(lines,"functions:")
    names = [unit.name for unit in program.units if unit.function_node !== nothing]
    sort!(names;by=name -> (-get(functions,name,0),name))
    for name in names
        push!(lines,"  $name calls=$(get(execution.calls,name,0)) executed=$(get(functions,name,0))")
    end
    push!(lines,"calls:")
    for ((caller,callee),count) in sort(collect(execution.pairs);by=pair -> (-pair.second,pair.first[1],pair.first[2]))
        push!(lines,"  $caller -> $callee $count")
    end
    push!(lines,"hot lines:")
    executed_lines = sort([(line,count) for (line,count) in source_lines if count > 0];by=pair -> (-pair[2],pair[1]))
    for (line,count) in executed_lines[1:min(5,length(executed_lines))]
        push!(lines,"  line $line: $count")
    end
    push!(lines,"coverage: $(length(executed_lines)) of $(length(source_lines)) lines")
    unexecuted = sort([line for (line,count) in source_lines if count == 0])
    push!(lines,"not executed: " * (isempty(unexecuted) ? "none" : join(unexecuted," ")))
    push!(lines,"hot spots:")
    hot_spots = sort([(address-1,count) for (address,count) in enumerate(execution.counts) if count > 0];by=pair -> (-pair[2],pair[1]))
    for (address,count) in hot_spots[1:min(5,length(hot_spots))]
        push!(lines,"  pc=$address count=$count $(spelling(program.after[address+1]))")
    end
    lines
end
function summary_lines(programs)
    compiled = [program for program in programs if program.error === nothing]
    errors = Dict(kind=>count(program -> program.error !== nothing && program.error.kind == kind,programs) for kind in ("lexical","syntax","semantic"))
    runtime_errors = count(program -> program.execution.error !== nothing,compiled)
    folds = sum((program.folds for program in compiled);init=0)
    peephole = [sum((program.peephole[index] for program in compiled);init=0) for index in eachindex(RULES)]
    executed = sum((program.execution.executed for program in compiled);init=0)
    lines = ["== summary ==","programs: $(length(programs))","compiled: $(length(compiled))",
        "compile errors: lexical $(errors["lexical"]) syntax $(errors["syntax"]) semantic $(errors["semantic"])","runtime errors: $runtime_errors","folds: $folds","peephole: $(sum(peephole))"]
    append!(lines,["  $rule $count" for (rule,count) in zip(RULES,peephole)])
    push!(lines,"executed: $executed")
    rows = [["program","status","code","executed","output"]]
    for program in programs
        if program.error !== nothing
            push!(rows,[program.name,program.error.kind * " error","-","-","-"])
        else
            execution = program.execution
            status = execution.error === nothing ? "ok" : "runtime error"
            push!(rows,[program.name,status,string(length(program.after)),string(execution.executed),string(length(execution.output))])
        end
    end
    widths = [maximum(length(row[column]) for row in rows) for column in 1:5]
    for row in rows
        fields = [column <= 2 ? rpad(row[column],widths[column]) : lpad(row[column],widths[column]) for column in 1:5]
        push!(lines,"  " * join(fields,"  "))
    end
    lines
end
function read_programs()
    programs = ToyProgram[]
    for (number,line) in enumerate(readlines("input/program.src"))
        if startswith(line,"#program ")
            push!(programs,ToyProgram(line[10:end]))
        else
            push!(programs[end].lines,(number,line))
        end
    end
    by_name = Dict(program.name=>program for program in programs)
    current = nothing
    for line in readlines("input/input.txt")
        if startswith(line,"#input ")
            current = by_name[line[8:end]]
        else
            append!(current.inputs,parse.(Int64,split(line,' ')))
        end
    end
    programs
end
function main()
    programs = read_programs()
    reports = Dict(name=>String[] for name in REPORTS)
    for program in programs
        compile_program!(program)
        heading = "== program $(program.name) =="
        for name in REPORTS
            push!(reports[name],heading)
        end
        append!(reports["diagnostics.txt"],diagnostics(program))
        if program.error !== nothing
            push!(reports["listing.txt"],"not compiled")
            push!(reports["stats.txt"],"not compiled")
        else
            append!(reports["listing.txt"],listing(program))
            append!(reports["output.txt"],program.execution.output)
            append!(reports["stats.txt"],statistics(program))
        end
    end
    append!(reports["stats.txt"],summary_lines(programs))
    mkpath("output")
    for name in REPORTS
        write(joinpath("output",name),join(reports[name],"\n") * "\n")
    end
end
main()
