is_letter(character) = 'A' <= character <= 'Z' || 'a' <= character <= 'z'
struct Hyphenation
    words::Dict{String,Vector{Int}}
    left_min::Int
    right_min::Int
end
function Hyphenation(lines,additions,left_min,right_min)
    words = Dict{String,Vector{Int}}()
    for spelling in vcat(lines,additions)
        parts = split(spelling,'-')
        position = 0
        points = Int[]
        for part in parts[1:end-1]
            position += length(part)
            push!(points,position)
        end
        words[join(parts)] = points
    end
    Hyphenation(words,left_min,right_min)
end
function split_points(dictionary,word)
    points = Dict{Int,Bool}()
    first,last = 1,length(word)
    while first <= last && !is_letter(word[first])
        first += 1
    end
    while last >= first && !is_letter(word[last])
        last -= 1
    end
    core = word[first:last]
    if !isempty(core) && all(is_letter,core)
        for position in get(dictionary.words,lowercase(core),Int[])
            if position >= dictionary.left_min && length(core)-position >= dictionary.right_min
                points[first-1+position] = true
            end
        end
    end
    for position in 2:length(word)-1
        word[position] == '-' && is_letter(word[position-1]) && is_letter(word[position+1]) && (points[position]=false)
    end
    sort(collect(points),by=pair->pair[1])
end
