mod dataset;
mod minstd;
mod resampling;
mod tests;
mod report;

use std::collections::BTreeMap;
use std::{fs, io};
use dataset::{Dataset, load_dataset};
use minstd::Minstd;
use report::{bar, bin_number, number_list, p_value, real, write_lines};
use resampling::*;
use tests::*;

const GROUP_NAMES: [&str; 4] = ["mean", "median", "trimmed_mean", "sd"];
const PAIR_NAMES: [&str; 4] = ["mean_diff", "median_ratio", "hodges_lehmann", "cohen_d"];
const TEST_NAMES: [&str; 4] = ["mean", "median", "ranksum", "absdev"];

struct Summary {
    estimate: f64,
    values: Vec<f64>,
    ordered: Vec<f64>,
    se: f64,
    bias: f64,
    low: f64,
    high: f64,
    basic_low: f64,
    basic_high: f64,
}
impl Summary {
    fn new(estimate: f64, values: Vec<f64>, ranks: [usize; 2]) -> Self {
        let (average, se) = mean_and_se(&values);
        let mut ordered = values.clone(); ordered.sort_by(f64::total_cmp);
        let low = ordered[ranks[0] - 1]; let high = ordered[ranks[1] - 1];
        Self { estimate, values, ordered, se, bias: average - estimate, low, high,
            basic_low: 2.0 * estimate - high, basic_high: 2.0 * estimate - low }
    }
    fn csv_line(&self, name: &str, statistic: &str) -> String {
        let mut fields = vec![name.to_owned(), statistic.to_owned()];
        fields.extend([self.estimate, self.se, self.bias, self.low, self.high, self.basic_low, self.basic_high].map(real));
        fields.join(",")
    }
    fn interval_text(&self) -> String {
        format!("se {} bias {} percentile {} {} basic {} {}", real(self.se), real(self.bias), real(self.low), real(self.high), real(self.basic_low), real(self.basic_high))
    }
}
struct GroupBootstrap { group: usize, indices: Vec<Vec<usize>>, samples: Vec<Vec<i64>>, summaries: [Summary; 4] }
impl GroupBootstrap {
    fn new(group: usize, values: &[i64], indices: Vec<Vec<usize>>, ranks: [usize; 2]) -> Self {
        let samples: Vec<Vec<i64>> = indices.iter().map(|replicate| replicate.iter().map(|&index| values[index]).collect()).collect();
        let estimates = group_statistics(values);
        let statistics: Vec<_> = samples.iter().map(|sample| group_statistics(sample)).collect();
        let summaries = std::array::from_fn(|index| Summary::new(estimates[index], statistics.iter().map(|values| values[index]).collect(), ranks));
        Self { group, indices, samples, summaries }
    }
}
struct PairBootstrap { first: usize, second: usize, name: String, summaries: [Summary; 4] }
struct Jackknife { values: Vec<f64>, average: f64, variance: f64, bias: f64 }
impl Jackknife {
    fn new(estimate: f64, values: Vec<f64>) -> Self {
        let (average, variance) = jackknife_spread(&values);
        let bias = (values.len() - 1) as f64 * (average - estimate);
        Self { values, average, variance, bias }
    }
}
#[derive(Clone, Copy)]
struct Tally { observed: i64, extreme: usize, greater: usize }
impl Tally {
    fn new(observed: i64) -> Self { Self { observed, extreme: 0, greater: 0 } }
    fn count(&mut self, value: i64) { if value.abs() >= self.observed.abs() { self.extreme += 1; } if value >= self.observed { self.greater += 1; } }
    fn text(self, offset: usize, denominator: usize) -> String {
        format!("extreme {} greater {} p_two {} p_greater {}", self.extreme, self.greater, p_value(self.extreme + offset, denominator), p_value(self.greater + offset, denominator))
    }
}
struct DisplayRange { low: i64, delta: i64 }
impl DisplayRange {
    fn new(values: &[i64]) -> Self { let low = *values.iter().min().unwrap(); Self { low, delta: 100 * (values.iter().max().unwrap() - low) } }
    fn position(&self, value: i64) -> usize { ((120 * (value - 100 * self.low) + self.delta) / (2 * self.delta)) as usize }
}
fn jackknife_spread(values: &[f64]) -> (f64, f64) {
    let count = values.len() as f64; let average = sequential_sum(values.iter().copied()) / count;
    let squares = sequential_sum(values.iter().map(|value| (value - average) * (value - average)));
    (average, (count - 1.0) * squares / count)
}
fn series_lines(kind: &str, name: &str, values: &[i64], display: &DisplayRange, with_stems: bool) -> Vec<String> {
    let count = values.len(); let average = mean(values); let deviation = sd(values);
    let [second, third, fourth] = central_moments(values); let clipped = winsorized(values);
    let first = quantile_numerator(values, 25); let third_quartile = quantile_numerator(values, 75);
    let outliers: Vec<_> = values.iter().enumerate().filter_map(|(index, &value)| (200 * value < 5 * first - 3 * third_quartile || 200 * value > 5 * third_quartile - 3 * first).then_some(index)).collect();
    let inside: Vec<_> = values.iter().enumerate().filter(|(index, _)| !outliers.contains(index)).map(|(_, &value)| value).collect();
    let low = *inside.iter().min().unwrap(); let high = *inside.iter().max().unwrap();
    let mut band = vec!['.'; 61];
    for position in display.position(100 * low)..=display.position(100 * high) { band[position] = '-'; }
    for position in display.position(first)..=display.position(third_quartile) { band[position] = '='; }
    band[display.position(quantile_numerator(values, 50))] = '|';
    for &index in &outliers { band[display.position(100 * values[index])] = 'o'; }
    let percentiles = [(5, "p05"), (10, "p10"), (90, "p90"), (95, "p95")].iter().map(|&(percent, label)| format!("{label} {}", real(quantile_numerator(values, percent) as f64 / 10000.0))).collect::<Vec<_>>().join(" ");
    let mut lines = vec![format!("{kind} {name}"), format!("n {count}"), format!("mean {}", real(average)), format!("median {}", real(median(values))),
        format!("trimmed_mean {} trim {}", real(trimmed_mean(values)), trim_count(count)), format!("winsorized_mean {} winsorized_sd {}", real(mean(&clipped)), real(sd(&clipped))),
        format!("sd {}", real(deviation)), format!("se_mean {}", real(deviation / (count as f64).sqrt())), format!("cv {}", real(deviation / average)),
        format!("skewness {}", real(third / (second * second.sqrt()))), format!("kurtosis {}", real(fourth / (second * second) - 3.0)), format!("mad {}", real(mad(values))),
        format!("min {}", real(*values.iter().min().unwrap() as f64 / 100.0)), format!("q1 {}", real(first as f64 / 10000.0)), format!("q3 {}", real(third_quartile as f64 / 10000.0)),
        format!("iqr {}", real((third_quartile - first) as f64 / 10000.0)), format!("max {}", real(*values.iter().max().unwrap() as f64 / 100.0)), format!("percentiles {percentiles}"),
        format!("whiskers {} {}", real(low as f64 / 100.0), real(high as f64 / 100.0)), format!("outliers {}", number_list(&outliers.iter().map(|index| index + 1).collect::<Vec<_>>())), format!("box {}", band.iter().collect::<String>())];
    if with_stems {
        let mut ordered = values.to_vec(); ordered.sort_unstable();
        for stem in ordered[0] / 100..=ordered[ordered.len() - 1] / 100 {
            let leaves = ordered.iter().filter(|&&value| value / 100 == stem).map(|value| ((value % 100) / 10).to_string()).collect::<String>();
            lines.push(if leaves.is_empty() { format!("stem {stem}") } else { format!("stem {stem} {leaves}") });
        }
    }
    lines
}
fn split_statistics(values: &[i64], ranks: &[i64], order: &[usize], size: usize) -> [i64; 4] {
    let first: Vec<_> = order[..size].iter().map(|&index| values[index]).collect();
    let second: Vec<_> = order[size..].iter().map(|&index| values[index]).collect();
    let first_center = doubled_median(&first); let second_center = doubled_median(&second);
    let rank_total: i64 = order[..size].iter().map(|&index| ranks[index]).sum();
    let first_dev: i64 = first.iter().map(|&value| (2 * value - first_center).abs()).sum();
    let second_dev: i64 = second.iter().map(|&value| (2 * value - second_center).abs()).sum();
    [contrast(total(&first), first.len(), total(&second), second.len()), first_center - second_center,
        rank_total - (first.len() * (first.len() + second.len() + 1)) as i64, contrast(first_dev, first.len(), second_dev, second.len())]
}
fn group_deltas(samples: &[Vec<i64>], pairs: &[(usize, usize)]) -> Vec<(i64, i64)> {
    pairs.iter().map(|&(first, second)| (contrast(total(&samples[first]), samples[first].len(), total(&samples[second]), samples[second].len()).abs(), (samples[first].len() * samples[second].len()) as i64)).collect()
}
fn delta_at_least(first: (i64, i64), second: (i64, i64)) -> bool { first.0 * second.1 >= second.0 * first.1 }
fn hyperbolic_tangent(value: f64) -> f64 { let growth = (2.0 * value).exp(); (growth - 1.0) / (growth + 1.0) }

struct Study<'a> { data: &'a Dataset, generator: Minstd, ranks: [usize; 2], z_low: f64 }
impl<'a> Study<'a> {
    fn new(data: &'a Dataset) -> Self {
        let low = (data.settings.bootstrap + 1) * (100 - data.settings.confidence) / 200;
        Self { data, generator: Minstd { state: data.settings.seed }, ranks: [low, data.settings.bootstrap + 1 - low], z_low: phi_inverse((100 - data.settings.confidence) as f64 / 200.0) }
    }
    fn descriptive_lines(&self) -> Vec<String> {
        let everything: Vec<_> = self.data.groups.iter().flat_map(|group| group.values.iter().copied()).collect();
        let mut lines = vec![format!("groups {} observations {}", self.data.groups.len(), everything.len())];
        let display = DisplayRange::new(&everything);
        for group in &self.data.groups { lines.extend(series_lines("group", &group.name, &group.values, &display, true)); }
        let paired = &self.data.paired;
        lines.push(format!("paired subjects {}", paired.differences.len()));
        let combined: Vec<_> = paired.before.iter().chain(&paired.after).copied().collect();
        let display = DisplayRange::new(&combined);
        lines.extend(series_lines("series", "before", &paired.before, &display, false));
        lines.extend(series_lines("series", "after", &paired.after, &display, false));
        lines.extend(series_lines("series", "diff", &paired.differences, &DisplayRange::new(&paired.differences), false));
        lines
    }
    fn paired_bootstrap(&mut self) -> (Summary, Summary) {
        let paired = &self.data.paired; let mut means = Vec::new(); let mut correlations = Vec::new();
        for indices in ordinary_indices(&mut self.generator, paired.differences.len(), self.data.settings.bootstrap) {
            let differences: Vec<_> = indices.iter().map(|&index| paired.differences[index]).collect();
            let before: Vec<_> = indices.iter().map(|&index| paired.before[index]).collect();
            let after: Vec<_> = indices.iter().map(|&index| paired.after[index]).collect();
            means.push(mean(&differences)); correlations.push(correlation(&before, &after));
        }
        (Summary::new(mean(&paired.differences), means, self.ranks), Summary::new(correlation(&paired.before, &paired.after), correlations, self.ranks))
    }
    fn histogram_lines(&self, name: &str, statistic: &str, summary: &Summary) -> Vec<String> {
        let bins = self.data.settings.bins; let low = summary.ordered[0]; let high = *summary.ordered.last().unwrap();
        let mut counts = vec![0; bins]; for &value in &summary.values { counts[bin_number(value, low, high, bins)] += 1; }
        let top = *counts.iter().max().unwrap(); let mut marks = vec![Vec::new(); bins];
        marks[bin_number(summary.low, low, high, bins)].push("L");
        let estimate_bin = if low <= summary.estimate && summary.estimate <= high { let index = bin_number(summary.estimate, low, high, bins); marks[index].push("E"); (index + 1).to_string() } else { "none".to_owned() };
        marks[bin_number(summary.high, low, high, bins)].push("H");
        let convergence = (1..=4).map(|quarter| { let size = quarter * self.data.settings.bootstrap / 4; format!("{size}:{}", real(mean_and_se(&summary.values[..size]).1)) }).collect::<Vec<_>>().join(" ");
        let mut lines = vec![format!("histogram {name} {statistic} min {} max {} width {} top {top} estimate_bin {estimate_bin}", real(low), real(high), real((high - low) / bins as f64)), format!("convergence {convergence}")];
        for (index, &count) in counts.iter().enumerate() {
            let mut parts = vec!["bin".to_owned(), (index + 1).to_string(), real(low + (high - low) * index as f64 / bins as f64), count.to_string()];
            if count > 0 { parts.push(bar(count, top)); } parts.extend(marks[index].iter().map(|mark| (*mark).to_owned())); lines.push(parts.join(" "));
        }
        lines
    }
    fn bca_line(&self, statistic: &str, summary: &Summary, jackknife: &Jackknife) -> String {
        let count = self.data.settings.bootstrap;
        let below = summary.values.iter().filter(|&&value| value < summary.estimate).count();
        let z0 = phi_inverse(below as f64 / count as f64);
        let deviations: Vec<_> = jackknife.values.iter().map(|value| jackknife.average - value).collect();
        let squares = sequential_sum(deviations.iter().map(|value| value * value));
        let cubes = sequential_sum(deviations.iter().map(|value| value * value * value));
        let acceleration = cubes / (6.0 * squares * squares.sqrt());
        let alpha = |z: f64| phi(z0 + (z0 + z) / (1.0 - acceleration * (z0 + z)));
        let low = (((count + 1) as f64 * alpha(self.z_low)).floor() as usize).clamp(1, count);
        let high = (count + 1 - ((count + 1) as f64 * (1.0 - alpha(-self.z_low))).floor() as usize).clamp(1, count);
        format!("bca {statistic} below {below} z0 {} acceleration {} ranks {low} {high} interval {} {}", real(z0), real(acceleration), real(summary.ordered[low - 1]), real(summary.ordered[high - 1]))
    }
    fn group_jackknife_lines(&self, bootstrap: &GroupBootstrap) -> Vec<String> {
        let group = &self.data.groups[bootstrap.group]; let values = &group.values; let count = values.len();
        let statistics: Vec<_> = (0..count).map(|index| group_statistics(&without(values, index))).collect();
        let jackknives: [Jackknife; 4] = std::array::from_fn(|column| Jackknife::new(bootstrap.summaries[column].estimate, statistics.iter().map(|row| row[column]).collect()));
        let mut lines = vec![format!("group {} n {count}", group.name)];
        for column in 0..4 { let jackknife = &jackknives[column]; lines.push(format!("jackknife {} estimate {} average {} bias {} se {}", GROUP_NAMES[column], real(bootstrap.summaries[column].estimate), real(jackknife.average), real(jackknife.bias), real(jackknife.variance.sqrt()))); }
        for column in 0..4 { lines.push(self.bca_line(GROUP_NAMES[column], &bootstrap.summaries[column], &jackknives[column])); }
        let omitted: Vec<Vec<usize>> = (0..count).map(|index| bootstrap.indices.iter().enumerate().filter_map(|(replicate, chosen)| (!chosen.contains(&index)).then_some(replicate)).collect()).collect();
        let errors: Vec<Vec<f64>> = (0..4).map(|column| omitted.iter().map(|replicates| mean_and_se(&replicates.iter().map(|&r| bootstrap.summaries[column].values[r]).collect::<Vec<_>>()).1).collect()).collect();
        for column in 0..4 { let (average, variance) = jackknife_spread(&errors[column]); lines.push(format!("after_bootstrap {} se {} average {} se_of_se {}", GROUP_NAMES[column], real(bootstrap.summaries[column].se), real(average), real(variance.sqrt()))); }
        let sizes: Vec<_> = omitted.iter().map(Vec::len).collect();
        lines.push(format!("without min {} max {}", sizes.iter().min().unwrap(), sizes.iter().max().unwrap()));
        let sum = total(values); let mut ranking: Vec<_> = (0..count).collect();
        ranking.sort_by_key(|&index| (std::cmp::Reverse((count as i64 * values[index] - sum).abs()), index));
        for (rank, index) in ranking.into_iter().take(5).enumerate() {
            let influence = (count - 1) as f64 * (jackknives[0].average - jackknives[0].values[index]);
            let summary = &bootstrap.summaries[0]; let mut shifted: Vec<_> = omitted[index].iter().map(|&r| summary.values[r] - summary.estimate).collect(); shifted.sort_by(f64::total_cmp);
            let quantiles = [5, 50, 95].map(|percent| real(shifted[(percent * sizes[index]).div_ceil(100) - 1]));
            lines.push(format!("influence {} obs {} value {} l {} without {} se {} q05 {} q50 {} q95 {}", rank + 1, index + 1, real(values[index] as f64 / 100.0), real(influence), sizes[index], real(errors[0][index]), quantiles[0], quantiles[1], quantiles[2]));
        }
        lines
    }
    fn pair_jackknife_lines(&self, pair: &PairBootstrap) -> Vec<String> {
        let x = &self.data.groups[pair.first].values; let y = &self.data.groups[pair.second].values;
        let first: Vec<_> = (0..x.len()).map(|index| pair_statistics(&without(x, index), y)).collect();
        let second: Vec<_> = (0..y.len()).map(|index| pair_statistics(x, &without(y, index))).collect();
        (0..4).map(|column| {
            let estimate = pair.summaries[column].estimate;
            let first = Jackknife::new(estimate, first.iter().map(|row| row[column]).collect());
            let second = Jackknife::new(estimate, second.iter().map(|row| row[column]).collect());
            let mut bias = 0.0; bias += first.bias; bias += second.bias;
            let mut variance = 0.0; variance += first.variance; variance += second.variance;
            format!("pair {} {} estimate {} bias {} se {}", pair.name, PAIR_NAMES[column], real(estimate), real(bias), real(variance.sqrt()))
        }).collect()
    }
    fn permutation_lines(&mut self, x: &[i64], y: &[i64]) -> (Vec<String>, [usize; 4]) {
        let settings = &self.data.settings; let mut combined = x.to_vec(); combined.extend_from_slice(y);
        let ranks = doubled_ranks(&combined); let positions: Vec<_> = (0..combined.len()).collect();
        let observed = split_statistics(&combined, &ranks, &positions, x.len());
        let mut tallies = observed.map(Tally::new);
        for _ in 0..settings.permutations { let mut order = positions.clone(); self.generator.shuffle(&mut order);
            let values = split_statistics(&combined, &ranks, &order, x.len()); for column in 0..4 { tallies[column].count(values[column]); } }
        let k = x.len(); let m = y.len(); let rank_total = total(&ranks[..k]);
        let results = tallies.map(|tally| tally.text(1, settings.permutations + 1));
        (vec![format!("permutation n {k} {m} perms {}", settings.permutations), format!("mean diff {} {}", real(mean_difference(x, y)), results[0]),
            format!("median diff {} {}", real(observed[1] as f64 / 200.0), results[1]), format!("ranksum w {} u {} {}", real(rank_total as f64 / 2.0), real((rank_total - (k * (k + 1)) as i64) as f64 / 2.0), results[2]),
            format!("absdev diff {} {}", real(observed[3] as f64 / (200 * k * m) as f64), results[3])], tallies.map(|tally| tally.extreme))
    }
    fn power_line(&mut self, x: &[i64], y: &[i64]) -> String {
        let settings = &self.data.settings; let k = x.len(); let m = y.len(); let mut rejections = 0;
        for _ in 0..settings.power_sims {
            let first: Vec<_> = resample_indices(&mut self.generator, k).iter().map(|&index| x[index]).collect();
            let second: Vec<_> = resample_indices(&mut self.generator, m).iter().map(|&index| y[index]).collect();
            let observed = contrast(total(&first), k, total(&second), m).abs();
            let mut combined = first; combined.extend(second); let sum = total(&combined); let mut count = 0;
            for _ in 0..settings.power_perms { let mut shuffled = combined.clone(); self.generator.shuffle(&mut shuffled); let head = total(&shuffled[..k]); if contrast(head, k, sum - head, m).abs() >= observed { count += 1; } }
            if 100 * (count + 1) <= (100 - settings.confidence) * (settings.power_perms + 1) { rejections += 1; }
        }
        let power = rejections as f64 / settings.power_sims as f64;
        format!("power sims {} perms {} rejections {rejections} power {} se {}", settings.power_sims, settings.power_perms, real(power), real((power * (1.0 - power) / settings.power_sims as f64).sqrt()))
    }
    fn exact_lines(&self, x: &[i64], y: &[i64]) -> Vec<String> {
        let size = self.data.settings.pilot; let mut combined = x[..size].to_vec(); combined.extend_from_slice(&y[..size]);
        let ranks = doubled_ranks(&combined); let sum = total(&combined); let mut means = Vec::new(); let mut ranksums = Vec::new();
        for choice in position_choices(2 * size, size) { let chosen: i64 = choice.iter().map(|&index| combined[index]).sum(); means.push(contrast(chosen, size, sum - chosen, size)); ranksums.push(choice.iter().map(|&index| ranks[index]).sum::<i64>() - (size * (2 * size + 1)) as i64); }
        let splits = means.len(); let mut mean_tally = Tally::new(means[0]); let mut rank_tally = Tally::new(ranksums[0]);
        for (&mean_value, &rank_value) in means.iter().zip(&ranksums) { mean_tally.count(mean_value); rank_tally.count(rank_value); }
        let rank_total = total(&ranks[..size]); let counts = value_counts(&means.iter().map(|value| value.abs()).collect::<Vec<_>>());
        let mut cumulative = 0; let mut critical = None;
        for (&value, &count) in counts.iter().rev() { cumulative += count; if 100 * cumulative > (100 - self.data.settings.confidence) * splits { break; } critical = Some((value, cumulative)); }
        let critical = critical.map(|(value, cumulative)| format!("critical diff {} attained {}", real(value as f64 / (100 * size * size) as f64), p_value(cumulative, splits))).unwrap_or_else(|| "critical diff none attained none".to_owned());
        vec![format!("exact size {size} splits {splits}"), format!("mean diff {} {}", real(mean_difference(&x[..size], &y[..size])), mean_tally.text(0, splits)),
            format!("ranksum w {} u {} {}", real(rank_total as f64 / 2.0), real((rank_total - (size * (size + 1)) as i64) as f64 / 2.0), rank_tally.text(0, splits)), critical]
    }
    fn studentized_lines(&self, pair: &PairBootstrap, ordinary: &[GroupBootstrap]) -> Vec<String> {
        let x = &self.data.groups[pair.first].values; let y = &self.data.groups[pair.second].values; let k = x.len() as f64; let m = y.len() as f64;
        let estimate = mean_difference(x, y); let first_sd = sd(x); let second_sd = sd(y);
        let first_variance = first_sd * first_sd / k; let second_variance = second_sd * second_sd / m; let se0 = (first_variance + second_variance).sqrt(); let t = estimate / se0;
        let first = &ordinary[pair.first].summaries[3].values; let second = &ordinary[pair.second].summaries[3].values;
        let statistics: Vec<_> = pair.summaries[0].values.iter().enumerate().map(|(index, &difference)| (difference - estimate) / (first[index] * first[index] / k + second[index] * second[index] / m).sqrt()).collect();
        let extreme = statistics.iter().filter(|&&value| value.abs() >= t.abs()).count(); let mut ordered = statistics; ordered.sort_by(f64::total_cmp);
        let lower = estimate - ordered[self.ranks[1] - 1] * se0; let upper = estimate - ordered[self.ranks[0] - 1] * se0;
        let degrees = (first_variance + second_variance) * (first_variance + second_variance) / (first_variance * first_variance / (k - 1.0) + second_variance * second_variance / (m - 1.0));
        let greater = x.iter().flat_map(|a| y.iter().map(move |b| a > b)).filter(|&value| value).count();
        let equal = x.iter().flat_map(|a| y.iter().map(move |b| a == b)).filter(|&value| value).count();
        let d = cohen_d(x, y); let hedges = d * (1.0 - 3.0 / (4.0 * (k + m - 2.0) - 1.0)); let cles = (2 * greater + equal) as f64 / (2.0 * k * m);
        vec![format!("bootstrap_t t {} df {} extreme {extreme} p {} interval {} {}", real(t), real(degrees), p_value(extreme + 1, self.data.settings.bootstrap + 1), real(lower), real(upper)),
            format!("effect pooled_sd {} cohen_d {} hedges_g {} cles {}", real(pooled_sd(x, y)), real(d), real(hedges), real(cles))]
    }
    fn pair_test_lines(&mut self, pair: &PairBootstrap, ordinary: &[GroupBootstrap]) -> (Vec<String>, [usize; 4]) {
        let data = self.data; let first = &data.groups[pair.first]; let second = &data.groups[pair.second];
        let mut lines = vec![format!("compare {} {}", first.name, second.name)];
        let (permutation, extremes) = self.permutation_lines(&first.values, &second.values); lines.extend(permutation);
        lines.push(self.power_line(&first.values, &second.values)); lines.extend(self.exact_lines(&first.values, &second.values)); lines.extend(self.studentized_lines(pair, ordinary)); (lines, extremes)
    }
    fn holm_lines(&self, extremes: &[[usize; 4]]) -> Vec<String> {
        let settings = &self.data.settings; let count = self.data.pairs.len(); let mut lines = Vec::new();
        for column in 0..4 { let mut order: Vec<_> = (0..count).collect(); order.sort_by_key(|&index| (extremes[index][column], index)); let mut adjusted = 0;
            for (rank, index) in order.into_iter().enumerate() { let extreme = extremes[index][column]; adjusted = adjusted.max(((count - rank) * (extreme + 1)).min(settings.permutations + 1));
                let rejected = 100 * adjusted <= (100 - settings.confidence) * (settings.permutations + 1); let (first, second) = self.data.pairs[index];
                lines.push(format!("holm {} rank {} {} {} p {} adjusted {} {}", TEST_NAMES[column], rank + 1, self.data.groups[first].name, self.data.groups[second].name, p_value(extreme + 1, settings.permutations + 1), p_value(adjusted, settings.permutations + 1), if rejected { "reject" } else { "retain" })); }
        }
        lines
    }
    fn paired_lines(&self, mean_summary: &Summary, correlation_summary: &Summary) -> Vec<String> {
        let paired = &self.data.paired; let differences = &paired.differences; let count = differences.len();
        let positive = differences.iter().filter(|&&value| value > 0).count(); let negative = differences.iter().filter(|&&value| value < 0).count();
        let average = mean(differences); let deviation = sd(differences); let r = correlation(&paired.before, &paired.after); let z = 0.5 * ((1.0 + r) / (1.0 - r)).ln(); let half_width = -self.z_low / ((count - 3) as f64).sqrt();
        vec![format!("paired subjects {count} positive {positive} negative {negative} zero {}", count - positive - negative),
            format!("paired before {} after {} diff {} sd_diff {} t {} dz {}", real(mean(&paired.before)), real(mean(&paired.after)), real(average), real(deviation), real(average / (deviation / (count as f64).sqrt())), real(average / deviation)),
            format!("paired_bootstrap {}", mean_summary.interval_text()), format!("correlation r {} {} fisher {} {}", real(r), correlation_summary.interval_text(), real(hyperbolic_tangent(z - half_width)), real(hyperbolic_tangent(z + half_width)))]
    }
    fn sign_flip_lines(&mut self) -> Vec<String> {
        let differences = &self.data.paired.differences; let magnitudes: Vec<_> = differences.iter().filter(|&&value| value != 0).map(|value| value.abs()).collect();
        let ranks = doubled_ranks(&magnitudes); let rank_of: BTreeMap<_, _> = magnitudes.into_iter().zip(ranks).collect();
        let signed: Vec<_> = differences.iter().map(|&value| if value > 0 { rank_of[&value] } else if value < 0 { -rank_of[&-value] } else { 0 }).collect();
        let mut mean_tally = Tally::new(total(differences)); let mut rank_tally = Tally::new(total(&signed));
        let permutations = self.data.settings.permutations;
        for _ in 0..permutations { let signs: Vec<i64> = differences.iter().map(|_| if self.generator.draw() % 2 == 1 { -1 } else { 1 }).collect(); mean_tally.count(signs.iter().zip(differences).map(|(sign, value)| sign * value).sum()); rank_tally.count(signs.iter().zip(&signed).map(|(sign, rank)| sign * rank).sum()); }
        let w_plus: i64 = signed.iter().copied().filter(|&rank| rank > 0).sum();
        vec![format!("signflip flips {permutations}"), format!("mean diff {} {}", real(mean(differences)), mean_tally.text(1, permutations + 1)), format!("signedrank w_plus {} {}", real(w_plus as f64 / 2.0), rank_tally.text(1, permutations + 1))]
    }
    fn welch_line(&self, samples: &[Vec<i64>]) -> String {
        let groups = samples.len(); let means: Vec<_> = samples.iter().map(|sample| mean(sample)).collect();
        let weights: Vec<_> = samples.iter().map(|sample| { let deviation = sd(sample); sample.len() as f64 / (deviation * deviation) }).collect();
        let total_weight = sequential_sum(weights.iter().copied()); let center = sequential_sum(weights.iter().zip(&means).map(|(weight, value)| weight * value)) / total_weight;
        let spread = sequential_sum(weights.iter().zip(&means).map(|(weight, value)| weight * ((value - center) * (value - center)))) / (groups - 1) as f64;
        let mut lambda = 0.0; for (weight, sample) in weights.iter().zip(samples) { let share = 1.0 - weight / total_weight; lambda += share * share / (sample.len() - 1) as f64; }
        let f = spread / (1.0 + (2 * (groups - 2)) as f64 * lambda / (groups * groups - 1) as f64); let df = (groups * groups - 1) as f64 / (3.0 * lambda);
        format!("welch f {} df {} {}", real(f), groups - 1, real(df))
    }
    fn anova_permutation_lines(&mut self, samples: &[Vec<i64>], ranks: &[i64], f: f64, h: f64, correction: f64) -> Vec<String> {
        let count: usize = samples.iter().map(Vec::len).sum(); let sizes: Vec<_> = samples.iter().map(Vec::len).collect(); let groups = samples.len();
        let combined: Vec<_> = samples.iter().flatten().copied().collect(); let pairs: Vec<_> = (0..groups).flat_map(|first| (first + 1..groups).map(move |second| (first, second))).collect();
        let observed = group_deltas(samples, &pairs); let mut f_extreme = 0; let mut h_extreme = 0; let mut extremes = vec![0; pairs.len()]; let mut maxima = vec![0; pairs.len()]; let positions: Vec<_> = (0..count).collect();
        let permutations = self.data.settings.permutations;
        for _ in 0..permutations { let mut order = positions.clone(); self.generator.shuffle(&mut order); let parts = split_list(&order, &sizes);
            let samples: Vec<Vec<i64>> = parts.iter().map(|part| part.iter().map(|&index| combined[index]).collect()).collect(); let (between, within) = sums_of_squares(&samples);
            if f_statistic(between, within, groups, count) >= f - 0.000000001 * f { f_extreme += 1; }
            let rank_sums: Vec<_> = parts.iter().map(|part| part.iter().map(|&index| ranks[index]).sum()).collect();
            if h_statistic(&rank_sums, &sizes, correction) >= h - 0.000000001 * h { h_extreme += 1; }
            let deltas = group_deltas(&samples, &pairs); let mut largest = deltas[0]; for &delta in &deltas[1..] { if !delta_at_least(largest, delta) { largest = delta; } }
            for (index, &bound) in observed.iter().enumerate() { if delta_at_least(deltas[index], bound) { extremes[index] += 1; } if delta_at_least(largest, bound) { maxima[index] += 1; } }
        }
        let mut lines = vec![format!("anova_permutation perms {permutations} f_extreme {f_extreme} f_p {} h_extreme {h_extreme} h_p {}", p_value(f_extreme + 1, permutations + 1), p_value(h_extreme + 1, permutations + 1))];
        for (index, &(first, second)) in pairs.iter().enumerate() { lines.push(format!("pairwise {} {} diff {} extreme {} p {} maxt {} adjusted {}", self.data.groups[first].name, self.data.groups[second].name, real(mean_difference(&samples[first], &samples[second])), extremes[index], p_value(extremes[index] + 1, permutations + 1), maxima[index], p_value(maxima[index] + 1, permutations + 1))); }
        lines
    }
    fn anova_lines(&mut self, ordinary: &[GroupBootstrap]) -> Vec<String> {
        let samples: Vec<_> = self.data.groups.iter().map(|group| group.values.clone()).collect(); let sizes: Vec<_> = samples.iter().map(Vec::len).collect(); let groups = samples.len(); let count: usize = sizes.iter().sum();
        let (between, within) = sums_of_squares(&samples); let f = f_statistic(between, within, groups, count); let eta = between / (between + within); let msw = within / (count - groups) as f64; let omega = (between - (groups - 1) as f64 * msw) / (between + within + msw);
        let eta_values = (0..self.data.settings.bootstrap).map(|replicate| { let samples: Vec<_> = ordinary.iter().map(|bootstrap| bootstrap.samples[replicate].clone()).collect(); let (between, within) = sums_of_squares(&samples); between / (between + within) }).collect();
        let eta_summary = Summary::new(eta, eta_values, self.ranks); let combined: Vec<_> = samples.iter().flatten().copied().collect(); let ranks = doubled_ranks(&combined); let rank_sums: Vec<_> = split_list(&ranks, &sizes).iter().map(|part| total(part)).collect();
        let ties: Vec<_> = value_counts(&combined).into_values().filter(|&count| count >= 2).collect(); let tie_total: usize = ties.iter().map(|count| count * count * count - count).sum();
        let correction = 1.0 - tie_total as f64 / (count * count * count - count) as f64; let h = h_statistic(&rank_sums, &sizes, correction);
        let mut lines = vec![format!("anova groups {groups} observations {count} ssb {} ssw {} df {} {} f {} eta_squared {} omega_squared {}", real(between), real(within), groups - 1, count - groups, real(f), real(eta), real(omega)), format!("eta_bootstrap {}", eta_summary.interval_text()), self.welch_line(&samples), format!("kruskal h {} tie_groups {}", real(h), ties.len())];
        lines.extend(self.anova_permutation_lines(&samples, &ranks, f, h, correction)); lines
    }
    fn run(&mut self) -> Vec<(&'static str, Vec<String>)> {
        let data = self.data; let count = data.settings.bootstrap;
        let mut ordinary = Vec::new(); let mut balanced = Vec::new();
        for (index, group) in data.groups.iter().enumerate() { let indices = ordinary_indices(&mut self.generator, group.values.len(), count); ordinary.push(GroupBootstrap::new(index, &group.values, indices, self.ranks)); }
        for (index, group) in data.groups.iter().enumerate() { let indices = balanced_indices(&mut self.generator, group.values.len(), count); balanced.push(GroupBootstrap::new(index, &group.values, indices, self.ranks)); }
        let (mean_summary, correlation_summary) = self.paired_bootstrap();
        let pairs: Vec<_> = data.pairs.iter().map(|&(first, second)| { let estimates = pair_statistics(&data.groups[first].values, &data.groups[second].values);
            let statistics: Vec<_> = ordinary[first].samples.iter().zip(&ordinary[second].samples).map(|(a, b)| pair_statistics(a, b)).collect();
            PairBootstrap { first, second, name: format!("{}-{}", data.groups[first].name, data.groups[second].name), summaries: std::array::from_fn(|column| Summary::new(estimates[column], statistics.iter().map(|values| values[column]).collect(), self.ranks)) } }).collect();
        let mut test_lines = Vec::new(); let mut extremes = Vec::new();
        for pair in &pairs { let (lines, counts) = self.pair_test_lines(pair, &ordinary); test_lines.extend(lines); extremes.push(counts); }
        test_lines.extend(self.holm_lines(&extremes)); test_lines.extend(self.paired_lines(&mean_summary, &correlation_summary)); test_lines.extend(self.sign_flip_lines()); test_lines.extend(self.anova_lines(&ordinary));
        let mut bootstrap_lines = vec!["group,statistic,estimate,se,bias,percentile_lo,percentile_hi,basic_lo,basic_hi".to_owned()]; let mut jackknife_lines = Vec::new(); let mut histogram_lines = Vec::new();
        for (plain, even) in ordinary.iter().zip(&balanced) { let name = &data.groups[plain.group].name;
            for column in 0..4 { bootstrap_lines.push(plain.summaries[column].csv_line(name, GROUP_NAMES[column])); }
            for column in 0..4 { bootstrap_lines.push(even.summaries[column].csv_line(name, &format!("balanced_{}", GROUP_NAMES[column]))); }
            jackknife_lines.extend(self.group_jackknife_lines(plain));
            for column in 0..4 { histogram_lines.extend(self.histogram_lines(name, GROUP_NAMES[column], &plain.summaries[column])); }
        }
        for pair in &pairs { for column in 0..4 { bootstrap_lines.push(pair.summaries[column].csv_line(&pair.name, PAIR_NAMES[column])); histogram_lines.extend(self.histogram_lines(&pair.name, PAIR_NAMES[column], &pair.summaries[column])); } jackknife_lines.extend(self.pair_jackknife_lines(pair)); }
        vec![("descriptives.txt", self.descriptive_lines()), ("bootstrap.csv", bootstrap_lines), ("jackknife.txt", jackknife_lines), ("tests.txt", test_lines), ("histograms.txt", histogram_lines)]
    }
}

fn main() -> io::Result<()> {
    let data = load_dataset("input")?; let mut study = Study::new(&data); let files = study.run(); fs::create_dir_all("output")?;
    for (name, lines) in files { write_lines(&format!("output/{name}"), &lines)?; }
    Ok(())
}
