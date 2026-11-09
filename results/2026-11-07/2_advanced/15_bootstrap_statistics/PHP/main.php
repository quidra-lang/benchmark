<?php

namespace Bootstrap;

require_once __DIR__ . '/dataset.php';
require_once __DIR__ . '/minstd.php';
require_once __DIR__ . '/resampling.php';
require_once __DIR__ . '/tests.php';
require_once __DIR__ . '/report.php';

const GROUP_NAMES = ['mean', 'median', 'trimmed_mean', 'sd'];
const PAIR_NAMES = ['mean_diff', 'median_ratio', 'hodges_lehmann', 'cohen_d'];
const TEST_NAMES = ['mean', 'median', 'ranksum', 'absdev'];

function select_values(array $values, array $indices): array
{
    return array_map(fn($index) => $values[$index], $indices);
}

function append_statistics(array &$columns, array $values): void
{
    foreach ($values as $index => $value) {
        $columns[$index][] = $value;
    }
}

function bootstrap_samples(array $sample, array $indices): array
{
    $result = ['samples' => [], 'values' => [[], [], [], []], 'indices' => $indices];
    foreach ($indices as $chosen) {
        $values = select_values($sample, $chosen);
        $result['samples'][] = $values;
        append_statistics($result['values'], sample_statistics($values));
    }
    return $result;
}

function bootstrap_summary(float $estimate, array $values, int $confidence): array
{
    [$average, $se] = mean_and_se($values);
    $ordered = sorted($values);
    $lowRank = intdiv((count($values) + 1) * (100 - $confidence), 200);
    $highRank = count($values) + 1 - $lowRank;
    $low = $ordered[$lowRank - 1];
    $high = $ordered[$highRank - 1];
    return ['estimate' => $estimate, 'values' => $values, 'ordered' => $ordered, 'average' => $average, 'se' => $se,
        'bias' => $average - $estimate, 'low' => $low, 'high' => $high, 'basic_low' => 2 * $estimate - $high,
        'basic_high' => 2 * $estimate - $low, 'low_rank' => $lowRank, 'high_rank' => $highRank];
}

function summary_text(array $value): string
{
    return sprintf('se %s bias %s percentile %s %s basic %s %s', real($value['se']), real($value['bias']),
        real($value['low']), real($value['high']), real($value['basic_low']), real($value['basic_high']));
}

function jackknife_summary(array $values, float $estimate): array
{
    $average = float_sum($values) / count($values);
    $squares = 0.0;
    foreach ($values as $value) {
        $e = $value - $average;
        $squares += $e * $e;
    }
    $variance = (count($values) - 1) * $squares / count($values);
    return ['average' => $average, 'variance' => $variance, 'bias' => (count($values) - 1) * ($average - $estimate), 'se' => sqrt($variance)];
}

function describe(string $kind, string $name, array $sample, int $low, int $high, bool $stems): array
{
    $ordered = sorted($sample);
    $count = count($sample);
    $center = mean($sample);
    $moment = moments($sample);
    $wins = winsorized($sample);
    $q1 = quantile_numerator($sample, 25);
    $q3 = quantile_numerator($sample, 75);
    $outliers = [];
    $inside = [];
    foreach ($sample as $index => $value) {
        if (200 * $value < 5 * $q1 - 3 * $q3 || 200 * $value > 5 * $q3 - 3 * $q1) {
            $outliers[] = $index + 1;
        } else {
            $inside[] = $value;
        }
    }
    $w1 = min($inside);
    $w2 = max($inside);
    $delta = 100 * ($high - $low);
    $position = fn($value) => intdiv(120 * ($value - 100 * $low) + $delta, 2 * $delta);
    $band = array_fill(0, 61, '.');
    for ($index = $position(100 * $w1); $index <= $position(100 * $w2); $index++) {
        $band[$index] = '-';
    }
    for ($index = $position($q1); $index <= $position($q3); $index++) {
        $band[$index] = '=';
    }
    $band[$position(quantile_numerator($sample, 50))] = '|';
    foreach ($outliers as $index) {
        $band[$position(100 * $sample[$index - 1])] = 'o';
    }
    $lines = ["$kind $name", "n $count", 'mean ' . real($center), 'median ' . real(median($sample)),
        'trimmed_mean ' . real(trimmed_mean($sample)) . ' trim ' . intdiv($count, 10),
        'winsorized_mean ' . real(mean($wins)) . ' winsorized_sd ' . real(sd($wins)),
        'sd ' . real($moment['sd']), 'se_mean ' . real($moment['sd'] / sqrt($count)), 'cv ' . real($moment['sd'] / $center),
        'skewness ' . real($moment['m3'] / ($moment['m2'] * sqrt($moment['m2']))),
        'kurtosis ' . real($moment['m4'] / ($moment['m2'] * $moment['m2']) - 3), 'mad ' . real(mad($sample)),
        'min ' . real($ordered[0] / 100), 'q1 ' . real($q1 / 10000), 'q3 ' . real($q3 / 10000),
        'iqr ' . real(($q3 - $q1) / 10000), 'max ' . real($ordered[count($ordered) - 1] / 100),
        sprintf('percentiles p05 %s p10 %s p90 %s p95 %s', real(quantile_numerator($sample, 5) / 10000),
            real(quantile_numerator($sample, 10) / 10000), real(quantile_numerator($sample, 90) / 10000), real(quantile_numerator($sample, 95) / 10000)),
        'whiskers ' . real($w1 / 100) . ' ' . real($w2 / 100), 'outliers ' . number_list($outliers), 'box ' . implode('', $band)];
    if ($stems) {
        for ($stem = intdiv($ordered[0], 100); $stem <= intdiv($ordered[count($ordered) - 1], 100); $stem++) {
            $leaves = '';
            foreach ($ordered as $value) {
                if (intdiv($value, 100) === $stem) {
                    $leaves .= intdiv($value % 100, 10);
                }
            }
            $lines[] = "stem $stem" . ($leaves !== '' ? ' ' . $leaves : '');
        }
    }
    return $lines;
}

function tally_counts(int $size): array
{
    return array_fill(0, $size, ['extreme' => 0, 'greater' => 0]);
}

function count_comparisons(array $observed, array $trial, array &$counts): void
{
    foreach ($observed as $index => $value) {
        if (abs($trial[$index]) >= abs($value)) {
            $counts[$index]['extreme']++;
        }
        if ($trial[$index] >= $value) {
            $counts[$index]['greater']++;
        }
    }
}

function result_text(array $count, int $trials, int $offset = 1): string
{
    return sprintf('extreme %d greater %d p_two %s p_greater %s', $count['extreme'], $count['greater'],
        p_value($count['extreme'] + $offset, $trials + $offset), p_value($count['greater'] + $offset, $trials + $offset));
}

function ranked_sample(array $values): array
{
    $ranks = doubled_ranks($values);
    $result = [];
    foreach ($values as $index => $value) {
        $result[] = ['value' => $value, 'rank' => $ranks[$index]];
    }
    return $result;
}

function permutation_statistics(array $items, int $size): array
{
    $first = array_slice($items, 0, $size);
    $x = array_column($first, 'value');
    $y = array_column(array_slice($items, $size), 'value');
    $rankTotal = array_sum(array_column($first, 'rank'));
    $mx = doubled_median($x);
    $my = doubled_median($y);
    $ax = array_sum(array_map(fn($value) => abs(2 * $value - $mx), $x));
    $ay = array_sum(array_map(fn($value) => abs(2 * $value - $my), $y));
    return ['values' => [contrast($x, $y), $mx - $my, $rankTotal - $size * (count($items) + 1), count($y) * $ax - count($x) * $ay],
        'w' => $rankTotal / 2, 'u' => ($rankTotal - $size * ($size + 1)) / 2];
}

class Study
{
    public array $groups;
    public array $pairs;
    public array $settings;
    public Minstd $generator;
    public float $zLow;
    public array $pairedMean;
    public array $pairedCorrelation;

    public function __construct(public array $data)
    {
        $this->groups = $data['groups'];
        $this->pairs = $data['pairs'];
        $this->settings = $data['settings'];
        $this->generator = new Minstd($this->settings['seed']);
        $this->zLow = phi_inverse((100 - $this->settings['confidence']) / 200);
    }

    public function prepareBootstraps(): void
    {
        $count = $this->settings['bootstrap'];
        $confidence = $this->settings['confidence'];
        foreach ($this->groups as $group) {
            $group->estimates = sample_statistics($group->sample);
            $group->ordinary = bootstrap_samples($group->sample, ordinary_indices($this->generator, count($group->sample), $count));
            for ($statistic = 0; $statistic < 4; $statistic++) {
                $group->summaries[] = bootstrap_summary($group->estimates[$statistic], $group->ordinary['values'][$statistic], $confidence);
            }
        }
        foreach ($this->groups as $group) {
            $balanced = bootstrap_samples($group->sample, balanced_indices($this->generator, count($group->sample), $count));
            for ($statistic = 0; $statistic < 4; $statistic++) {
                $group->balancedSummaries[] = bootstrap_summary($group->estimates[$statistic], $balanced['values'][$statistic], $confidence);
            }
        }
        $differences = [];
        $correlations = [];
        for ($replicate = 0; $replicate < $count; $replicate++) {
            $indices = resample_indices($this->generator, count($this->data['before']));
            $differences[] = mean(select_values($this->data['differences'], $indices));
            $correlations[] = correlation(select_values($this->data['before'], $indices), select_values($this->data['after'], $indices));
        }
        $this->pairedMean = bootstrap_summary(mean($this->data['differences']), $differences, $confidence);
        $this->pairedCorrelation = bootstrap_summary(correlation($this->data['before'], $this->data['after']), $correlations, $confidence);
        foreach ($this->pairs as $pair) {
            $pair->estimates = pair_statistics($pair->first->sample, $pair->second->sample);
            $pair->values = [[], [], [], []];
            for ($replicate = 0; $replicate < $count; $replicate++) {
                append_statistics($pair->values, pair_statistics($pair->first->ordinary['samples'][$replicate], $pair->second->ordinary['samples'][$replicate]));
            }
            for ($statistic = 0; $statistic < 4; $statistic++) {
                $pair->summaries[] = bootstrap_summary($pair->estimates[$statistic], $pair->values[$statistic], $confidence);
            }
        }
    }

    public function descriptiveLines(): array
    {
        $values = [];
        foreach ($this->groups as $group) {
            array_push($values, ...$group->sample);
        }
        $low = min($values);
        $high = max($values);
        $lines = ['groups ' . count($this->groups) . ' observations ' . count($values)];
        foreach ($this->groups as $group) {
            array_push($lines, ...describe('group', $group->name, $group->sample, $low, $high, true));
        }
        $lines[] = 'paired subjects ' . count($this->data['before']);
        $together = array_merge($this->data['before'], $this->data['after']);
        $low = min($together);
        $high = max($together);
        array_push($lines, ...describe('series', 'before', $this->data['before'], $low, $high, false));
        array_push($lines, ...describe('series', 'after', $this->data['after'], $low, $high, false));
        $values = $this->data['differences'];
        array_push($lines, ...describe('series', 'diff', $values, min($values), max($values), false));
        return $lines;
    }

    public function bootstrapLines(): array
    {
        $lines = ['group,statistic,estimate,se,bias,percentile_lo,percentile_hi,basic_lo,basic_hi'];
        $row = function ($name, $statistic, $value) use (&$lines) {
            $fields = [$value['estimate'], $value['se'], $value['bias'], $value['low'], $value['high'], $value['basic_low'], $value['basic_high']];
            $lines[] = implode(',', [$name, $statistic, ...array_map(fn($field) => real($field), $fields)]);
        };
        foreach ($this->groups as $group) {
            foreach (GROUP_NAMES as $statistic => $name) {
                $row($group->name, $name, $group->summaries[$statistic]);
            }
            foreach (GROUP_NAMES as $statistic => $name) {
                $row($group->name, 'balanced_' . $name, $group->balancedSummaries[$statistic]);
            }
        }
        foreach ($this->pairs as $pair) {
            foreach (PAIR_NAMES as $statistic => $name) {
                $row($pair->name, $name, $pair->summaries[$statistic]);
            }
        }
        return $lines;
    }

    public function histogram(string $name, string $statistic, array $value): array
    {
        $bins = $this->settings['bins'];
        $low = $value['ordered'][0];
        $high = $value['ordered'][count($value['ordered']) - 1];
        $counts = array_fill(0, $bins, 0);
        $marks = array_fill(0, $bins, []);
        foreach ($value['values'] as $replicate) {
            $counts[bin_number($replicate, $low, $high, $bins) - 1]++;
        }
        $top = max($counts);
        $estimateBin = 'none';
        $marks[bin_number($value['low'], $low, $high, $bins) - 1][] = 'L';
        if ($value['estimate'] >= $low && $value['estimate'] <= $high) {
            $estimateBin = bin_number($value['estimate'], $low, $high, $bins);
            $marks[$estimateBin - 1][] = 'E';
        }
        $marks[bin_number($value['high'], $low, $high, $bins) - 1][] = 'H';
        $convergence = [];
        for ($quarter = 1; $quarter <= 4; $quarter++) {
            $size = intdiv($quarter * $this->settings['bootstrap'], 4);
            [$average, $se] = mean_and_se(array_slice($value['values'], 0, $size));
            $convergence[] = $size . ':' . real($se);
        }
        $lines = [sprintf('histogram %s %s min %s max %s width %s top %d estimate_bin %s', $name, $statistic,
            real($low), real($high), real(($high - $low) / $bins), $top, $estimateBin), 'convergence ' . implode(' ', $convergence)];
        foreach ($counts as $index => $count) {
            $parts = ['bin', $index + 1, real($low + ($high - $low) * $index / $bins), $count];
            if ($count > 0) {
                $parts[] = bar($count, $top);
            }
            array_push($parts, ...$marks[$index]);
            $lines[] = implode(' ', $parts);
        }
        return $lines;
    }

    public function histogramLines(): array
    {
        $lines = [];
        foreach ($this->groups as $group) {
            foreach (GROUP_NAMES as $statistic => $name) {
                array_push($lines, ...$this->histogram($group->name, $name, $group->summaries[$statistic]));
            }
        }
        foreach ($this->pairs as $pair) {
            foreach (PAIR_NAMES as $statistic => $name) {
                array_push($lines, ...$this->histogram($pair->name, $name, $pair->summaries[$statistic]));
            }
        }
        return $lines;
    }

    public function groupJackknife(Group $group): array
    {
        $sample = $group->sample;
        $size = count($sample);
        $values = [[], [], [], []];
        for ($index = 0; $index < $size; $index++) {
            append_statistics($values, sample_statistics(without($sample, $index)));
        }
        $moments = [];
        $lines = ["group $group->name n $size"];
        foreach (GROUP_NAMES as $statistic => $name) {
            $moment = jackknife_summary($values[$statistic], $group->estimates[$statistic]);
            $moments[] = $moment;
            $lines[] = sprintf('jackknife %s estimate %s average %s bias %s se %s', $name, real($group->estimates[$statistic]), real($moment['average']), real($moment['bias']), real($moment['se']));
        }
        foreach (GROUP_NAMES as $statistic => $name) {
            $value = $group->summaries[$statistic];
            $below = count(array_filter($value['values'], fn($replicate) => $replicate < $value['estimate']));
            $z0 = phi_inverse($below / count($value['values']));
            $v2 = 0.0;
            $v3 = 0.0;
            foreach ($values[$statistic] as $deleted) {
                $u = $moments[$statistic]['average'] - $deleted;
                $v2 += $u * $u;
                $v3 += $u * $u * $u;
            }
            $acceleration = $v3 / (6 * $v2 * sqrt($v2));
            $alpha = fn($z) => phi($z0 + ($z0 + $z) / (1 - $acceleration * ($z0 + $z)));
            $b = count($value['values']);
            $first = max(1, min($b, (int) floor(($b + 1) * $alpha($this->zLow))));
            $second = max(1, min($b, $b + 1 - (int) floor(($b + 1) * (1 - $alpha(-$this->zLow)))));
            $lines[] = sprintf('bca %s below %d z0 %s acceleration %s ranks %d %d interval %s %s', $name, $below, real($z0), real($acceleration),
                $first, $second, real($value['ordered'][$first - 1]), real($value['ordered'][$second - 1]));
        }
        $omitted = array_fill(0, $size, []);
        foreach ($group->ordinary['indices'] as $replicate => $indices) {
            $chosen = array_fill_keys($indices, true);
            for ($index = 0; $index < $size; $index++) {
                if (!isset($chosen[$index])) {
                    $omitted[$index][] = $replicate;
                }
            }
        }
        $errors = [[], [], [], []];
        foreach (GROUP_NAMES as $statistic => $name) {
            foreach ($omitted as $index => $indices) {
                [$average, $se] = mean_and_se(select_values($group->ordinary['values'][$statistic], $indices));
                $errors[$statistic][$index] = $se;
            }
            $moment = jackknife_summary($errors[$statistic], 0);
            $lines[] = sprintf('after_bootstrap %s se %s average %s se_of_se %s', $name, real($group->summaries[$statistic]['se']), real($moment['average']), real($moment['se']));
        }
        $sizes = array_map('count', $omitted);
        $lines[] = sprintf('without min %d max %d', min($sizes), max($sizes));
        $total = array_sum($sample);
        $order = range(0, $size - 1);
        usort($order, fn($a, $b) => abs($size * $sample[$b] - $total) <=> abs($size * $sample[$a] - $total) ?: $a <=> $b);
        foreach (array_slice($order, 0, 5) as $rank => $index) {
            $shifted = sorted(array_map(fn($replicate) => $group->ordinary['values'][0][$replicate] - $group->estimates[0], $omitted[$index]));
            $quantile = fn($p) => $shifted[intdiv($p * count($shifted) + 99, 100) - 1];
            $influence = ($size - 1) * ($moments[0]['average'] - $values[0][$index]);
            $lines[] = sprintf('influence %d obs %d value %s l %s without %d se %s q05 %s q50 %s q95 %s', $rank + 1, $index + 1,
                real($sample[$index] / 100), real($influence), $sizes[$index], real($errors[0][$index]), real($quantile(5)), real($quantile(50)), real($quantile(95)));
        }
        return $lines;
    }

    public function pairJackknife(Pair $pair): array
    {
        $x = $pair->first->sample;
        $y = $pair->second->sample;
        $first = [[], [], [], []];
        $second = [[], [], [], []];
        foreach ($x as $index => $value) {
            append_statistics($first, pair_statistics(without($x, $index), $y));
        }
        foreach ($y as $index => $value) {
            append_statistics($second, pair_statistics($x, without($y, $index)));
        }
        $lines = [];
        foreach (PAIR_NAMES as $statistic => $name) {
            $bias = 0.0;
            $variance = 0.0;
            foreach ([$first, $second] as $part) {
                $moment = jackknife_summary($part[$statistic], $pair->estimates[$statistic]);
                $bias += $moment['bias'];
                $variance += $moment['variance'];
            }
            $lines[] = sprintf('pair %s %s estimate %s bias %s se %s', $pair->name, $name, real($pair->estimates[$statistic]), real($bias), real(sqrt($variance)));
        }
        return $lines;
    }

    public function jackknifeLines(): array
    {
        $lines = [];
        foreach ($this->groups as $group) {
            array_push($lines, ...$this->groupJackknife($group));
        }
        foreach ($this->pairs as $pair) {
            array_push($lines, ...$this->pairJackknife($pair));
        }
        return $lines;
    }

    public function permutationLines(Pair $pair): array
    {
        $x = $pair->first->sample;
        $y = $pair->second->sample;
        $items = ranked_sample(array_merge($x, $y));
        $observed = permutation_statistics($items, count($x));
        $counts = tally_counts(4);
        $r = $this->settings['permutations'];
        for ($replicate = 0; $replicate < $r; $replicate++) {
            $trial = permutation_statistics($this->generator->shuffle($items), count($x));
            count_comparisons($observed['values'], $trial['values'], $counts);
        }
        $pair->extremes = array_column($counts, 'extreme');
        return ["compare {$pair->first->name} {$pair->second->name}", sprintf('permutation n %d %d perms %d', count($x), count($y), $r),
            'mean diff ' . real($pair->estimates[0]) . ' ' . result_text($counts[0], $r),
            'median diff ' . real($observed['values'][1] / 200) . ' ' . result_text($counts[1], $r),
            sprintf('ranksum w %s u %s %s', real($observed['w']), real($observed['u']), result_text($counts[2], $r)),
            'absdev diff ' . real($observed['values'][3] / (200 * count($x) * count($y))) . ' ' . result_text($counts[3], $r)];
    }

    public function powerLine(Pair $pair): string
    {
        $x = $pair->first->sample;
        $y = $pair->second->sample;
        $settings = $this->settings;
        $rejections = 0;
        for ($simulation = 0; $simulation < $settings['power_sims']; $simulation++) {
            $first = select_values($x, resample_indices($this->generator, count($x)));
            $second = select_values($y, resample_indices($this->generator, count($y)));
            $combined = array_merge($first, $second);
            $observed = abs(contrast($first, $second));
            $extreme = 0;
            for ($permutation = 0; $permutation < $settings['power_perms']; $permutation++) {
                $shuffled = $this->generator->shuffle($combined);
                if (abs(contrast(array_slice($shuffled, 0, count($x)), array_slice($shuffled, count($x)))) >= $observed) {
                    $extreme++;
                }
            }
            if (100 * ($extreme + 1) <= (100 - $settings['confidence']) * ($settings['power_perms'] + 1)) {
                $rejections++;
            }
        }
        $power = $rejections / $settings['power_sims'];
        return sprintf('power sims %d perms %d rejections %d power %s se %s', $settings['power_sims'], $settings['power_perms'],
            $rejections, real($power), real(sqrt($power * (1 - $power) / $settings['power_sims'])));
    }

    public function exactLines(Pair $pair): array
    {
        $size = $this->settings['pilot'];
        $x = array_slice($pair->first->sample, 0, $size);
        $y = array_slice($pair->second->sample, 0, $size);
        $combined = array_merge($x, $y);
        $ranks = doubled_ranks($combined);
        $total = array_sum($combined);
        $rankTotal = array_sum(array_slice($ranks, 0, $size));
        $observed = [contrast($x, $y), $rankTotal - $size * (2 * $size + 1)];
        $counts = tally_counts(2);
        $frequencies = [];
        $splits = 0;
        foreach (position_choices(2 * $size, $size) as $choice) {
            $chosen = array_sum(select_values($combined, $choice));
            $rankSum = array_sum(select_values($ranks, $choice));
            $value = $size * $chosen - $size * ($total - $chosen);
            count_comparisons($observed, [$value, $rankSum - $size * (2 * $size + 1)], $counts);
            $absolute = abs($value);
            $frequencies[$absolute] = ($frequencies[$absolute] ?? 0) + 1;
            $splits++;
        }
        krsort($frequencies, SORT_NUMERIC);
        $cumulative = 0;
        $critical = null;
        $attained = 0;
        foreach ($frequencies as $value => $count) {
            $cumulative += $count;
            if (100 * $cumulative > (100 - $this->settings['confidence']) * $splits) {
                break;
            }
            $critical = $value;
            $attained = $cumulative;
        }
        $criticalLine = $critical === null ? 'critical diff none attained none'
            : 'critical diff ' . real($critical / (100 * $size * $size)) . ' attained ' . p_value($attained, $splits);
        return ["exact size $size splits $splits", 'mean diff ' . real(mean_difference($x, $y)) . ' ' . result_text($counts[0], $splits, 0),
            sprintf('ranksum w %s u %s %s', real($rankTotal / 2), real(($rankTotal - $size * ($size + 1)) / 2), result_text($counts[1], $splits, 0)), $criticalLine];
    }

    public function studentizedLines(Pair $pair): array
    {
        $x = $pair->first->sample;
        $y = $pair->second->sample;
        $k = count($x);
        $m = count($y);
        $sx = sd($x);
        $sy = sd($y);
        $vx = $sx * $sx / $k;
        $vy = $sy * $sy / $m;
        $se0 = sqrt($vx + $vy);
        $estimate = $pair->estimates[0];
        $statistic = $estimate / $se0;
        $values = [];
        $extreme = 0;
        for ($replicate = 0; $replicate < $this->settings['bootstrap']; $replicate++) {
            $first = $pair->first->ordinary['values'][3][$replicate];
            $second = $pair->second->ordinary['values'][3][$replicate];
            $value = ($pair->values[0][$replicate] - $estimate) / sqrt($first * $first / $k + $second * $second / $m);
            $values[] = $value;
            if (abs($value) >= abs($statistic)) {
                $extreme++;
            }
        }
        $values = sorted($values);
        $low = $estimate - $values[$pair->summaries[0]['high_rank'] - 1] * $se0;
        $high = $estimate - $values[$pair->summaries[0]['low_rank'] - 1] * $se0;
        $df = ($vx + $vy) * ($vx + $vy) / ($vx * $vx / ($k - 1) + $vy * $vy / ($m - 1));
        $greater = 0;
        $equal = 0;
        foreach ($x as $first) {
            foreach ($y as $second) {
                if ($first > $second) {
                    $greater++;
                }
                if ($first === $second) {
                    $equal++;
                }
            }
        }
        $d = $pair->estimates[3];
        return [sprintf('bootstrap_t t %s df %s extreme %d p %s interval %s %s', real($statistic), real($df), $extreme,
            p_value($extreme + 1, $this->settings['bootstrap'] + 1), real($low), real($high)),
            sprintf('effect pooled_sd %s cohen_d %s hedges_g %s cles %s', real(pooled_sd($x, $y)), real($d),
                real($d * (1 - 3 / (4 * ($k + $m - 2) - 1))), real((2 * $greater + $equal) / (2 * $k * $m)))];
    }

    public function holmLines(): array
    {
        $lines = [];
        $denominator = $this->settings['permutations'] + 1;
        foreach (TEST_NAMES as $statistic => $name) {
            $order = $this->pairs;
            usort($order, fn($a, $b) => $a->extremes[$statistic] <=> $b->extremes[$statistic] ?: $a->number <=> $b->number);
            $adjusted = 0;
            foreach ($order as $rank => $pair) {
                $numerator = $pair->extremes[$statistic] + 1;
                $adjusted = max($adjusted, min($denominator, (count($order) - $rank) * $numerator));
                $decision = 100 * $adjusted <= (100 - $this->settings['confidence']) * $denominator ? 'reject' : 'retain';
                $lines[] = sprintf('holm %s rank %d %s %s p %s adjusted %s %s', $name, $rank + 1, $pair->first->name, $pair->second->name,
                    p_value($numerator, $denominator), p_value($adjusted, $denominator), $decision);
            }
        }
        return $lines;
    }

    public function pairedLines(): array
    {
        $d = $this->data['differences'];
        $count = count($d);
        $positive = count(array_filter($d, fn($value) => $value > 0));
        $negative = count(array_filter($d, fn($value) => $value < 0));
        $zero = $count - $positive - $negative;
        $magnitudes = array_values(array_map('abs', array_filter($d, fn($value) => $value !== 0)));
        $ranks = doubled_ranks($magnitudes);
        $signed = [];
        $cursor = 0;
        $positiveRanks = 0;
        foreach ($d as $value) {
            if ($value === 0) {
                $signed[] = 0;
            } else {
                $signed[] = $value > 0 ? $ranks[$cursor] : -$ranks[$cursor];
                if ($value > 0) {
                    $positiveRanks += $ranks[$cursor];
                }
                $cursor++;
            }
        }
        $center = mean($d);
        $deviation = sd($d);
        $r = $this->pairedCorrelation['estimate'];
        $z = 0.5 * log((1 + $r) / (1 - $r));
        $half = -$this->zLow / sqrt($count - 3);
        $tanh = function ($value) {
            $exponential = exp(2 * $value);
            return ($exponential - 1) / ($exponential + 1);
        };
        $lines = ["paired subjects $count positive $positive negative $negative zero $zero",
            sprintf('paired before %s after %s diff %s sd_diff %s t %s dz %s', real(mean($this->data['before'])), real(mean($this->data['after'])),
                real($center), real($deviation), real($center / ($deviation / sqrt($count))), real($center / $deviation)),
            'paired_bootstrap ' . summary_text($this->pairedMean),
            sprintf('correlation r %s %s fisher %s %s', real($r), summary_text($this->pairedCorrelation), real($tanh($z - $half)), real($tanh($z + $half)))];
        $observed = [array_sum($d), array_sum($signed)];
        $counts = tally_counts(2);
        for ($replicate = 0; $replicate < $this->settings['permutations']; $replicate++) {
            $total = 0;
            $rankTotal = 0;
            foreach ($d as $index => $value) {
                $sign = $this->generator->draw() % 2 === 1 ? -1 : 1;
                $total += $sign * $value;
                $rankTotal += $sign * $signed[$index];
            }
            count_comparisons($observed, [$total, $rankTotal], $counts);
        }
        $lines[] = 'signflip flips ' . $this->settings['permutations'];
        $lines[] = 'mean diff ' . real($center) . ' ' . result_text($counts[0], $this->settings['permutations']);
        $lines[] = 'signedrank w_plus ' . real($positiveRanks / 2) . ' ' . result_text($counts[1], $this->settings['permutations']);
        return $lines;
    }

    public function anovaLines(): array
    {
        $samples = array_map(fn($group) => $group->sample, $this->groups);
        $sizes = array_map('count', $samples);
        $combined = array_merge(...$samples);
        $original = anova($samples);
        $groupCount = count($samples);
        $count = count($combined);
        $msw = $original['ssw'] / ($count - $groupCount);
        $eta = $original['ssb'] / ($original['ssb'] + $original['ssw']);
        $omega = ($original['ssb'] - ($groupCount - 1) * $msw) / ($original['ssb'] + $original['ssw'] + $msw);
        $etaValues = [];
        for ($replicate = 0; $replicate < $this->settings['bootstrap']; $replicate++) {
            $values = array_map(fn($group) => $group->ordinary['samples'][$replicate], $this->groups);
            $result = anova($values);
            $etaValues[] = $result['ssb'] / ($result['ssb'] + $result['ssw']);
        }
        $weights = [];
        foreach ($samples as $sample) {
            $deviation = sd($sample);
            $weights[] = count($sample) / ($deviation * $deviation);
        }
        $totalWeight = float_sum($weights);
        $weighted = 0.0;
        foreach ($weights as $index => $weight) {
            $weighted += $weight * $original['means'][$index];
        }
        $center = $weighted / $totalWeight;
        $spread = 0.0;
        $lambda = 0.0;
        foreach ($weights as $index => $weight) {
            $difference = $original['means'][$index] - $center;
            $share = 1 - $weight / $totalWeight;
            $spread += $weight * ($difference * $difference);
            $lambda += $share * $share / ($sizes[$index] - 1);
        }
        $aw = $spread / ($groupCount - 1);
        $welch = $aw / (1 + 2 * ($groupCount - 2) * $lambda / ($groupCount * $groupCount - 1));
        $df2 = ($groupCount * $groupCount - 1) / (3 * $lambda);
        $tieGroups = 0;
        $tieTotal = 0;
        foreach (value_counts($combined) as $size) {
            if ($size >= 2) {
                $tieGroups++;
                $tieTotal += $size * $size * $size - $size;
            }
        }
        $correction = 1 - $tieTotal / ($count * $count * $count - $count);
        $ranks = doubled_ranks($combined);
        $h = kruskal(split_list($ranks, $sizes), $correction);
        $lines = [sprintf('anova groups %d observations %d ssb %s ssw %s df %d %d f %s eta_squared %s omega_squared %s', $groupCount,
            $count, real($original['ssb']), real($original['ssw']), $groupCount - 1, $count - $groupCount, real($original['f']), real($eta), real($omega)),
            'eta_bootstrap ' . summary_text(bootstrap_summary($eta, $etaValues, $this->settings['confidence'])),
            sprintf('welch f %s df %d %s', real($welch), $groupCount - 1, real($df2)), "kruskal h " . real($h) . " tie_groups $tieGroups"];
        $pairs = [];
        for ($first = 0; $first < $groupCount; $first++) {
            for ($second = $first + 1; $second < $groupCount; $second++) {
                $pairs[] = ['first' => $first, 'second' => $second, 'numerator' => abs(contrast($samples[$first], $samples[$second])),
                    'denominator' => $sizes[$first] * $sizes[$second], 'extreme' => 0, 'maximum' => 0];
            }
        }
        $atLeast = fn($a, $b) => $a['numerator'] * $b['denominator'] >= $b['numerator'] * $a['denominator'];
        $fExtreme = 0;
        $hExtreme = 0;
        $items = ranked_sample($combined);
        for ($replicate = 0; $replicate < $this->settings['permutations']; $replicate++) {
            $parts = split_list($this->generator->shuffle($items), $sizes);
            $trialSamples = array_map(fn($part) => array_column($part, 'value'), $parts);
            $rankGroups = array_map(fn($part) => array_column($part, 'rank'), $parts);
            $result = anova($trialSamples);
            $trialH = kruskal($rankGroups, $correction);
            if ($result['f'] >= $original['f'] - 0.000000001 * $original['f']) {
                $fExtreme++;
            }
            if ($trialH >= $h - 0.000000001 * $h) {
                $hExtreme++;
            }
            $deltas = [];
            $maximum = null;
            foreach ($pairs as $index => $pair) {
                $value = ['numerator' => abs(contrast($trialSamples[$pair['first']], $trialSamples[$pair['second']])), 'denominator' => $pair['denominator']];
                $deltas[] = $value;
                if ($maximum === null || !$atLeast($maximum, $value)) {
                    $maximum = $value;
                }
            }
            foreach ($pairs as $index => &$pair) {
                if ($atLeast($deltas[$index], $pair)) {
                    $pair['extreme']++;
                }
                if ($atLeast($maximum, $pair)) {
                    $pair['maximum']++;
                }
            }
            unset($pair);
        }
        $lines[] = sprintf('anova_permutation perms %d f_extreme %d f_p %s h_extreme %d h_p %s', $this->settings['permutations'],
            $fExtreme, p_value($fExtreme + 1, $this->settings['permutations'] + 1), $hExtreme, p_value($hExtreme + 1, $this->settings['permutations'] + 1));
        foreach ($pairs as $pair) {
            $lines[] = sprintf('pairwise %s %s diff %s extreme %d p %s maxt %d adjusted %s', $this->groups[$pair['first']]->name, $this->groups[$pair['second']]->name,
                real(mean_difference($samples[$pair['first']], $samples[$pair['second']])), $pair['extreme'], p_value($pair['extreme'] + 1, $this->settings['permutations'] + 1),
                $pair['maximum'], p_value($pair['maximum'] + 1, $this->settings['permutations'] + 1));
        }
        return $lines;
    }

    public function run(): array
    {
        $this->prepareBootstraps();
        $lines = [];
        foreach ($this->pairs as $pair) {
            array_push($lines, ...$this->permutationLines($pair));
            $lines[] = $this->powerLine($pair);
            array_push($lines, ...$this->exactLines($pair));
            array_push($lines, ...$this->studentizedLines($pair));
        }
        array_push($lines, ...$this->holmLines());
        array_push($lines, ...$this->pairedLines());
        array_push($lines, ...$this->anovaLines());
        return ['descriptives.txt' => $this->descriptiveLines(), 'bootstrap.csv' => $this->bootstrapLines(),
            'jackknife.txt' => $this->jackknifeLines(), 'tests.txt' => $lines, 'histograms.txt' => $this->histogramLines()];
    }
}

write_files((new Study(load_dataset('input')))->run());
