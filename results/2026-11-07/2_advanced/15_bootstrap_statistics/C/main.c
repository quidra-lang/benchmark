#include "statistics.h"

static const char *group_names[] = {"mean", "median", "trimmed_mean", "sd"};
static const char *pair_names[] = {"mean_diff", "median_ratio", "hodges_lehmann", "cohen_d"};
static const char *test_names[] = {"mean", "median", "ranksum", "absdev"};
typedef struct {
    double estimate, average, se, bias, low, high, basic_low, basic_high;
    Values values, ordered;
} Summary;
typedef struct { int *indices; Integer *samples; Summary ordinary[4], balanced[4]; } GroupResult;
typedef struct { int first, second; char *name; Summary summaries[4]; Integer extremes[4]; } PairResult;
typedef struct { Values values; double average, variance, bias, se; } Jackknife;
typedef struct { Integer observed, extreme, greater; } Tally;
typedef struct {
    Dataset data;
    Minstd generator;
    int low_rank, high_rank;
    double z_low;
    GroupResult groups[4];
    PairResult pairs[6];
    Summary paired_mean, paired_correlation;
} Study;
static Values values_new(int count) { return (Values){allocate((size_t)count * sizeof(double)), count}; }
static Summary summarize(const Study *study, double estimate, Values values) {
    Summary result = {.estimate = estimate, .values = values, .ordered = values_new(values.n)};
    memcpy(result.ordered.v, values.v, (size_t)values.n * sizeof(double));
    qsort(result.ordered.v, (size_t)values.n, sizeof(double), compare_real);
    Spread spread = mean_and_se(values);
    result.average = spread.average;
    result.se = spread.se;
    result.bias = spread.average - estimate;
    result.low = result.ordered.v[study->low_rank - 1];
    result.high = result.ordered.v[study->high_rank - 1];
    result.basic_low = 2 * estimate - result.high;
    result.basic_high = 2 * estimate - result.low;
    return result;
}
static char *interval(Summary summary) {
    return format("se %s bias %s percentile %s %s basic %s %s", real_text(summary.se), real_text(summary.bias), real_text(summary.low), real_text(summary.high), real_text(summary.basic_low), real_text(summary.basic_high));
}
static char *summary_csv(const char *name, const char *statistic, Summary summary) {
    return format("%s,%s,%s,%s,%s,%s,%s,%s,%s", name, statistic, real_text(summary.estimate), real_text(summary.se), real_text(summary.bias), real_text(summary.low), real_text(summary.high), real_text(summary.basic_low), real_text(summary.basic_high));
}
static Jackknife jackknife(double estimate, Values values) {
    Jackknife result = {.values = values, .average = sequential_sum(values) / values.n};
    double squares = 0;
    for (int i = 0; i < values.n; ++i) { double difference = values.v[i] - result.average; squares += difference * difference; }
    result.variance = (values.n - 1) * squares / values.n;
    result.bias = (values.n - 1) * (result.average - estimate);
    result.se = sqrt(result.variance);
    return result;
}
static void tally_count(Tally *tally, Integer value) {
    if (llabs(value) >= llabs(tally->observed)) ++tally->extreme;
    if (value >= tally->observed) ++tally->greater;
}
static char *tally_text(Tally tally, Integer offset, Integer denominator) {
    return format("extreme %lld greater %lld p_two %s p_greater %s", tally.extreme, tally.greater, p_value(tally.extreme + offset, denominator), p_value(tally.greater + offset, denominator));
}
static Sample replicate(const Study *study, int group, int number) {
    int count = study->data.groups[group].count;
    return (Sample){study->groups[group].samples + number * count, count};
}
static void bootstraps(Study *study) {
    Dataset *data = &study->data;
    int count = data->settings.bootstrap;
    for (int g = 0; g < data->group_count; ++g) {
        Sample original = group_sample(&data->groups[g]);
        GroupResult *result = &study->groups[g];
        result->indices = ordinary_indices(&study->generator, original.n, count);
        result->samples = allocate((size_t)original.n * count * sizeof(Integer));
        Values columns[4];
        for (int s = 0; s < 4; ++s) columns[s] = values_new(count);
        for (int r = 0; r < count; ++r) {
            Sample sample = chosen(original, result->indices + r * original.n, original.n, result->samples + r * original.n);
            double statistics[4];
            group_statistics(sample, statistics);
            for (int s = 0; s < 4; ++s) columns[s].v[r] = statistics[s];
        }
        double estimates[4];
        group_statistics(original, estimates);
        for (int s = 0; s < 4; ++s) result->ordinary[s] = summarize(study, estimates[s], columns[s]);
    }
    for (int g = 0; g < data->group_count; ++g) {
        Sample original = group_sample(&data->groups[g]);
        int *indices = balanced_indices(&study->generator, original.n, count);
        Values columns[4];
        for (int s = 0; s < 4; ++s) columns[s] = values_new(count);
        for (int r = 0; r < count; ++r) {
            Integer storage[80];
            double statistics[4];
            group_statistics(chosen(original, indices + r * original.n, original.n, storage), statistics);
            for (int s = 0; s < 4; ++s) columns[s].v[r] = statistics[s];
        }
        for (int s = 0; s < 4; ++s) study->groups[g].balanced[s] = summarize(study, study->groups[g].ordinary[s].estimate, columns[s]);
    }
    Values means = values_new(count), correlations = values_new(count);
    Sample before = {data->before, data->subjects}, after = {data->after, data->subjects}, differences = {data->differences, data->subjects};
    for (int r = 0; r < count; ++r) {
        int indices[60];
        Integer x[60], y[60], d[60];
        resample_indices(&study->generator, data->subjects, indices);
        means.v[r] = mean(chosen(differences, indices, data->subjects, d));
        Sample first = chosen(before, indices, data->subjects, x), second = chosen(after, indices, data->subjects, y);
        correlations.v[r] = correlation(first, second);
    }
    study->paired_mean = summarize(study, mean(differences), means);
    study->paired_correlation = summarize(study, correlation(before, after), correlations);
    for (int p = 0; p < data->pair_count; ++p) {
        PairResult *result = &study->pairs[p];
        result->first = data->pairs[p][0];
        result->second = data->pairs[p][1];
        result->name = format("%s-%s", data->groups[result->first].name, data->groups[result->second].name);
        Values columns[4];
        for (int s = 0; s < 4; ++s) columns[s] = values_new(count);
        for (int r = 0; r < count; ++r) {
            double statistics[4];
            pair_statistics(replicate(study, result->first, r), replicate(study, result->second, r), statistics);
            for (int s = 0; s < 4; ++s) columns[s].v[r] = statistics[s];
        }
        double estimates[4];
        pair_statistics(group_sample(&data->groups[result->first]), group_sample(&data->groups[result->second]), estimates);
        for (int s = 0; s < 4; ++s) result->summaries[s] = summarize(study, estimates[s], columns[s]);
    }
}
static Integer minimum(Sample values) {
    Integer result = values.v[0];
    for (int i = 1; i < values.n; ++i) if (values.v[i] < result) result = values.v[i];
    return result;
}
static Integer maximum(Sample values) {
    Integer result = values.v[0];
    for (int i = 1; i < values.n; ++i) if (values.v[i] > result) result = values.v[i];
    return result;
}
static int box_position(Integer value, Integer low, Integer high) {
    Integer delta = 100 * (high - low);
    return (int)((120 * (value - 100 * low) + delta) / (2 * delta));
}
static Lines describe(const char *kind, const char *name, Sample sample, Integer low, Integer high, bool stems) {
    Integer ordered[sample.n], wins[sample.n], inside[sample.n];
    memcpy(ordered, sample.v, sizeof ordered);
    qsort(ordered, (size_t)sample.n, sizeof(*ordered), compare_integer);
    winsorized(sample, wins);
    double center = mean(sample);
    Moments moment = moments(sample);
    Integer q1 = quantile_numerator(sample, 25), q3 = quantile_numerator(sample, 75);
    int outliers[80], out_count = 0, in_count = 0;
    for (int i = 0; i < sample.n; ++i) {
        Integer value = sample.v[i];
        if (200 * value < 5 * q1 - 3 * q3 || 200 * value > 5 * q3 - 3 * q1) outliers[out_count++] = i + 1;
        else inside[in_count++] = value;
    }
    Integer w1 = minimum((Sample){inside, in_count}), w2 = maximum((Sample){inside, in_count});
    char band[62];
    memset(band, '.', 61);
    band[61] = '\0';
    for (int i = box_position(100 * w1, low, high); i <= box_position(100 * w2, low, high); ++i) band[i] = '-';
    for (int i = box_position(q1, low, high); i <= box_position(q3, low, high); ++i) band[i] = '=';
    band[box_position(quantile_numerator(sample, 50), low, high)] = '|';
    for (int i = 0; i < out_count; ++i) band[box_position(100 * sample.v[outliers[i] - 1], low, high)] = 'o';
    Lines lines = {0};
    add_line(&lines, "%s %s", kind, name);
    add_line(&lines, "n %d", sample.n);
    add_line(&lines, "mean %s", real_text(center));
    add_line(&lines, "median %s", real_text(median(sample)));
    add_line(&lines, "trimmed_mean %s trim %d", real_text(trimmed_mean(sample)), sample.n / 10);
    add_line(&lines, "winsorized_mean %s winsorized_sd %s", real_text(mean((Sample){wins, sample.n})), real_text(sd((Sample){wins, sample.n})));
    add_line(&lines, "sd %s", real_text(moment.sd));
    add_line(&lines, "se_mean %s", real_text(moment.sd / sqrt(sample.n)));
    add_line(&lines, "cv %s", real_text(moment.sd / center));
    add_line(&lines, "skewness %s", real_text(moment.third / (moment.second * sqrt(moment.second))));
    add_line(&lines, "kurtosis %s", real_text(moment.fourth / (moment.second * moment.second) - 3));
    add_line(&lines, "mad %s", real_text(mad(sample)));
    add_line(&lines, "min %s", real_text((double)ordered[0] / 100));
    add_line(&lines, "q1 %s", real_text((double)q1 / 10000));
    add_line(&lines, "q3 %s", real_text((double)q3 / 10000));
    add_line(&lines, "iqr %s", real_text((double)(q3 - q1) / 10000));
    add_line(&lines, "max %s", real_text((double)ordered[sample.n - 1] / 100));
    add_line(&lines, "percentiles p05 %s p10 %s p90 %s p95 %s", real_text((double)quantile_numerator(sample, 5) / 10000), real_text((double)quantile_numerator(sample, 10) / 10000), real_text((double)quantile_numerator(sample, 90) / 10000), real_text((double)quantile_numerator(sample, 95) / 10000));
    add_line(&lines, "whiskers %s %s", real_text((double)w1 / 100), real_text((double)w2 / 100));
    add_line(&lines, "outliers %s", number_list(outliers, out_count));
    add_line(&lines, "box %s", band);
    if (stems) for (Integer stem = ordered[0] / 100; stem <= ordered[sample.n - 1] / 100; ++stem) {
        char leaves[81];
        int count = 0;
        for (int i = 0; i < sample.n; ++i) if (ordered[i] / 100 == stem) leaves[count++] = (char)('0' + ordered[i] % 100 / 10);
        leaves[count] = '\0';
        add_line(&lines, "stem %lld%s%s", stem, count ? " " : "", leaves);
    }
    return lines;
}
static Lines descriptive_lines(Study *study) {
    Dataset *data = &study->data;
    Integer combined[320];
    int count = 0;
    for (int g = 0; g < data->group_count; ++g) for (int i = 0; i < data->groups[g].count; ++i) combined[count++] = data->groups[g].values[i];
    Integer low = minimum((Sample){combined, count}), high = maximum((Sample){combined, count});
    Lines lines = {0};
    add_line(&lines, "groups %d observations %d", data->group_count, count);
    for (int g = 0; g < data->group_count; ++g) extend(&lines, describe("group", data->groups[g].name, group_sample(&data->groups[g]), low, high, true));
    memcpy(combined, data->before, (size_t)data->subjects * sizeof(Integer));
    memcpy(combined + data->subjects, data->after, (size_t)data->subjects * sizeof(Integer));
    low = minimum((Sample){combined, 2 * data->subjects});
    high = maximum((Sample){combined, 2 * data->subjects});
    add_line(&lines, "paired subjects %d", data->subjects);
    extend(&lines, describe("series", "before", (Sample){data->before, data->subjects}, low, high, false));
    extend(&lines, describe("series", "after", (Sample){data->after, data->subjects}, low, high, false));
    Sample differences = {data->differences, data->subjects};
    extend(&lines, describe("series", "diff", differences, minimum(differences), maximum(differences), false));
    return lines;
}
static Lines bootstrap_lines(const Study *study) {
    Lines lines = {0};
    add_line(&lines, "group,statistic,estimate,se,bias,percentile_lo,percentile_hi,basic_lo,basic_hi");
    for (int g = 0; g < study->data.group_count; ++g) {
        for (int s = 0; s < 4; ++s) add_line(&lines, "%s", summary_csv(study->data.groups[g].name, group_names[s], study->groups[g].ordinary[s]));
        for (int s = 0; s < 4; ++s) add_line(&lines, "%s", summary_csv(study->data.groups[g].name, format("balanced_%s", group_names[s]), study->groups[g].balanced[s]));
    }
    for (int p = 0; p < study->data.pair_count; ++p) for (int s = 0; s < 4; ++s) add_line(&lines, "%s", summary_csv(study->pairs[p].name, pair_names[s], study->pairs[p].summaries[s]));
    return lines;
}
static int clamp_rank(int rank, int count) { return rank < 1 ? 1 : rank > count ? count : rank; }
static double bca_alpha(double z0, double acceleration, double z) { return phi(z0 + (z0 + z) / (1 - acceleration * (z0 + z))); }
static Lines group_jackknife(const Study *study, int group) {
    Sample sample = group_sample(&study->data.groups[group]);
    const GroupResult *bootstrap = &study->groups[group];
    int count = study->data.settings.bootstrap;
    double deleted[4][80];
    for (int i = 0; i < sample.n; ++i) {
        Integer storage[80];
        double statistics[4];
        group_statistics(without(sample, i, storage), statistics);
        for (int s = 0; s < 4; ++s) deleted[s][i] = statistics[s];
    }
    Jackknife jackknives[4];
    Lines lines = {0};
    add_line(&lines, "group %s n %d", study->data.groups[group].name, sample.n);
    for (int s = 0; s < 4; ++s) {
        jackknives[s] = jackknife(bootstrap->ordinary[s].estimate, (Values){deleted[s], sample.n});
        Jackknife jack = jackknives[s];
        add_line(&lines, "jackknife %s estimate %s average %s bias %s se %s", group_names[s], real_text(bootstrap->ordinary[s].estimate), real_text(jack.average), real_text(jack.bias), real_text(jack.se));
    }
    for (int s = 0; s < 4; ++s) {
        Summary summary = bootstrap->ordinary[s];
        Integer below_count = 0;
        for (int r = 0; r < count; ++r) if (summary.values.v[r] < summary.estimate) ++below_count;
        double z0 = phi_inverse((double)below_count / count), squares = 0, cubes = 0;
        for (int i = 0; i < sample.n; ++i) {
            double difference = jackknives[s].average - deleted[s][i];
            squares += difference * difference;
            cubes += difference * difference * difference;
        }
        double acceleration = cubes / (6 * squares * sqrt(squares));
        int first = clamp_rank((int)floor((count + 1) * bca_alpha(z0, acceleration, study->z_low)), count);
        int second = clamp_rank(count + 1 - (int)floor((count + 1) * (1 - bca_alpha(z0, acceleration, -study->z_low))), count);
        add_line(&lines, "bca %s below %lld z0 %s acceleration %s ranks %d %d interval %s %s", group_names[s], below_count, real_text(z0), real_text(acceleration), first, second, real_text(summary.ordered.v[first - 1]), real_text(summary.ordered.v[second - 1]));
    }
    int *omitted = allocate((size_t)sample.n * count * sizeof(int));
    int omitted_counts[80] = {0};
    for (int r = 0; r < count; ++r) {
        bool seen[80] = {0};
        for (int j = 0; j < sample.n; ++j) seen[bootstrap->indices[r * sample.n + j]] = true;
        for (int i = 0; i < sample.n; ++i) if (!seen[i]) omitted[i * count + omitted_counts[i]++] = r;
    }
    double errors[4][80];
    for (int s = 0; s < 4; ++s) {
        for (int i = 0; i < sample.n; ++i) {
            double values[2000];
            for (int j = 0; j < omitted_counts[i]; ++j) values[j] = bootstrap->ordinary[s].values.v[omitted[i * count + j]];
            errors[s][i] = mean_and_se((Values){values, omitted_counts[i]}).se;
        }
        Jackknife spread = jackknife(0, (Values){errors[s], sample.n});
        add_line(&lines, "after_bootstrap %s se %s average %s se_of_se %s", group_names[s], real_text(bootstrap->ordinary[s].se), real_text(spread.average), real_text(spread.se));
    }
    int smallest = count, largest = 0, order[80];
    Integer total = sample_sum(sample);
    for (int i = 0; i < sample.n; ++i) {
        if (omitted_counts[i] < smallest) smallest = omitted_counts[i];
        if (omitted_counts[i] > largest) largest = omitted_counts[i];
        Integer magnitude = llabs(sample.n * sample.v[i] - total);
        int j = i;
        while (j && llabs(sample.n * sample.v[order[j - 1]] - total) < magnitude) { order[j] = order[j - 1]; --j; }
        order[j] = i;
    }
    add_line(&lines, "without min %d max %d", smallest, largest);
    for (int rank = 0; rank < 5; ++rank) {
        int index = order[rank], size = omitted_counts[index];
        double shifted[2000];
        for (int j = 0; j < size; ++j) shifted[j] = bootstrap->ordinary[0].values.v[omitted[index * count + j]] - bootstrap->ordinary[0].estimate;
        qsort(shifted, (size_t)size, sizeof(double), compare_real);
        double influence = (sample.n - 1) * (jackknives[0].average - deleted[0][index]);
        add_line(&lines, "influence %d obs %d value %s l %s without %d se %s q05 %s q50 %s q95 %s", rank + 1, index + 1, real_text((double)sample.v[index] / 100), real_text(influence), size, real_text(errors[0][index]), real_text(shifted[(5 * size + 99) / 100 - 1]), real_text(shifted[(50 * size + 99) / 100 - 1]), real_text(shifted[(95 * size + 99) / 100 - 1]));
    }
    return lines;
}
static Lines pair_jackknife(const Study *study, const PairResult *pair) {
    Sample x = group_sample(&study->data.groups[pair->first]), y = group_sample(&study->data.groups[pair->second]);
    double deleted[2][4][80];
    for (int i = 0; i < x.n; ++i) {
        Integer storage[80];
        double statistics[4];
        pair_statistics(without(x, i, storage), y, statistics);
        for (int s = 0; s < 4; ++s) deleted[0][s][i] = statistics[s];
    }
    for (int i = 0; i < y.n; ++i) {
        Integer storage[80];
        double statistics[4];
        pair_statistics(x, without(y, i, storage), statistics);
        for (int s = 0; s < 4; ++s) deleted[1][s][i] = statistics[s];
    }
    Lines lines = {0};
    for (int s = 0; s < 4; ++s) {
        double bias = 0, variance = 0;
        for (int part = 0; part < 2; ++part) {
            Jackknife jack = jackknife(pair->summaries[s].estimate, (Values){deleted[part][s], part ? y.n : x.n});
            bias += jack.bias;
            variance += jack.variance;
        }
        add_line(&lines, "pair %s %s estimate %s bias %s se %s", pair->name, pair_names[s], real_text(pair->summaries[s].estimate), real_text(bias), real_text(sqrt(variance)));
    }
    return lines;
}
static Lines jackknife_lines(const Study *study) {
    Lines lines = {0};
    for (int g = 0; g < study->data.group_count; ++g) extend(&lines, group_jackknife(study, g));
    for (int p = 0; p < study->data.pair_count; ++p) extend(&lines, pair_jackknife(study, &study->pairs[p]));
    return lines;
}
static Lines histogram(const Study *study, const char *name, const char *statistic, Summary summary) {
    int bins = study->data.settings.bins, counts[40] = {0}, top = 0;
    double low = summary.ordered.v[0], high = summary.ordered.v[summary.ordered.n - 1];
    for (int r = 0; r < summary.values.n; ++r) ++counts[bin_number(summary.values.v[r], low, high, bins) - 1];
    for (int i = 0; i < bins; ++i) if (counts[i] > top) top = counts[i];
    int estimate = summary.estimate >= low && summary.estimate <= high ? bin_number(summary.estimate, low, high, bins) : 0;
    int first = bin_number(summary.low, low, high, bins), last = bin_number(summary.high, low, high, bins);
    Lines lines = {0};
    add_line(&lines, "histogram %s %s min %s max %s width %s top %d estimate_bin %s", name, statistic, real_text(low), real_text(high), real_text((high - low) / bins), top, estimate ? format("%d", estimate) : "none");
    char *convergence = "convergence";
    for (int quarter = 1; quarter <= 4; ++quarter) {
        int size = quarter * summary.values.n / 4;
        convergence = format("%s %d:%s", convergence, size, real_text(mean_and_se((Values){summary.values.v, size}).se));
    }
    add_line(&lines, "%s", convergence);
    for (int i = 0; i < bins; ++i) {
        char *line = format("bin %d %s %d", i + 1, real_text(low + (high - low) * i / bins), counts[i]);
        if (counts[i]) line = format("%s %s", line, bar(counts[i], top));
        if (i + 1 == first) line = format("%s L", line);
        if (i + 1 == estimate) line = format("%s E", line);
        if (i + 1 == last) line = format("%s H", line);
        add_line(&lines, "%s", line);
    }
    return lines;
}
static Lines histogram_lines(const Study *study) {
    Lines lines = {0};
    for (int g = 0; g < study->data.group_count; ++g) for (int s = 0; s < 4; ++s) extend(&lines, histogram(study, study->data.groups[g].name, group_names[s], study->groups[g].ordinary[s]));
    for (int p = 0; p < study->data.pair_count; ++p) for (int s = 0; s < 4; ++s) extend(&lines, histogram(study, study->pairs[p].name, pair_names[s], study->pairs[p].summaries[s]));
    return lines;
}
static void split_statistics(Sample values, const Integer *ranks, const int *order, int size, Integer result[4]) {
    Integer shuffled[160], rank_total = 0;
    for (int i = 0; i < values.n; ++i) {
        shuffled[i] = values.v[order[i]];
        if (i < size) rank_total += ranks[order[i]];
    }
    Sample first = {shuffled, size}, second = {shuffled + size, values.n - size};
    Integer first_median = doubled_median(first), second_median = doubled_median(second), first_deviation = 0, second_deviation = 0;
    for (int i = 0; i < first.n; ++i) first_deviation += llabs(2 * first.v[i] - first_median);
    for (int i = 0; i < second.n; ++i) second_deviation += llabs(2 * second.v[i] - second_median);
    result[0] = contrast(first, second);
    result[1] = first_median - second_median;
    result[2] = rank_total - size * (Integer)(values.n + 1);
    result[3] = second.n * first_deviation - first.n * second_deviation;
}
static Lines permutation_lines(Study *study, PairResult *pair) {
    Sample x = group_sample(&study->data.groups[pair->first]), y = group_sample(&study->data.groups[pair->second]);
    Integer combined[160], ranks[160], observed[4];
    int order[160], count = x.n + y.n;
    memcpy(combined, x.v, (size_t)x.n * sizeof(Integer));
    memcpy(combined + x.n, y.v, (size_t)y.n * sizeof(Integer));
    doubled_ranks((Sample){combined, count}, ranks);
    for (int i = 0; i < count; ++i) order[i] = i;
    split_statistics((Sample){combined, count}, ranks, order, x.n, observed);
    Tally tallies[4];
    for (int s = 0; s < 4; ++s) tallies[s] = (Tally){observed[s], 0, 0};
    for (int r = 0; r < study->data.settings.permutations; ++r) {
        for (int i = 0; i < count; ++i) order[i] = i;
        shuffle(&study->generator, order, count);
        Integer statistics[4];
        split_statistics((Sample){combined, count}, ranks, order, x.n, statistics);
        for (int s = 0; s < 4; ++s) tally_count(&tallies[s], statistics[s]);
    }
    Integer rank_total = 0;
    for (int i = 0; i < x.n; ++i) rank_total += ranks[i];
    Integer denominator = study->data.settings.permutations + 1;
    Lines lines = {0};
    add_line(&lines, "permutation n %d %d perms %d", x.n, y.n, study->data.settings.permutations);
    add_line(&lines, "mean diff %s %s", real_text(mean_difference(x, y)), tally_text(tallies[0], 1, denominator));
    add_line(&lines, "median diff %s %s", real_text((double)observed[1] / 200), tally_text(tallies[1], 1, denominator));
    add_line(&lines, "ranksum w %s u %s %s", real_text((double)rank_total / 2), real_text((double)(rank_total - x.n * (Integer)(x.n + 1)) / 2), tally_text(tallies[2], 1, denominator));
    add_line(&lines, "absdev diff %s %s", real_text((double)observed[3] / (200 * (Integer)x.n * y.n)), tally_text(tallies[3], 1, denominator));
    for (int s = 0; s < 4; ++s) pair->extremes[s] = tallies[s].extreme;
    return lines;
}
static char *power_line(Study *study, const PairResult *pair) {
    Sample x = group_sample(&study->data.groups[pair->first]), y = group_sample(&study->data.groups[pair->second]);
    Settings settings = study->data.settings;
    int rejections = 0, count = x.n + y.n;
    for (int e = 0; e < settings.simulations; ++e) {
        Integer combined[160], shuffled[160];
        int indices[80], order[160];
        resample_indices(&study->generator, x.n, indices);
        chosen(x, indices, x.n, combined);
        resample_indices(&study->generator, y.n, indices);
        chosen(y, indices, y.n, combined + x.n);
        Integer observed = llabs(contrast((Sample){combined, x.n}, (Sample){combined + x.n, y.n})), extreme = 0;
        for (int r = 0; r < settings.inner_permutations; ++r) {
            for (int i = 0; i < count; ++i) order[i] = i;
            shuffle(&study->generator, order, count);
            chosen((Sample){combined, count}, order, count, shuffled);
            if (llabs(contrast((Sample){shuffled, x.n}, (Sample){shuffled + x.n, y.n})) >= observed) ++extreme;
        }
        if (100 * (extreme + 1) <= (100 - settings.confidence) * (settings.inner_permutations + 1)) ++rejections;
    }
    double power = (double)rejections / settings.simulations;
    return format("power sims %d perms %d rejections %d power %s se %s", settings.simulations, settings.inner_permutations, rejections, real_text(power), real_text(sqrt(power * (1 - power) / settings.simulations)));
}
static Lines exact_lines(const Study *study, const PairResult *pair) {
    int q = study->data.settings.pilot;
    Sample x = {study->data.groups[pair->first].values, q}, y = {study->data.groups[pair->second].values, q};
    Integer combined[16], ranks[16], absolute[12870];
    int choice[8];
    memcpy(combined, x.v, (size_t)q * sizeof(Integer));
    memcpy(combined + q, y.v, (size_t)q * sizeof(Integer));
    doubled_ranks((Sample){combined, 2 * q}, ranks);
    Integer total = sample_sum((Sample){combined, 2 * q}), rank_total = sample_sum((Sample){ranks, q});
    Tally means = {contrast(x, y), 0, 0}, rank_sums = {rank_total - q * (Integer)(2 * q + 1), 0, 0};
    for (int i = 0; i < q; ++i) choice[i] = i;
    int splits = 0;
    do {
        Integer chosen_total = 0, chosen_ranks = 0;
        for (int i = 0; i < q; ++i) { chosen_total += combined[choice[i]]; chosen_ranks += ranks[choice[i]]; }
        Integer value = q * chosen_total - q * (total - chosen_total);
        tally_count(&means, value);
        tally_count(&rank_sums, chosen_ranks - q * (Integer)(2 * q + 1));
        absolute[splits++] = llabs(value);
    } while (next_choice(choice, q, 2 * q));
    qsort(absolute, (size_t)splits, sizeof(Integer), compare_integer);
    int cumulative = 0, attained = 0, position = splits;
    Integer critical = 0;
    while (position) {
        Integer value = absolute[position - 1];
        do { --position; ++cumulative; } while (position && absolute[position - 1] == value);
        if (100 * cumulative > (100 - study->data.settings.confidence) * splits) break;
        attained = cumulative;
        critical = value;
    }
    Lines lines = {0};
    add_line(&lines, "exact size %d splits %d", q, splits);
    add_line(&lines, "mean diff %s %s", real_text(mean_difference(x, y)), tally_text(means, 0, splits));
    add_line(&lines, "ranksum w %s u %s %s", real_text((double)rank_total / 2), real_text((double)(rank_total - q * (Integer)(q + 1)) / 2), tally_text(rank_sums, 0, splits));
    if (attained) add_line(&lines, "critical diff %s attained %s", real_text((double)critical / (100 * (Integer)q * q)), p_value(attained, splits));
    else add_line(&lines, "critical diff none attained none");
    return lines;
}
static Lines studentized_lines(const Study *study, const PairResult *pair) {
    Sample x = group_sample(&study->data.groups[pair->first]), y = group_sample(&study->data.groups[pair->second]);
    int count = study->data.settings.bootstrap;
    double sx = sd(x), sy = sd(y), vx = sx * sx / x.n, vy = sy * sy / y.n;
    double se0 = sqrt(vx + vy), estimate = pair->summaries[0].estimate, statistic = estimate / se0, values[2000];
    Integer extreme = 0;
    for (int r = 0; r < count; ++r) {
        double first = study->groups[pair->first].ordinary[3].values.v[r], second = study->groups[pair->second].ordinary[3].values.v[r];
        values[r] = (pair->summaries[0].values.v[r] - estimate) / sqrt(first * first / x.n + second * second / y.n);
        if (fabs(values[r]) >= fabs(statistic)) ++extreme;
    }
    qsort(values, (size_t)count, sizeof(double), compare_real);
    double low = estimate - values[study->high_rank - 1] * se0, high = estimate - values[study->low_rank - 1] * se0;
    double degrees = (vx + vy) * (vx + vy) / (vx * vx / (x.n - 1) + vy * vy / (y.n - 1));
    Integer greater = 0, equal = 0;
    for (int i = 0; i < x.n; ++i) for (int j = 0; j < y.n; ++j) { if (x.v[i] > y.v[j]) ++greater; if (x.v[i] == y.v[j]) ++equal; }
    double d = cohen_d(x, y), hedges = d * (1 - 3.0 / (4 * (x.n + y.n - 2) - 1));
    double cles = (double)(2 * greater + equal) / (2 * (Integer)x.n * y.n);
    Lines lines = {0};
    add_line(&lines, "bootstrap_t t %s df %s extreme %lld p %s interval %s %s", real_text(statistic), real_text(degrees), extreme, p_value(extreme + 1, count + 1), real_text(low), real_text(high));
    add_line(&lines, "effect pooled_sd %s cohen_d %s hedges_g %s cles %s", real_text(pooled_sd(x, y)), real_text(d), real_text(hedges), real_text(cles));
    return lines;
}
static Lines holm_lines(const Study *study) {
    Lines lines = {0};
    Integer denominator = study->data.settings.permutations + 1;
    int count = study->data.pair_count;
    for (int s = 0; s < 4; ++s) {
        int order[6];
        for (int i = 0; i < count; ++i) {
            int j = i;
            while (j && study->pairs[order[j - 1]].extremes[s] > study->pairs[i].extremes[s]) { order[j] = order[j - 1]; --j; }
            order[j] = i;
        }
        Integer adjusted = 0;
        for (int rank = 0; rank < count; ++rank) {
            const PairResult *pair = &study->pairs[order[rank]];
            Integer numerator = pair->extremes[s] + 1, candidate = (count - rank) * numerator;
            if (candidate > denominator) candidate = denominator;
            if (candidate > adjusted) adjusted = candidate;
            bool reject = 100 * adjusted <= (100 - study->data.settings.confidence) * denominator;
            add_line(&lines, "holm %s rank %d %s %s p %s adjusted %s %s", test_names[s], rank + 1, study->data.groups[pair->first].name, study->data.groups[pair->second].name, p_value(numerator, denominator), p_value(adjusted, denominator), reject ? "reject" : "retain");
        }
    }
    return lines;
}
static double hyperbolic_tangent(double value) { double e = exp(2 * value); return (e - 1) / (e + 1); }
static Lines paired_lines(Study *study) {
    Dataset *data = &study->data;
    Sample before = {data->before, data->subjects}, after = {data->after, data->subjects}, differences = {data->differences, data->subjects};
    int positive = 0, negative = 0;
    for (int i = 0; i < data->subjects; ++i) { if (data->differences[i] > 0) ++positive; if (data->differences[i] < 0) ++negative; }
    double average = mean(differences), deviation = sd(differences), r = study->paired_correlation.estimate;
    double z = 0.5 * log((1 + r) / (1 - r)), half = -study->z_low / sqrt(data->subjects - 3);
    Lines lines = {0};
    add_line(&lines, "paired subjects %d positive %d negative %d zero %d", data->subjects, positive, negative, data->subjects - positive - negative);
    add_line(&lines, "paired before %s after %s diff %s sd_diff %s t %s dz %s", real_text(mean(before)), real_text(mean(after)), real_text(average), real_text(deviation), real_text(average / (deviation / sqrt(data->subjects))), real_text(average / deviation));
    add_line(&lines, "paired_bootstrap %s", interval(study->paired_mean));
    add_line(&lines, "correlation r %s %s fisher %s %s", real_text(r), interval(study->paired_correlation), real_text(hyperbolic_tangent(z - half)), real_text(hyperbolic_tangent(z + half)));
    return lines;
}
static Lines sign_flip_lines(Study *study) {
    Dataset *data = &study->data;
    Integer absolute[60], ranks[60], signed_ranks[60], plus = 0;
    int count = 0, position = 0;
    for (int i = 0; i < data->subjects; ++i) if (data->differences[i]) absolute[count++] = llabs(data->differences[i]);
    doubled_ranks((Sample){absolute, count}, ranks);
    for (int i = 0; i < data->subjects; ++i) {
        Integer value = data->differences[i], rank = value ? (value > 0 ? ranks[position] : -ranks[position]) : 0;
        if (value) ++position;
        signed_ranks[i] = rank;
        if (rank > 0) plus += rank;
    }
    Tally means = {sample_sum((Sample){data->differences, data->subjects}), 0, 0}, rank_sums = {sample_sum((Sample){signed_ranks, data->subjects}), 0, 0};
    for (int r = 0; r < data->settings.permutations; ++r) {
        Integer total = 0, rank_total = 0;
        for (int i = 0; i < data->subjects; ++i) {
            Integer sign = draw(&study->generator) % 2 ? -1 : 1;
            total += sign * data->differences[i];
            rank_total += sign * signed_ranks[i];
        }
        tally_count(&means, total);
        tally_count(&rank_sums, rank_total);
    }
    Lines lines = {0};
    add_line(&lines, "signflip flips %d", data->settings.permutations);
    add_line(&lines, "mean diff %s %s", real_text(mean((Sample){data->differences, data->subjects})), tally_text(means, 1, data->settings.permutations + 1));
    add_line(&lines, "signedrank w_plus %s %s", real_text((double)plus / 2), tally_text(rank_sums, 1, data->settings.permutations + 1));
    return lines;
}
typedef struct { int first, second; Integer numerator, denominator, extreme, maximum; } Comparison;
static Lines anova_lines(Study *study) {
    Dataset *data = &study->data;
    Sample samples[4], rank_groups[4];
    int sizes[4], count = 0, group_count = data->group_count;
    Integer combined[320], ranks[320];
    for (int g = 0; g < group_count; ++g) {
        samples[g] = group_sample(&data->groups[g]);
        sizes[g] = samples[g].n;
        memcpy(combined + count, samples[g].v, (size_t)sizes[g] * sizeof(Integer));
        count += sizes[g];
    }
    Anova original = anova(samples, group_count);
    double eta = original.between / (original.between + original.within), msw = original.within / (count - group_count);
    double omega = (original.between - (group_count - 1) * msw) / (original.between + original.within + msw);
    Values eta_values = values_new(data->settings.bootstrap);
    for (int r = 0; r < data->settings.bootstrap; ++r) {
        Sample replicates[4];
        for (int g = 0; g < group_count; ++g) replicates[g] = replicate(study, g, r);
        Anova trial = anova(replicates, group_count);
        eta_values.v[r] = trial.between / (trial.between + trial.within);
    }
    Summary eta_summary = summarize(study, eta, eta_values);
    double weights[4], weight_total = 0, weighted_total = 0;
    for (int g = 0; g < group_count; ++g) {
        double deviation = sd(samples[g]);
        weights[g] = sizes[g] / (deviation * deviation);
        weight_total += weights[g];
        weighted_total += weights[g] * original.means[g];
    }
    double center = weighted_total / weight_total, aw = 0, lambda = 0;
    for (int g = 0; g < group_count; ++g) {
        double difference = original.means[g] - center, remaining = 1 - weights[g] / weight_total;
        aw += weights[g] * (difference * difference);
        lambda += remaining * remaining / (sizes[g] - 1);
    }
    aw /= group_count - 1;
    double welch = aw / (1 + 2 * (group_count - 2) * lambda / (group_count * group_count - 1));
    double degrees = (group_count * group_count - 1) / (3 * lambda);
    doubled_ranks((Sample){combined, count}, ranks);
    Integer keys[320], counts[320], ties = 0;
    int distinct = value_counts((Sample){combined, count}, keys, counts), tie_groups = 0;
    for (int i = 0; i < distinct; ++i) if (counts[i] >= 2) { Integer t = counts[i]; ties += t * t * t - t; ++tie_groups; }
    Integer n = count;
    double correction = 1 - (double)ties / (n * n * n - n);
    divide((Sample){ranks, count}, sizes, group_count, rank_groups);
    double h = kruskal(rank_groups, group_count, correction);
    Lines lines = {0};
    add_line(&lines, "anova groups %d observations %d ssb %s ssw %s df %d %d f %s eta_squared %s omega_squared %s", group_count, count, real_text(original.between), real_text(original.within), group_count - 1, count - group_count, real_text(original.f), real_text(eta), real_text(omega));
    add_line(&lines, "eta_bootstrap %s", interval(eta_summary));
    add_line(&lines, "welch f %s df %d %s", real_text(welch), group_count - 1, real_text(degrees));
    add_line(&lines, "kruskal h %s tie_groups %d", real_text(h), tie_groups);
    Comparison comparisons[6];
    int pair_count = 0;
    for (int i = 0; i < group_count; ++i) for (int j = i + 1; j < group_count; ++j) comparisons[pair_count++] = (Comparison){i, j, llabs(contrast(samples[i], samples[j])), (Integer)sizes[i] * sizes[j], 0, 0};
    Integer f_extreme = 0, h_extreme = 0;
    for (int r = 0; r < data->settings.permutations; ++r) {
        int order[320];
        Integer shuffled[320], shuffled_ranks[320];
        Sample trial_samples[4];
        for (int i = 0; i < count; ++i) order[i] = i;
        shuffle(&study->generator, order, count);
        chosen((Sample){combined, count}, order, count, shuffled);
        chosen((Sample){ranks, count}, order, count, shuffled_ranks);
        divide((Sample){shuffled, count}, sizes, group_count, trial_samples);
        divide((Sample){shuffled_ranks, count}, sizes, group_count, rank_groups);
        Anova trial = anova(trial_samples, group_count);
        if (trial.f >= original.f - 0.000000001 * original.f) ++f_extreme;
        if (kruskal(rank_groups, group_count, correction) >= h - 0.000000001 * h) ++h_extreme;
        Integer numerators[6];
        int largest = 0;
        for (int p = 0; p < pair_count; ++p) {
            Comparison pair = comparisons[p];
            numerators[p] = llabs(contrast(trial_samples[pair.first], trial_samples[pair.second]));
            if (numerators[p] * comparisons[largest].denominator > numerators[largest] * pair.denominator) largest = p;
        }
        for (int p = 0; p < pair_count; ++p) {
            Comparison *pair = &comparisons[p];
            if (numerators[p] >= pair->numerator) ++pair->extreme;
            if (numerators[largest] * pair->denominator >= pair->numerator * comparisons[largest].denominator) ++pair->maximum;
        }
    }
    Integer denominator = data->settings.permutations + 1;
    add_line(&lines, "anova_permutation perms %d f_extreme %lld f_p %s h_extreme %lld h_p %s", data->settings.permutations, f_extreme, p_value(f_extreme + 1, denominator), h_extreme, p_value(h_extreme + 1, denominator));
    for (int p = 0; p < pair_count; ++p) {
        Comparison pair = comparisons[p];
        add_line(&lines, "pairwise %s %s diff %s extreme %lld p %s maxt %lld adjusted %s", data->groups[pair.first].name, data->groups[pair.second].name, real_text(mean_difference(samples[pair.first], samples[pair.second])), pair.extreme, p_value(pair.extreme + 1, denominator), pair.maximum, p_value(pair.maximum + 1, denominator));
    }
    return lines;
}
int main(void) {
    Study study = {0};
    load_dataset(&study.data);
    study.generator.state = study.data.settings.seed;
    study.low_rank = (study.data.settings.bootstrap + 1) * (100 - study.data.settings.confidence) / 200;
    study.high_rank = study.data.settings.bootstrap + 1 - study.low_rank;
    study.z_low = phi_inverse((double)(100 - study.data.settings.confidence) / 200);
    bootstraps(&study);
    Lines tests = {0};
    for (int p = 0; p < study.data.pair_count; ++p) {
        PairResult *pair = &study.pairs[p];
        add_line(&tests, "compare %s %s", study.data.groups[pair->first].name, study.data.groups[pair->second].name);
        extend(&tests, permutation_lines(&study, pair));
        add_line(&tests, "%s", power_line(&study, pair));
        extend(&tests, exact_lines(&study, pair));
        extend(&tests, studentized_lines(&study, pair));
    }
    extend(&tests, holm_lines(&study));
    extend(&tests, paired_lines(&study));
    extend(&tests, sign_flip_lines(&study));
    extend(&tests, anova_lines(&study));
    write_lines("descriptives.txt", descriptive_lines(&study));
    write_lines("bootstrap.csv", bootstrap_lines(&study));
    write_lines("jackknife.txt", jackknife_lines(&study));
    write_lines("tests.txt", tests);
    write_lines("histograms.txt", histogram_lines(&study));
    return 0;
}
