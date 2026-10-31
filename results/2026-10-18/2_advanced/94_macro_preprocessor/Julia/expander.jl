mutable struct Expander
    macros::Dict{String,MacroDefinition}
    diagnostic::Function
    counter::Int
    builtin_counts::Dict{String,Int}
end
Expander(macros,diagnostic) = Expander(macros,diagnostic,0,Dict{String,Int}())
expansion_error!(expander,context,token,message) = expander.diagnostic(display_position(context,token.line),"error",message)
function expand_builtin!(expander,token,context)
    expander.builtin_counts[token.spelling] = get(expander.builtin_counts,token.spelling,0)+1
    if token.spelling == "__FILE__"
        kind,spelling = "string","\"" * context.display_file * "\""
    elseif token.spelling == "__LINE__"
        kind,spelling = "number",string(display_position(context,token.line)[2])
    else
        kind,spelling = "number",string(expander.counter)
        expander.counter += 1
    end
    PPToken(kind,spelling,token.line,token.space)
end
function collect_arguments!(expander,pending,definition,token,context)
    arguments,separators,nesting = [PPToken[]],PPToken[],0
    closing,consumed = nothing,0
    for (index,current) in enumerate(Iterators.reverse(pending))
        index == 1 && continue
        if current.spelling == ")" && nesting == 0
            closing,consumed = current,index
            break
        elseif current.spelling == "," && nesting == 0
            push!(separators,current)
            push!(arguments,PPToken[])
        else
            current.spelling == "(" && (nesting += 1)
            current.spelling == ")" && (nesting -= 1)
            push!(arguments[end],current)
        end
    end
    if closing === nothing
        expansion_error!(expander,context,token,"unterminated argument list invoking macro \"$(definition.name)\"")
        return nothing
    end
    argument_count = length(arguments)
    fixed = length(definition.parameters)-Int(definition.variadic)
    error = nothing
    if !definition.variadic && fixed == 0 && (argument_count != 1 || !isempty(arguments[1]))
        error = "macro \"$(definition.name)\" passed $argument_count arguments, but takes just 0"
    elseif argument_count < fixed
        error = "macro \"$(definition.name)\" requires $fixed arguments, but only $argument_count given"
    elseif argument_count > fixed && !definition.variadic
        error = "macro \"$(definition.name)\" passed $argument_count arguments, but takes just $fixed"
    end
    if error !== nothing
        expansion_error!(expander,context,token,error)
        return nothing
    end
    raw = Dict{String,Vector{PPToken}}(definition.parameters[index]=>arguments[index] for index in 1:fixed)
    if definition.variadic
        variable = PPToken[]
        for index in fixed+1:argument_count
            index > fixed+1 && push!(variable,separators[index-1])
            append!(variable,arguments[index])
        end
        raw[VARIADIC_NAME] = variable
    end
    raw,consumed,closing
end
function stringize(tokens,sharp)
    pieces = String[]
    for (index,token) in enumerate(tokens)
        index > 1 && token.space && push!(pieces," ")
        spelling = token.spelling
        if token.kind in ("string","character")
            spelling = replace(spelling,"\\"=>"\\\\","\""=>"\\\"")
        end
        push!(pieces,spelling)
    end
    PPToken("string","\"" * join(pieces) * "\"",sharp.line,sharp.space)
end
function paste_tokens!(expander,left,right,token,context)
    left.kind == "placemarker" && return [token_with(right;space=left.space)]
    right.kind == "placemarker" && return [left]
    spelling = left.spelling * right.spelling
    kind = single_token(spelling)
    if kind !== nothing
        return [PPToken(kind,spelling,left.line,left.space,intersect(left.hide,right.hide))]
    end
    expansion_error!(expander,context,token,"pasting \"$(left.spelling)\" and \"$(right.spelling)\" does not give a valid preprocessing token")
    [left,token_with(right;space=false)]
end
function substitute!(expander,definition,raw,token,hide,context)
    replacement = definition.replacement
    items = Union{PPToken,Vector{PPToken}}[]
    expanded = Dict{String,Vector{PPToken}}()
    index = 1
    while index <= length(replacement)
        current = replacement[index]
        if current.spelling == "#" && definition.parameters !== nothing
            push!(items,[stringize(raw[replacement[index+1].spelling],current)])
            index += 2
            continue
        elseif current.spelling == "##"
            push!(items,current)
        elseif current.kind == "identifier" && haskey(raw,current.spelling)
            adjacent = (index > 1 && replacement[index-1].spelling == "##") || (index < length(replacement) && replacement[index+1].spelling == "##")
            if adjacent
                sequence = raw[current.spelling]
            else
                if !haskey(expanded,current.spelling)
                    expanded[current.spelling] = expand!(expander,raw[current.spelling],context)
                end
                sequence = expanded[current.spelling]
            end
            if isempty(sequence)
                push!(items,[PPToken("placemarker","",current.line,current.space)])
            else
                push!(items,[token_with(sequence[1];space=current.space);sequence[2:end]])
            end
        else
            push!(items,[current])
        end
        index += 1
    end
    pasted,index = PPToken[],1
    while index <= length(items)
        item = items[index]
        if item isa PPToken
            left = pop!(pasted)
            right = items[index+1]
            right isa PPToken && (right = [right])
            append!(pasted,paste_tokens!(expander,left,right[1],token,context))
            append!(pasted,right[2:end])
            index += 2
        else
            append!(pasted,item)
            index += 1
        end
    end
    result,carry_space = PPToken[],false
    for current in pasted
        if current.kind == "placemarker"
            carry_space |= current.space
        else
            push!(result,token_with(current;line=token.line,space=current.space || carry_space,hide=union(current.hide,hide)))
            carry_space = false
        end
    end
    isempty(result) || (result[1] = token_with(result[1];space=token.space))
    result
end
function expand!(expander,sequence,context)
    pending,result = reverse(sequence),PPToken[]
    while !isempty(pending)
        token = pop!(pending)
        if token.kind != "identifier" || token.spelling in token.hide
            push!(result,token)
            continue
        elseif token.spelling in BUILTINS
            push!(result,expand_builtin!(expander,token,context))
            continue
        end
        definition = get(expander.macros,token.spelling,nothing)
        if definition === nothing || (definition.parameters !== nothing && (isempty(pending) || pending[end].spelling != "("))
            push!(result,token)
            continue
        end
        raw = Dict{String,Vector{PPToken}}()
        hide = union(token.hide,Set([definition.name]))
        if definition.parameters !== nothing
            collected = collect_arguments!(expander,pending,definition,token,context)
            if collected === nothing
                push!(result,token)
                continue
            end
            raw,consumed,closing = collected
            resize!(pending,length(pending)-consumed)
            hide = union(intersect(token.hide,closing.hide),Set([definition.name]))
        end
        replacement = substitute!(expander,definition,raw,token,hide,context)
        definition.expanded += 1
        if isempty(replacement) && token.space && !isempty(pending)
            pending[end] = token_with(pending[end];space=true)
        end
        append!(pending,reverse(replacement))
    end
    result
end
