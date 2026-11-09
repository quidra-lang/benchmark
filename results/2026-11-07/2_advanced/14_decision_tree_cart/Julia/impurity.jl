function class_counts(rows, count)
    result = zeros(Int, count)
    for row in rows
        result[row.label] += 1
    end
    result
end

square_sum(counts) = sum(count * count for count in counts)
majority(counts) = findmax(counts)[2]
error_count(counts) = sum(counts) - maximum(counts)
evaluation_value(left, right) = (square_sum(left) * sum(right) + square_sum(right) * sum(left), sum(left) * sum(right))
is_greater(first, second) = first[1] * second[2] > second[1] * first[2]
improves(value, counts) = value[1] * sum(counts) > square_sum(counts) * value[2]
impurity_decrease(counts, left, right) = square_sum(left) / sum(left) + square_sum(right) / sum(right) - square_sum(counts) / sum(counts)
