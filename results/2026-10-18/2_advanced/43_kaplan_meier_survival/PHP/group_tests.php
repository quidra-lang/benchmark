<?php

function emptySums($count)
{
    return ['events' => array_fill(0, $count, 0), 'observed' => array_fill(0, $count, 0.0),
        'expected' => array_fill(0, $count, 0.0),
        'covariance' => array_fill(0, $count, array_fill(0, $count, 0.0))];
}

function finishTest($sums)
{
    $degrees = count($sums['events']) - 1;
    $difference = [];
    $matrix = [];
    for ($h = 0; $h < $degrees; $h++) {
        $difference[] = $sums['observed'][$h] - $sums['expected'][$h];
        $matrix[] = array_slice($sums['covariance'][$h], 0, $degrees);
    }
    $solution = solve($matrix, $difference);
    $chisq = 0.0;
    for ($h = 0; $h < $degrees; $h++) {
        $chisq += $difference[$h] * $solution[$h];
    }
    $sums['chisq'] = $chisq;
    $sums['degrees'] = $degrees;
    $sums['p'] = chiSquareP($chisq, $degrees);
    return $sums;
}

function weightedTest($subjects, $groups, $weight, $totalSubjects)
{
    $count = count($groups);
    $indices = array_flip($groups);
    $sums = emptySums($count);
    foreach (riskSets($subjects) as $row) {
        if ($row['events'] === 0) {
            continue;
        }
        $atRisk = array_fill(0, $count, 0);
        $events = array_fill(0, $count, 0);
        foreach ($subjects as $subject) {
            $h = $indices[$subject['group']];
            if ($subject['time'] >= $row['time']) {
                $atRisk[$h]++;
            }
            if ($subject['time'] === $row['time'] && $subject['event'] === 1) {
                $events[$h]++;
            }
        }
        $n = array_sum($atRisk);
        $d = array_sum($events);
        $nu = $weight === 'logrank' ? 1.0 :
            ($weight === 'gehan_wilcoxon' ? $n / $totalSubjects : sqrt($n / $totalSubjects));
        for ($h = 0; $h < $count; $h++) {
            $sums['events'][$h] += $events[$h];
            $sums['observed'][$h] += $nu * $events[$h];
            $sums['expected'][$h] += $nu * (($d * $atRisk[$h]) / $n);
            if ($n < 2) {
                continue;
            }
            for ($l = 0; $l < $count; $l++) {
                $multiplier = $h === $l ? $atRisk[$h] * ($n - $atRisk[$h]) : -($atRisk[$h] * $atRisk[$l]);
                $sums['covariance'][$h][$l] += $nu * $nu * (($d * ($n - $d)) / (($n - 1) * $n * $n)) * $multiplier;
            }
        }
    }
    return finishTest($sums);
}

function combineStrata($tests)
{
    $count = count($tests[0]['events']);
    $totals = emptySums($count);
    foreach ($tests as $test) {
        for ($h = 0; $h < $count; $h++) {
            $totals['events'][$h] += $test['events'][$h];
            $totals['observed'][$h] += $test['observed'][$h];
            $totals['expected'][$h] += $test['expected'][$h];
            for ($l = 0; $l < $count; $l++) {
                $totals['covariance'][$h][$l] += $test['covariance'][$h][$l];
            }
        }
    }
    return finishTest($totals);
}
