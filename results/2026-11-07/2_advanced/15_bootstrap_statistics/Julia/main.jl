include("dataset.jl")
include("minstd.jl")
include("resampling.jl")
include("tests.jl")
include("report.jl")

const GROUP_NAMES = ("mean", "median", "trimmed_mean", "sd")
const GROUP_FUNCTIONS = (mean, median, trimmed_mean, sd)
const PAIR_NAMES = ("mean_diff", "median_ratio", "hodges_lehmann", "cohen_d")
const PAIR_FUNCTIONS = (mean_difference, median_ratio, hodges_lehmann, cohen_d)
const TEST_NAMES = ("mean", "median", "ranksum", "absdev")

struct Summary
    estimate::Float64
    values::Vector{Float64}
    ordered::Vector{Float64}
    average::Float64
    se::Float64
    bias::Float64
    low::Float64
    high::Float64
    basic_low::Float64
    basic_high::Float64
end

function Summary(estimate, values, ranks)
    ordered = sort(values)
    average, se = mean_and_se(values)
    low, high = ordered[ranks[1]], ordered[ranks[2]]
    Summary(estimate, values, ordered, average, se, average - estimate, low, high, 2 * estimate - high, 2 * estimate - low)
end

struct GroupBootstrap
    group::Group
    indices::Vector{Vector{Int}}
    samples::Vector{Vector{Int}}
    summaries::Vector{Summary}
end

function GroupBootstrap(group, indices, ranks)
    samples = [group.values[index] for index in indices]
    summaries = [Summary(function_(group.values), [function_(sample) for sample in samples], ranks) for function_ in GROUP_FUNCTIONS]
    GroupBootstrap(group, indices, samples, summaries)
end

struct PairBootstrap
    first::GroupBootstrap
    second::GroupBootstrap
    name::String
    summaries::Vector{Summary}
end

function PairBootstrap(first, second, ranks)
    summaries = [Summary(function_(first.group.values, second.group.values), [function_(x, y) for (x, y) in zip(first.samples, second.samples)], ranks) for function_ in PAIR_FUNCTIONS]
    PairBootstrap(first, second, first.group.name * "-" * second.group.name, summaries)
end

struct Jackknife
    values::Vector{Float64}
    average::Float64
    variance::Float64
    bias::Float64
    se::Float64
end

function jackknife_spread(values)
    count = length(values)
    average = sequential_sum(values) / count
    squares = sequential_sum((value - average) * (value - average) for value in values)
    average, (count - 1) * squares / count
end

function Jackknife(estimate, values)
    average, variance = jackknife_spread(values)
    Jackknife(values, average, variance, (length(values) - 1) * (average - estimate), sqrt(variance))
end

mutable struct Tally
    observed::Int
    extreme::Int
    greater::Int
end

Tally(observed) = Tally(observed, 0, 0)

function count!(tally, value)
    tally.extreme += abs(value) >= abs(tally.observed)
    tally.greater += value >= tally.observed
end

tally_text(tally, offset, denominator) = "extreme $(tally.extreme) greater $(tally.greater) p_two $(p_value(tally.extreme + offset, denominator)) p_greater $(p_value(tally.greater + offset, denominator))"
interval_text(s) = "se $(real_text(s.se)) bias $(real_text(s.bias)) percentile $(real_text(s.low)) $(real_text(s.high)) basic $(real_text(s.basic_low)) $(real_text(s.basic_high))"

struct Study
    data::Dataset
    generator::Minstd
    ranks::Tuple{Int,Int}
    z_low::Float64
end

function Study(data)
    b, confidence = data.settings.bootstrap, data.settings.confidence
    low = div((b + 1) * (100 - confidence), 200)
    Study(data, Minstd(data.settings.seed), (low, b + 1 - low), phi_inverse((100 - confidence) / 200))
end

ceil_div(a, b) = div(a + b - 1, b)
display_range(values) = (minimum(values), 100 * (maximum(values) - minimum(values)))
display_position(display, value) = div(120 * (value - 100 * display[1]) + display[2], 2 * display[2]) + 1

function series_lines(kind, name, values, display, with_stems)
    count = length(values)
    average, deviation = mean(values), sd(values)
    second, third, fourth = central_moments(values)
    clipped = winsorized(values)
    first, last = quantile_numerator(values, 25), quantile_numerator(values, 75)
    outliers = [index for (index, value) in enumerate(values) if 200 * value < 5 * first - 3 * last || 200 * value > 5 * last - 3 * first]
    inside = [value for (index, value) in enumerate(values) if !(index in outliers)]
    whiskers = extrema(inside)
    band = fill('.', 61)
    band[display_position(display, 100 * whiskers[1]):display_position(display, 100 * whiskers[2])] .= '-'
    band[display_position(display, first):display_position(display, last)] .= '='
    band[display_position(display, quantile_numerator(values, 50))] = '|'
    for index in outliers
        band[display_position(display, 100 * values[index])] = 'o'
    end
    percentiles = join(["$label $(real_text(quantile_numerator(values, p) / 10000))" for (p, label) in ((5, "p05"), (10, "p10"), (90, "p90"), (95, "p95"))], " ")
    lines = ["$kind $name", "n $count", "mean $(real_text(average))", "median $(real_text(median(values)))",
        "trimmed_mean $(real_text(trimmed_mean(values))) trim $(trim_count(count))", "winsorized_mean $(real_text(mean(clipped))) winsorized_sd $(real_text(sd(clipped)))",
        "sd $(real_text(deviation))", "se_mean $(real_text(deviation / sqrt(count)))", "cv $(real_text(deviation / average))",
        "skewness $(real_text(third / (second * sqrt(second))))", "kurtosis $(real_text(fourth / (second * second) - 3))", "mad $(real_text(mad(values)))",
        "min $(real_text(minimum(values) / 100))", "q1 $(real_text(first / 10000))", "q3 $(real_text(last / 10000))", "iqr $(real_text((last - first) / 10000))",
        "max $(real_text(maximum(values) / 100))", "percentiles $percentiles", "whiskers $(real_text(whiskers[1] / 100)) $(real_text(whiskers[2] / 100))",
        "outliers $(number_list(outliers))", "box $(String(band))"]
    if with_stems
        ordered = sort(values)
        for stem in div(ordered[1], 100):div(ordered[end], 100)
            leaf = join([string(div(mod(value, 100), 10)) for value in ordered if div(value, 100) == stem])
            push!(lines, isempty(leaf) ? "stem $stem" : "stem $stem $leaf")
        end
    end
    lines
end

function descriptive_lines(study)
    data = study.data
    all = [value for group in data.groups for value in group.values]
    lines = ["groups $(length(data.groups)) observations $(length(all))"]
    for group in data.groups
        append!(lines, series_lines("group", group.name, group.values, display_range(all), true))
    end
    paired = data.paired
    push!(lines, "paired subjects $(length(paired.differences))")
    display = display_range([paired.before; paired.after])
    append!(lines, series_lines("series", "before", paired.before, display, false), series_lines("series", "after", paired.after, display, false),
        series_lines("series", "diff", paired.differences, display_range(paired.differences), false))
    lines
end

function paired_bootstrap(study)
    p = study.data.paired
    means, correlations = Float64[], Float64[]
    for indices in ordinary_indices(study.generator, length(p.differences), study.data.settings.bootstrap)
        push!(means, mean(p.differences[indices]))
        push!(correlations, correlation(p.before[indices], p.after[indices]))
    end
    Summary(mean(p.differences), means, study.ranks), Summary(correlation(p.before, p.after), correlations, study.ranks)
end

function bootstrap_lines(ordinary, balanced, pairs)
    lines = ["group,statistic,estimate,se,bias,percentile_lo,percentile_hi,basic_lo,basic_hi"]
    function add(name, statistic, summary)
        fields = (summary.estimate, summary.se, summary.bias, summary.low, summary.high, summary.basic_low, summary.basic_high)
        push!(lines, join([name, statistic, real_text.(fields)...], ','))
    end
    for (plain, even) in zip(ordinary, balanced)
        for (name, summary) in zip(GROUP_NAMES, plain.summaries)
            add(plain.group.name, name, summary)
        end
        for (name, summary) in zip(GROUP_NAMES, even.summaries)
            add(plain.group.name, "balanced_" * name, summary)
        end
    end
    for pair in pairs, (name, summary) in zip(PAIR_NAMES, pair.summaries)
        add(pair.name, name, summary)
    end
    lines
end

function histogram_lines(study, name, statistic, summary)
    bins, b = study.data.settings.bins, study.data.settings.bootstrap
    low, high = extrema(summary.values)
    counts, marks = zeros(Int, bins), [String[] for _ in 1:bins]
    for value in summary.values
        counts[bin_number(value, low, high, bins)] += 1
    end
    top = maximum(counts)
    push!(marks[bin_number(summary.low, low, high, bins)], "L")
    estimate_bin = "none"
    if low <= summary.estimate <= high
        index = bin_number(summary.estimate, low, high, bins)
        estimate_bin = string(index)
        push!(marks[index], "E")
    end
    push!(marks[bin_number(summary.high, low, high, bins)], "H")
    convergence = ["$size:$(real_text(last(mean_and_se(summary.values[1:size]))))" for size in [div(quarter * b, 4) for quarter in 1:4]]
    lines = ["histogram $name $statistic min $(real_text(low)) max $(real_text(high)) width $(real_text((high - low) / bins)) top $top estimate_bin $estimate_bin", "convergence " * join(convergence, " ")]
    for (number, count) in enumerate(counts)
        parts = ["bin", string(number), real_text(low + (high - low) * (number - 1) / bins), string(count)]
        count > 0 && push!(parts, bar(count, top))
        append!(parts, marks[number])
        push!(lines, join(parts, " "))
    end
    lines
end

bca_alpha(z0, acceleration, z) = phi(z0 + (z0 + z) / (1 - acceleration * (z0 + z)))

function bca_line(study, name, summary, jackknife)
    b = study.data.settings.bootstrap
    below = count(<(summary.estimate), summary.values)
    z0 = phi_inverse(below / b)
    differences = [jackknife.average - value for value in jackknife.values]
    squares = sequential_sum(u * u for u in differences)
    cubes = sequential_sum(u * u * u for u in differences)
    acceleration = cubes / (6 * squares * sqrt(squares))
    low = clamp(floor(Int, (b + 1) * bca_alpha(z0, acceleration, study.z_low)), 1, b)
    high = clamp(b + 1 - floor(Int, (b + 1) * (1 - bca_alpha(z0, acceleration, -study.z_low))), 1, b)
    "bca $name below $below z0 $(real_text(z0)) acceleration $(real_text(acceleration)) ranks $low $high interval $(real_text(summary.ordered[low])) $(real_text(summary.ordered[high]))"
end

function group_jackknife_lines(study, bootstrap)
    values = bootstrap.group.values
    n = length(values)
    jackknives = [Jackknife(summary.estimate, [function_(without(values, index)) for index in eachindex(values)]) for (function_, summary) in zip(GROUP_FUNCTIONS, bootstrap.summaries)]
    lines = ["group $(bootstrap.group.name) n $n"]
    for (name, summary, jackknife) in zip(GROUP_NAMES, bootstrap.summaries, jackknives)
        push!(lines, "jackknife $name estimate $(real_text(summary.estimate)) average $(real_text(jackknife.average)) bias $(real_text(jackknife.bias)) se $(real_text(jackknife.se))")
    end
    for (name, summary, jackknife) in zip(GROUP_NAMES, bootstrap.summaries, jackknives)
        push!(lines, bca_line(study, name, summary, jackknife))
    end
    omitted = [[replicate for (replicate, indices) in enumerate(bootstrap.indices) if !(index in indices)] for index in eachindex(values)]
    errors = [[last(mean_and_se(summary.values[numbers])) for numbers in omitted] for summary in bootstrap.summaries]
    for (name, summary, ses) in zip(GROUP_NAMES, bootstrap.summaries, errors)
        average, variance = jackknife_spread(ses)
        push!(lines, "after_bootstrap $name se $(real_text(summary.se)) average $(real_text(average)) se_of_se $(real_text(sqrt(variance)))")
    end
    sizes = length.(omitted)
    push!(lines, "without min $(minimum(sizes)) max $(maximum(sizes))")
    total = sum(values)
    order = sort(collect(eachindex(values)); by=index -> (-abs(n * values[index] - total), index))
    summary, jackknife = bootstrap.summaries[1], jackknives[1]
    for (rank, index) in enumerate(order[1:5])
        influence = (n - 1) * (jackknife.average - jackknife.values[index])
        shifted = sort([summary.values[replicate] - summary.estimate for replicate in omitted[index]])
        q05, q50, q95 = [shifted[ceil_div(percent * sizes[index], 100)] for percent in (5, 50, 95)]
        push!(lines, "influence $rank obs $index value $(real_text(values[index] / 100)) l $(real_text(influence)) without $(sizes[index]) se $(real_text(errors[1][index])) q05 $(real_text(q05)) q50 $(real_text(q50)) q95 $(real_text(q95))")
    end
    lines
end

function pair_jackknife_lines(pair)
    x, y = pair.first.group.values, pair.second.group.values
    lines = String[]
    for (name, function_, summary) in zip(PAIR_NAMES, PAIR_FUNCTIONS, pair.summaries)
        first = Jackknife(summary.estimate, [function_(without(x, index), y) for index in eachindex(x)])
        second = Jackknife(summary.estimate, [function_(x, without(y, index)) for index in eachindex(y)])
        bias = (0.0 + first.bias) + second.bias
        variance = (0.0 + first.variance) + second.variance
        push!(lines, "pair $(pair.name) $name estimate $(real_text(summary.estimate)) bias $(real_text(bias)) se $(real_text(sqrt(variance)))")
    end
    lines
end

function split_statistics(values, ranks, order, size)
    first, second = values[order[1:size]], values[order[size+1:end]]
    k, m = length(first), length(second)
    first_center, second_center = doubled_median(first), doubled_median(second)
    rank_total = sum(ranks[order[1:size]])
    first_dev = sum(abs(2 * value - first_center) for value in first)
    second_dev = sum(abs(2 * value - second_center) for value in second)
    (contrast(sum(first), k, sum(second), m), first_center - second_center, rank_total - k * (k + m + 1), contrast(first_dev, k, second_dev, m))
end

function permutation_lines(study, x, y)
    r, k, m = study.data.settings.permutations, length(x), length(y)
    combined = [x; y]
    ranks, positions = doubled_ranks(combined), collect(eachindex(combined))
    observed = split_statistics(combined, ranks, positions, k)
    tallies = Tally.(observed)
    for _ in 1:r
        order = shuffle!(study.generator, copy(positions))
        for (tally, value) in zip(tallies, split_statistics(combined, ranks, order, k))
            count!(tally, value)
        end
    end
    total = sum(ranks[1:k])
    results = [tally_text(tally, 1, r + 1) for tally in tallies]
    lines = ["permutation n $k $m perms $r", "mean diff $(real_text(mean_difference(x, y))) $(results[1])",
        "median diff $(real_text(observed[2] / 200)) $(results[2])", "ranksum w $(real_text(total / 2)) u $(real_text((total - k * (k + 1)) / 2)) $(results[3])",
        "absdev diff $(real_text(observed[4] / (200 * k * m))) $(results[4])"]
    lines, [tally.extreme for tally in tallies]
end

function power_line(study, x, y)
    options, k, m = study.data.settings, length(x), length(y)
    rejections = 0
    for _ in 1:options.power_sims
        first = x[resample_indices(study.generator, k)]
        second = y[resample_indices(study.generator, m)]
        combined = [first; second]
        total = sum(combined)
        observed = abs(contrast(sum(first), k, sum(second), m))
        count = 0
        for _ in 1:options.power_perms
            shuffled = shuffle!(study.generator, copy(combined))
            head = sum(shuffled[1:k])
            count += abs(contrast(head, k, total - head, m)) >= observed
        end
        rejections += 100 * (count + 1) <= (100 - options.confidence) * (options.power_perms + 1)
    end
    power = rejections / options.power_sims
    "power sims $(options.power_sims) perms $(options.power_perms) rejections $rejections power $(real_text(power)) se $(real_text(sqrt(power * (1 - power) / options.power_sims)))"
end

function exact_lines(study, x, y)
    q = study.data.settings.pilot
    combined = [x[1:q]; y[1:q]]
    ranks, total = doubled_ranks(combined), sum(combined)
    means, rank_values = Int[], Int[]
    for choice in position_choices(2 * q, q)
        chosen = sum(combined[choice])
        push!(means, contrast(chosen, q, total - chosen, q))
        push!(rank_values, sum(ranks[choice]) - q * (2 * q + 1))
    end
    splits = length(means)
    mean_tally, rank_tally = Tally(means[1]), Tally(rank_values[1])
    for (first, second) in zip(means, rank_values)
        count!(mean_tally, first)
        count!(rank_tally, second)
    end
    rank_total = sum(ranks[1:q])
    lines = ["exact size $q splits $splits", "mean diff $(real_text(mean_difference(x[1:q], y[1:q]))) $(tally_text(mean_tally, 0, splits))",
        "ranksum w $(real_text(rank_total / 2)) u $(real_text((rank_total - q * (q + 1)) / 2)) $(tally_text(rank_tally, 0, splits))"]
    critical = nothing
    cumulative = 0
    for (value, count) in reverse(value_counts(abs.(means)))
        cumulative += count
        100 * cumulative > (100 - study.data.settings.confidence) * splits && break
        critical = (value, cumulative)
    end
    if isnothing(critical)
        push!(lines, "critical diff none attained none")
    else
        value, cumulative = critical
        push!(lines, "critical diff $(real_text(value / (100 * q * q))) attained $(p_value(cumulative, splits))")
    end
    lines
end

function studentized_lines(study, pair)
    x, y = pair.first.group.values, pair.second.group.values
    k, m = length(x), length(y)
    estimate, first_sd, second_sd = mean_difference(x, y), sd(x), sd(y)
    first_variance, second_variance = first_sd * first_sd / k, second_sd * second_sd / m
    se0 = sqrt(first_variance + second_variance)
    t = estimate / se0
    statistics = [(difference - estimate) / sqrt(first * first / k + second * second / m) for (difference, first, second) in zip(pair.summaries[1].values, pair.first.summaries[4].values, pair.second.summaries[4].values)]
    extreme = count(value -> abs(value) >= abs(t), statistics)
    ordered = sort(statistics)
    lower, upper = estimate - ordered[study.ranks[2]] * se0, estimate - ordered[study.ranks[1]] * se0
    degrees = (first_variance + second_variance) * (first_variance + second_variance) / (first_variance * first_variance / (k - 1) + second_variance * second_variance / (m - 1))
    greater = count(first > second for first in x for second in y)
    equal = count(first == second for first in x for second in y)
    d = cohen_d(x, y)
    hedges = d * (1 - 3 / (4 * (k + m - 2) - 1))
    cles = (2 * greater + equal) / (2 * k * m)
    ["bootstrap_t t $(real_text(t)) df $(real_text(degrees)) extreme $extreme p $(p_value(extreme + 1, study.data.settings.bootstrap + 1)) interval $(real_text(lower)) $(real_text(upper))",
        "effect pooled_sd $(real_text(pooled_sd(x, y))) cohen_d $(real_text(d)) hedges_g $(real_text(hedges)) cles $(real_text(cles))"]
end

function holm_lines(study, extremes)
    options, pairs = study.data.settings, study.data.pairs
    lines = String[]
    for (column, name) in enumerate(TEST_NAMES)
        order = sort(collect(eachindex(pairs)); by=index -> (extremes[index][column], index))
        adjusted = 0
        for (rank, index) in enumerate(order)
            extreme = extremes[index][column]
            adjusted = max(adjusted, min(options.permutations + 1, (length(pairs) - rank + 1) * (extreme + 1)))
            verdict = 100 * adjusted <= (100 - options.confidence) * (options.permutations + 1) ? "reject" : "retain"
            first, second = pairs[index]
            push!(lines, "holm $name rank $rank $(study.data.groups[first].name) $(study.data.groups[second].name) p $(p_value(extreme + 1, options.permutations + 1)) adjusted $(p_value(adjusted, options.permutations + 1)) $verdict")
        end
    end
    lines
end

function hyperbolic_tangent(value)
    growth = exp(2 * value)
    (growth - 1) / (growth + 1)
end

function paired_lines(study, mean_summary, correlation_summary)
    p = study.data.paired
    differences = p.differences
    n = length(differences)
    positive, negative, zero = count(>(0), differences), count(<(0), differences), count(==(0), differences)
    average, deviation, r = mean(differences), sd(differences), correlation(p.before, p.after)
    z = 0.5 * log((1 + r) / (1 - r))
    half_width = -study.z_low / sqrt(n - 3)
    ["paired subjects $n positive $positive negative $negative zero $zero", "paired before $(real_text(mean(p.before))) after $(real_text(mean(p.after))) diff $(real_text(average)) sd_diff $(real_text(deviation)) t $(real_text(average / (deviation / sqrt(n)))) dz $(real_text(average / deviation))",
        "paired_bootstrap $(interval_text(mean_summary))", "correlation r $(real_text(r)) $(interval_text(correlation_summary)) fisher $(real_text(hyperbolic_tangent(z - half_width))) $(real_text(hyperbolic_tangent(z + half_width)))"]
end

function sign_flip_lines(study)
    differences = study.data.paired.differences
    nonzero = abs.([value for value in differences if value != 0])
    ranks = Dict(zip(nonzero, doubled_ranks(nonzero)))
    signed = [value == 0 ? 0 : value > 0 ? ranks[value] : -ranks[-value] for value in differences]
    first, second = Tally(sum(differences)), Tally(sum(signed))
    r = study.data.settings.permutations
    for _ in 1:r
        signs = [isodd(draw!(study.generator)) ? -1 : 1 for _ in differences]
        count!(first, sum(signs .* differences))
        count!(second, sum(signs .* signed))
    end
    w_plus = sum(rank for rank in signed if rank > 0) / 2
    ["signflip flips $r", "mean diff $(real_text(mean(differences))) $(tally_text(first, 1, r + 1))", "signedrank w_plus $(real_text(w_plus)) $(tally_text(second, 1, r + 1))"]
end

function welch_line(samples)
    groups = length(samples)
    means = mean.(samples)
    weights = [length(sample) / (sd(sample) * sd(sample)) for sample in samples]
    total_weight = sequential_sum(weights)
    center = sequential_sum(weight * value for (weight, value) in zip(weights, means)) / total_weight
    spread = sequential_sum(weight * ((value - center) * (value - center)) for (weight, value) in zip(weights, means)) / (groups - 1)
    lambda = 0.0
    for (weight, sample) in zip(weights, samples)
        share = 1 - weight / total_weight
        lambda += share * share / (length(sample) - 1)
    end
    f = spread / (1 + 2 * (groups - 2) * lambda / (groups * groups - 1))
    df = (groups * groups - 1) / (3 * lambda)
    "welch f $(real_text(f)) df $(groups - 1) $(real_text(df))"
end

group_deltas(samples, pairs) = [(abs(contrast(sum(samples[i]), length(samples[i]), sum(samples[j]), length(samples[j]))), length(samples[i]) * length(samples[j])) for (i, j) in pairs]
delta_at_least(value, bound) = value[1] * bound[2] >= bound[1] * value[2]

function anova_lines(study, ordinary)
    samples = [group.values for group in study.data.groups]
    sizes = length.(samples)
    groups, total = length(samples), sum(sizes)
    between, within = sums_of_squares(samples)
    f = f_statistic(between, within, groups, total)
    eta, msw = between / (between + within), within / (total - groups)
    omega = (between - (groups - 1) * msw) / (between + within + msw)
    eta_values = Float64[]
    for replicate in 1:study.data.settings.bootstrap
        first, second = sums_of_squares([bootstrap.samples[replicate] for bootstrap in ordinary])
        push!(eta_values, first / (first + second))
    end
    eta_summary = Summary(eta, eta_values, study.ranks)
    combined = reduce(vcat, samples)
    ranks = doubled_ranks(combined)
    rank_sums = sum.(split_list(ranks, sizes))
    ties = [count for (_, count) in value_counts(combined) if count >= 2]
    tie_total = sum((count * count * count - count for count in ties); init=0)
    correction = 1 - tie_total / (total * total * total - total)
    h = h_statistic(rank_sums, sizes, correction)
    lines = ["anova groups $groups observations $total ssb $(real_text(between)) ssw $(real_text(within)) df $(groups - 1) $(total - groups) f $(real_text(f)) eta_squared $(real_text(eta)) omega_squared $(real_text(omega))",
        "eta_bootstrap $(interval_text(eta_summary))", welch_line(samples), "kruskal h $(real_text(h)) tie_groups $(length(ties))"]
    pairs = [(i, j) for i in 1:groups for j in i+1:groups]
    observed = group_deltas(samples, pairs)
    extremes, maxima = zeros(Int, length(pairs)), zeros(Int, length(pairs))
    f_extreme = h_extreme = 0
    r = study.data.settings.permutations
    for _ in 1:r
        order = shuffle!(study.generator, collect(eachindex(combined)))
        parts = split_list(order, sizes)
        shuffled = [combined[part] for part in parts]
        first, second = sums_of_squares(shuffled)
        f_extreme += f_statistic(first, second, groups, total) >= f - 0.000000001 * f
        h_extreme += h_statistic([sum(ranks[part]) for part in parts], sizes, correction) >= h - 0.000000001 * h
        deltas = group_deltas(shuffled, pairs)
        largest = deltas[1]
        for delta in deltas[2:end]
            !delta_at_least(largest, delta) && (largest = delta)
        end
        for (index, bound) in enumerate(observed)
            extremes[index] += delta_at_least(deltas[index], bound)
            maxima[index] += delta_at_least(largest, bound)
        end
    end
    push!(lines, "anova_permutation perms $r f_extreme $f_extreme f_p $(p_value(f_extreme + 1, r + 1)) h_extreme $h_extreme h_p $(p_value(h_extreme + 1, r + 1))")
    for ((i, j), extreme, maximum) in zip(pairs, extremes, maxima)
        push!(lines, "pairwise $(study.data.groups[i].name) $(study.data.groups[j].name) diff $(real_text(mean_difference(samples[i], samples[j]))) extreme $extreme p $(p_value(extreme + 1, r + 1)) maxt $maximum adjusted $(p_value(maximum + 1, r + 1))")
    end
    lines
end

function main()
    study = Study(load_dataset("input"))
    b = study.data.settings.bootstrap
    ordinary = [GroupBootstrap(group, ordinary_indices(study.generator, length(group.values), b), study.ranks) for group in study.data.groups]
    balanced = [GroupBootstrap(group, balanced_indices(study.generator, length(group.values), b), study.ranks) for group in study.data.groups]
    mean_summary, correlation_summary = paired_bootstrap(study)
    pairs = [PairBootstrap(ordinary[first], ordinary[second], study.ranks) for (first, second) in study.data.pairs]
    tests, extremes = String[], Vector{Int}[]
    for pair in pairs
        push!(tests, "compare $(pair.first.group.name) $(pair.second.group.name)")
        lines, counts = permutation_lines(study, pair.first.group.values, pair.second.group.values)
        append!(tests, lines)
        push!(extremes, counts)
        push!(tests, power_line(study, pair.first.group.values, pair.second.group.values))
        append!(tests, exact_lines(study, pair.first.group.values, pair.second.group.values), studentized_lines(study, pair))
    end
    append!(tests, holm_lines(study, extremes), paired_lines(study, mean_summary, correlation_summary), sign_flip_lines(study), anova_lines(study, ordinary))
    jackknives, histograms = String[], String[]
    for bootstrap in ordinary
        append!(jackknives, group_jackknife_lines(study, bootstrap))
        for (name, summary) in zip(GROUP_NAMES, bootstrap.summaries)
            append!(histograms, histogram_lines(study, bootstrap.group.name, name, summary))
        end
    end
    for pair in pairs
        append!(jackknives, pair_jackknife_lines(pair))
        for (name, summary) in zip(PAIR_NAMES, pair.summaries)
            append!(histograms, histogram_lines(study, pair.name, name, summary))
        end
    end
    mkpath("output")
    for (name, lines) in [("descriptives.txt", descriptive_lines(study)), ("bootstrap.csv", bootstrap_lines(ordinary, balanced, pairs)), ("jackknife.txt", jackknives), ("tests.txt", tests), ("histograms.txt", histograms)]
        write_lines(joinpath("output", name), lines)
    end
end

main()
