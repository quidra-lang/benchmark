module Playfair

export square, valid, prepare, apply

function square(key::AbstractString)
    seen = Set{Char}()
    result = Char[]
    for c in replace(uppercase(key), 'J' => 'I') * "ABCDEFGHIKLMNOPQRSTUVWXYZ"
        if !(c in seen)
            push!(seen, c)
            push!(result, c)
        end
    end
    return join(result)
end

function valid(text::AbstractString)
    chars = collect(replace(text, 'J' => 'I'))
    isodd(length(chars)) && return false
    for i in 1:2:length(chars)
        chars[i] == chars[i + 1] && return false
    end
    return true
end

function prepare(text::AbstractString)
    chars = collect(replace(text, 'J' => 'I'))
    pairs = Char[]
    i = 1
    while i <= length(chars)
        first = chars[i]
        if i < length(chars) && chars[i + 1] != first
            second = chars[i + 1]
            i += 2
        else
            second = first == 'X' ? 'Q' : 'X'
            i += 1
        end
        push!(pairs, first, second)
    end
    return join(pairs)
end

function apply(text::AbstractString, key::String, encrypt::Bool)
    board = collect(square(key))
    chars = collect(encrypt ? prepare(text) : replace(text, 'J' => 'I'))
    delta = encrypt ? 1 : 4
    result = Char[]
    for i in 1:2:length(chars)
        ai = findfirst(==(chars[i]), board) - 1
        bi = findfirst(==(chars[i + 1]), board) - 1
        ar, ac = divrem(ai, 5)
        br, bc = divrem(bi, 5)
        if ar == br
            ac, bc = mod(ac + delta, 5), mod(bc + delta, 5)
        elseif ac == bc
            ar, br = mod(ar + delta, 5), mod(br + delta, 5)
        else
            ac, bc = bc, ac
        end
        push!(result, board[5 * ar + ac + 1], board[5 * br + bc + 1])
    end
    return join(result)
end

end
