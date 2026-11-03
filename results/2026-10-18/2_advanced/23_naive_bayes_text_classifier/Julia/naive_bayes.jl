struct TrainingCounts
    class_count::Int
    vocabulary_size::Int
    document_total::Int
    documents::Vector{Int}
    occurrences::Vector{Vector{Int}}
    containing::Vector{Vector{Int}}
    totals::Vector{Int}
    total::Int
    term_totals::Vector{Int}
end
function TrainingCounts(sequences::Vector{Vector{Int}}, labels::Vector{Int}, class_count::Int, vocabulary_size::Int)
    documents = zeros(Int, class_count)
    occurrences = [zeros(Int, vocabulary_size) for _ in 1:class_count]
    containing = [zeros(Int, vocabulary_size) for _ in 1:class_count]
    for (sequence, label) in zip(sequences, labels)
        documents[label] += 1
        for term in sequence
            occurrences[label][term] += 1
        end
        for term in first_occurrences(sequence)
            containing[label][term] += 1
        end
    end
    totals = sum.(occurrences)
    term_totals = [sum(row[term] for row in occurrences) for term in 1:vocabulary_size]
    TrainingCounts(class_count, vocabulary_size, length(sequences), documents, occurrences, containing, totals, sum(totals), term_totals)
end
struct Prediction
    label::Int
    score::Float64
    ranking::Vector{Int}
    scores::Vector{Float64}
    probabilities::Vector{Float64}
    normalizer::Float64
    margin::Float64
end
function posterior(scores::Vector{Float64})
    ranking = sortperm(eachindex(scores); by = label -> (-scores[label], label))
    label = ranking[1]
    best = scores[label]
    exponentials = [exp(score - best) for score in scores]
    normalizer = 0.0
    for value in exponentials
        normalizer += value
    end
    probabilities = [value / normalizer for value in exponentials]
    Prediction(label, probabilities[label], ranking, scores, probabilities, normalizer, best - scores[ranking[2]])
end
smoothed_log(count::Int, total::Int, alpha::Int, outcomes::Int) = log((100 * count + alpha) / (100 * total + alpha * outcomes))
struct NaiveBayes
    kind::Int
    priors::Vector{Float64}
    base::Vector{Float64}
    weights::Vector{Vector{Float64}}
end
function train_model(kind::Int, counts::TrainingCounts, alpha::Int)
    priors = [log(value / counts.document_total) for value in counts.documents]
    base = zeros(counts.class_count)
    weights = [zeros(counts.vocabulary_size) for _ in 1:counts.class_count]
    for label in 1:counts.class_count, term in 1:counts.vocabulary_size
        if kind == 1
            weights[label][term] = smoothed_log(counts.occurrences[label][term], counts.totals[label], alpha, counts.vocabulary_size)
        elseif kind == 2
            present = smoothed_log(counts.containing[label][term], counts.documents[label], alpha, 2)
            absent = smoothed_log(counts.documents[label] - counts.containing[label][term], counts.documents[label], alpha, 2)
            base[label] += absent
            weights[label][term] = present - absent
        else
            weights[label][term] = -smoothed_log(counts.term_totals[term] - counts.occurrences[label][term], counts.total - counts.totals[label], alpha, counts.vocabulary_size)
        end
    end
    NaiveBayes(kind, priors, base, weights)
end
function predict(model::NaiveBayes, sequence::Vector{Int})
    selected_terms = model.kind == 2 ? first_occurrences(sequence) : sequence
    scores = Float64[]
    for label in eachindex(model.priors)
        score = model.base[label]
        for term in selected_terms
            score += model.weights[label][term]
        end
        push!(scores, score + model.priors[label])
    end
    posterior(scores)
end
