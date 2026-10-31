function can_complete(statement)
    pending = [(statement,false)]
    while !isempty(pending)
        node,expanded = pop!(pending)
        haskey(node.fields,:completes) && continue
        if node.kind in ("return","break","continue")
            node.completes = false
        elseif node.kind == "block"
            if expanded
                node.completes = all(child.completes for child in node.statements)
            else
                push!(pending,(node,true))
                append!(pending,[(child,false) for child in node.statements])
            end
        elseif node.kind == "if" && node.otherwise !== nothing
            if expanded
                node.completes = node.then.completes || node.otherwise.completes
            else
                append!(pending,[(node,true),(node.then,false),(node.otherwise,false)])
            end
        else
            node.completes = true
        end
    end
    statement.completes
end
mutable struct Analyzer
    declarations::Vector{ToyNode}
    end_position::ToyPosition
    globals::Dict{String,ToyNode}
    functions::Vector{ToyNode}
    variables::Vector{ToyNode}
    scopes::Vector{Dict{String,ToyNode}}
    current_function::Union{Nothing,ToyNode}
end
Analyzer(declarations,end_position) = Analyzer(declarations,end_position,Dict{String,ToyNode}(),ToyNode[],ToyNode[],Dict{String,ToyNode}[],nothing)
semantic_error(position,message) = throw(CompileError("semantic",position,message))
function prepare!(analyzer,declaration)
    declaration.references = ToyPosition[]
    declaration.read_accesses = 0
    if declaration.kind == "function"
        declaration.calls = Set{ToyNode}()
        push!(analyzer.functions,declaration)
    else
        push!(analyzer.variables,declaration)
    end
end
function lookup!(analyzer,name,position;read=true)
    referent = nothing
    for scope in reverse(analyzer.scopes)
        if haskey(scope,name)
            referent = scope[name]
            break
        end
    end
    referent === nothing && (referent = get(analyzer.globals,name,nothing))
    if referent !== nothing
        push!(referent.references,position)
        referent.read_accesses += read
    end
    referent
end
function variable!(analyzer,name,position,indexed;read=true)
    referent = lookup!(analyzer,name,position;read)
    referent === nothing && semantic_error(position,"undeclared identifier '$name'")
    referent.kind == "function" && semantic_error(position,"'$name' is a function, not a variable")
    is_array = referent.kind == "global" && referent.size !== nothing
    indexed && !is_array && semantic_error(position,"'$name' is not an array")
    !indexed && is_array && semantic_error(position,"array '$name' used without index")
    referent
end
function analyze_expression!(analyzer,node;call_statement=false)
    kind = node.kind
    if kind in ("integer","read")
        result = "int"
    elseif kind == "boolean"
        result = "bool"
    elseif kind in ("variable","array")
        node.referent = variable!(analyzer,node.name,node.position,kind == "array")
        kind == "array" && analyze_expression!(analyzer,node.index) != "int" && semantic_error(node.position,"index of '$(node.name)' must be int")
        result = node.referent.type
    elseif kind == "call"
        referent = lookup!(analyzer,node.name,node.position)
        referent === nothing && semantic_error(node.position,"undeclared function '$(node.name)'")
        referent.kind == "function" || semantic_error(node.position,"'$(node.name)' is not a function")
        node.referent = referent
        push!(analyzer.current_function.calls,referent)
        expected,found = length(referent.parameters),length(node.arguments)
        expected == found || semantic_error(node.position,"wrong number of arguments to '$(node.name)' (expected $expected, found $found)")
        for (number,(argument,parameter)) in enumerate(zip(node.arguments,referent.parameters))
            analyze_expression!(analyzer,argument) == parameter.type || semantic_error(node.position,"argument $number of '$(node.name)' must be $(parameter.type)")
        end
        !call_statement && referent.type == "void" && semantic_error(node.position,"void function '$(node.name)' used as a value")
        result = referent.type
    elseif kind == "unary"
        result = analyze_expression!(analyzer,node.operand)
        required = node.operator == "-" ? "int" : "bool"
        result == required || semantic_error(node.position,"operator '$(node.operator)' requires $required operand")
    else
        left = analyze_expression!(analyzer,node.left)
        right = analyze_expression!(analyzer,node.right)
        operator = node.operator
        if operator in ("+","-","*","/","%","<","<=",">",">=")
            left == right == "int" || semantic_error(node.position,"operator '$operator' requires int operands")
            result = operator in ("+","-","*","/","%") ? "int" : "bool"
        elseif operator in ("==","!=")
            left == right || semantic_error(node.position,"operator '$operator' requires operands of the same type")
            result = "bool"
        else
            left == right == "bool" || semantic_error(node.position,"operator '$operator' requires bool operands")
            result = "bool"
        end
    end
    node.type = result
    result
end
function constant_initializer!(analyzer,node)
    positions = ToyPosition[]
    pending = [node]
    while !isempty(pending)
        current = pop!(pending)
        current.kind in ("variable","array","call","read") && push!(positions,current.position)
        append!(pending,expression_children(current))
    end
    isempty(positions) || semantic_error(minimum(positions),"global initializer must be constant")
    analyze_expression!(analyzer,node)
end
function analyze_statement!(analyzer,node,loop_depth=0)
    kind = node.kind
    if kind == "declaration"
        node.type == "void" && semantic_error(node.name_position,"variable '$(node.name)' cannot have type void")
        haskey(analyzer.scopes[end],node.name) && semantic_error(node.name_position,"redeclaration of '$(node.name)'")
        node.initializer !== nothing && analyze_expression!(analyzer,node.initializer) != node.type && semantic_error(node.name_position,"type mismatch in initialization of '$(node.name)'")
        prepare!(analyzer,node)
        analyzer.scopes[end][node.name] = node
    elseif kind == "assignment"
        node.referent = variable!(analyzer,node.name,node.position,node.index !== nothing;read=false)
        node.index !== nothing && analyze_expression!(analyzer,node.index) != "int" && semantic_error(node.position,"index of '$(node.name)' must be int")
        analyze_expression!(analyzer,node.value) == node.referent.type || semantic_error(node.position,"type mismatch in assignment to '$(node.name)'")
    elseif kind == "call_statement"
        analyze_expression!(analyzer,node.expression;call_statement=true)
    elseif kind in ("if","while")
        analyze_expression!(analyzer,node.condition) == "bool" || semantic_error(node.position,"condition of '$kind' must be bool")
        if kind == "if"
            analyze_statement!(analyzer,node.then,loop_depth)
            node.otherwise === nothing || analyze_statement!(analyzer,node.otherwise,loop_depth)
        else
            analyze_statement!(analyzer,node.body,loop_depth+1)
        end
    elseif kind == "for"
        push!(analyzer.scopes,Dict{String,ToyNode}())
        node.initial === nothing || analyze_statement!(analyzer,node.initial,loop_depth)
        node.condition !== nothing && analyze_expression!(analyzer,node.condition) != "bool" && semantic_error(node.position,"condition of 'for' must be bool")
        node.update === nothing || analyze_statement!(analyzer,node.update,loop_depth)
        analyze_statement!(analyzer,node.body,loop_depth+1)
        pop!(analyzer.scopes)
    elseif kind in ("break","continue")
        loop_depth > 0 || semantic_error(node.position,"'$kind' outside loop")
    elseif kind == "return"
        current = analyzer.current_function
        current.type == "void" && node.value !== nothing && semantic_error(node.position,"function '$(current.name)' must not return a value")
        if current.type != "void"
            node.value === nothing && semantic_error(node.position,"function '$(current.name)' must return a value")
            analyze_expression!(analyzer,node.value) == current.type || semantic_error(node.position,"return value of '$(current.name)' must be $(current.type)")
        end
    elseif kind == "print"
        for (number,argument) in enumerate(node.arguments)
            analyze_expression!(analyzer,argument) == "int" || semantic_error(node.position,"argument $number of 'print' must be int")
        end
    elseif kind == "block"
        push!(analyzer.scopes,Dict{String,ToyNode}())
        foreach(child -> analyze_statement!(analyzer,child,loop_depth),node.statements)
        pop!(analyzer.scopes)
    end
end
function analyze!(analyzer)
    for node in analyzer.declarations
        if node.kind == "global"
            if node.size !== nothing
                node.type == "int" || semantic_error(node.name_position,"array '$(node.name)' must have element type int")
                node.size > 0 || semantic_error(node.size_position,"array '$(node.name)' must have a positive size")
            elseif node.type == "void"
                semantic_error(node.name_position,"variable '$(node.name)' cannot have type void")
            end
        end
        haskey(analyzer.globals,node.name) && semantic_error(node.name_position,"redeclaration of '$(node.name)'")
        if node.kind == "global"
            node.initializer !== nothing && constant_initializer!(analyzer,node.initializer) != node.type && semantic_error(node.name_position,"type mismatch in initialization of '$(node.name)'")
        else
            names = Set{String}()
            for parameter in node.parameters
                parameter.type == "void" && semantic_error(parameter.name_position,"parameter '$(parameter.name)' cannot have type void")
                parameter.name in names && semantic_error(parameter.name_position,"redeclaration of '$(parameter.name)'")
                push!(names,parameter.name)
                prepare!(analyzer,parameter)
            end
        end
        prepare!(analyzer,node)
        analyzer.globals[node.name] = node
    end
    main = get(analyzer.globals,"main",nothing)
    (main === nothing || main.kind != "function") && semantic_error(analyzer.end_position,"no main function")
    main.type == "void" && isempty(main.parameters) || semantic_error(main.name_position,"main must be declared as 'void main()'")
    for function_node in analyzer.functions
        analyzer.current_function = function_node
        analyzer.scopes = [Dict{String,ToyNode}(parameter.name=>parameter for parameter in function_node.parameters)]
        foreach(statement -> analyze_statement!(analyzer,statement),function_node.body.statements)
        function_node.type != "void" && can_complete(function_node.body) && semantic_error(function_node.name_position,"missing return in function '$(function_node.name)'")
    end
    analyzer
end
