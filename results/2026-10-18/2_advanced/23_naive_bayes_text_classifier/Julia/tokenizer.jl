struct Tokens
    raw_count::Int
    stopword_count::Int
    short_count::Int
    words::Vector{String}
    bigrams::Vector{String}
    combined::Vector{String}
end
function Tokens(text::AbstractString, stopwords::Set{String})
    raw = String[]
    word = UInt8[]
    for byte in vcat(collect(codeunits(text)), UInt8[32])
        if 65 <= byte <= 90
            push!(word, byte + UInt8(32))
        elseif 97 <= byte <= 122 || 48 <= byte <= 57
            push!(word, byte)
        elseif !isempty(word)
            push!(raw, String(copy(word)))
            empty!(word)
        end
    end
    stopword_count = short_count = 0
    words = String[]
    for word in raw
        if word in stopwords
            stopword_count += 1
        elseif ncodeunits(word) == 1
            short_count += 1
        else
            push!(words, word)
        end
    end
    bigrams = [words[i] * "_" * words[i + 1] for i in 1:(length(words) - 1)]
    Tokens(length(raw), stopword_count, short_count, words, bigrams, vcat(words, bigrams))
end
terms(tokens::Tokens, use_bigrams::Bool) = use_bigrams ? tokens.combined : tokens.words
