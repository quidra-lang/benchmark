module Matcher

wildcard(element) = element in ("*", "#") || startswith(element, "@")

function wordfits(element, word, groups)
    element == "#" && return true
    startswith(element, "@") && return word in get(groups, element[2:end], Set{String}())
    return element == word
end

function matchpattern(pattern, words, groups)
    ends = Int[]
    function visit(position, start)
        position > length(pattern) && return start > length(words)
        element = pattern[position]
        candidates = element == "*" ? (start:length(words) + 1) :
            start <= length(words) && wordfits(element, words[start], groups) ? (start + 1:start + 1) : (1:0)
        for finish in candidates
            push!(ends, finish)
            visit(position + 1, finish) && return true
            pop!(ends)
        end
        return false
    end
    visit(1, 1) || return nothing
    bindings = Vector{String}[]
    start = 1
    for (element, finish) in zip(pattern, ends)
        wildcard(element) && push!(bindings, words[start:finish - 1])
        start = finish
    end
    return bindings
end

function elementcovers(element, other, groups)
    element == "#" && return other != "*"
    if startswith(element, "@")
        members = groups[element[2:end]]
        return startswith(other, "@") ? issubset(groups[other[2:end]], members) : other in members
    end
    return element == other
end

function covers(earlier, later, groups)
    function visit(position, start)
        position > length(earlier) && return start > length(later)
        if earlier[position] == "*"
            return any(finish -> visit(position + 1, finish), start:length(later) + 1)
        end
        return start <= length(later) && elementcovers(earlier[position], later[start], groups) && visit(position + 1, start + 1)
    end
    return visit(1, 1)
end

end
