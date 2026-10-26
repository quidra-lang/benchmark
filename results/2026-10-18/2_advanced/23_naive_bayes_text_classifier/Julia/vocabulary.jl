function first_occurrences(sequence::Vector{Int})
    seen = Set{Int}()
    result = Int[]
    for term in sequence
        if !(term in seen)
            push!(seen, term)
            push!(result, term)
        end
    end
    result
end
struct RankedTerm
    term::String
    frequency::Int
    score::Float64
    best_class::Int
end
struct Vocabulary
    term_count::Int
    candidate_count::Int
    ranking::Vector{RankedTerm}
    terms::Vector{String}
    index::Dict{String,Int}
    frequencies::Vector{Int}
end
vocabulary_size(vocabulary::Vocabulary) = length(vocabulary.terms)
function Vocabulary(sequences::Vector{Vector{String}}, labels::Vector{Int}, class_count::Int, min_df::Int, size::Int)
    counts = Dict{String,Vector{Int}}()
    class_sizes = zeros(Int, class_count)
    for (sequence, label) in zip(sequences, labels)
        class_sizes[label] += 1
        for term in Set(sequence)
            row = get!(() -> zeros(Int, class_count), counts, term)
            row[label] += 1
        end
    end
    ranking = RankedTerm[]
    total = length(sequences)
    for term in sort!(collect(keys(counts)))
        row = counts[term]
        frequency = sum(row)
        frequency < min_df && continue
        best_class, best_score = 1, -1.0
        for label in 1:class_count
            a = row[label]
            b = frequency - a
            c = class_sizes[label] - a
            e = total - class_sizes[label] - b
            difference = a * e - b * c
            numerator = total * difference * difference
            denominator = frequency * (total - frequency) * class_sizes[label] * (total - class_sizes[label])
            score = denominator == 0 ? 0.0 : numerator / denominator
            if score > best_score
                best_class, best_score = label, score
            end
        end
        push!(ranking, RankedTerm(term, frequency, best_score, best_class))
    end
    candidate_count = length(ranking)
    sort!(ranking; by = entry -> (-entry.score, entry.term))
    if size > 0 && length(ranking) > size
        resize!(ranking, size)
    end
    selected_terms = sort!([entry.term for entry in ranking])
    index = Dict{String,Int}(term => i for (i, term) in enumerate(selected_terms))
    frequencies = zeros(Int, length(selected_terms))
    for entry in ranking
        frequencies[index[entry.term]] = entry.frequency
    end
    Vocabulary(length(counts), candidate_count, ranking, selected_terms, index, frequencies)
end
encode(vocabulary::Vocabulary, sequence::Vector{String}) = [vocabulary.index[term] for term in sequence if haskey(vocabulary.index, term)]
