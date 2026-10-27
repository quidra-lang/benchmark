<?php

require_once __DIR__ . '/dataset.php';
require_once __DIR__ . '/numerics.php';
require_once __DIR__ . '/estimators.php';
require_once __DIR__ . '/group_tests.php';
require_once __DIR__ . '/cox.php';
require_once __DIR__ . '/plot.php';

const WEIGHTS = ['logrank', 'gehan_wilcoxon', 'tarone_ware'];
const CONTINUOUS = ['age', 'male', 'stage'];

function fixed($value, $digits = 4)
{
    if ($value === null) {
        return 'NA';
    }
    $result = number_format(abs($value), $digits, '.', '');
    return $value < 0 && $result !== '0.' . str_repeat('0', $digits) ? '-' . $result : $result;
}

function day($value)
{
    return $value === null ? 'NA' : (string)$value;
}

function eventCount($subjects)
{
    $count = 0;
    foreach ($subjects as $subject) {
        $count += $subject['event'];
    }
    return $count;
}

function levelsOf($subjects, $variable)
{
    $values = array_values(array_unique(array_column($subjects, $variable)));
    sort($values);
    return $values;
}

function firstDay($rows, $predicate)
{
    foreach ($rows as $row) {
        if ($predicate($row)) {
            return $row['time'];
        }
    }
    return null;
}

function restrictedMean($rows, $tau)
{
    $selected = array_values(array_filter($rows, fn($row) => $row['time'] <= $tau));
    $times = array_merge([0], array_column($selected, 'time'), [$tau]);
    $rectangles = [];
    for ($i = 0; $i <= count($selected); $i++) {
        $survival = $i === 0 ? 1.0 : $selected[$i - 1]['survival'];
        $rectangles[] = $survival * ($times[$i + 1] - $times[$i]);
    }
    $suffix = array_fill(0, count($rectangles), 0.0);
    $last = count($rectangles) - 1;
    $suffix[$last] = $rectangles[$last];
    for ($i = $last - 1; $i >= 0; $i--) {
        $suffix[$i] = $rectangles[$i] + $suffix[$i + 1];
    }
    $variance = 0.0;
    for ($i = 1; $i <= count($selected); $i++) {
        $n = $selected[$i - 1]['atRisk'];
        $d = $selected[$i - 1]['events'];
        $variance += $suffix[$i] * $suffix[$i] * ($d / ($n * ($n - $d)));
    }
    $estimate = $suffix[0];
    $se = sqrt($variance);
    return ['estimate' => $estimate, 'se' => $se, 'lower' => $estimate - Z * $se, 'upper' => $estimate + Z * $se];
}

function ageSummary($subjects)
{
    $ageSum = $male = 0;
    $stages = array_fill(0, 4, 0);
    foreach ($subjects as $subject) {
        $ageSum += $subject['age'];
        if ($subject['sex'] === 'M') {
            $male++;
        }
        $stages[$subject['stage'] - 1]++;
    }
    $mean = $ageSum / count($subjects);
    $squares = 0.0;
    foreach ($subjects as $subject) {
        $squares += ($subject['age'] - $mean) * ($subject['age'] - $mean);
    }
    $ages = array_column($subjects, 'age');
    sort($ages, SORT_NUMERIC);
    $n = count($ages);
    $median = ($ages[intdiv($n - 1, 2)] + $ages[intdiv($n, 2)]) / 2;
    return ['mean' => $mean, 'sd' => sqrt($squares / ($n - 1)), 'median' => $median,
        'male' => $male, 'stages' => $stages];
}

function makeCollection($name, $subjects, $params)
{
    $km = kaplanMeier($subjects);
    $life = lifeTable($subjects, $params['lifeWidth'], $params['lifeCount']);
    $events = eventCount($subjects);
    $personDays = $maxTime = 0;
    foreach ($subjects as $subject) {
        $personDays += $subject['time'];
        $maxTime = max($maxTime, $subject['time']);
    }
    $rate = (1000 * $events) / $personDays;
    $eta = Z / sqrt($events);
    $reverse = [];
    foreach ($subjects as $subject) {
        $subject['event'] = 1 - $subject['event'];
        $reverse[] = $subject;
    }
    $followupMedian = firstDay(kaplanMeier($reverse), fn($row) => $row['survival'] <= 0.5);
    $lifeMedian = null;
    $previous = 1.0;
    foreach ($life as $row) {
        if ($row['survival'] <= 0.5) {
            $lifeMedian = $row['start'] + $params['lifeWidth'] * ($previous - 0.5) / ($previous - $row['survival']);
            break;
        }
        $previous = $row['survival'];
    }
    $percentiles = [];
    foreach ([[25, 0.75], [50, 0.5], [75, 0.25]] as [$percentile, $q]) {
        $percentiles[] = ['percentile' => $percentile,
            'time' => firstDay($km, fn($row) => $row['survival'] <= $q),
            'lower' => firstDay($km, fn($row) => ($row['survival'] == 0 ? 0 : $row['lower']) <= $q),
            'upper' => firstDay($km, fn($row) => ($row['survival'] == 0 ? 0 : $row['upper']) <= $q)];
    }
    $reports = [];
    foreach ($params['reportTimes'] as $time) {
        $atRisk = $cumulativeEvents = 0;
        foreach ($subjects as $subject) {
            if ($subject['time'] >= $time) {
                $atRisk++;
            }
            if ($subject['time'] <= $time && $subject['event'] === 1) {
                $cumulativeEvents++;
            }
        }
        $reports[] = ['time' => $time, 'atRisk' => $atRisk, 'events' => $cumulativeEvents, 'row' => rowAt($km, $time)];
    }
    return ['name' => $name, 'subjects' => $subjects, 'km' => $km, 'life' => $life, 'events' => $events,
        'personDays' => $personDays, 'maxTime' => $maxTime, 'rate' => $rate,
        'rateLower' => exp(log($rate) - $eta), 'rateUpper' => exp(log($rate) + $eta),
        'followupMedian' => $followupMedian, 'lifeMedian' => $lifeMedian, 'percentiles' => $percentiles,
        'reports' => $reports, 'rmst' => restrictedMean($km, $params['tau']), 'age' => ageSummary($subjects)];
}

function kmReport($collections, $params)
{
    $blocks = [];
    $header = ['time', 'at_risk', 'events', 'censored', 'survival', 'std_err', 'lower', 'upper', 'cum_haz', 'haz_se'];
    foreach ($collections as $collection) {
        $n = count($collection['subjects']);
        $rmst = $collection['rmst'];
        $lines = [
            "group {$collection['name']} subjects $n events {$collection['events']} censored " . ($n - $collection['events']) . " max_time {$collection['maxTime']}",
            'person_days ' . $collection['personDays'] . ' rate ' . fixed($collection['rate']) . ' lower ' . fixed($collection['rateLower']) . ' upper ' . fixed($collection['rateUpper']),
            'followup_median ' . day($collection['followupMedian']),
            'life_table_median ' . fixed($collection['lifeMedian'])
        ];
        foreach ($collection['percentiles'] as $percentile) {
            $lines[] = "percentile {$percentile['percentile']} time " . day($percentile['time']) . ' lower ' . day($percentile['lower']) . ' upper ' . day($percentile['upper']);
        }
        $lines[] = "rmst tau {$params['tau']} estimate " . fixed($rmst['estimate']) . ' se ' . fixed($rmst['se']) . ' lower ' . fixed($rmst['lower']) . ' upper ' . fixed($rmst['upper']);
        foreach ($collection['reports'] as $report) {
            $row = $report['row'];
            $lines[] = "at {$report['time']} at_risk {$report['atRisk']} events {$report['events']}" .
                ' survival ' . fixed($row['survival']) . ' std_err ' . fixed($row['stdErr']) . ' lower ' . fixed($row['lower']) . ' upper ' . fixed($row['upper']) .
                ' cum_hazard ' . fixed($row['cumHazard']) . ' hazard_se ' . fixed($row['hazardSe']);
        }
        $lines[] = implode('', array_map(fn($field) => str_pad((string)$field, 9, ' ', STR_PAD_LEFT), $header));
        foreach ($collection['km'] as $row) {
            $fields = [$row['time'], $row['atRisk'], $row['events'], $row['censored'], fixed($row['survival']),
                fixed($row['stdErr']), fixed($row['lower']), fixed($row['upper']), fixed($row['cumHazard']), fixed($row['hazardSe'])];
            $lines[] = implode('', array_map(fn($field) => str_pad((string)$field, 9, ' ', STR_PAD_LEFT), $fields));
        }
        $blocks[] = implode("\n", $lines);
    }
    return implode("\n\n", $blocks);
}

function lifeReport($collections)
{
    $lines = ['group,interval,at_risk,events,withdrawn,exposed,q,survival,std_err,hazard'];
    foreach ($collections as $collection) {
        foreach ($collection['life'] as $row) {
            $lines[] = implode(',', [$collection['name'], $row['start'] . '-' . $row['end'], $row['atRisk'],
                $row['events'], $row['withdrawn'], fixed($row['exposed'], 1), fixed($row['q']),
                fixed($row['survival']), fixed($row['stdErr']), fixed($row['hazard'])]);
        }
    }
    return implode("\n", $lines);
}

function statistic($chisq, $degrees)
{
    return ['chisq' => $chisq, 'degrees' => $degrees, 'p' => chiSquareP($chisq, $degrees)];
}

function testFields($test)
{
    return 'chisq ' . fixed($test['chisq']) . ' df ' . $test['degrees'] . ' p ' . fixed($test['p']);
}

function baselineReport($subjects, $groups, $collections)
{
    $lines = ['baseline'];
    foreach ($collections as $collection) {
        $age = $collection['age'];
        $lines[] = '  group ' . $collection['name'] . ' subjects ' . count($collection['subjects']) .
            ' age_mean ' . fixed($age['mean']) . ' age_sd ' . fixed($age['sd']) . ' age_median ' . fixed($age['median'], 1) .
            ' male ' . $age['male'] . ' stage ' . implode(' ', $age['stages']);
    }
    $byAge = $subjects;
    usort($byAge, fn($a, $b) => ($a['age'] <=> $b['age']) ?: ($a['id'] <=> $b['id']));
    $ranks = [];
    $ties = $p = 0;
    while ($p < count($byAge)) {
        $q = $p + 1;
        while ($q < count($byAge) && $byAge[$q]['age'] === $byAge[$p]['age']) {
            $q++;
        }
        $rank = ($p + 1 + $q) / 2;
        for ($i = $p; $i < $q; $i++) {
            $ranks[$byAge[$i]['id']] = $rank;
        }
        $count = $q - $p;
        $ties += $count * $count * $count - $count;
        $p = $q;
    }
    $indices = array_flip($groups);
    $rankSums = array_fill(0, count($groups), 0.0);
    foreach ($subjects as $subject) {
        $rankSums[$indices[$subject['group']]] += $ranks[$subject['id']];
    }
    $rankTerm = 0.0;
    foreach ($groups as $g => $group) {
        $rankTerm += $rankSums[$g] * $rankSums[$g] / count($collections[$g]['subjects']);
    }
    $n = count($subjects);
    $w0 = 12 * $rankTerm / ($n * ($n + 1)) - 3 * ($n + 1);
    $w = $w0 / (1 - $ties / ($n * $n * $n - $n));
    $lines[] = '  age kruskal_wallis ' . testFields(statistic($w, count($groups) - 1));
    foreach (['sex', 'stage'] as $variable) {
        $levels = levelsOf($subjects, $variable);
        $counts = [];
        foreach ($levels as $level) {
            $counts[] = count(array_filter($subjects, fn($subject) => $subject[$variable] === $level));
        }
        $chisq = 0.0;
        foreach ($groups as $g => $group) {
            $groupSubjects = $collections[$g]['subjects'];
            foreach ($levels as $j => $level) {
                $observed = count(array_filter($groupSubjects, fn($subject) => $subject[$variable] === $level));
                $expected = (count($groupSubjects) * $counts[$j]) / $n;
                $chisq += ($observed - $expected) * ($observed - $expected) / $expected;
            }
        }
        $lines[] = '  ' . $variable . ' ' . testFields(statistic($chisq, (count($groups) - 1) * (count($levels) - 1)));
    }
    return implode("\n", $lines);
}

function groupLines($test, $groups)
{
    $lines = [];
    foreach ($groups as $h => $name) {
        $lines[] = "  group $name events {$test['events'][$h]} observed " . fixed($test['observed'][$h]) .
            ' expected ' . fixed($test['expected'][$h]) . ' o_minus_e ' . fixed($test['observed'][$h] - $test['expected'][$h]) .
            ' variance ' . fixed($test['covariance'][$h][$h]);
    }
    return $lines;
}

function overallReport($subjects, $groups)
{
    $lines = [];
    $logrank = null;
    foreach (WEIGHTS as $weight) {
        $test = weightedTest($subjects, $groups, $weight, count($subjects));
        if ($weight === 'logrank') {
            $logrank = $test;
        }
        $lines[] = 'test ' . $weight . ' ' . testFields($test);
        array_push($lines, ...groupLines($test, $groups));
    }
    $difference = $variance = 0.0;
    foreach ($groups as $g => $group) {
        $difference += ($g + 1) * ($logrank['observed'][$g] - $logrank['expected'][$g]);
        $inner = 0.0;
        foreach ($groups as $h => $name) {
            $inner += (($g + 1) * ($h + 1)) * $logrank['covariance'][$g][$h];
        }
        $variance += $inner;
    }
    $lines[] = 'test logrank_trend ' . testFields(statistic($difference * $difference / $variance, 1));
    return implode("\n", $lines);
}

function stratifiedReport($subjects, $params)
{
    $levels = levelsOf($subjects, $params['strata']);
    $strata = [];
    foreach ($levels as $level) {
        $strata[] = array_values(array_filter($subjects, fn($subject) => $subject[$params['strata']] === $level));
    }
    $lines = [];
    foreach (WEIGHTS as $weight) {
        $tests = [];
        foreach ($strata as $stratum) {
            $tests[] = weightedTest($stratum, $params['groups'], $weight, count($subjects));
        }
        $combined = combineStrata($tests);
        $lines[] = "stratified $weight by {$params['strata']} " . testFields($combined);
        foreach ($strata as $i => $stratum) {
            $lines[] = '  stratum ' . $levels[$i] . ' subjects ' . count($stratum) . ' events ' . eventCount($stratum) .
                ' chisq ' . fixed($tests[$i]['chisq']) . ' p ' . fixed($tests[$i]['p']);
        }
        array_push($lines, ...groupLines($combined, $params['groups']));
    }
    return implode("\n", $lines);
}

function twoGroup($subjects, $a, $b, $totalSubjects)
{
    $test = weightedTest($subjects, [$a, $b], 'logrank', $totalSubjects);
    $hr = ($test['observed'][1] / $test['expected'][1]) / ($test['observed'][0] / $test['expected'][0]);
    $phi = 1 / $test['expected'][0] + 1 / $test['expected'][1];
    $logHr = log($hr);
    $test['hr'] = $hr;
    $test['phi'] = $phi;
    $test['logHr'] = $logHr;
    $test['lower'] = exp($logHr - Z * sqrt($phi));
    $test['upper'] = exp($logHr + Z * sqrt($phi));
    return $test;
}

function hazardFields($test)
{
    return 'hr ' . fixed($test['hr']) . ' lower ' . fixed($test['lower']) . ' upper ' . fixed($test['upper']);
}

function pairwiseReport($subjects, $groups)
{
    $pairs = [];
    for ($a = 0; $a < count($groups); $a++) {
        for ($b = $a + 1; $b < count($groups); $b++) {
            $selected = array_values(array_filter($subjects, fn($subject) => $subject['group'] === $groups[$a] || $subject['group'] === $groups[$b]));
            $pairs[] = array_merge(['a' => $a, 'b' => $b, 'order' => count($pairs)], twoGroup($selected, $groups[$a], $groups[$b], count($subjects)));
        }
    }
    $order = array_keys($pairs);
    usort($order, fn($a, $b) => ($pairs[$a]['p'] <=> $pairs[$b]['p']) ?: ($a <=> $b));
    $preceding = 0.0;
    foreach ($order as $i => $index) {
        $candidate = (count($order) - $i) * $pairs[$index]['p'];
        $pairs[$index]['adjusted'] = max($preceding, min(1, $candidate));
        $preceding = $pairs[$index]['adjusted'];
    }
    $lines = ['pairwise logrank adjust holm'];
    foreach ($pairs as $pair) {
        $lines[] = '  ' . $groups[$pair['a']] . ' ' . $groups[$pair['b']] . ' chisq ' . fixed($pair['chisq']) . ' p ' . fixed($pair['p']) .
            ' p_holm ' . fixed($pair['adjusted']) . ' ' . hazardFields($pair);
    }
    return implode("\n", $lines);
}

function subgroupReport($subjects, $params)
{
    $control = $params['groups'][0];
    $lines = ["subgroups reference $control"];
    foreach ($params['subgroups'] as $variable) {
        $levels = levelsOf($subjects, $variable);
        foreach (array_slice($params['groups'], 1) as $group) {
            $tests = [];
            foreach ($levels as $level) {
                $selected = array_values(array_filter($subjects, fn($subject) => $subject[$variable] === $level &&
                    ($subject['group'] === $control || $subject['group'] === $group)));
                $test = twoGroup($selected, $control, $group, count($subjects));
                $tests[] = $test;
                $lines[] = "  $variable $level $group subjects " . count($selected) . ' events ' . eventCount($selected) .
                    ' ' . hazardFields($test) . ' p ' . fixed($test['p']);
            }
            $numerator = $denominator = 0.0;
            foreach ($tests as $test) {
                $psi = 1 / $test['phi'];
                $numerator += $psi * $test['logHr'];
                $denominator += $psi;
            }
            $mean = $numerator / $denominator;
            $heterogeneity = 0.0;
            foreach ($tests as $test) {
                $heterogeneity += (1 / $test['phi']) * ($test['logHr'] - $mean) * ($test['logHr'] - $mean);
            }
            $lines[] = "  $variable $group heterogeneity " . testFields(statistic($heterogeneity, count($levels) - 1));
        }
    }
    return implode("\n", $lines);
}

function differenceFields($difference, $se)
{
    $zeta = $difference / $se;
    return 'difference ' . fixed($difference) . ' se ' . fixed($se) . ' lower ' . fixed($difference - Z * $se) .
        ' upper ' . fixed($difference + Z * $se) . ' z ' . fixed($zeta) . ' p ' . fixed(chiSquareP($zeta * $zeta, 1));
}

function comparisonsReport($subjects, $params, $collections)
{
    $groups = $params['groups'];
    $parts = [baselineReport($subjects, $groups, $collections), overallReport($subjects, $groups), stratifiedReport($subjects, $params)];
    $landmarkSubjects = array_values(array_filter($subjects, fn($subject) => $subject['time'] > $params['landmark']));
    $landmark = weightedTest($landmarkSubjects, $groups, 'logrank', count($subjects));
    $parts[] = implode("\n", array_merge(['landmark ' . $params['landmark'] . ' subjects ' . count($landmarkSubjects) . ' ' . testFields($landmark)], groupLines($landmark, $groups)));
    $parts[] = pairwiseReport($subjects, $groups);
    $parts[] = subgroupReport($subjects, $params);
    $control = $collections[0];
    $rmstLines = ['rmst_difference tau ' . $params['tau'] . ' reference ' . $groups[0]];
    $rateLines = ['rate_ratio reference ' . $groups[0]];
    for ($g = 1; $g < count($groups); $g++) {
        $collection = $collections[$g];
        $difference = $collection['rmst']['estimate'] - $control['rmst']['estimate'];
        $se = sqrt($collection['rmst']['se'] * $collection['rmst']['se'] + $control['rmst']['se'] * $control['rmst']['se']);
        $rmstLines[] = '  ' . $groups[$g] . ' ' . differenceFields($difference, $se);
        $ratio = $collection['rate'] / $control['rate'];
        $rateSe = sqrt(1 / $collection['events'] + 1 / $control['events']);
        $logarithm = log($ratio);
        $zeta = $logarithm / $rateSe;
        $rateLines[] = '  ' . $groups[$g] . ' ratio ' . fixed($ratio) . ' lower ' . fixed(exp($logarithm - Z * $rateSe)) .
            ' upper ' . fixed(exp($logarithm + Z * $rateSe)) . ' z ' . fixed($zeta) . ' p ' . fixed(chiSquareP($zeta * $zeta, 1));
    }
    $parts[] = implode("\n", $rmstLines);
    $parts[] = implode("\n", $rateLines);
    $survivalLines = ['survival_difference reference ' . $groups[0]];
    foreach ($params['reportTimes'] as $i => $time) {
        $reference = $control['reports'][$i]['row'];
        for ($g = 1; $g < count($groups); $g++) {
            $row = $collections[$g]['reports'][$i]['row'];
            $difference = $row['survival'] - $reference['survival'];
            $se = sqrt($row['stdErr'] * $row['stdErr'] + $reference['stdErr'] * $reference['stdErr']);
            $survivalLines[] = "  at $time {$groups[$g]} " . differenceFields($difference, $se);
        }
    }
    $parts[] = implode("\n", $survivalLines);
    return implode("\n\n", $parts);
}

function covariateValue($subject, $name)
{
    if ($name === 'age') {
        return $subject['age'];
    }
    if ($name === 'male') {
        return $subject['sex'] === 'M' ? 1 : 0;
    }
    if ($name === 'stage') {
        return $subject['stage'];
    }
    return $subject['group'] === $name ? 1 : 0;
}

function coefficientFields($coefficient, $se)
{
    $zeta = $coefficient / $se;
    return 'coef ' . fixed($coefficient) . ' se ' . fixed($se) . ' z ' . fixed($zeta) . ' p ' . fixed(chiSquareP($zeta * $zeta, 1)) .
        ' hr ' . fixed(exp($coefficient)) . ' lower ' . fixed(exp($coefficient - Z * $se)) .
        ' upper ' . fixed(exp($coefficient + Z * $se));
}

function concordanceLine($subjects, $vectors, $predictors)
{
    $comparable = $concordant = $tied = 0;
    foreach ($subjects as $i => $subject) {
        if ($subject['event'] !== 1) {
            continue;
        }
        foreach ($subjects as $j => $other) {
            if ($i === $j || !($subject['time'] < $other['time'] ||
                ($subject['time'] === $other['time'] && $other['event'] === 0))) {
                continue;
            }
            $comparable++;
            if ($vectors[$i] === $vectors[$j]) {
                $tied++;
            } elseif ($predictors[$i] > $predictors[$j]) {
                $concordant++;
            }
        }
    }
    $value = (2 * $concordant + $tied) / (2 * $comparable);
    return 'concordance ' . fixed($value) . " comparable $comparable concordant $concordant tied $tied";
}

function proportionalHazardsLines($subjects, $vectors, $covariates, $evaluation)
{
    $order = [];
    foreach ($subjects as $index => $subject) {
        if ($subject['event'] === 1) {
            $order[] = $index;
        }
    }
    usort($order, fn($a, $b) => ($subjects[$a]['time'] <=> $subjects[$b]['time']) ?:
        ($subjects[$a]['id'] <=> $subjects[$b]['id']));
    $totalTime = 0;
    foreach ($order as $index) {
        $totalTime += $subjects[$index]['time'];
    }
    $meanTime = $totalTime / count($order);
    $lines = [];
    foreach ($covariates as $c => $name) {
        $residuals = [];
        $residualSum = 0.0;
        foreach ($order as $index) {
            $row = $evaluation['eventRows'][$subjects[$index]['time']];
            $residual = $vectors[$index][$c] - $row['s1'][$c] / $row['s0'];
            $residuals[] = $residual;
            $residualSum += $residual;
        }
        $meanResidual = $residualSum / count($order);
        $sxy = $sxx = $syy = 0.0;
        foreach ($order as $i => $index) {
            $centeredResidual = $residuals[$i] - $meanResidual;
            $centeredTime = $subjects[$index]['time'] - $meanTime;
            $sxy += $centeredResidual * $centeredTime;
            $sxx += $centeredResidual * $centeredResidual;
            $syy += $centeredTime * $centeredTime;
        }
        $rho = $sxy / sqrt($sxx * $syy);
        $zeta = 0.5 * log((1 + $rho) / (1 - $rho)) * sqrt(count($order) - 3);
        $lines[] = "ph_check $name rho " . fixed($rho) . ' z ' . fixed($zeta) . ' p ' . fixed(chiSquareP($zeta * $zeta, 1));
    }
    return $lines;
}

function baselineHazard($evaluation)
{
    $rows = $evaluation['eventRows'];
    ksort($rows, SORT_NUMERIC);
    $baseline = [];
    $cumulative = 0.0;
    foreach ($rows as $row) {
        $cumulative += $row['events'] / $row['s0'];
        $baseline[] = ['time' => $row['time'], 'cumulative' => $cumulative];
    }
    return $baseline;
}

function hazardAt($baseline, $time)
{
    $cumulative = 0.0;
    foreach ($baseline as $row) {
        if ($row['time'] > $time) {
            break;
        }
        $cumulative = $row['cumulative'];
    }
    return $cumulative;
}

function residualLines($subjects, $evaluation, $baseline, $count)
{
    $residuals = [];
    foreach ($subjects as $index => $subject) {
        $martingale = $subject['event'] - hazardAt($baseline, $subject['time']) * exp($evaluation['predictors'][$index]);
        $deviance = $subject['event'] === 1 ?
            sqrt(-2 * ($martingale + log(1 - $martingale))) : sqrt(-2 * $martingale);
        if (!($martingale > 0)) {
            $deviance = -$deviance;
        }
        $residuals[] = ['subject' => $subject, 'martingale' => $martingale, 'deviance' => $deviance];
    }
    usort($residuals, fn($a, $b) => (abs($b['deviance']) <=> abs($a['deviance'])) ?:
        ($a['subject']['id'] <=> $b['subject']['id']));
    $lines = ["residuals top $count"];
    foreach (array_slice($residuals, 0, $count) as $residual) {
        $subject = $residual['subject'];
        $lines[] = "  id {$subject['id']} group {$subject['group']} time {$subject['time']} event {$subject['event']}" .
            ' martingale ' . fixed($residual['martingale']) . ' deviance ' . fixed($residual['deviance']);
    }
    return $lines;
}

function adjustedLines($subjects, $params, $vectors, $beta, $baseline)
{
    $means = array_fill(0, count($params['covariates']), null);
    $meanFields = [];
    foreach ($params['covariates'] as $c => $name) {
        if (!in_array($name, CONTINUOUS, true)) {
            continue;
        }
        $total = 0;
        foreach ($vectors as $vector) {
            $total += $vector[$c];
        }
        $means[$c] = $total / count($subjects);
        $meanFields[] = $name;
        $meanFields[] = fixed($means[$c]);
    }
    $risks = [];
    foreach ($params['groups'] as $group) {
        $predictor = 0.0;
        foreach ($params['covariates'] as $c => $name) {
            $value = $means[$c] === null ? ($name === $group ? 1 : 0) : $means[$c];
            $predictor += $beta[$c] * $value;
        }
        $risks[] = exp($predictor);
    }
    $lines = ['adjusted_survival mean ' . (count($meanFields) === 0 ? 'none' : implode(' ', $meanFields))];
    foreach ($params['reportTimes'] as $time) {
        $fields = [];
        $cumulative = hazardAt($baseline, $time);
        foreach ($params['groups'] as $g => $group) {
            $fields[] = $group;
            $fields[] = fixed(exp(-$cumulative * $risks[$g]));
        }
        $lines[] = "  at $time " . implode(' ', $fields);
    }
    $medianFields = [];
    foreach ($params['groups'] as $g => $group) {
        $median = firstDay($baseline, fn($row) => exp(-$row['cumulative'] * $risks[$g]) <= 0.5);
        $medianFields[] = $group;
        $medianFields[] = day($median);
    }
    $lines[] = '  median ' . implode(' ', $medianFields);
    return $lines;
}

function coxReport($subjects, $params)
{
    $covariates = $params['covariates'];
    $vectors = [];
    foreach ($subjects as $subject) {
        $vector = [];
        foreach ($covariates as $name) {
            $vector[] = covariateValue($subject, $name);
        }
        $vectors[] = $vector;
    }
    $model = fitCox($subjects, $vectors);
    $beta = $model['beta'];
    $final = $model['finalEvaluation'];
    $initial = $model['nullEvaluation'];
    $covariance = inverse($final['information']);
    $lines = ['cox covariates ' . implode(' ', $covariates) . ' subjects ' . count($subjects) .
        ' events ' . eventCount($subjects) . ' event_times ' . count($final['eventRows'])];
    foreach ($model['iterations'] as $iteration) {
        $lines[] = 'iter ' . $iteration['iteration'] . ' loglik ' . fixed($iteration['loglik']) . ' beta ' .
            implode(' ', array_map(fn($value) => fixed($value), $iteration['beta']));
    }
    $lines[] = 'final loglik ' . fixed($final['loglik']) . ' null_loglik ' . fixed($initial['loglik']);
    foreach ($covariates as $c => $name) {
        $lines[] = "term $name " . coefficientFields($beta[$c], sqrt($covariance[$c][$c]));
    }
    for ($a = 0; $a < count($covariates); $a++) {
        if (in_array($covariates[$a], CONTINUOUS, true)) {
            continue;
        }
        for ($b = $a + 1; $b < count($covariates); $b++) {
            if (in_array($covariates[$b], CONTINUOUS, true)) {
                continue;
            }
            $coefficient = $beta[$b] - $beta[$a];
            $se = sqrt($covariance[$b][$b] + $covariance[$a][$a] - 2 * $covariance[$a][$b]);
            $lines[] = 'contrast ' . $covariates[$b] . ' vs ' . $covariates[$a] . ' ' . coefficientFields($coefficient, $se);
        }
    }
    $likelihoodRatio = 2 * ($final['loglik'] - $initial['loglik']);
    $wald = 0.0;
    foreach ($covariates as $c => $name) {
        $inner = 0.0;
        foreach ($covariates as $d => $other) {
            $inner += $final['information'][$c][$d] * $beta[$d];
        }
        $wald += $beta[$c] * $inner;
    }
    $scoreSolution = solve($initial['information'], $initial['score']);
    $score = 0.0;
    foreach ($covariates as $c => $name) {
        $score += $initial['score'][$c] * $scoreSolution[$c];
    }
    foreach ([['likelihood_ratio', $likelihoodRatio], ['wald', $wald], ['score', $score]] as [$name, $value]) {
        $lines[] = $name . ' ' . testFields(statistic($value, count($covariates)));
    }
    foreach ($covariates as $c => $name) {
        if (count($covariates) === 1) {
            $loglik = $initial['loglik'];
        } else {
            $reduced = [];
            foreach ($vectors as $vector) {
                $reduced[] = array_merge(array_slice($vector, 0, $c), array_slice($vector, $c + 1));
            }
            $loglik = fitCox($subjects, $reduced)['finalEvaluation']['loglik'];
        }
        $test = statistic(2 * ($final['loglik'] - $loglik), 1);
        $lines[] = "drop $name loglik " . fixed($loglik) . ' ' . testFields($test);
    }
    $lines[] = concordanceLine($subjects, $vectors, $final['predictors']);
    array_push($lines, ...proportionalHazardsLines($subjects, $vectors, $covariates, $final));
    $baseline = baselineHazard($final);
    array_push($lines, ...residualLines($subjects, $final, $baseline, $params['residuals']));
    array_push($lines, ...adjustedLines($subjects, $params, $vectors, $beta, $baseline));
    return implode("\n", $lines);
}

function kmPlotReport($collections, $params)
{
    $width = $params['plot']['width'];
    $height = $params['plot']['height'];
    $time = $params['plot']['time'];
    $divisions = $params['plot']['divisions'];
    $groups = array_slice($collections, 0, count($params['groups']));
    $legend = [];
    foreach ($groups as $g => $group) {
        $legend[] = chr(65 + $g);
        $legend[] = $group['name'];
    }
    $lines = array_merge(["km_plot width $width height $height time $time", 'legend ' . implode(' ', $legend)],
        plotLines($groups, $width, $height, $time));
    $riskTimes = [];
    for ($i = 0; $i <= $divisions; $i++) {
        $riskTimes[] = $i * intdiv($time, $divisions);
    }
    $lines[] = 'at_risk ' . implode(' ', $riskTimes);
    foreach ($groups as $group) {
        $counts = [];
        foreach ($riskTimes as $sampleTime) {
            $counts[] = count(array_filter($group['subjects'], fn($subject) => $subject['time'] >= $sampleTime));
        }
        $lines[] = $group['name'] . ' ' . implode(' ', $counts);
    }
    return implode("\n", $lines);
}

function main()
{
    [$subjects, $params] = readDataset();
    $collections = [];
    foreach ($params['groups'] as $name) {
        $group = array_values(array_filter($subjects, fn($subject) => $subject['group'] === $name));
        $collections[] = makeCollection($name, $group, $params);
    }
    $collections[] = makeCollection('all', $subjects, $params);
    $outputs = [
        'km_tables.txt' => kmReport($collections, $params),
        'life_table.csv' => lifeReport($collections),
        'tests.txt' => comparisonsReport($subjects, $params, $collections),
        'cox.txt' => coxReport($subjects, $params),
        'km_plot.txt' => kmPlotReport($collections, $params)
    ];
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    foreach ($outputs as $name => $content) {
        file_put_contents('output/' . $name, $content . "\n");
    }
}

main();
