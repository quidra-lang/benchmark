include("lexer.jl")
include("unifier.jl")
include("parser.jl")
include("inference.jl")
include("evaluator.jl")
function print_value(value)
    value isa Bool && return value ? "true" : "false"
    value isa Integer && return string(value)
    if value isa String
        escaped = replace(value,"\\"=>"\\\\","\""=>"\\\"","\n"=>"\\n","\t"=>"\\t")
        return "\"" * escaped * "\""
    elseif value isa Tuple
        return "(" * print_value(value[1]) * ", " * print_value(value[2]) * ")"
    elseif value isa AbstractVector
        return "[" * join(print_value.(value),"; ") * "]"
    end
    "<fun>"
end
mutable struct TypePrinter
    names::IdDict{TypeVariable,String}
    quantified::Union{Nothing,Set{TypeVariable}}
end
TypePrinter(quantified=nothing) = TypePrinter(IdDict{TypeVariable,String}(),quantified)
function print_type!(printer,value)
    value = resolve_type(value)
    if value isa TypeVariable
        if !haskey(printer.names,value)
            index = length(printer.names)
            prefix = printer.quantified !== nothing && !(value in printer.quantified) ? "'_" : "'"
            suffix = index >= 26 ? string(index ÷ 26) : ""
            printer.names[value] = prefix * string(Char(Int('a')+index%26)) * suffix
        end
        return printer.names[value]
    end
    value.kind in ("int","bool","string") && return value.kind
    first = resolve_type(value.children[1])
    left = print_type!(printer,first)
    first_kind = first isa TypeVariable ? "" : first.kind
    if value.kind == "list"
        first_kind in ("pair","function") && (left = "(" * left * ")")
        return left * " list"
    end
    second = resolve_type(value.children[2])
    right = print_type!(printer,second)
    second_kind = second isa TypeVariable ? "" : second.kind
    if value.kind == "pair"
        first_kind in ("pair","function") && (left = "(" * left * ")")
        second_kind in ("pair","function") && (right = "(" * right * ")")
        return left * " * " * right
    end
    first_kind == "function" && (left = "(" * left * ")")
    left * " -> " * right
end
function format_declared_type(expression)
    expression.kind == "type_variable" && return expression.value
    expression.kind in ("int","bool","string") && return expression.kind
    first = expression.children[1]
    left = format_declared_type(first)
    if expression.kind == "list"
        first.kind in ("pair","function") && (left = "(" * left * ")")
        return left * " list"
    end
    second = expression.children[2]
    right = format_declared_type(second)
    if expression.kind == "pair"
        first.kind in ("pair","function") && (left = "(" * left * ")")
        second.kind in ("pair","function") && (right = "(" * right * ")")
        return left * " * " * right
    end
    first.kind == "function" && (left = "(" * left * ")")
    left * " -> " * right
end
function signature_type(expression,variables)
    if expression.kind == "type_variable"
        return get!(() -> TypeVariable(),variables,expression.value)
    end
    ml_type(expression.kind,[signature_type(child,variables) for child in expression.children]...)
end
function identical_types(first,second)
    first,second = resolve_type(first),resolve_type(second)
    (first isa TypeVariable || second isa TypeVariable) && return first === second
    first.kind == second.kind && all(identical_types(a,b) for (a,b) in zip(first.children,second.children))
end
function signature_matches(inferred,declared,assignments)
    inferred,declared = resolve_type(inferred),resolve_type(declared)
    if inferred isa TypeVariable
        haskey(assignments,inferred) && return identical_types(assignments[inferred],declared)
        assignments[inferred] = declared
        return true
    end
    (declared isa TypeVariable || inferred.kind != declared.kind) && return false
    all(signature_matches(first,second,assignments) for (first,second) in zip(inferred.children,declared.children))
end
function check_signatures!(group,signatures)
    for (binding,signature) in zip(group.bindings,signatures)
        signature === nothing && continue
        declared = signature_type(signature[2],Dict{String,TypeVariable}())
        inferred = binding.scheme.value
        signature_matches(inferred,declared,IdDict{TypeVariable,MLType}()) || inference_error("signature",binding.position;name=binding.name,inferred,declared)
        binding.scheme = Scheme(declared,free_variables(declared))
    end
end
function edit_distance(first,second)
    previous = collect(0:length(second))
    for (row,left) in enumerate(first)
        current = [row]
        for (column,right) in enumerate(second)
            push!(current,min(current[end]+1,previous[column+1]+1,previous[column]+Int(left != right)))
        end
        previous = current
    end
    previous[end]
end
function name_candidate(name,candidates)
    choices = Tuple{Int,String}[]
    for candidate in candidates
        distance = edit_distance(name,candidate)
        distance <= 2 && distance < length(name) && push!(choices,(distance,candidate))
    end
    isempty(choices) ? nothing : minimum(choices)[2]
end
function type_error_message(error)
    details,printer = error.details,TypePrinter()
    if error.kind == "unbound"
        message = "unbound variable '$(details.name)'"
        candidate = name_candidate(details.name,details.candidates)
        candidate === nothing ? message : message * " (did you mean '$candidate'?)"
    elseif error.kind == "not_function"
        "expected a function but found " * print_type!(printer,details.found)
    elseif error.kind == "check"
        message = "expected " * print_type!(printer,details.expected) * " but found " * print_type!(printer,details.found)
        failure = details.failure
        if failure.infinite
            variable,value = failure.expected,failure.found
            variable isa TypeVariable || ((variable,value) = (value,variable))
            message *= " (infinite type " * print_type!(printer,variable) * " = " * print_type!(printer,value) * ")"
        elseif failure.nested
            message *= " (" * print_type!(printer,failure.expected) * " vs " * print_type!(printer,failure.found) * ")"
        end
        message
    elseif error.kind == "duplicate_pattern"
        "variable '$(details.name)' is bound twice in this pattern"
    elseif error.kind == "duplicate_let"
        "variable '$(details.name)' is bound twice in this let"
    elseif error.kind == "recursive_function"
        "'$(details.name)' in let rec must be a function"
    else
        "'$(details.name)' has type " * print_type!(printer,details.inferred) * " but its signature is " * print_type!(printer,details.declared)
    end
end
function built_in_environments()
    first,second = TypeVariable(),TypeVariable()
    fst_scheme = Scheme(ml_type("function",ml_type("pair",first,second),first),Set([first,second]))
    first,second = TypeVariable(),TypeVariable()
    snd_scheme = Scheme(ml_type("function",ml_type("pair",first,second),second),Set([first,second]))
    result = TypeVariable()
    types = Dict("fst"=>fst_scheme,"snd"=>snd_scheme,"not"=>Scheme(ml_type("function",BOOL,BOOL)),
        "string_of_int"=>Scheme(ml_type("function",INT,STRING)),"failwith"=>Scheme(ml_type("function",STRING,result),Set([result])))
    values = Dict{String,Any}("fst"=>Builtin((value,position) -> value[1]),"snd"=>Builtin((value,position) -> value[2]),
        "not"=>Builtin((value,position) -> !value),"string_of_int"=>Builtin((value,position) -> string(value)),
        "failwith"=>Builtin((value,position) -> throw(RuntimeFailure(position,"failure " * print_value(value)))))
    types,values
end
function leading_parameters(expression)
    parameters = String[]
    while expression.kind == "fun"
        push!(parameters,expression.value.spelling)
        expression = expression.children[1]
    end
    parameters,expression
end
function format_binding(binding)
    parameters,body = leading_parameters(binding.expression)
    join([binding.name;parameters;"=";format_expression(body)]," ")
end
format_group(group) = (group.rec_position === nothing ? "let " : "let rec ") * join(format_binding.(group.bindings)," and ")
function ends_with_match(expression)
    expression.kind == "match" && return true
    expression.kind in ("let","fun") && return ends_with_match(expression.children[1])
    expression.kind == "if" && return ends_with_match(expression.children[3])
    false
end
function format_pattern(pattern)
    kind = pattern.kind
    kind in ("wildcard","name") && return pattern.value
    kind in ("integer","boolean","string") && return print_value(pattern.value)
    kind == "list" && return "[" * join(format_pattern.(pattern.children),"; ") * "]"
    first,second = pattern.children
    left,right = format_pattern(first),format_pattern(second)
    kind == "pair" && return "(" * left * ", " * right * ")"
    first.kind == "cons" && (left = "(" * left * ")")
    left * " :: " * right
end
function format_expression(expression,minimum=0)
    kind,children = expression.kind,expression.children
    strength = 9
    if kind in ("integer","boolean","string")
        text = print_value(expression.value)
    elseif kind == "name"
        text = expression.value
    elseif kind == "fun"
        strength = 0
        parameters,body = leading_parameters(expression)
        text = "fun " * join(parameters," ") * " -> " * format_expression(body)
    elseif kind == "apply"
        strength = 8
        text = format_expression(children[1],8) * " " * format_expression(children[2],9)
    elseif kind == "binary"
        operator = expression.value.spelling
        strength,right_associative = OPERATORS[operator]
        text = format_expression(children[1],strength+Int(right_associative)) * " " * operator * " " * format_expression(children[2],strength+Int(!right_associative))
    elseif kind == "negate"
        strength = 7
        text = "-" * format_expression(children[1],7)
    elseif kind == "if"
        strength = 0
        text = "if " * format_expression(children[1]) * " then " * format_expression(children[2]) * " else " * format_expression(children[3])
    elseif kind == "pair"
        text = "(" * format_expression(children[1]) * ", " * format_expression(children[2]) * ")"
    elseif kind == "list"
        text = "[" * join(format_expression.(children),"; ") * "]"
    elseif kind == "let"
        strength = 0
        text = format_group(expression.value) * " in " * format_expression(children[1])
    else
        strength = 0
        arms = String[]
        for (index,(pattern,arm)) in enumerate(expression.value)
            body = format_expression(arm)
            index < length(expression.value) && ends_with_match(arm) && (body = "(" * body * ")")
            push!(arms,format_pattern(pattern) * " -> " * body)
        end
        text = "match " * format_expression(children[1]) * " with " * join(arms," | ")
    end
    strength < minimum ? "(" * text * ")" : text
end
function format_item(item)
    if item.kind == "signature"
        name,declared = item.value
        return "val " * name.spelling * " : " * format_declared_type(declared) * ";;"
    end
    (item.kind == "declaration" ? format_group(item.value) : format_expression(item.value)) * ";;"
end
function coverage_type(value)
    value = resolve_type(value)
    (value isa TypeVariable || value.kind == "function") && return ("opaque",)
    (value.kind,(coverage_type(child) for child in value.children)...)
end
function coverage_pattern(pattern)
    pattern.kind in ("wildcard","name") && return nothing
    pattern.kind in ("integer","boolean","string") && return ((pattern.kind,pattern.value),())
    if pattern.kind == "list"
        result = (("nil",),())
        for child in reverse(pattern.children)
            result = (("cons",),(coverage_pattern(child),result))
        end
        return result
    end
    ((pattern.kind == "pair" ? "pair" : "cons",),Tuple(coverage_pattern.(pattern.children)))
end
function constructors(value_type)
    value_type[1] == "bool" && return (("boolean",false),("boolean",true))
    value_type[1] == "list" && return (("nil",),("cons",))
    value_type[1] == "pair" && return (("pair",),)
    ()
end
function constructor_arguments(constructor,value_type)
    constructor == ("pair",) && return value_type[2:end]
    constructor == ("cons",) && return (value_type[2],value_type)
    ()
end
function specialize(matrix,constructor,arity)
    rows = Any[]
    for row in matrix
        if row[1] === nothing
            push!(rows,(ntuple(_ -> nothing,arity)...,row[2:end]...))
        elseif row[1][1] == constructor
            push!(rows,(row[1][2]...,row[2:end]...))
        end
    end
    Tuple(rows)
end
function useful_pattern(matrix,query,types,cache)
    key = (matrix,query,types)
    haskey(cache,key) && return cache[key]
    function compute()
        isempty(query) && return isempty(matrix)
        isempty(matrix) && return true
        head = query[1]
        if head !== nothing
            constructor,arguments = head
            argument_types = constructor_arguments(constructor,types[1])
            return useful_pattern(specialize(matrix,constructor,length(arguments)),(arguments...,query[2:end]...),(argument_types...,types[2:end]...),cache)
        end
        possible = constructors(types[1])
        present = Set(row[1][1] for row in matrix if row[1] !== nothing)
        if !isempty(possible) && all(constructor in present for constructor in possible)
            for constructor in possible
                argument_types = constructor_arguments(constructor,types[1])
                selected = specialize(matrix,constructor,length(argument_types))
                arguments = ntuple(_ -> nothing,length(argument_types))
                useful_pattern(selected,(arguments...,query[2:end]...),(argument_types...,types[2:end]...),cache) && return true
            end
            return false
        end
        defaults = Tuple(row[2:end] for row in matrix if row[1] === nothing)
        useful_pattern(defaults,query[2:end],types[2:end],cache)
    end
    cache[key] = compute()
end
function expression_nodes(expression)
    nodes = [expression]
    if expression.kind == "let"
        for binding in expression.value.bindings
            append!(nodes,expression_nodes(binding.expression))
        end
    end
    for child in expression.children
        append!(nodes,expression_nodes(child))
    end
    if expression.kind == "match"
        for (pattern,arm) in expression.value
            append!(nodes,expression_nodes(arm))
        end
    end
    nodes
end
function recursion_classification(expression,targets,references)
    parameters,body = leading_parameters(expression)
    calls = Bool[]
    function visit(node,tail)
        kind,children = node.kind,node.children
        if kind == "name"
            get(references,node,nothing) in targets && push!(calls,false)
        elseif kind == "apply"
            arguments = MLNode[]
            function_node = node
            while function_node.kind == "apply"
                push!(arguments,function_node.children[2])
                function_node = function_node.children[1]
            end
            if function_node.kind == "name" && get(references,function_node,nothing) in targets
                push!(calls,tail)
            else
                visit(function_node,false)
            end
            foreach(argument -> visit(argument,false),reverse(arguments))
        elseif kind == "if"
            visit(children[1],false)
            visit(children[2],tail)
            visit(children[3],tail)
        elseif kind == "match"
            visit(children[1],false)
            foreach(arm -> visit(arm[2],tail),node.value)
        elseif kind == "let"
            foreach(binding -> visit(binding.expression,false),node.value.bindings)
            visit(children[1],tail)
        elseif kind == "binary" && node.value.spelling in ("&&","||")
            visit(children[1],false)
            visit(children[2],tail)
        else
            foreach(child -> visit(child,false),children)
        end
    end
    visit(body,true)
    isempty(calls) ? "" : all(calls) ? "tail recursive" : "recursive"
end
mutable struct StaticSymbol
    name::String
    position::MLPosition
    top_level::Bool
    used::Bool
end
mutable struct StaticChecks
    symbols::Vector{StaticSymbol}
    references::IdDict{MLNode,Union{Nothing,StaticSymbol}}
    groups::Vector{Tuple{BindingGroup,Set{StaticSymbol}}}
    warnings::Vector{Tuple{MLPosition,Int,String}}
end
StaticChecks() = StaticChecks(StaticSymbol[],IdDict{MLNode,Union{Nothing,StaticSymbol}}(),Tuple{BindingGroup,Set{StaticSymbol}}[],Tuple{MLPosition,Int,String}[])
function new_symbol!(checks,name,position;top_level=false)
    symbol = StaticSymbol(name,position,top_level,false)
    push!(checks.symbols,symbol)
    symbol
end
function bind_pattern!(checks,pattern,environment)
    pattern.kind == "name" && (environment[pattern.value] = new_symbol!(checks,pattern.value,pattern.position))
    foreach(child -> bind_pattern!(checks,child,environment),pattern.children)
end
function check_group!(checks,group,environment;top_level=false)
    symbols = [new_symbol!(checks,binding.name,binding.position;top_level) for binding in group.bindings]
    push!(checks.groups,(group,Set(symbols)))
    inner = copy(environment)
    for symbol in symbols
        inner[symbol.name] = symbol
    end
    right_environment = group.rec_position === nothing ? environment : inner
    foreach(binding -> check_expression!(checks,binding.expression,right_environment),group.bindings)
    inner
end
function match_warnings!(checks,expression)
    cache = Dict{Any,Bool}()
    matrix = ()
    matched_type = (coverage_type(expression.children[1].inferred),)
    for (index,(pattern,arm)) in enumerate(expression.value)
        query = (coverage_pattern(pattern),)
        index > 1 && !useful_pattern(matrix,query,matched_type,cache) && push!(checks.warnings,(pattern.position,2,"this match case is unused"))
        matrix = (matrix...,query)
    end
    useful_pattern(matrix,(nothing,),matched_type,cache) && push!(checks.warnings,(expression.position,1,"this match is not exhaustive"))
end
function check_expression!(checks,expression,environment)
    kind = expression.kind
    if kind == "name"
        symbol = get(environment,expression.value,nothing)
        checks.references[expression] = symbol
        symbol === nothing || (symbol.used = true)
    elseif kind == "fun"
        inner = copy(environment)
        parameter = expression.value
        parameter.spelling == "_" || (inner[parameter.spelling] = new_symbol!(checks,parameter.spelling,parameter.position))
        check_expression!(checks,expression.children[1],inner)
    elseif kind == "let"
        inner = check_group!(checks,expression.value,environment)
        check_expression!(checks,expression.children[1],inner)
    elseif kind == "match"
        check_expression!(checks,expression.children[1],environment)
        match_warnings!(checks,expression)
        for (pattern,arm) in expression.value
            inner = copy(environment)
            bind_pattern!(checks,pattern,inner)
            check_expression!(checks,arm,inner)
        end
    else
        foreach(child -> check_expression!(checks,child,environment),expression.children)
    end
end
function check_item!(item,environment_names)
    checks = StaticChecks()
    environment = Dict{String,Union{Nothing,StaticSymbol}}(name=>nothing for name in environment_names)
    if item.kind == "declaration"
        check_group!(checks,item.value,environment;top_level=true)
    else
        check_expression!(checks,item.value,environment)
    end
    for (group,targets) in checks.groups
        group.rec_position === nothing && continue
        referenced = any(get(checks.references,node,nothing) in targets for binding in group.bindings for node in expression_nodes(binding.expression))
        referenced || push!(checks.warnings,(group.rec_position,3,"unused rec flag"))
        for binding in group.bindings
            binding.classification = recursion_classification(binding.expression,targets,checks.references)
        end
    end
    for symbol in checks.symbols
        !symbol.top_level && !symbol.used && !startswith(symbol.name,"_") && push!(checks.warnings,(symbol.position,4,"unused variable '$(symbol.name)'"))
    end
    sort!(checks.warnings;by=warning -> (warning[1][2],warning[1][3],warning[2]))
end
classification_suffix(binding) = isempty(binding.classification) ? "" : " ($(binding.classification))"
function syntax_error_message(token)
    token.kind == "invalid" && return token.value
    token.kind == "EOF" && return "unexpected end of file"
    "unexpected '$(token.spelling)'"
end
const FILE_NAMES = ("prelude.ml","program.ml")
const COUNTER_NAMES = ("items","bindings","syntax","type","runtime","warnings","calls")
mutable struct MLRunner
    sources::Dict{String,Vector{String}}
    type_environment::Dict{String,Scheme}
    value_environment::Dict{String,Any}
    current_file::String
    statistics::Dict{String,Dict{String,Int}}
    reports::Vector{String}
    types::Vector{String}
    values::Vector{String}
    formatted::Vector{String}
end
function report!(runner,kind,position,message)
    filename,line,column = position
    counter = kind == "warning" ? "warnings" : split(kind)[1]
    runner.statistics[runner.current_file][counter] += 1
    push!(runner.reports,"$filename:$line:$column: $kind: $message")
    source_lines = runner.sources[filename]
    if line <= length(source_lines)
        push!(runner.reports,"    " * source_lines[line])
        push!(runner.reports,repeat(" ",column+3) * "^")
    end
end
function unused_signature!(runner,signature)
    name = signature[1]
    report!(runner,"warning",name.position,"signature for '$(name.spelling)' is never used")
end
function write_types!(runner,item,inferred,local_bindings)
    if item.kind == "declaration"
        for binding in item.value.bindings
            push!(runner.types,binding.name * " : " * print_type!(TypePrinter(),binding.scheme.value) * classification_suffix(binding))
        end
    else
        push!(runner.types,"- : " * print_type!(TypePrinter(),inferred))
    end
    for binding in sort(local_bindings;by=b -> b.position[2:3])
        filename,line,column = binding.position
        text = "  $(binding.name) ($line:$column) : " * print_type!(TypePrinter(binding.scheme.quantified),binding.scheme.value)
        push!(runner.types,text * classification_suffix(binding))
    end
end
function process_item!(runner,item,pending,evaluator,counts)
    push!(runner.formatted,format_item(item))
    if item.kind == "signature"
        name = item.value[1].spelling
        haskey(pending,name) && unused_signature!(runner,pending[name])
        pending[name] = item.value
        return
    end
    signatures = item.kind == "declaration" ? [pop!(pending,binding.name,nothing) for binding in item.value.bindings] : Any[]
    inferencer,inferred = Inferencer(),nothing
    try
        if item.kind == "declaration"
            infer_group!(inferencer,item.value,runner.type_environment)
            check_signatures!(item.value,signatures)
        else
            inferred = infer_expression!(inferencer,item.value,runner.type_environment)
        end
    catch error
        error isa InferenceError || rethrow()
        report!(runner,"type error",error.position,type_error_message(error))
        return
    end
    warnings = check_item!(item,keys(runner.type_environment))
    write_types!(runner,item,inferred,inferencer.local_bindings)
    for (position,priority,message) in warnings
        report!(runner,"warning",position,message)
    end
    environment,values,value = nothing,nothing,nothing
    try
        if item.kind == "declaration"
            environment = evaluate_group!(evaluator,item.value,runner.value_environment)
            values = Any[environment[binding.name] for binding in item.value.bindings]
        else
            value = evaluate!(evaluator,item.value,runner.value_environment)
        end
    catch error
        error isa RuntimeFailure || rethrow()
        report!(runner,"runtime error",error.position,error.message)
        return
    end
    if item.kind == "declaration"
        types = copy(runner.type_environment)
        for (binding,value) in zip(item.value.bindings,values)
            push!(runner.values,binding.name * " = " * print_value(value))
            types[binding.name] = binding.scheme
        end
        runner.type_environment,runner.value_environment = types,environment
        counts["bindings"] += length(item.value.bindings)
    else
        push!(runner.values,"- = " * print_value(value))
    end
end
function process_file!(runner,filename,source)
    runner.current_file = filename
    counts = runner.statistics[filename]
    push!(runner.types,"== $filename ==")
    push!(runner.values,"== $filename ==")
    push!(runner.formatted,"(* $filename *)")
    pending = Dict{String,Tuple{MLToken,MLNode}}()
    evaluator = Evaluator()
    parser = MLParser(tokenize(source,filename))
    while next_token(parser).kind != "EOF"
        counts["items"] += 1
        try
            item = parse_item!(parser)
            process_item!(runner,item,pending,evaluator,counts)
        catch error
            error isa SyntaxFailure || rethrow()
            report!(runner,"syntax error",error.token.position,syntax_error_message(error.token))
            recover!(parser)
        end
    end
    for signature in sort(collect(values(pending));by=s -> s[1].position[2:3])
        unused_signature!(runner,signature)
    end
    counts["calls"] = evaluator.calls
end
function main()
    raw_sources = Dict(filename=>read(joinpath("input",filename),String) for filename in FILE_NAMES)
    sources = Dict(filename=>String.(split(raw_sources[filename],'\n';keepempty=true)[1:end-1]) for filename in FILE_NAMES)
    types,values = built_in_environments()
    statistics = Dict(filename=>Dict(name=>0 for name in COUNTER_NAMES) for filename in FILE_NAMES)
    runner = MLRunner(sources,types,values,"",statistics,String[],String[],String[],String[])
    for filename in FILE_NAMES
        process_file!(runner,filename,raw_sources[filename])
    end
    push!(runner.reports,"== summary ==")
    for filename in FILE_NAMES
        summary = join(["$name=$(runner.statistics[filename][name])" for name in COUNTER_NAMES]," ")
        push!(runner.reports,"$filename: $summary")
    end
    mkpath("output")
    for (filename,lines) in [("types.txt",runner.types),("values.txt",runner.values),("errors.txt",runner.reports),("formatted.ml",runner.formatted)]
        write(joinpath("output",filename),join(lines,"\n") * "\n")
    end
end
main()
