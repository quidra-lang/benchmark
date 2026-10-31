sequential_sum(values) = foldl(+, values; init=0.0)
mean(values) = sum(values) / (100 * length(values))

function doubled_median(values)
    ordered, count = sort(values), length(values)
    ordered[div(count + 1, 2)] + ordered[div(count + 2, 2)]
end

median(values) = doubled_median(values) / 200
trim_count(count) = div(count, 10)

function trimmed_mean(values)
    ordered, count = sort(values), length(values)
    trim = trim_count(count)
    sum(ordered[trim+1:count-trim]) / (100 * (count - 2 * trim))
end

function deviations(values)
    center = mean(values)
    [value / 100 - center for value in values]
end

sd(values) = sqrt(sequential_sum(value * value for value in deviations(values)) / (length(values) - 1))

function central_moments(values)
    second = third = fourth = 0.0
    for value in deviations(values)
        second += value * value
        third += value * value * value
        fourth += value * value * value * value
    end
    count = length(values)
    second / count, third / count, fourth / count
end

mad(values) = doubled_median([abs(2 * value - doubled_median(values)) for value in values]) / 400

function quantile_numerator(values, percent)
    ordered = sort(values)
    position = (length(ordered) - 1) * percent
    index, fraction = divrem(position, 100)
    fraction == 0 ? 100 * ordered[index + 1] : 100 * ordered[index + 1] + fraction * (ordered[index + 2] - ordered[index + 1])
end

function winsorized(values)
    ordered, trim = sort(values), trim_count(length(values))
    [clamp(value, ordered[trim + 1], ordered[end - trim]) for value in values]
end

mean_difference(x, y) = (length(y) * sum(x) - length(x) * sum(y)) / (100 * length(x) * length(y))
median_ratio(x, y) = doubled_median(x) / doubled_median(y)
hodges_lehmann(x, y) = doubled_median([first - second for first in x for second in y]) / 200

function pooled_sd(x, y)
    first, second = sd(x), sd(y)
    sqrt(((length(x) - 1) * first * first + (length(y) - 1) * second * second) / (length(x) + length(y) - 2))
end

cohen_d(x, y) = mean_difference(x, y) / pooled_sd(x, y)

function correlation(x, y)
    first, second = deviations(x), deviations(y)
    products = sequential_sum(e * f for (e, f) in zip(first, second))
    products / sqrt(sequential_sum(e * e for e in first) * sequential_sum(f * f for f in second))
end

resample_indices(generator, size) = [draw_below!(generator, size) + 1 for _ in 1:size]
ordinary_indices(generator, size, count) = [resample_indices(generator, size) for _ in 1:count]

function balanced_indices(generator, size, count)
    sequence = repeat(collect(1:size), count)
    shuffle!(generator, sequence)
    [sequence[(replicate-1)*size+1:replicate*size] for replicate in 1:count]
end

without(values, index) = [values[1:index-1]; values[index+1:end]]

function mean_and_se(values)
    count = length(values)
    average = sequential_sum(values) / count
    average, sqrt(sequential_sum((value - average) * (value - average) for value in values) / (count - 1))
end

function phi(x)
    x < 0 && return 1 - phi(-x)
    eta = 1 / (1 + 0.2316419 * x)
    psi = eta * (0.319381530 + eta * (-0.356563782 + eta * (1.781477937 + eta * (-1.821255978 + eta * 1.330274429))))
    1 - 0.3989422804014327 * exp(-(x * x) / 2) * psi
end

function phi_inverse(p)
    p > 0.5 && return -phi_inverse(1 - p)
    eta = sqrt(-2 * log(p))
    -(eta - (2.515517 + eta * (0.802853 + eta * 0.010328)) / (1 + eta * (1.432788 + eta * (0.189269 + eta * 0.001308))))
end
