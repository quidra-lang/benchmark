module Substitution

import ..Scoring

export apply, inverse

function inverse(value::Int)
    for i in 1:25
        if mod(value * i, 26) == 1
            return i
        end
    end
    error("non-invertible affine key")
end

function apply(text::AbstractString, cipher::String, key::String, encrypt::Bool)
    a, b = 1, 0
    if cipher == "caesar"
        b = parse(Int, key)
    elseif cipher == "affine"
        pieces = split(key, ',')
        a, b = parse(Int, pieces[1]), parse(Int, pieces[2])
    end
    inv = cipher == "affine" ? inverse(a) : 1
    previous = Int[]
    result = Char[]
    count = 0
    for c in text
        if !Scoring.isletterascii(c)
            push!(result, c)
            continue
        end
        x, shift = Scoring.value(c), 0
        if cipher == "vigenere"
            shift = Scoring.value(key[mod(count, length(key)) + 1])
        elseif cipher == "autokey"
            shift = count < length(key) ? Scoring.value(key[count + 1]) :
                previous[count - length(key) + 1]
        end
        y = if cipher == "caesar"
            mod(x + (encrypt ? b : -b), 26)
        elseif cipher == "affine"
            encrypt ? mod(a * x + b, 26) : mod(inv * (x - b), 26)
        else
            mod(x + (encrypt ? shift : -shift), 26)
        end
        push!(previous, encrypt ? x : y)
        push!(result, Char(Int('a' <= c <= 'z' ? 'a' : 'A') + y))
        count += 1
    end
    return join(result)
end

end
