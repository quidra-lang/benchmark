abstract type PrologTerm end
struct IntegerTerm <: PrologTerm
    value::Int64
end
struct AtomTerm <: PrologTerm
    name::String
end
mutable struct VariableTerm <: PrologTerm
    binding::Union{Nothing,PrologTerm}
end
VariableTerm() = VariableTerm(nothing)
struct CompoundTerm <: PrologTerm
    name::String
    arguments::Vector{PrologTerm}
end
compound(name,arguments...) = CompoundTerm(name,PrologTerm[arguments...])
const NIL = AtomTerm("[]")
const PredicateIndicator = Tuple{String,Int}
struct PrologFault <: Exception
    term::PrologTerm
end
struct PrologBall <: Exception
    term::PrologTerm
end
function dereference(term)
    while term isa VariableTerm && term.binding !== nothing
        term = term.binding
    end
    term
end
is_atom(term,name) = term isa AtomTerm && term.name == name
function indicator(term)
    term = dereference(term)
    term isa CompoundTerm ? (term.name,length(term.arguments)) : (term.name,0)
end
indicator_term(key) = compound("/",AtomTerm(key[1]),IntegerTerm(key[2]))
function make_list(elements,tail=NIL)
    for element in reverse(elements)
        tail = compound(".",element,tail)
    end
    tail
end
function list_parts(term)
    elements = PrologTerm[]
    term = dereference(term)
    while term isa CompoundTerm && term.name == "." && length(term.arguments) == 2
        push!(elements,term.arguments[1])
        term = dereference(term.arguments[2])
    end
    elements,term
end
function copy_terms(terms...)
    variables = IdDict{VariableTerm,VariableTerm}()
    function duplicate(term)
        term === nothing && return nothing
        term = dereference(term)
        if term isa VariableTerm
            return get!(variables,term) do
                VariableTerm()
            end
        end
        term isa CompoundTerm && return CompoundTerm(term.name,PrologTerm[duplicate(argument) for argument in term.arguments])
        term
    end
    map(duplicate,terms)
end
copy_term(term) = copy_terms(term)[1]
function variables_in(terms...)
    result = VariableTerm[]
    pending = Union{Nothing,PrologTerm}[reverse(terms)...]
    while !isempty(pending)
        term = dereference(pop!(pending))
        if term isa VariableTerm
            push!(result,term)
        elseif term isa CompoundTerm
            append!(pending,reverse(term.arguments))
        end
    end
    result
end
function same_kind(left,right)
    left,right = dereference(left),dereference(right)
    (left isa VariableTerm || right isa VariableTerm) && return true
    if left isa CompoundTerm && right isa CompoundTerm
        return left.name == right.name && length(left.arguments) == length(right.arguments)
    end
    left isa IntegerTerm && right isa IntegerTerm && return left.value == right.value
    left isa AtomTerm && right isa AtomTerm && return left.name == right.name
    false
end
type_error(kind,term) = compound("type_error",AtomTerm(kind),term)
domain_error(kind,term) = compound("domain_error",AtomTerm(kind),term)
