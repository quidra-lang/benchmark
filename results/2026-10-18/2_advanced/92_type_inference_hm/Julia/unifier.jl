abstract type MLType end
mutable struct TypeVariable <: MLType
    binding::Union{Nothing,MLType}
end
TypeVariable() = TypeVariable(nothing)
struct TypeConstructor <: MLType
    kind::String
    children::Vector{MLType}
end
ml_type(kind,children...) = TypeConstructor(kind,MLType[children...])
struct Scheme
    value::MLType
    quantified::Set{TypeVariable}
end
Scheme(value) = Scheme(value,Set{TypeVariable}())
const INT = ml_type("int")
const BOOL = ml_type("bool")
const STRING = ml_type("string")
function resolve_type(value)
    path = TypeVariable[]
    while value isa TypeVariable && value.binding !== nothing
        push!(path,value)
        value = value.binding
    end
    for variable in path
        variable.binding = value
    end
    value
end
function occurs(variable,value)
    value = resolve_type(value)
    value isa TypeVariable && return variable === value
    any(child -> occurs(variable,child),value.children)
end
struct UnificationFailure <: Exception
    expected::MLType
    found::MLType
    infinite::Bool
    nested::Bool
end
function unify!(expected,found,nested=false)
    expected,found = resolve_type(expected),resolve_type(found)
    expected === found && return
    if expected isa TypeVariable
        occurs(expected,found) && throw(UnificationFailure(expected,found,true,nested))
        expected.binding = found
    elseif found isa TypeVariable
        occurs(found,expected) && throw(UnificationFailure(expected,found,true,nested))
        found.binding = expected
    else
        expected.kind == found.kind || throw(UnificationFailure(expected,found,false,nested))
        for (first,second) in zip(expected.children,found.children)
            unify!(first,second,true)
        end
    end
end
function free_variables(value)
    value = resolve_type(value)
    value isa TypeVariable && return Set([value])
    variables = Set{TypeVariable}()
    for child in value.children
        union!(variables,free_variables(child))
    end
    variables
end
function generalize(value,environment)
    free_in_environment = Set{TypeVariable}()
    for scheme in values(environment)
        union!(free_in_environment,setdiff(free_variables(scheme.value),scheme.quantified))
    end
    Scheme(value,setdiff(free_variables(value),free_in_environment))
end
function instantiate(scheme)
    replacements = IdDict{TypeVariable,TypeVariable}()
    function copy_type(value)
        value = resolve_type(value)
        if value isa TypeVariable
            value in scheme.quantified || return value
            return get!(() -> TypeVariable(),replacements,value)
        end
        ml_type(value.kind,[copy_type(child) for child in value.children]...)
    end
    copy_type(scheme.value)
end
