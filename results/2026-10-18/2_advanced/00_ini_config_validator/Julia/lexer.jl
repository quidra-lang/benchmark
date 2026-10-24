const Origin = Tuple{String,Int}
const Diagnostic = Tuple{String,Int,String,String}
const LITERAL_DOLLAR = '\x01'
const ESCAPES = Dict('\\' => '\\', '"' => '"', 'n' => '\n', 't' => '\t', '$' => LITERAL_DOLLAR)

struct LogicalLine
    number::Int
    segments::Vector{String}
    error::Union{Nothing,Tuple{String,String}}
end

space_trim(text) = String(strip(text, [' ']))

function logical_lines(physical)
    lines = LogicalLine[]
    index = 1
    while index <= length(physical)
        number = index
        source = physical[index]
        index += 1
        segments = String[]
        current = IOBuffer()
        quoted = false
        error = nothing
        position = 1
        while position <= lastindex(source)
            char = source[position]
            if char == '\\' && position == lastindex(source)
                source = String(lstrip(physical[index], [' ']))
                index += 1
                position = 1
            elseif quoted && char == '\\'
                follower = source[position + 1]
                if haskey(ESCAPES, follower)
                    print(current, ESCAPES[follower])
                elseif error === nothing
                    error = ("E_ESCAPE", "invalid escape sequence \\" * string(follower))
                end
                position += 2
            elseif char == '"'
                push!(segments, String(take!(current)))
                quoted = !quoted
                position += 1
            elseif !quoted && char in (';', '#')
                break
            else
                print(current, char)
                position += 1
            end
        end
        if quoted && error === nothing
            error = ("E_UNTERMINATED", "unterminated string")
        end
        push!(segments, String(take!(current)))
        push!(lines, LogicalLine(number, segments, error))
    end
    lines
end
