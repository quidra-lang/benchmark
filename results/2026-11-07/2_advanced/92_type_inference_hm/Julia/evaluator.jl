struct Closure
    parameter::String
    body::MLNode
    environment::Dict{String,Any}
end
struct Builtin
    behavior::Function
end
struct RuntimeFailure <: Exception
    position::MLPosition
    message::String
end
function checked_integer(value,position)
    -2147483648 <= value <= 2147483647 || throw(RuntimeFailure(position,"integer overflow"))
    value
end
function compare_values(first,second,position)
    first isa Union{Closure,Builtin} && throw(RuntimeFailure(position,"functional value compared"))
    if first isa Tuple || first isa AbstractVector
        for (left,right) in zip(first,second)
            order = compare_values(left,right,position)
            order == 0 || return order
        end
        return Int(length(first) > length(second))-Int(length(first) < length(second))
    end
    Int(first > second)-Int(first < second)
end
function binary_operation(operator,first,second,position)
    operator == "+" && return checked_integer(first+second,position)
    operator == "-" && return checked_integer(first-second,position)
    operator == "*" && return checked_integer(first*second,position)
    if operator in ("/","mod")
        second == 0 && throw(RuntimeFailure(position,"division by zero"))
        quotient = div(first,second)
        return operator == "/" ? checked_integer(quotient,position) : first-second*quotient
    end
    operator == "^" && return first * second
    operator == "::" && return [Any[first];second]
    order = compare_values(first,second,position)
    operator == "=" && return order == 0
    operator == "<>" && return order != 0
    operator == "<" && return order < 0
    operator == ">" && return order > 0
    operator == "<=" ? order <= 0 : order >= 0
end
function match_pattern!(pattern,value,bindings)
    kind = pattern.kind
    kind == "wildcard" && return true
    if kind == "name"
        bindings[pattern.value] = value
        return true
    elseif kind in ("integer","boolean","string")
        return pattern.value == value
    elseif kind == "cons"
        return !isempty(value) && match_pattern!(pattern.children[1],value[1],bindings) && match_pattern!(pattern.children[2],value[2:end],bindings)
    elseif kind == "list" && length(value) != length(pattern.children)
        return false
    end
    all(match_pattern!(child,item,bindings) for (child,item) in zip(pattern.children,value))
end
mutable struct Evaluator
    calls::Int
end
Evaluator() = Evaluator(0)
function evaluate!(evaluator,expression,environment)
    kind,children = expression.kind,expression.children
    kind in ("integer","boolean","string") && return expression.value
    kind == "name" && return environment[expression.value]
    kind == "fun" && return Closure(expression.value.spelling,children[1],copy(environment))
    if kind == "apply"
        function_value = evaluate!(evaluator,children[1],environment)
        argument = evaluate!(evaluator,children[2],environment)
        evaluator.calls += 1
        function_value isa Builtin && return function_value.behavior(argument,expression.position)
        inner = copy(function_value.environment)
        function_value.parameter == "_" || (inner[function_value.parameter] = argument)
        return evaluate!(evaluator,function_value.body,inner)
    elseif kind == "binary"
        first = evaluate!(evaluator,children[1],environment)
        operator = expression.value.spelling
        operator == "&&" && return first ? evaluate!(evaluator,children[2],environment) : false
        operator == "||" && return first ? true : evaluate!(evaluator,children[2],environment)
        second = evaluate!(evaluator,children[2],environment)
        return binary_operation(operator,first,second,expression.value.position)
    elseif kind == "negate"
        return checked_integer(-evaluate!(evaluator,children[1],environment),expression.value.position)
    elseif kind == "if"
        selected = evaluate!(evaluator,children[1],environment) ? children[2] : children[3]
        return evaluate!(evaluator,selected,environment)
    elseif kind == "pair"
        first = evaluate!(evaluator,children[1],environment)
        second = evaluate!(evaluator,children[2],environment)
        return first,second
    elseif kind == "list"
        return Any[evaluate!(evaluator,child,environment) for child in children]
    elseif kind == "match"
        value = evaluate!(evaluator,children[1],environment)
        for (pattern,arm) in expression.value
            bindings = Dict{String,Any}()
            if match_pattern!(pattern,value,bindings)
                return evaluate!(evaluator,arm,merge(environment,bindings))
            end
        end
        throw(RuntimeFailure(expression.position,"match failure"))
    end
    evaluate!(evaluator,children[1],evaluate_group!(evaluator,expression.value,environment))
end
function evaluate_group!(evaluator,group,environment)
    result = copy(environment)
    if group.rec_position !== nothing
        for binding in group.bindings
            expression = binding.expression
            result[binding.name] = Closure(expression.value.spelling,expression.children[1],result)
        end
    else
        values = Any[evaluate!(evaluator,binding.expression,environment) for binding in group.bindings]
        for (binding,value) in zip(group.bindings,values)
            result[binding.name] = value
        end
    end
    result
end
