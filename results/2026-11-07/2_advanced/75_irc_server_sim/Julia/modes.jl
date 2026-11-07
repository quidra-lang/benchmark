function channel_items(mode,arguments)
    items,sign,position = Tuple{Char,Char,Union{Nothing,String}}[],'+',1
    for c in mode
        if c in "+-"
            sign = c
            continue
        end
        argument = nothing
        if c in "ovbk" || (c=='l' && sign=='+')
            if position<=length(arguments)
                argument = arguments[position]
                position += 1
            end
        end
        if c=='k' && sign=='-'
            argument = "*"
        elseif c=='l' && sign=='+'
            if isnothing(argument) || !is_digits(argument) || length(argument)>4 || parse(Int,argument)<1
                argument = nothing
            end
        end
        push!(items,(sign,c,argument))
    end
    items
end
function change_string(changes)
    mode,arguments,previous = "",String[],nothing
    for (sign,c,argument) in changes
        if sign!=previous
            mode *= sign
            previous = sign
        end
        mode *= c
        !isnothing(argument) && push!(arguments,argument)
    end
    mode*join([" "*a for a in arguments])
end
