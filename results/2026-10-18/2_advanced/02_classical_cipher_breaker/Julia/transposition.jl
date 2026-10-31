module Transposition

export rail, railfence, columnorder, rankstring, columnar

function rail(position::Int, rails::Int)
    cycle = 2 * rails - 2
    remainder = mod(position, cycle)
    return min(remainder, cycle - remainder)
end

function railfence(text::AbstractString, rails::Int, encrypt::Bool)
    chars = collect(text)
    order = sort(collect(eachindex(chars)), by=i -> (rail(i - 1, rails), i))
    result = Vector{Char}(undef, length(chars))
    for (index, position) in enumerate(order)
        if encrypt
            result[index] = chars[position]
        else
            result[position] = chars[index]
        end
    end
    return join(result)
end

function columnorder(key::AbstractString)
    chars = collect(key)
    return sort(collect(eachindex(chars)), by=i -> (chars[i], i))
end

function rankstring(key::AbstractString)
    positions = columnorder(key)
    ranks = Vector{Char}(undef, length(positions))
    for (rank, column) in enumerate(positions)
        ranks[column] = Char(Int('0') + rank)
    end
    return join(ranks)
end

function columnar(text::AbstractString, key::String, encrypt::Bool)
    chars = collect(text)
    result = Vector{Char}(undef, length(chars))
    pointer = 1
    for column in columnorder(key)
        for index in column:length(key):length(chars)
            if encrypt
                result[pointer] = chars[index]
            else
                result[index] = chars[pointer]
            end
            pointer += 1
        end
    end
    return join(result)
end

end
