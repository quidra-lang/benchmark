struct Split
    attribute::Attribute
    point::Int
end

struct Surrogate
    split::Split
    left::Bool
    score::Int
end

struct Candidate
    split::Split
    left::Vector{Int}
    right::Vector{Int}
end

mutable struct Node
    number::Int
    depth::Int
    counts::Vector{Int}
    size::Int
    prediction::Int
    errors::Int
    split::Union{Nothing,Split}
    surrogates::Vector{Surrogate}
    default_left::Bool
    left::Union{Nothing,Node}
    right::Union{Nothing,Node}
end

struct TreeBuilder
    attributes::Vector{Attribute}
    class_count::Int
    settings::Settings
end

half_text(value) = "$(div(value, 2)).$(5 * mod(value, 2))"
goes_left(split::Split, value) = split.attribute.integer ? 2 * value <= split.point : value == split.point
candidate_value(candidate) = evaluation_value(candidate.left, candidate.right)

function split_text(split, left=true)
    a = split.attribute
    a.integer ? "$(a.name) $(left ? "<=" : ">") $(half_text(split.point))" : "$(a.name) $(left ? "=" : "!=") $(a.values[split.point])"
end

function candidates(attribute, rows, labels, count)
    groups = Dict{Int,Vector{Int}}()
    total = zeros(Int, count)
    for (row, label) in zip(rows, labels)
        value = row.values[attribute.index]
        get!(groups, value, zeros(Int, count))[label] += 1
        total[label] += 1
    end
    result = Candidate[]
    if attribute.integer
        ordered = sort(collect(keys(groups)))
        left = zeros(Int, count)
        for index in 1:length(ordered)-1
            left = left + groups[ordered[index]]
            push!(result, Candidate(Split(attribute, ordered[index] + ordered[index + 1]), left, total - left))
        end
    elseif length(groups) > 1
        for point in eachindex(attribute.values)
            haskey(groups, point) && push!(result, Candidate(Split(attribute, point), groups[point], total - groups[point]))
        end
    end
    result
end

function best_split(builder, rows, attributes=builder.attributes)
    best = nothing
    labels = [row.label for row in rows]
    for attribute in attributes, candidate in candidates(attribute, rows, labels, builder.class_count)
        min(sum(candidate.left), sum(candidate.right)) < builder.settings.min_samples_leaf && continue
        if isnothing(best) || is_greater(candidate_value(candidate), candidate_value(best))
            best = candidate
        end
    end
    best
end

function find_surrogates(builder, rows, split)
    directions = [goes_left(split, row.values[split.attribute.index]) ? 1 : 2 for row in rows]
    size = length(rows)
    largest = max(count(==(1), directions), count(==(2), directions))
    chosen = Surrogate[]
    for attribute in builder.attributes
        attribute.index == split.attribute.index && continue
        best = nothing
        for candidate in candidates(attribute, rows, directions, 2)
            agreement = candidate.left[1] + candidate.right[2]
            surrogate = Surrogate(candidate.split, agreement >= size - agreement, max(agreement, size - agreement))
            if isnothing(best) || surrogate.score > best.score
                best = surrogate
            end
        end
        !isnothing(best) && best.score > largest && push!(chosen, best)
    end
    sort!(chosen; by=s -> (-s.score, s.split.attribute.index))
    chosen[1:min(end, builder.settings.max_surrogates)]
end

function grow(builder, rows, number=1, depth=0)
    counts = class_counts(rows, builder.class_count)
    node = Node(number, depth, counts, length(rows), majority(counts), error_count(counts), nothing, Surrogate[], true, nothing, nothing)
    (maximum(counts) == node.size || depth == builder.settings.max_depth || node.size < builder.settings.min_samples_split) && return node
    best = best_split(builder, rows)
    (isnothing(best) || !improves(candidate_value(best), counts)) && return node
    split = best.split
    left = [row for row in rows if goes_left(split, row.values[split.attribute.index])]
    right = [row for row in rows if !goes_left(split, row.values[split.attribute.index])]
    node.split = split
    node.surrogates = find_surrogates(builder, rows, split)
    node.default_left = length(left) >= length(right)
    node.left = grow(builder, left, 2 * number, depth + 1)
    node.right = grow(builder, right, 2 * number + 1, depth + 1)
    node
end
