struct InferenceError <: Exception
    kind::String
    position::MLPosition
    details::NamedTuple
end
inference_error(kind,position;details...) = throw(InferenceError(kind,position,(;details...)))
mutable struct Inferencer
    local_bindings::Vector{Binding}
end
Inferencer() = Inferencer(Binding[])
function check_type!(expected,found,position)
    try
        unify!(expected,found)
    catch failure
        failure isa UnificationFailure || rethrow()
        inference_error("check",position;expected,found,failure)
    end
end
function operator_types(operator)
    operator in ("+","-","*","/","mod") && return (INT,INT,INT)
    operator == "^" && return (STRING,STRING,STRING)
    operator in ("&&","||") && return (BOOL,BOOL,BOOL)
    variable = TypeVariable()
    if operator == "::"
        sequence = ml_type("list",variable)
        return variable,sequence,sequence
    end
    variable,variable,BOOL
end
function infer_expression!(inferencer,expression,environment)
    kind,children = expression.kind,expression.children
    if kind in ("integer","boolean","string")
        result = Dict("integer"=>INT,"boolean"=>BOOL,"string"=>STRING)[kind]
    elseif kind == "name"
        haskey(environment,expression.value) || inference_error("unbound",expression.position;name=expression.value,candidates=collect(keys(environment)))
        result = instantiate(environment[expression.value])
    elseif kind == "fun"
        argument = TypeVariable()
        inner = copy(environment)
        expression.value.spelling == "_" || (inner[expression.value.spelling] = Scheme(argument))
        result = ml_type("function",argument,infer_expression!(inferencer,children[1],inner))
    elseif kind == "apply"
        function_type = resolve_type(infer_expression!(inferencer,children[1],environment))
        if function_type isa TypeVariable
            argument,result = TypeVariable(),TypeVariable()
            function_type.binding = ml_type("function",argument,result)
        elseif function_type.kind == "function"
            argument,result = function_type.children
        else
            inference_error("not_function",children[1].position;found=function_type)
        end
        found = infer_expression!(inferencer,children[2],environment)
        check_type!(argument,found,children[2].position)
    elseif kind == "binary"
        first,second,result = operator_types(expression.value.spelling)
        check_type!(first,infer_expression!(inferencer,children[1],environment),children[1].position)
        check_type!(second,infer_expression!(inferencer,children[2],environment),children[2].position)
    elseif kind == "negate"
        check_type!(INT,infer_expression!(inferencer,children[1],environment),children[1].position)
        result = INT
    elseif kind == "if"
        check_type!(BOOL,infer_expression!(inferencer,children[1],environment),children[1].position)
        result = infer_expression!(inferencer,children[2],environment)
        found = infer_expression!(inferencer,children[3],environment)
        check_type!(result,found,children[3].position)
    elseif kind == "pair"
        first = infer_expression!(inferencer,children[1],environment)
        second = infer_expression!(inferencer,children[2],environment)
        result = ml_type("pair",first,second)
    elseif kind == "list"
        element = TypeVariable()
        for child in children
            check_type!(element,infer_expression!(inferencer,child,environment),child.position)
        end
        result = ml_type("list",element)
    elseif kind == "match"
        matched = infer_expression!(inferencer,children[1],environment)
        result = TypeVariable()
        for (pattern,arm) in expression.value
            bindings = Dict{String,MLType}()
            pattern_type = infer_pattern!(pattern,bindings)
            check_type!(matched,pattern_type,pattern.position)
            inner = copy(environment)
            for (name,value) in bindings
                inner[name] = Scheme(value)
            end
            check_type!(result,infer_expression!(inferencer,arm,inner),arm.position)
        end
    else
        inner = infer_group!(inferencer,expression.value,environment;local_group=true)
        result = infer_expression!(inferencer,children[1],inner)
    end
    expression.inferred = result
    result
end
function infer_pattern!(pattern,bindings)
    kind,children = pattern.kind,pattern.children
    kind == "wildcard" && return TypeVariable()
    if kind == "name"
        haskey(bindings,pattern.value) && inference_error("duplicate_pattern",pattern.position;name=pattern.value)
        result = TypeVariable()
        bindings[pattern.value] = result
        return result
    elseif kind in ("integer","boolean","string")
        return Dict("integer"=>INT,"boolean"=>BOOL,"string"=>STRING)[kind]
    elseif kind == "pair"
        first = infer_pattern!(children[1],bindings)
        second = infer_pattern!(children[2],bindings)
        return ml_type("pair",first,second)
    end
    element = TypeVariable()
    sequence = ml_type("list",element)
    if kind == "cons"
        check_type!(element,infer_pattern!(children[1],bindings),children[1].position)
        check_type!(sequence,infer_pattern!(children[2],bindings),children[2].position)
    else
        for child in children
            check_type!(element,infer_pattern!(child,bindings),child.position)
        end
    end
    sequence
end
function infer_group!(inferencer,group,environment;local_group=false)
    names = Set{String}()
    for binding in group.bindings
        binding.name in names && inference_error("duplicate_let",binding.position;name=binding.name)
        push!(names,binding.name)
        group.rec_position !== nothing && binding.expression.kind != "fun" && inference_error("recursive_function",binding.position;name=binding.name)
    end
    if group.rec_position === nothing
        inferred = MLType[infer_expression!(inferencer,binding.expression,environment) for binding in group.bindings]
    else
        inferred = MLType[TypeVariable() for _ in group.bindings]
        recursive = copy(environment)
        for (binding,value) in zip(group.bindings,inferred)
            recursive[binding.name] = Scheme(value)
        end
        for (binding,expected) in zip(group.bindings,inferred)
            found = infer_expression!(inferencer,binding.expression,recursive)
            check_type!(expected,found,binding.position)
        end
    end
    result = copy(environment)
    for (binding,value) in zip(group.bindings,inferred)
        binding.scheme = generalize(value,environment)
        result[binding.name] = binding.scheme
    end
    local_group && append!(inferencer.local_bindings,group.bindings)
    result
end
