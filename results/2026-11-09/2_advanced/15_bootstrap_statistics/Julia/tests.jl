function position_choices(total, size)
    result = Vector{Int}[]
    function choose(prefix, first)
        if length(prefix) == size
            push!(result, prefix)
            return
        end
        remaining = size - length(prefix)
        for next in first:total-remaining+1
            choose([prefix; next], next + 1)
        end
    end
    choose(Int[], 1)
    result
end

function reduced_fraction(numerator, denominator)
    divisor = gcd(numerator, denominator)
    div(numerator, divisor), div(denominator, divisor)
end

contrast(first_total, first_size, second_total, second_size) = second_size * first_total - first_size * second_total

function value_counts(values)
    counts = Dict{Int,Int}()
    for value in values
        counts[value] = get(counts, value, 0) + 1
    end
    [(value, counts[value]) for value in sort(collect(keys(counts)))]
end

function doubled_ranks(values)
    ranks = Dict{Int,Int}()
    smaller = 0
    for (value, count) in value_counts(values)
        ranks[value] = 2 * smaller + count + 1
        smaller += count
    end
    [ranks[value] for value in values]
end

function split_list(items, sizes)
    result = Vector{eltype(items)}[]
    start = 0
    for size in sizes
        push!(result, items[start+1:start+size])
        start += size
    end
    result
end

function sums_of_squares(samples)
    count = sum(length, samples)
    grand_mean = sum(sum, samples) / (100 * count)
    between = within = 0.0
    for sample in samples
        center = mean(sample)
        between += length(sample) * ((center - grand_mean) * (center - grand_mean))
        squares = 0.0
        for value in sample
            deviation = value / 100 - center
            squares += deviation * deviation
        end
        within += squares
    end
    between, within
end

f_statistic(between, within, groups, total) = between / (groups - 1) / (within / (total - groups))

function h_statistic(rank_sums, sizes, correction)
    total = sum(sizes)
    value = sequential_sum(rank * rank / (4 * size) for (rank, size) in zip(rank_sums, sizes))
    (12 * value / (total * (total + 1)) - 3 * (total + 1)) / correction
end
