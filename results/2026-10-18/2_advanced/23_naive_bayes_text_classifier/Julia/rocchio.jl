function vector_length(values::Vector{Float64})
    total = 0.0
    for value in values
        total += value * value
    end
    sqrt(total)
end
function tfidf_vector(sequence::Vector{Int}, idf::Vector{Float64})
    frequencies = zeros(Int, length(idf))
    for term in sequence
        frequencies[term] += 1
    end
    [frequencies[term] * idf[term] for term in eachindex(idf)]
end
struct Rocchio
    idf::Vector{Float64}
    centroids::Vector{Vector{Float64}}
    lengths::Vector{Float64}
end
function Rocchio(sequences::Vector{Vector{Int}}, labels::Vector{Int}, class_count::Int, frequencies::Vector{Int})
    idf = [log(length(sequences) / frequency) for frequency in frequencies]
    sums = [zeros(length(frequencies)) for _ in 1:class_count]
    documents = zeros(Int, class_count)
    for (sequence, label) in zip(sequences, labels)
        documents[label] += 1
        vector = tfidf_vector(sequence, idf)
        norm = vector_length(vector)
        if norm > 0
            for term in eachindex(vector)
                sums[label][term] += vector[term] / norm
            end
        end
    end
    centroids = [[value / documents[label] for value in row] for (label, row) in enumerate(sums)]
    Rocchio(idf, centroids, vector_length.(centroids))
end
function predict(model::Rocchio, sequence::Vector{Int})
    vector = tfidf_vector(sequence, model.idf)
    norm = vector_length(vector)
    similarities = Float64[]
    for (centroid, centroid_norm) in zip(model.centroids, model.lengths)
        if norm > 0 && centroid_norm > 0
            product = 0.0
            for term in eachindex(vector)
                product += vector[term] * centroid[term]
            end
            push!(similarities, product / (norm * centroid_norm))
        else
            push!(similarities, 0.0)
        end
    end
    ranking = sortperm(eachindex(similarities); by = label -> (-similarities[label], label))
    label = ranking[1]
    Prediction(label, similarities[label], ranking, similarities, Float64[], 0.0, 0.0)
end
