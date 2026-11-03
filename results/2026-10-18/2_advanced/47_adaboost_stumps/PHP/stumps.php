<?php

class Stump
{
    public $feature;
    public $thresholds;
    public $values;

    public function __construct($feature, $thresholds, $values)
    {
        $this->feature = $feature;
        $this->thresholds = $thresholds;
        $this->values = $values;
    }

    public function output($values)
    {
        $bin = 0;
        foreach ($this->thresholds as $threshold) if ($values[$this->feature] > $threshold) $bin++;
        return $this->values[$bin];
    }
}

function prepare($rows)
{
    $plans = [];
    foreach ($rows[0]['values'] as $feature => $value) {
        $order = range(0, count($rows) - 1);
        usort($order, fn($a, $b) => ($rows[$a]['values'][$feature] <=> $rows[$b]['values'][$feature]) ?: ($a <=> $b));
        $groups = [];
        $distinct = [];
        foreach ($order as $i) {
            $current = $rows[$i]['values'][$feature];
            if (count($distinct) === 0 || $distinct[count($distinct) - 1] != $current) {
                $distinct[] = $current;
                $groups[] = [];
            }
            $groups[count($groups) - 1][] = $i;
        }
        $thresholds = [$distinct[0] - 1];
        for ($i = 1; $i < count($distinct); $i++) $thresholds[] = ($distinct[$i - 1] + $distinct[$i]) / 2;
        $plans[] = compact('feature', 'order', 'groups', 'thresholds');
    }
    return $plans;
}

function choose($candidates)
{
    $minimum = $candidates[0]['error'];
    foreach ($candidates as $candidate) if ($candidate['error'] < $minimum) $minimum = $candidate['error'];
    foreach ($candidates as $candidate) if ($candidate['error'] <= $minimum + 1e-9) return $candidate;
}

function discrete_search($rows, $weights, $plans)
{
    $positive = 0.0;
    $negative = 0.0;
    foreach ($rows as $i => $row) {
        $positive += $row['label'] === 1 ? $weights[$i] : 0;
        $negative += $row['label'] === -1 ? $weights[$i] : 0;
    }
    $candidates = [];
    foreach ($plans as $plan) {
        $leftPositive = 0.0;
        $leftNegative = 0.0;
        foreach ($plan['thresholds'] as $k => $threshold) {
            if ($k > 0) foreach ($plan['groups'][$k - 1] as $i) {
                $leftPositive += $rows[$i]['label'] === 1 ? $weights[$i] : 0;
                $leftNegative += $rows[$i]['label'] === -1 ? $weights[$i] : 0;
            }
            $candidates[] = ['feature' => $plan['feature'], 'threshold' => $threshold, 'polarity' => 1, 'error' => $leftPositive + ($negative - $leftNegative)];
            $candidates[] = ['feature' => $plan['feature'], 'threshold' => $threshold, 'polarity' => -1, 'error' => $leftNegative + ($positive - $leftPositive)];
        }
    }
    return choose($candidates);
}

function regression_search($rows, $targets, $weights, $plans)
{
    $weight = 0.0;
    $total = 0.0;
    $squares = 0.0;
    foreach ($rows as $i => $row) {
        $weight += $weights[$i];
        $total += $weights[$i] * $targets[$i];
        $squares += $weights[$i] * $targets[$i] * $targets[$i];
    }
    $candidates = [];
    foreach ($plans as $plan) {
        $leftWeight = 0.0;
        $leftTotal = 0.0;
        foreach ($plan['thresholds'] as $k => $threshold) {
            if ($k > 0) foreach ($plan['groups'][$k - 1] as $i) {
                $leftWeight += $weights[$i];
                $leftTotal += $weights[$i] * $targets[$i];
            }
            $rightWeight = $weight - $leftWeight;
            $rightTotal = $total - $leftTotal;
            $left = $k === 0 ? 0.0 : $leftTotal / $leftWeight;
            $gain = $k === 0 ? $rightTotal * $rightTotal / $rightWeight :
                $leftTotal * $leftTotal / $leftWeight + $rightTotal * $rightTotal / $rightWeight;
            $right = $rightTotal / $rightWeight;
            $candidates[] = ['stump' => new Stump($plan['feature'], [$threshold], [$left, $right]), 'error' => $squares - $gain];
        }
    }
    return choose($candidates);
}

function largest_index($values)
{
    $best = 0;
    for ($i = 1; $i < count($values); $i++) if ($values[$i] > $values[$best]) $best = $i;
    return $best;
}

function multiclass_search($rows, $weights, $plans, $classes)
{
    $total = 0.0;
    $totals = array_fill(0, $classes, 0.0);
    foreach ($rows as $i => $row) {
        $total += $weights[$i];
        for ($c = 0; $c < $classes; $c++) $totals[$c] += $row['category'] === $c + 1 ? $weights[$i] : 0;
    }
    $candidates = [];
    foreach ($plans as $plan) {
        $left = array_fill(0, $classes, 0.0);
        foreach ($plan['thresholds'] as $k => $threshold) {
            if ($k > 0) foreach ($plan['groups'][$k - 1] as $i) {
                for ($c = 0; $c < $classes; $c++) $left[$c] += $rows[$i]['category'] === $c + 1 ? $weights[$i] : 0;
            }
            $right = [];
            foreach ($totals as $c => $value) $right[] = $value - $left[$c];
            $a = largest_index($left);
            $b = largest_index($right);
            $candidates[] = ['stump' => new Stump($plan['feature'], [$threshold], [$a + 1, $b + 1]), 'error' => $total - ($left[$a] + $right[$b])];
        }
    }
    return choose($candidates);
}

function real_plans($rows, $bins)
{
    $result = [];
    foreach (prepare($rows) as $plan) {
        $cuts = [];
        for ($b = 1; $b < $bins; $b++) {
            $r = intdiv($b * count($rows), $bins);
            $cuts[] = ($rows[$plan['order'][$r - 1]]['values'][$plan['feature']] + $rows[$plan['order'][$r]]['values'][$plan['feature']]) / 2;
        }
        $assignments = [];
        foreach ($rows as $row) {
            $bin = 0;
            foreach ($cuts as $cut) if ($cut < $row['values'][$plan['feature']]) $bin++;
            $assignments[] = $bin;
        }
        $result[] = ['feature' => $plan['feature'], 'cuts' => $cuts, 'assignments' => $assignments];
    }
    return $result;
}

function real_search($rows, $weights, $plans, $bins)
{
    $candidates = [];
    foreach ($plans as $plan) {
        $positive = array_fill(0, $bins, 0.0);
        $negative = array_fill(0, $bins, 0.0);
        foreach ($rows as $i => $row) {
            $bin = $plan['assignments'][$i];
            if ($row['label'] === 1) $positive[$bin] += $weights[$i];
            else $negative[$bin] += $weights[$i];
        }
        $overlap = 0.0;
        for ($b = 0; $b < $bins; $b++) $overlap += sqrt($positive[$b] * $negative[$b]);
        $candidates[] = ['feature' => $plan['feature'], 'cuts' => $plan['cuts'], 'positive' => $positive, 'negative' => $negative, 'error' => 2 * $overlap];
    }
    return choose($candidates);
}
