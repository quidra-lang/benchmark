is_valid_word(text) = 3 <= length(text) <= 15 && all('A' <= letter <= 'Z' for letter in text)
function is_valid_integer(text, low, high)
    isempty(text) || startswith(text, '0') || length(text) > length(string(high)) || !all('0' <= digit <= '9' for digit in text) ? false : low <= parse(Int, text) <= high
end
function word_line_error(line)
    count(==(' '), line) == 1 || return "bad format"
    word, score = split(line, ' '; keepempty=true)
    is_valid_word(word) || return "bad word"
    is_valid_integer(score, 1, 100) ? nothing : "bad score"
end
function clue_line_error(line)
    count(==('|'), line) == 1 || return "bad format"
    word, clue = split(line, '|'; keepempty=true)
    is_valid_word(word) || return "bad word"
    1 <= length(clue) <= 60 && !startswith(clue, ' ') && !endswith(clue, ' ') ? nothing : "bad clue"
end
matches(word, pattern) = all(mark == '.' || mark == letter for (letter, mark) in zip(word, pattern))

struct Word
    text::String
    letters::Vector{Char}
    score::Int
end
struct WordIndex
    words::Vector{Word}
    lookup::Dict{String,Int}
    by_length::Dict{Int,Vector{Int}}
    by_letter::Dict{Tuple{Int,Int,Char},Vector{Int}}
end
function WordIndex(scores)
    ranked = sort(collect(keys(scores)); by=word -> (-scores[word], word))
    words, lookup = Word[], Dict{String,Int}()
    by_length, by_letter = Dict{Int,Vector{Int}}(), Dict{Tuple{Int,Int,Char},Vector{Int}}()
    for (id, text) in enumerate(ranked)
        letters = collect(text)
        lookup[text] = id
        push!(get!(by_length, length(letters), Int[]), id)
        for (position, letter) in enumerate(letters)
            push!(get!(by_letter, (length(letters), position, letter), Int[]), id)
        end
        push!(words, Word(text, letters, scores[text]))
    end
    WordIndex(words, lookup, by_length, by_letter)
end
function candidates(index, pattern, minimum, used)
    pool = get(index.by_length, length(pattern), Int[])
    for (position, mark) in enumerate(pattern)
        mark == '.' && continue
        bucket = get(index.by_letter, (length(pattern), position, mark), Int[])
        length(bucket) < length(pool) && (pool = bucket)
    end
    result = Int[]
    for id in pool
        index.words[id].score < minimum && break
        !(id in used) && matches(index.words[id].letters, pattern) && push!(result, id)
    end
    result
end
