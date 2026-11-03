function correlation(first, second)
    mean_a, mean_b = sequential_sum(first) / length(first), sequential_sum(second) / length(second)
    cross = sequential_sum((a - mean_a) * (b - mean_b) for (a, b) in zip(first, second))
    spread_a = sequential_sum((a - mean_a) * (a - mean_a) for a in first)
    spread_b = sequential_sum((b - mean_b) * (b - mean_b) for b in second)
    cross / sqrt(spread_a * spread_b)
end

function contingency_table(first, second, rows, columns)
    table = zeros(Int, rows, columns)
    for (a, b) in zip(first, second)
        table[a, b] += 1
    end
    table
end

pair_count(count) = count * (count - 1) ÷ 2

function adjusted_rand_index(table)
    count = sum(table)
    same = sum(pair_count(cell) for cell in table)
    row_pairs = sum(pair_count(sum(table[g, :])) for g in axes(table, 1))
    column_pairs = sum(pair_count(sum(table[:, t])) for t in axes(table, 2))
    total = pair_count(count)
    numerator = 2 * (total * same - row_pairs * column_pairs)
    denominator = total * (row_pairs + column_pairs) - 2 * row_pairs * column_pairs
    denominator == 0 ? 1 // 1 : numerator // denominator
end

function silhouette_values(partition, groups, delta)
    sizes = zeros(Int, groups)
    for number in partition
        sizes[number] += 1
    end
    values = Float64[]
    for (i, own) in enumerate(partition)
        if sizes[own] == 1
            push!(values, 0.0)
            continue
        end
        sums = zeros(groups)
        for (j, other) in enumerate(partition)
            j != i && (sums[other] += delta[i, j])
        end
        inner = sums[own] / (sizes[own] - 1)
        outer = minimum(sums[g] / sizes[g] for g in 1:groups if g != own)
        push!(values, (outer - inner) / max(inner, outer))
    end
    values
end
