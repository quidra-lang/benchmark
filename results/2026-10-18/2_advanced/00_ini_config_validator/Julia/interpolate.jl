mutable struct Expander
    values::Dict{String,String}
    origins::Dict{String,Origin}
    results::Dict{String,Union{Nothing,String}}
    in_progress::Vector{String}
    cycle_keys::Set{String}
    diagnostics::Vector{Diagnostic}
end

Expander(values, origins) = Expander(values, origins, Dict{String,Union{Nothing,String}}(), String[], Set{String}(), Diagnostic[])

function report!(expander::Expander, origin, code, message)
    push!(expander.diagnostics, (origin[1], origin[2], code, message))
end

function expand!(expander, key)
    if !haskey(expander.results, key)
        push!(expander.in_progress, key)
        result = evaluate!(expander, key)
        pop!(expander.in_progress)
        expander.results[key] = result
    end
    expander.results[key]
end

function evaluate!(expander, key)
    value = expander.values[key]
    origin = expander.origins[key]
    result = IOBuffer()
    position = 1
    while position <= lastindex(value)
        char = value[position]
        if char != '$' || position == lastindex(value) || value[position + 1] != '{'
            print(result, char == LITERAL_DOLLAR ? '$' : char)
            position += 1
            continue
        end
        close = findnext(==('}'), value, position + 2)
        if close === nothing || !is_section_name(value[position+2:close-1])
            report!(expander, origin, "E_BAD_REF", "$key: invalid reference")
            return nothing
        end
        reference = String(value[position+2:close-1])
        target = occursin('.', reference) ? reference : section_of(key) * "." * reference
        if !haskey(expander.values, target)
            report!(expander, origin, "E_UNDEFINED", "$key: undefined reference $target")
            return nothing
        end
        cycle_start = findfirst(==(target), expander.in_progress)
        if cycle_start !== nothing
            path = [expander.in_progress[cycle_start:end]; target]
            report!(expander, expander.origins[target], "E_CYCLE", "interpolation cycle " * join(path, " -> "))
            union!(expander.cycle_keys, path)
            expanded = nothing
        else
            expanded = expand!(expander, target)
        end
        if expanded === nothing
            if !(key in expander.cycle_keys)
                report!(expander, origin, "E_DEPENDENCY", "$key: depends on failed key $target")
            end
            return nothing
        end
        print(result, expanded)
        position = close + 1
    end
    String(take!(result))
end
