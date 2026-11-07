import os
from math import exp, floor, log, sqrt

from dataset import load_dataset
from minstd import Minstd
from report import bar, bin_number, number_list, p_value, real, write_lines
from resampling import (
    balanced_indices, central_moments, cohen_d, correlation, doubled_median, hodges_lehmann,
    mad, mean, mean_and_se, mean_difference, median, median_ratio, ordinary_indices, phi,
    phi_inverse, pooled_sd, quantile_numerator, resample_indices, sd, sequential_sum,
    trim_count, trimmed_mean, winsorized, without,
)
from tests import (
    contrast, doubled_ranks, f_statistic, h_statistic, position_choices, split_list,
    sums_of_squares, value_counts,
)


GROUP_STATISTICS = {
    "mean": mean, "median": median, "trimmed_mean": trimmed_mean, "sd": sd,
}
PAIR_STATISTICS = {
    "mean_diff": mean_difference, "median_ratio": median_ratio,
    "hodges_lehmann": hodges_lehmann, "cohen_d": cohen_d,
}
TEST_STATISTICS = ("mean", "median", "ranksum", "absdev")
PERCENTILES = ((5, "p05"), (10, "p10"), (90, "p90"), (95, "p95"))
INFLUENCE_QUANTILES = (5, 50, 95)
BOOTSTRAP_HEADER = "group,statistic,estimate,se,bias,percentile_lo,percentile_hi,basic_lo,basic_hi"
BAND_SIZE = 61
INFLUENCE_COUNT = 5
TOLERANCE = 0.000000001


def ceil_div(numerator, denominator):
    return (numerator + denominator - 1) // denominator


def clamp_rank(rank, limit):
    return min(max(rank, 1), limit)


def hyperbolic_tangent(value):
    growth = exp(2 * value)
    return (growth - 1) / (growth + 1)


class Summary:
    def __init__(self, estimate, values, ranks):
        self.estimate = estimate
        self.values = values
        self.ordered = sorted(values)
        self.average, self.se = mean_and_se(values)
        self.bias = self.average - estimate
        self.low = self.ordered[ranks[0] - 1]
        self.high = self.ordered[ranks[1] - 1]
        self.basic_low = 2 * estimate - self.high
        self.basic_high = 2 * estimate - self.low

    def csv_line(self, name, statistic):
        fields = (
            self.estimate, self.se, self.bias, self.low, self.high,
            self.basic_low, self.basic_high,
        )
        return ",".join([name, statistic] + [real(field) for field in fields])

    def interval_text(self):
        return (
            f"se {real(self.se)} bias {real(self.bias)}"
            f" percentile {real(self.low)} {real(self.high)}"
            f" basic {real(self.basic_low)} {real(self.basic_high)}"
        )


class GroupBootstrap:
    def __init__(self, group, indices, ranks):
        self.group = group
        self.indices = indices
        self.samples = [[group.values[index] for index in replicate] for replicate in indices]
        self.summaries = {
            statistic: Summary(
                function(group.values), [function(sample) for sample in self.samples], ranks
            )
            for statistic, function in GROUP_STATISTICS.items()
        }


class PairBootstrap:
    def __init__(self, first, second, ranks):
        self.first = first
        self.second = second
        self.name = f"{first.group.name}-{second.group.name}"
        x = first.group.values
        y = second.group.values
        self.summaries = {
            statistic: Summary(
                function(x, y),
                [function(a, b) for a, b in zip(first.samples, second.samples)],
                ranks,
            )
            for statistic, function in PAIR_STATISTICS.items()
        }


class Jackknife:
    def __init__(self, estimate, values):
        self.values = values
        self.average, self.variance = jackknife_spread(values)
        self.bias = (len(values) - 1) * (self.average - estimate)
        self.se = sqrt(self.variance)


class Tally:
    def __init__(self, observed):
        self.observed = observed
        self.extreme = 0
        self.greater = 0

    def count(self, value):
        if abs(value) >= abs(self.observed):
            self.extreme += 1
        if value >= self.observed:
            self.greater += 1

    def text(self, offset, denominator):
        two_sided = p_value(self.extreme + offset, denominator)
        one_sided = p_value(self.greater + offset, denominator)
        return (
            f"extreme {self.extreme} greater {self.greater}"
            f" p_two {two_sided} p_greater {one_sided}"
        )


class DisplayRange:
    def __init__(self, values):
        self.low = min(values)
        self.delta = 100 * (max(values) - self.low)

    def position(self, value):
        return (120 * (value - 100 * self.low) + self.delta) // (2 * self.delta)


def jackknife_spread(values):
    count = len(values)
    average = sequential_sum(values) / count
    squares = sequential_sum((value - average) * (value - average) for value in values)
    return average, (count - 1) * squares / count


def outlier_indices(values):
    first = quantile_numerator(values, 25)
    third = quantile_numerator(values, 75)
    return [
        index for index, value in enumerate(values)
        if 200 * value < 5 * first - 3 * third or 200 * value > 5 * third - 3 * first
    ]


def fill(band, start, end, symbol):
    for position in range(start, end + 1):
        band[position] = symbol


def box_plot(values, display, outliers, whiskers):
    band = ["."] * BAND_SIZE
    fill(band, display.position(100 * whiskers[0]), display.position(100 * whiskers[1]), "-")
    fill(
        band, display.position(quantile_numerator(values, 25)),
        display.position(quantile_numerator(values, 75)), "=",
    )
    band[display.position(quantile_numerator(values, 50))] = "|"
    for index in outliers:
        band[display.position(100 * values[index])] = "o"
    return "".join(band)


def stem_lines(values):
    ordered = sorted(values)
    lines = []
    for stem in range(ordered[0] // 100, ordered[-1] // 100 + 1):
        leaves = "".join(str(value % 100 // 10) for value in ordered if value // 100 == stem)
        lines.append(f"stem {stem} {leaves}" if leaves else f"stem {stem}")
    return lines


def series_lines(kind, name, values, display, with_stems):
    count = len(values)
    average = mean(values)
    deviation = sd(values)
    second, third, fourth = central_moments(values)
    clipped = winsorized(values)
    first_quartile = quantile_numerator(values, 25)
    third_quartile = quantile_numerator(values, 75)
    outliers = outlier_indices(values)
    inside = [value for index, value in enumerate(values) if index not in outliers]
    whiskers = min(inside), max(inside)
    percentiles = " ".join(
        f"{label} {real(quantile_numerator(values, percent) / 10000)}"
        for percent, label in PERCENTILES
    )
    lines = [
        f"{kind} {name}",
        f"n {count}",
        f"mean {real(average)}",
        f"median {real(median(values))}",
        f"trimmed_mean {real(trimmed_mean(values))} trim {trim_count(count)}",
        f"winsorized_mean {real(mean(clipped))} winsorized_sd {real(sd(clipped))}",
        f"sd {real(deviation)}",
        f"se_mean {real(deviation / sqrt(count))}",
        f"cv {real(deviation / average)}",
        f"skewness {real(third / (second * sqrt(second)))}",
        f"kurtosis {real(fourth / (second * second) - 3)}",
        f"mad {real(mad(values))}",
        f"min {real(min(values) / 100)}",
        f"q1 {real(first_quartile / 10000)}",
        f"q3 {real(third_quartile / 10000)}",
        f"iqr {real((third_quartile - first_quartile) / 10000)}",
        f"max {real(max(values) / 100)}",
        f"percentiles {percentiles}",
        f"whiskers {real(whiskers[0] / 100)} {real(whiskers[1] / 100)}",
        f"outliers {number_list([index + 1 for index in outliers])}",
        f"box {box_plot(values, display, outliers, whiskers)}",
    ]
    if with_stems:
        lines.extend(stem_lines(values))
    return lines


def bootstrap_lines(ordinary, balanced, pairs):
    lines = [BOOTSTRAP_HEADER]
    for plain, even in zip(ordinary, balanced):
        name = plain.group.name
        for statistic, summary in plain.summaries.items():
            lines.append(summary.csv_line(name, statistic))
        for statistic, summary in even.summaries.items():
            lines.append(summary.csv_line(name, "balanced_" + statistic))
    for pair in pairs:
        for statistic, summary in pair.summaries.items():
            lines.append(summary.csv_line(pair.name, statistic))
    return lines


def bca_alpha(z0, acceleration, z):
    return phi(z0 + (z0 + z) / (1 - acceleration * (z0 + z)))


def omitted_replicates(indices, size):
    chosen = [set(replicate) for replicate in indices]
    return [
        [number for number, used in enumerate(chosen) if index not in used]
        for index in range(size)
    ]


def pair_jackknife_lines(pair):
    x = pair.first.group.values
    y = pair.second.group.values
    lines = []
    for statistic, function in PAIR_STATISTICS.items():
        summary = pair.summaries[statistic]
        first = Jackknife(
            summary.estimate, [function(without(x, index), y) for index in range(len(x))]
        )
        second = Jackknife(
            summary.estimate, [function(x, without(y, index)) for index in range(len(y))]
        )
        bias = first.bias + second.bias
        se = sqrt(first.variance + second.variance)
        lines.append(
            f"pair {pair.name} {statistic} estimate {real(summary.estimate)}"
            f" bias {real(bias)} se {real(se)}"
        )
    return lines


def deviation_total(sample, center):
    return sum(abs(2 * value - center) for value in sample)


def split_statistics(values, ranks, order, size):
    first = [values[index] for index in order[:size]]
    second = [values[index] for index in order[size:]]
    first_size = len(first)
    second_size = len(second)
    first_center = doubled_median(first)
    second_center = doubled_median(second)
    rank_total = sum(ranks[index] for index in order[:size])
    return (
        contrast(sum(first), first_size, sum(second), second_size),
        first_center - second_center,
        rank_total - first_size * (first_size + second_size + 1),
        contrast(
            deviation_total(first, first_center), first_size,
            deviation_total(second, second_center), second_size,
        ),
    )


def signed_ranks(differences):
    magnitudes = [abs(difference) for difference in differences if difference != 0]
    rank_of = dict(zip(magnitudes, doubled_ranks(magnitudes)))
    signed = []
    for difference in differences:
        if difference > 0:
            signed.append(rank_of[difference])
        elif difference < 0:
            signed.append(-rank_of[-difference])
        else:
            signed.append(0)
    return signed


def welch_line(samples):
    group_count = len(samples)
    means = [mean(sample) for sample in samples]
    weights = []
    for sample in samples:
        deviation = sd(sample)
        weights.append(len(sample) / (deviation * deviation))
    total_weight = sequential_sum(weights)
    center = sequential_sum(weight * value for weight, value in zip(weights, means)) / total_weight
    spread = sequential_sum(
        weight * ((value - center) * (value - center)) for weight, value in zip(weights, means)
    ) / (group_count - 1)
    lambda_ = 0.0
    for weight, sample in zip(weights, samples):
        share = 1 - weight / total_weight
        lambda_ += share * share / (len(sample) - 1)
    f = spread / (1 + 2 * (group_count - 2) * lambda_ / (group_count * group_count - 1))
    df = (group_count * group_count - 1) / (3 * lambda_)
    return f"welch f {real(f)} df {group_count - 1} {real(df)}"


def group_deltas(samples, pairs):
    sums = [sum(sample) for sample in samples]
    sizes = [len(sample) for sample in samples]
    return [
        (abs(contrast(sums[i], sizes[i], sums[j], sizes[j])), sizes[i] * sizes[j])
        for i, j in pairs
    ]


def delta_at_least(value, bound):
    return value[0] * bound[1] >= bound[0] * value[1]


def largest_delta(deltas):
    largest = deltas[0]
    for delta in deltas[1:]:
        if not delta_at_least(largest, delta):
            largest = delta
    return largest


class Study:
    def __init__(self, dataset):
        self.groups = dataset.groups
        self.paired = dataset.paired
        self.pairs = dataset.pairs
        self.settings = dataset.settings
        self.generator = Minstd(self.settings.seed)
        replicates = self.settings.bootstrap
        low_rank = (replicates + 1) * (100 - self.settings.confidence) // 200
        self.ranks = low_rank, replicates + 1 - low_rank
        self.z_low = phi_inverse((100 - self.settings.confidence) / 200)

    def descriptive_lines(self):
        everything = [value for group in self.groups for value in group.values]
        lines = [f"groups {len(self.groups)} observations {len(everything)}"]
        display = DisplayRange(everything)
        for group in self.groups:
            lines.extend(series_lines("group", group.name, group.values, display, True))
        paired = self.paired
        lines.append(f"paired subjects {len(paired.differences)}")
        display = DisplayRange(paired.before + paired.after)
        lines.extend(series_lines("series", "before", paired.before, display, False))
        lines.extend(series_lines("series", "after", paired.after, display, False))
        lines.extend(series_lines(
            "series", "diff", paired.differences, DisplayRange(paired.differences), False
        ))
        return lines

    def paired_bootstrap(self):
        before = self.paired.before
        after = self.paired.after
        differences = self.paired.differences
        mean_values = []
        correlation_values = []
        for indices in ordinary_indices(self.generator, len(differences), self.settings.bootstrap):
            mean_values.append(mean([differences[index] for index in indices]))
            correlation_values.append(correlation(
                [before[index] for index in indices], [after[index] for index in indices]
            ))
        return (
            Summary(mean(differences), mean_values, self.ranks),
            Summary(correlation(before, after), correlation_values, self.ranks),
        )

    def histogram_lines(self, name, statistic, summary):
        bins = self.settings.bins
        values = summary.values
        low = min(values)
        high = max(values)
        counts = [0] * bins
        for value in values:
            counts[bin_number(value, low, high, bins) - 1] += 1
        top = max(counts)
        marks = [[] for _ in range(bins)]
        marks[bin_number(summary.low, low, high, bins) - 1].append("L")
        estimate_bin = "none"
        if low <= summary.estimate <= high:
            estimate_bin = bin_number(summary.estimate, low, high, bins)
            marks[estimate_bin - 1].append("E")
        marks[bin_number(summary.high, low, high, bins) - 1].append("H")
        convergence = []
        for quarter in range(1, 5):
            size = quarter * self.settings.bootstrap // 4
            convergence.append(f"{size}:{real(mean_and_se(values[:size])[1])}")
        lines = [
            f"histogram {name} {statistic} min {real(low)} max {real(high)}"
            f" width {real((high - low) / bins)} top {top} estimate_bin {estimate_bin}",
            "convergence " + " ".join(convergence),
        ]
        for number, count in enumerate(counts, 1):
            parts = ["bin", str(number), real(low + (high - low) * (number - 1) / bins), str(count)]
            if count > 0:
                parts.append(bar(count, top))
            parts.extend(marks[number - 1])
            lines.append(" ".join(parts))
        return lines

    def histogram_file(self, ordinary, pairs):
        lines = []
        for bootstrap in ordinary:
            for statistic, summary in bootstrap.summaries.items():
                lines.extend(self.histogram_lines(bootstrap.group.name, statistic, summary))
        for pair in pairs:
            for statistic, summary in pair.summaries.items():
                lines.extend(self.histogram_lines(pair.name, statistic, summary))
        return lines

    def bca_line(self, statistic, summary, jackknife):
        replicates = self.settings.bootstrap
        below = sum(1 for value in summary.values if value < summary.estimate)
        z0 = phi_inverse(below / replicates)
        differences = [jackknife.average - value for value in jackknife.values]
        square_sum = sequential_sum(u * u for u in differences)
        cube_sum = sequential_sum(u * u * u for u in differences)
        acceleration = cube_sum / (6 * square_sum * sqrt(square_sum))
        lower = floor((replicates + 1) * bca_alpha(z0, acceleration, self.z_low))
        upper = replicates + 1 - floor(
            (replicates + 1) * (1 - bca_alpha(z0, acceleration, -self.z_low))
        )
        lower = clamp_rank(lower, replicates)
        upper = clamp_rank(upper, replicates)
        return (
            f"bca {statistic} below {below} z0 {real(z0)} acceleration {real(acceleration)}"
            f" ranks {lower} {upper} interval {real(summary.ordered[lower - 1])}"
            f" {real(summary.ordered[upper - 1])}"
        )

    def after_bootstrap_lines(self, bootstrap, mean_jackknife):
        values = bootstrap.group.values
        count = len(values)
        omitted = omitted_replicates(bootstrap.indices, count)
        errors = {
            statistic: [
                mean_and_se([summary.values[number] for number in numbers])[1]
                for numbers in omitted
            ]
            for statistic, summary in bootstrap.summaries.items()
        }
        lines = []
        for statistic, summary in bootstrap.summaries.items():
            average, variance = jackknife_spread(errors[statistic])
            lines.append(
                f"after_bootstrap {statistic} se {real(summary.se)} average {real(average)}"
                f" se_of_se {real(sqrt(variance))}"
            )
        sizes = [len(numbers) for numbers in omitted]
        lines.append(f"without min {min(sizes)} max {max(sizes)}")
        total = sum(values)
        ranking = sorted(range(count), key=lambda index: (-abs(count * values[index] - total), index))
        mean_summary = bootstrap.summaries["mean"]
        for rank, index in enumerate(ranking[:INFLUENCE_COUNT], 1):
            influence = (count - 1) * (mean_jackknife.average - mean_jackknife.values[index])
            shifted = sorted(
                mean_summary.values[number] - mean_summary.estimate for number in omitted[index]
            )
            quantiles = [
                real(shifted[ceil_div(percent * sizes[index], 100) - 1])
                for percent in INFLUENCE_QUANTILES
            ]
            lines.append(
                f"influence {rank} obs {index + 1} value {real(values[index] / 100)}"
                f" l {real(influence)} without {sizes[index]} se {real(errors['mean'][index])}"
                f" q05 {quantiles[0]} q50 {quantiles[1]} q95 {quantiles[2]}"
            )
        return lines

    def group_jackknife_lines(self, bootstrap):
        values = bootstrap.group.values
        jackknives = {
            statistic: Jackknife(
                bootstrap.summaries[statistic].estimate,
                [function(without(values, index)) for index in range(len(values))],
            )
            for statistic, function in GROUP_STATISTICS.items()
        }
        lines = [f"group {bootstrap.group.name} n {len(values)}"]
        for statistic, summary in bootstrap.summaries.items():
            jackknife = jackknives[statistic]
            lines.append(
                f"jackknife {statistic} estimate {real(summary.estimate)}"
                f" average {real(jackknife.average)} bias {real(jackknife.bias)}"
                f" se {real(jackknife.se)}"
            )
        for statistic, summary in bootstrap.summaries.items():
            lines.append(self.bca_line(statistic, summary, jackknives[statistic]))
        lines.extend(self.after_bootstrap_lines(bootstrap, jackknives["mean"]))
        return lines

    def jackknife_file(self, ordinary, pairs):
        lines = []
        for bootstrap in ordinary:
            lines.extend(self.group_jackknife_lines(bootstrap))
        for pair in pairs:
            lines.extend(pair_jackknife_lines(pair))
        return lines

    def permutation_lines(self, x, y):
        permutations = self.settings.permutations
        combined = x + y
        ranks = doubled_ranks(combined)
        positions = list(range(len(combined)))
        observed = split_statistics(combined, ranks, positions, len(x))
        tallies = [Tally(value) for value in observed]
        for _ in range(permutations):
            order = positions[:]
            self.generator.shuffle(order)
            for tally, value in zip(tallies, split_statistics(combined, ranks, order, len(x))):
                tally.count(value)
        k = len(x)
        m = len(y)
        rank_total = sum(ranks[:k])
        results = [tally.text(1, permutations + 1) for tally in tallies]
        lines = [
            f"permutation n {k} {m} perms {permutations}",
            f"mean diff {real(mean_difference(x, y))} {results[0]}",
            f"median diff {real(observed[1] / 200)} {results[1]}",
            f"ranksum w {real(rank_total / 2)} u {real((rank_total - k * (k + 1)) / 2)} {results[2]}",
            f"absdev diff {real(observed[3] / (200 * k * m))} {results[3]}",
        ]
        return lines, [tally.extreme for tally in tallies]

    def simulation_rejects(self, first, second):
        settings = self.settings
        k = len(first)
        m = len(second)
        combined = first + second
        total = sum(combined)
        observed = abs(contrast(sum(first), k, sum(second), m))
        count = 0
        for _ in range(settings.power_perms):
            shuffled = combined[:]
            self.generator.shuffle(shuffled)
            head = sum(shuffled[:k])
            if abs(contrast(head, k, total - head, m)) >= observed:
                count += 1
        return 100 * (count + 1) <= (100 - settings.confidence) * (settings.power_perms + 1)

    def power_line(self, x, y):
        settings = self.settings
        rejections = 0
        for _ in range(settings.power_sims):
            first = [x[index] for index in resample_indices(self.generator, len(x))]
            second = [y[index] for index in resample_indices(self.generator, len(y))]
            if self.simulation_rejects(first, second):
                rejections += 1
        power = rejections / settings.power_sims
        se = sqrt(power * (1 - power) / settings.power_sims)
        return (
            f"power sims {settings.power_sims} perms {settings.power_perms}"
            f" rejections {rejections} power {real(power)} se {real(se)}"
        )

    def critical_line(self, mean_values, size, splits):
        critical = None
        cumulative = 0
        for value, count in reversed(value_counts([abs(value) for value in mean_values])):
            cumulative += count
            if 100 * cumulative > (100 - self.settings.confidence) * splits:
                break
            critical = value, cumulative
        if critical is None:
            return "critical diff none attained none"
        value, cumulative = critical
        return (
            f"critical diff {real(value / (100 * size * size))}"
            f" attained {p_value(cumulative, splits)}"
        )

    def exact_lines(self, x, y):
        size = self.settings.pilot
        combined = x[:size] + y[:size]
        ranks = doubled_ranks(combined)
        total = sum(combined)
        mean_values = []
        rank_values = []
        for choice in position_choices(2 * size, size):
            chosen = sum(combined[index] for index in choice)
            mean_values.append(contrast(chosen, size, total - chosen, size))
            rank_values.append(sum(ranks[index] for index in choice) - size * (2 * size + 1))
        splits = len(mean_values)
        mean_tally = Tally(mean_values[0])
        rank_tally = Tally(rank_values[0])
        for mean_value, rank_value in zip(mean_values, rank_values):
            mean_tally.count(mean_value)
            rank_tally.count(rank_value)
        rank_total = sum(ranks[:size])
        difference = mean_difference(x[:size], y[:size])
        return [
            f"exact size {size} splits {splits}",
            f"mean diff {real(difference)} {mean_tally.text(0, splits)}",
            f"ranksum w {real(rank_total / 2)} u {real((rank_total - size * (size + 1)) / 2)}"
            f" {rank_tally.text(0, splits)}",
            self.critical_line(mean_values, size, splits),
        ]

    def studentized_lines(self, pair):
        x = pair.first.group.values
        y = pair.second.group.values
        k = len(x)
        m = len(y)
        estimate = mean_difference(x, y)
        first_sd = sd(x)
        second_sd = sd(y)
        first_variance = first_sd * first_sd / k
        second_variance = second_sd * second_sd / m
        se0 = sqrt(first_variance + second_variance)
        t = estimate / se0
        statistics = []
        for difference, first_replicate, second_replicate in zip(
            pair.summaries["mean_diff"].values,
            pair.first.summaries["sd"].values,
            pair.second.summaries["sd"].values,
        ):
            spread = sqrt(
                first_replicate * first_replicate / k + second_replicate * second_replicate / m
            )
            statistics.append((difference - estimate) / spread)
        extreme = sum(1 for value in statistics if abs(value) >= abs(t))
        ordered = sorted(statistics)
        lower = estimate - ordered[self.ranks[1] - 1] * se0
        upper = estimate - ordered[self.ranks[0] - 1] * se0
        degrees = (first_variance + second_variance) * (first_variance + second_variance) / (
            first_variance * first_variance / (k - 1) + second_variance * second_variance / (m - 1)
        )
        greater = sum(1 for a in x for b in y if a > b)
        equal = sum(1 for a in x for b in y if a == b)
        d = cohen_d(x, y)
        hedges = d * (1 - 3 / (4 * (k + m - 2) - 1))
        cles = (2 * greater + equal) / (2 * k * m)
        replicates = self.settings.bootstrap
        return [
            f"bootstrap_t t {real(t)} df {real(degrees)} extreme {extreme}"
            f" p {p_value(extreme + 1, replicates + 1)} interval {real(lower)} {real(upper)}",
            f"effect pooled_sd {real(pooled_sd(x, y))} cohen_d {real(d)}"
            f" hedges_g {real(hedges)} cles {real(cles)}",
        ]

    def pair_test_lines(self, pair):
        first = pair.first.group
        second = pair.second.group
        lines = [f"compare {first.name} {second.name}"]
        permutation, extremes = self.permutation_lines(first.values, second.values)
        lines.extend(permutation)
        lines.append(self.power_line(first.values, second.values))
        lines.extend(self.exact_lines(first.values, second.values))
        lines.extend(self.studentized_lines(pair))
        return lines, extremes

    def holm_lines(self, extremes):
        permutations = self.settings.permutations
        count = len(self.pairs)
        lines = []
        for column, statistic in enumerate(TEST_STATISTICS):
            values = [pair_extremes[column] for pair_extremes in extremes]
            order = sorted(range(count), key=lambda index: (values[index], index))
            adjusted = 0
            for rank, index in enumerate(order, 1):
                extreme = values[index]
                adjusted = max(adjusted, min(permutations + 1, (count - rank + 1) * (extreme + 1)))
                rejected = 100 * adjusted <= (100 - self.settings.confidence) * (permutations + 1)
                first, second = self.pairs[index]
                lines.append(
                    f"holm {statistic} rank {rank} {first.name} {second.name}"
                    f" p {p_value(extreme + 1, permutations + 1)}"
                    f" adjusted {p_value(adjusted, permutations + 1)}"
                    f" {'reject' if rejected else 'retain'}"
                )
        return lines

    def paired_lines(self, mean_summary, correlation_summary):
        before = self.paired.before
        after = self.paired.after
        differences = self.paired.differences
        count = len(differences)
        positive = sum(1 for difference in differences if difference > 0)
        negative = sum(1 for difference in differences if difference < 0)
        zero = count - positive - negative
        average = mean(differences)
        deviation = sd(differences)
        r = correlation(before, after)
        z = 0.5 * log((1 + r) / (1 - r))
        half_width = -self.z_low / sqrt(count - 3)
        return [
            f"paired subjects {count} positive {positive} negative {negative} zero {zero}",
            f"paired before {real(mean(before))} after {real(mean(after))} diff {real(average)}"
            f" sd_diff {real(deviation)} t {real(average / (deviation / sqrt(count)))}"
            f" dz {real(average / deviation)}",
            f"paired_bootstrap {mean_summary.interval_text()}",
            f"correlation r {real(r)} {correlation_summary.interval_text()}"
            f" fisher {real(hyperbolic_tangent(z - half_width))}"
            f" {real(hyperbolic_tangent(z + half_width))}",
        ]

    def sign_flip_lines(self):
        permutations = self.settings.permutations
        differences = self.paired.differences
        signed = signed_ranks(differences)
        mean_tally = Tally(sum(differences))
        rank_tally = Tally(sum(signed))
        for _ in range(permutations):
            signs = [-1 if self.generator.draw() % 2 == 1 else 1 for _ in differences]
            mean_tally.count(sum(sign * value for sign, value in zip(signs, differences)))
            rank_tally.count(sum(sign * rank for sign, rank in zip(signs, signed)))
        w_plus = sum(rank for rank in signed if rank > 0) / 2
        return [
            f"signflip flips {permutations}",
            f"mean diff {real(mean(differences))} {mean_tally.text(1, permutations + 1)}",
            f"signedrank w_plus {real(w_plus)} {rank_tally.text(1, permutations + 1)}",
        ]

    def anova_permutation_lines(self, combined, ranks, sizes, f, h, correction):
        permutations = self.settings.permutations
        group_count = len(sizes)
        total_count = len(combined)
        pairs = [(i, j) for i in range(group_count) for j in range(i + 1, group_count)]
        observed = group_deltas(split_list(combined, sizes), pairs)
        f_extreme = 0
        h_extreme = 0
        extremes = [0] * len(pairs)
        maxima = [0] * len(pairs)
        positions = list(range(total_count))
        for _ in range(permutations):
            order = positions[:]
            self.generator.shuffle(order)
            parts = split_list(order, sizes)
            samples = [[combined[index] for index in part] for part in parts]
            between, within = sums_of_squares(samples)
            if f_statistic(between, within, group_count, total_count) >= f - TOLERANCE * f:
                f_extreme += 1
            rank_sums = [sum(ranks[index] for index in part) for part in parts]
            if h_statistic(rank_sums, sizes, correction) >= h - TOLERANCE * h:
                h_extreme += 1
            deltas = group_deltas(samples, pairs)
            largest = largest_delta(deltas)
            for number, bound in enumerate(observed):
                if delta_at_least(deltas[number], bound):
                    extremes[number] += 1
                if delta_at_least(largest, bound):
                    maxima[number] += 1
        lines = [
            f"anova_permutation perms {permutations} f_extreme {f_extreme}"
            f" f_p {p_value(f_extreme + 1, permutations + 1)} h_extreme {h_extreme}"
            f" h_p {p_value(h_extreme + 1, permutations + 1)}"
        ]
        for (i, j), extreme, maximum in zip(pairs, extremes, maxima):
            first = self.groups[i]
            second = self.groups[j]
            difference = mean_difference(first.values, second.values)
            lines.append(
                f"pairwise {first.name} {second.name} diff {real(difference)}"
                f" extreme {extreme} p {p_value(extreme + 1, permutations + 1)}"
                f" maxt {maximum} adjusted {p_value(maximum + 1, permutations + 1)}"
            )
        return lines

    def anova_lines(self, ordinary):
        samples = [group.values for group in self.groups]
        sizes = [len(sample) for sample in samples]
        group_count = len(samples)
        total_count = sum(sizes)
        between, within = sums_of_squares(samples)
        f = f_statistic(between, within, group_count, total_count)
        eta = between / (between + within)
        msw = within / (total_count - group_count)
        omega = (between - (group_count - 1) * msw) / (between + within + msw)
        eta_values = []
        for number in range(self.settings.bootstrap):
            replicate_between, replicate_within = sums_of_squares(
                [bootstrap.samples[number] for bootstrap in ordinary]
            )
            eta_values.append(replicate_between / (replicate_between + replicate_within))
        eta_summary = Summary(eta, eta_values, self.ranks)
        combined = [value for sample in samples for value in sample]
        ranks = doubled_ranks(combined)
        rank_sums = [sum(part) for part in split_list(ranks, sizes)]
        ties = [count for _, count in value_counts(combined) if count >= 2]
        tie_total = sum(count * count * count - count for count in ties)
        correction = 1 - tie_total / (total_count * total_count * total_count - total_count)
        h = h_statistic(rank_sums, sizes, correction)
        lines = [
            f"anova groups {group_count} observations {total_count} ssb {real(between)}"
            f" ssw {real(within)} df {group_count - 1} {total_count - group_count} f {real(f)}"
            f" eta_squared {real(eta)} omega_squared {real(omega)}",
            f"eta_bootstrap {eta_summary.interval_text()}",
            welch_line(samples),
            f"kruskal h {real(h)} tie_groups {len(ties)}",
        ]
        lines.extend(self.anova_permutation_lines(combined, ranks, sizes, f, h, correction))
        return lines

    def run(self):
        replicates = self.settings.bootstrap
        ordinary = [
            GroupBootstrap(
                group, ordinary_indices(self.generator, len(group.values), replicates), self.ranks
            )
            for group in self.groups
        ]
        balanced = [
            GroupBootstrap(
                group, balanced_indices(self.generator, len(group.values), replicates), self.ranks
            )
            for group in self.groups
        ]
        mean_summary, correlation_summary = self.paired_bootstrap()
        pairs = [
            PairBootstrap(ordinary[first.number - 1], ordinary[second.number - 1], self.ranks)
            for first, second in self.pairs
        ]
        test_lines = []
        extremes = []
        for pair in pairs:
            lines, pair_extremes = self.pair_test_lines(pair)
            test_lines.extend(lines)
            extremes.append(pair_extremes)
        test_lines.extend(self.holm_lines(extremes))
        test_lines.extend(self.paired_lines(mean_summary, correlation_summary))
        test_lines.extend(self.sign_flip_lines())
        test_lines.extend(self.anova_lines(ordinary))
        return [
            ("descriptives.txt", self.descriptive_lines()),
            ("bootstrap.csv", bootstrap_lines(ordinary, balanced, pairs)),
            ("jackknife.txt", self.jackknife_file(ordinary, pairs)),
            ("tests.txt", test_lines),
            ("histograms.txt", self.histogram_file(ordinary, pairs)),
        ]


def main():
    study = Study(load_dataset("input"))
    files = study.run()
    os.makedirs("output", exist_ok=True)
    for name, lines in files:
        write_lines(os.path.join("output", name), lines)


if __name__ == "__main__":
    main()
