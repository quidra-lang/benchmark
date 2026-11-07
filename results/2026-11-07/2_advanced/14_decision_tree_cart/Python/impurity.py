def class_counts(rows, class_count):
    counts = [0] * class_count
    for row in rows:
        counts[row.label] += 1
    return counts


def square_sum(counts):
    return sum(count * count for count in counts)


def majority(counts):
    return counts.index(max(counts))


def error_count(counts):
    return sum(counts) - max(counts)


def evaluation_value(left_counts, right_counts):
    left_size = sum(left_counts)
    right_size = sum(right_counts)
    numerator = square_sum(left_counts) * right_size + square_sum(right_counts) * left_size
    return numerator, left_size * right_size


def is_greater(first, second):
    return first[0] * second[1] > second[0] * first[1]


def improves(value, counts):
    return value[0] * sum(counts) > square_sum(counts) * value[1]


def impurity_decrease(counts, left_counts, right_counts):
    return (
        square_sum(left_counts) / sum(left_counts)
        + square_sum(right_counts) / sum(right_counts)
        - square_sum(counts) / sum(counts)
    )
