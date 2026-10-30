struct BindingTrail
    bindings::Vector{VariableTerm}
end
BindingTrail() = BindingTrail(VariableTerm[])
trail_mark(trail) = length(trail.bindings)
function undo!(trail,mark)
    while length(trail.bindings) > mark
        pop!(trail.bindings).binding = nothing
    end
end
function unify!(trail,left,right)
    pending = Tuple{PrologTerm,PrologTerm}[(left,right)]
    while !isempty(pending)
        left,right = pop!(pending)
        left,right = dereference(left),dereference(right)
        left === right && continue
        if left isa VariableTerm
            left.binding = right
            push!(trail.bindings,left)
        elseif right isa VariableTerm
            right.binding = left
            push!(trail.bindings,right)
        elseif left isa CompoundTerm && right isa CompoundTerm
            (left.name != right.name || length(left.arguments) != length(right.arguments)) && return false
            append!(pending,reverse(collect(zip(left.arguments,right.arguments))))
        elseif left isa IntegerTerm && right isa IntegerTerm
            left.value == right.value || return false
        elseif left isa AtomTerm && right isa AtomTerm
            left.name == right.name || return false
        else
            return false
        end
    end
    true
end
function identical_terms(left,right)
    pending = Tuple{PrologTerm,PrologTerm}[(left,right)]
    while !isempty(pending)
        left,right = pop!(pending)
        left,right = dereference(left),dereference(right)
        left === right && continue
        (left isa VariableTerm || right isa VariableTerm) && return false
        if left isa CompoundTerm && right isa CompoundTerm
            (left.name != right.name || length(left.arguments) != length(right.arguments)) && return false
            append!(pending,reverse(collect(zip(left.arguments,right.arguments))))
        elseif left isa IntegerTerm && right isa IntegerTerm
            left.value == right.value || return false
        elseif left isa AtomTerm && right isa AtomTerm
            left.name == right.name || return false
        else
            return false
        end
    end
    true
end
