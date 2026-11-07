module Scoring

export isletterascii, value, upper, letters, groups, monogram, bigram, readweights

isletterascii(c::Char) = 'A' <= c <= 'Z' || 'a' <= c <= 'z'
value(c::Char) = 'a' <= c <= 'z' ? Int(c) - Int('a') : Int(c) - Int('A')
upper(v::Integer) = Char(Int('A') + v)

function letters(text::AbstractString)
    return join(upper(value(c)) for c in text if isletterascii(c))
end

function groups(text::AbstractString)
    chars = collect(text)
    pieces = [join(chars[i:min(i + 4, length(chars))]) for i in 1:5:length(chars)]
    return [join(pieces[i:min(i + 9, length(pieces))], " ") for i in 1:10:length(pieces)]
end

function monogram(text::AbstractString, weights::Vector{Int})
    result = 0
    for c in text
        result += weights[value(c) + 1]
    end
    return result
end

function bigram(text::AbstractString, weights::Vector{Vector{Int}})
    chars = collect(text)
    result = 0
    for i in 2:length(chars)
        result += weights[value(chars[i - 1]) + 1][value(chars[i]) + 1]
    end
    return result
end

function readweights(path::AbstractString)
    lines = readlines(path)
    mono = parse.(Int, split(lines[2], ' '))
    bi = [parse.(Int, split(lines[i + 3], ' ')) for i in 1:26]
    return mono, bi
end

end
