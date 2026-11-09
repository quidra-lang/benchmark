module Responder

using ..ScriptLoader: isreference

function reflect(words, substitutions)
    result = String[]
    for word in words
        append!(result, get(substitutions, word, [word]))
    end
    return result
end

binding(bindings, number) = 1 <= number <= length(bindings) ? bindings[number] : String[]

function reply(template, bindings, substitutions)
    out = IOBuffer()
    index = 1
    while index <= ncodeunits(template)
        if index + 2 <= ncodeunits(template) && isreference(template[index:index + 2])
            number = Int(template[index + 1] - '0')
            print(out, join(reflect(binding(bindings, number), substitutions), " "))
            index += 3
        else
            print(out, template[index])
            index += 1
        end
    end
    result = join(split(String(take!(out)), ' '; keepempty=false), " ")
    return !isempty(result) && 'a' <= result[1] <= 'z' ? uppercase(result[1:1]) * result[2:end] : result
end

function restate(arguments, bindings)
    result = String[]
    for argument in arguments
        if isreference(argument)
            append!(result, binding(bindings, Int(argument[2] - '0')))
        else
            push!(result, argument)
        end
    end
    return result
end

function wrap(text)
    words = split(text, ' '; keepempty=false)
    lines = ["ELIZA: " * words[1]]
    for word in words[2:end]
        if ncodeunits(lines[end]) + 1 + ncodeunits(word) <= 72
            lines[end] *= " " * word
        else
            push!(lines, "       " * word)
        end
    end
    return lines
end

end
