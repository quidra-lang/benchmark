<?php

require_once __DIR__ . '/dataset.php';
require_once __DIR__ . '/gaussian.php';
require_once __DIR__ . '/em.php';
require_once __DIR__ . '/kmeans.php';
require_once __DIR__ . '/report.php';

function rounded($value) {
    return (float)real($value);
}

function reals($values) {
    return implode(' ', array_map('real', $values));
}

function summarize($result, $K, $type, $typeIndex, $n, $tau) {
    $parameters = ['FULL' => 6 * $K - 1, 'TIED' => 3 * $K + 2, 'DIAG' => 5 * $K - 1, 'SPHERICAL' => 4 * $K - 1];
    $p = $parameters[$type];
    $assignment = $maximum = [];
    $sizes = array_fill(0, $K, 0);
    $entropy = 0.0;
    foreach ($result['responsibilities'] as $row) {
        $best = 0;
        $terms = 0.0;
        for ($k = 0; $k < $K; $k++) {
            if ($row[$k] > $row[$best]) $best = $k;
            if ($row[$k] != 0.0) $terms += $row[$k] * log($row[$k]);
        }
        $assignment[] = $best;
        $maximum[] = $row[$best];
        $sizes[$best]++;
        $entropy += -$terms;
    }
    $bic = -2 * $result['loglik'] + $p * log($n);
    $aic = -2 * $result['loglik'] + 2 * $p;
    $icl = $bic + 2 * $entropy;
    $N = count($result['trace']) - 1;
    $settledAt = $N;
    for ($t = $N - 1; $t >= 0; $t--) {
        if (abs($result['trace'][$t] - $result['loglik']) > $tau) break;
        $settledAt = $t;
    }
    $largestIncrease = ['iteration' => 1, 'value' => $result['trace'][1] - $result['trace'][0]];
    $violations = [];
    for ($t = 1; $t <= $N; $t++) {
        $increase = $result['trace'][$t] - $result['trace'][$t - 1];
        if ($increase > $largestIncrease['value']) $largestIncrease = ['iteration' => $t, 'value' => $increase];
        if ($result['trace'][$t] < $result['trace'][$t - 1] - 0.000001 * abs($result['trace'][$t - 1])) $violations[] = $t;
    }
    return array_merge($result, ['K' => $K, 'type' => $type, 'typeIndex' => $typeIndex, 'p' => $p, 'assignment' => $assignment,
        'maximum' => $maximum, 'sizes' => $sizes, 'entropy' => $entropy, 'meanEntropy' => $entropy / $n,
        'bic' => $bic, 'aic' => $aic, 'icl' => $icl, 'settledAt' => $settledAt, 'largestIncrease' => $largestIncrease, 'violations' => $violations]);
}

function compareModels($first, $second, $criterion) {
    return (rounded($first[$criterion]) <=> rounded($second[$criterion])) ?: (($first['p'] <=> $second['p']) ?: (($first['K'] <=> $second['K']) ?: ($first['typeIndex'] <=> $second['typeIndex'])));
}

function contingency($first, $second, $firstK, $secondK) {
    $table = array_fill(0, $firstK, array_fill(0, $secondK, 0));
    foreach ($first as $i => $cluster) $table[$cluster][$second[$i]]++;
    return $table;
}

function choose2($count) {
    return intdiv($count * ($count - 1), 2);
}

function adjustedRand($table, $n) {
    $columns = array_fill(0, count($table[0]), 0);
    $S = $A = 0;
    foreach ($table as $row) {
        $total = 0;
        foreach ($row as $b => $value) {
            $S += choose2($value);
            $total += $value;
            $columns[$b] += $value;
        }
        $A += choose2($total);
    }
    $B = 0;
    foreach ($columns as $count) $B += choose2($count);
    $Z = choose2($n);
    $numerator = 2 * ($Z * $S - $A * $B);
    $denominator = $Z * ($A + $B) - 2 * $A * $B;
    if ($denominator === 0) return ['numerator' => 1, 'denominator' => 1];
    if ($denominator < 0) {
        $numerator = -$numerator;
        $denominator = -$denominator;
    }
    $a = abs($numerator);
    $b = $denominator;
    while ($b !== 0) [$a, $b] = [$b, $a % $b];
    return ['numerator' => intdiv($numerator, $a), 'denominator' => intdiv($denominator, $a)];
}

function fractionText($fraction) {
    return $fraction['numerator'] . '/' . $fraction['denominator'] . ' ' . real($fraction['numerator'] / $fraction['denominator']);
}

function evaluatePartition($points, $assignment, $K) {
    $members = array_fill(0, $K, []);
    foreach ($points as $i => $point) $members[$assignment[$i]][] = $i;
    $active = [];
    foreach ($members as $k => $indices) if ($indices) $active[] = $k;
    $clusterSilhouettes = array_fill(0, $K, null);
    if (count($active) < 2) return ['silhouette' => null, 'ch' => null, 'db' => null, 'clusterSilhouettes' => $clusterSilhouettes];
    $centers = array_fill(0, $K, null);
    foreach ($active as $k) {
        $x = $y = 0.0;
        foreach ($members[$k] as $i) {
            $x += $points[$i]['x'];
            $y += $points[$i]['y'];
        }
        $centers[$k] = ['x' => $x / count($members[$k]), 'y' => $y / count($members[$k])];
    }
    $silhouetteSum = 0.0;
    $clusterSums = array_fill(0, $K, 0.0);
    foreach ($points as $i => $point) {
        $own = $assignment[$i];
        $silhouette = 0.0;
        if (count($members[$own]) > 1) {
            $inside = 0.0;
            foreach ($members[$own] as $j) if ($j !== $i) $inside += pointDistance($point, $points[$j]);
            $a = $inside / (count($members[$own]) - 1);
            $b = INF;
            foreach ($active as $other) {
                if ($other === $own) continue;
                $outside = 0.0;
                foreach ($members[$other] as $j) $outside += pointDistance($point, $points[$j]);
                $b = min($b, $outside / count($members[$other]));
            }
            $silhouette = ($b - $a) / max($a, $b);
        }
        $silhouetteSum += $silhouette;
        $clusterSums[$own] += $silhouette;
    }
    foreach ($active as $k) $clusterSilhouettes[$k] = $clusterSums[$k] / count($members[$k]);
    $x = $y = 0.0;
    foreach ($points as $point) {
        $x += $point['x'];
        $y += $point['y'];
    }
    $grand = ['x' => $x / count($points), 'y' => $y / count($points)];
    $between = $within = 0.0;
    foreach ($active as $k) $between += count($members[$k]) * squaredDistance($centers[$k], $grand);
    foreach ($points as $i => $point) $within += squaredDistance($point, $centers[$assignment[$i]]);
    $ch = ($between / (count($active) - 1)) / ($within / (count($points) - count($active)));
    $spreads = array_fill(0, $K, 0.0);
    foreach ($active as $k) {
        $total = 0.0;
        foreach ($members[$k] as $i) $total += pointDistance($points[$i], $centers[$k]);
        $spreads[$k] = $total / count($members[$k]);
    }
    $dbSum = 0.0;
    foreach ($active as $k) {
        $largest = -INF;
        foreach ($active as $other) if ($other !== $k) $largest = max($largest, ($spreads[$k] + $spreads[$other]) / pointDistance($centers[$k], $centers[$other]));
        $dbSum += $largest;
    }
    return ['silhouette' => $silhouetteSum / count($points), 'ch' => $ch, 'db' => $dbSum / count($active), 'clusterSilhouettes' => $clusterSilhouettes];
}

function parents($table) {
    $values = $shared = [];
    for ($b = 0; $b < count($table[0]); $b++) {
        $parent = 0;
        for ($a = 1; $a < count($table); $a++) if ($table[$a][$b] > $table[$parent][$b]) $parent = $a;
        $values[] = $table[$parent][$b] === 0 ? '-' : $parent + 1;
        $shared[] = $table[$parent][$b];
    }
    return compact('values', 'shared');
}

function matching($table) {
    $K = count($table);
    $used = array_fill(0, $K, false);
    $permutation = [];
    $agreement = -1;
    $best = [];
    $visit = function($column, $score) use (&$visit, &$used, &$permutation, &$agreement, &$best, $K, $table) {
        if ($column === $K) {
            if ($score > $agreement) {
                $agreement = $score;
                $best = $permutation;
            }
            return;
        }
        for ($row = 0; $row < $K; $row++) {
            if ($used[$row]) continue;
            $used[$row] = true;
            $permutation[] = $row;
            $visit($column + 1, $score + $table[$row][$column]);
            array_pop($permutation);
            $used[$row] = false;
        }
    };
    $visit(0, 0);
    return ['permutation' => $best, 'agreement' => $agreement];
}

function modelBlock($model) {
    $lines = ['model K=' . $model['K'] . ' type=' . $model['type'], 'parameters ' . $model['p'],
        'loglik ' . real($model['loglik']), 'bic ' . real($model['bic']), 'aic ' . real($model['aic']),
        'icl ' . real($model['icl']), 'mean_entropy ' . real($model['meanEntropy']), 'settled_at ' . $model['settledAt'],
        'largest_increase iteration ' . $model['largestIncrease']['iteration'] . ' value ' . real($model['largestIncrease']['value']),
        'violations ' . count($model['violations']), 'sizes ' . implode(' ', $model['sizes'])];
    foreach ($model['components'] as $k => $component) {
        $eigen = eigen($component);
        $axes = [sqrt($eigen['lambda1']), sqrt($eigen['lambda2'])];
        $lines[] = 'component ' . ($k + 1) . ' weight ' . real($component['w']) . ' mean ' . reals([$component['mx'], $component['my']])
            . ' cov ' . reals([$component['a'], $component['b'], $component['c']]) . ' axes ' . reals($axes) . ' angle ' . real($eigen['angle']);
    }
    return $lines;
}

function comparisonPart($comparison, $previous) {
    $K = $comparison['K'];
    $model = $comparison['model'];
    $km = $comparison['km'];
    $gmm = $comparison['gmmMetrics'];
    $kmMetrics = $comparison['kmMetrics'];
    $lines = ['K=' . $K . ' type=' . $model['type'] . ' bic ' . real($model['bic']),
        '  kmeans iterations ' . $km['iterations'] . ' inertia ' . real($km['inertia']),
        '  ari ' . fractionText($comparison['ari']),
        '  silhouette gmm ' . real($gmm['silhouette']) . ' kmeans ' . real($kmMetrics['silhouette']),
        '  calinski_harabasz gmm ' . real($gmm['ch']) . ' kmeans ' . real($kmMetrics['ch']),
        '  davies_bouldin gmm ' . real($gmm['db']) . ' kmeans ' . real($kmMetrics['db'])];
    if ($previous !== null) {
        $table = contingency($previous['model']['assignment'], $model['assignment'], $previous['K'], $K);
        $lineage = parents($table);
        $lines[] = '  parents K=' . $previous['K'] . ' ' . implode(' ', $lineage['values']) . ' shared ' . implode(' ', $lineage['shared']);
    }
    return $lines;
}

function componentDetails($points, $model, $metrics, $edges, $quadratics) {
    $lines = ['selected components'];
    foreach ($model['components'] as $k => $component) {
        $eigen = eigen($component);
        $major = sqrt($eigen['lambda1']);
        $minor = sqrt($eigen['lambda2']);
        $area = M_PI * sqrt($eigen['lambda1'] * $eigen['lambda2']);
        $correlation = $component['b'] / sqrt($component['a'] * $component['c']);
        $softSize = 0.0;
        $inside1 = $inside2 = 0;
        $observed = array_fill(0, count($edges) + 1, 0);
        foreach ($points as $i => $point) {
            $softSize += $model['responsibilities'][$i][$k];
            if ($model['assignment'][$i] !== $k) continue;
            $q = $quadratics[$i][$k];
            if ($q <= 1) $inside1++;
            if ($q <= 4) $inside2++;
            $rho = sqrt($q);
            $bin = 0;
            while ($bin < count($edges) && $rho >= $edges[$bin]) $bin++;
            $observed[$bin]++;
        }
        $expected = [];
        $chi2 = 0.0;
        for ($bin = 0; $bin <= count($edges); $bin++) {
            $lower = $bin === 0 ? 0.0 : $edges[$bin - 1];
            $tail = $bin === count($edges) ? 0.0 : exp(-$edges[$bin] * $edges[$bin] / 2);
            $value = $model['sizes'][$k] * (exp(-$lower * $lower / 2) - $tail);
            $expected[] = $value;
            $difference = $observed[$bin] - $value;
            $chi2 += $difference * $difference / $value;
        }
        $lines[] = 'component ' . ($k + 1) . ' weight ' . real($component['w']) . ' size ' . $model['sizes'][$k] . ' soft_size ' . real($softSize)
            . ' mean ' . reals([$component['mx'], $component['my']]);
        $lines[] = '  cov ' . reals([$component['a'], $component['b'], $component['c']]) . ' corr ' . real($correlation);
        $lines[] = '  eigen ' . reals([$eigen['lambda1'], $eigen['lambda2']]) . ' direction ' . reals([$eigen['ux'], $eigen['uy']]) . ' angle ' . real($eigen['angle']);
        $lines[] = '  axes_1sigma ' . reals([$major, $minor]) . ' axes_2sigma ' . reals([2 * $major, 2 * $minor]);
        $lines[] = '  inside_1sigma ' . $inside1 . ' inside_2sigma ' . $inside2 . ' area_1sigma ' . real($area);
        $lines[] = '  silhouette ' . real($metrics['clusterSilhouettes'][$k]);
        $lines[] = '  gof observed ' . implode(' ', $observed) . ' expected ' . reals($expected) . ' chi2 ' . real($chi2);
    }
    return $lines;
}

function overlapPart($model) {
    $lines = ['overlap'];
    for ($a = 0; $a < $model['K']; $a++) for ($b = $a + 1; $b < $model['K']; $b++) {
        $D = bhattacharyya($model['components'][$a], $model['components'][$b]);
        $shared = 0.0;
        foreach ($model['responsibilities'] as $row) $shared += $row[$a] * $row[$b];
        $lines[] = ($a + 1) . '-' . ($b + 1) . ' bhattacharyya ' . real($D) . ' coefficient ' . real(exp(-$D)) . ' shared ' . real($shared);
    }
    if ($model['K'] === 1) $lines[] = 'none';
    return $lines;
}

function mergedState($responsibilities, $clusters) {
    $entropy = 0.0;
    $sizes = array_fill(0, count($clusters), 0);
    foreach ($responsibilities as $row) {
        $masses = [];
        foreach ($clusters as $cluster) {
            $total = 0.0;
            foreach ($cluster as $k) $total += $row[$k];
            $masses[] = $total;
        }
        $terms = 0.0;
        $best = 0;
        foreach ($masses as $c => $value) {
            if ($value != 0.0) $terms += $value * log($value);
            if ($value > $masses[$best]) $best = $c;
        }
        $entropy += -$terms;
        $sizes[$best]++;
    }
    return compact('entropy', 'sizes');
}

function mergingPart($model) {
    $clusters = [];
    for ($k = 0; $k < $model['K']; $k++) $clusters[] = [$k];
    $start = mergedState($model['responsibilities'], $clusters);
    $lines = ['merging', 'start entropy ' . real($start['entropy'])];
    for ($step = 1; count($clusters) > 1; $step++) {
        $best = null;
        for ($a = 0; $a < count($clusters); $a++) for ($b = $a + 1; $b < count($clusters); $b++) {
            $next = [];
            foreach ($clusters as $c => $cluster) {
                if ($c === $b) continue;
                if ($c === $a) {
                    $cluster = array_merge($cluster, $clusters[$b]);
                    sort($cluster, SORT_NUMERIC);
                }
                $next[] = $cluster;
            }
            $state = mergedState($model['responsibilities'], $next);
            if ($best === null || rounded($state['entropy']) < rounded($best['state']['entropy'])) $best = ['a' => $a, 'b' => $b, 'clusters' => $next, 'state' => $state];
        }
        $nameA = implode('+', array_map(fn($k) => $k + 1, $clusters[$best['a']]));
        $nameB = implode('+', array_map(fn($k) => $k + 1, $clusters[$best['b']]));
        $lines[] = 'step ' . $step . ' merge ' . $nameA . ' ' . $nameB . ' entropy ' . real($best['state']['entropy']) . ' sizes ' . implode(' ', $best['state']['sizes']);
        $clusters = $best['clusters'];
    }
    return $lines;
}

function kmeansPart($points, $model, $comparison) {
    $km = $comparison['km'];
    $table = $comparison['table'];
    $match = matching($table);
    $lines = ['kmeans K=' . $model['K'], 'iterations ' . $km['iterations'], 'inertia ' . real($km['inertia']), 'sizes ' . implode(' ', $km['sizes'])];
    foreach ($km['centers'] as $k => $center) $lines[] = 'center ' . ($k + 1) . ' ' . reals([$center['x'], $center['y']]);
    $lines[] = 'contingency';
    foreach ($table as $row) $lines[] = implode(' ', $row);
    $lines[] = 'ari ' . fractionText($comparison['ari']);
    $lines[] = 'matching ' . implode(' ', array_map(fn($k) => $k + 1, $match['permutation']));
    $lines[] = 'agreement ' . $match['agreement'] . '/' . count($points) . ' ' . real($match['agreement'] / count($points));
    $disagreements = 0;
    foreach ($points as $i => $point) {
        if ($match['permutation'][$km['assignment'][$i]] !== $model['assignment'][$i]) {
            $lines[] = 'disagree ' . $point['id'] . ' gmm ' . ($model['assignment'][$i] + 1) . ' kmeans ' . ($km['assignment'][$i] + 1) . ' max ' . real($model['maximum'][$i]);
            $disagreements++;
        }
    }
    $lines[] = 'disagreements ' . $disagreements;
    return $lines;
}

function refitPart($points, $params, $model, $km) {
    $initial = [];
    foreach ($km['centers'] as $k => $center) {
        $A = $B = $C = 0.0;
        foreach ($points as $i => $point) {
            if ($km['assignment'][$i] !== $k) continue;
            $dx = $point['x'] - $center['x'];
            $dy = $point['y'] - $center['y'];
            $A += $dx * $dx;
            $B += $dx * $dy;
            $C += $dy * $dy;
        }
        $initial[] = ['w' => $km['sizes'][$k] / count($points), 'mx' => $center['x'], 'my' => $center['y'],
            'a' => $A / $km['sizes'][$k] + $params['eps'], 'b' => $B / $km['sizes'][$k], 'c' => $C / $km['sizes'][$k] + $params['eps']];
    }
    $result = emFit($points, $initial, $model['type'], $params['iterations'], $params['eps']);
    $refit = summarize($result, $model['K'], $model['type'], $model['typeIndex'], count($points), $params['tau']);
    $ari = adjustedRand(contingency($model['assignment'], $refit['assignment'], $model['K'], $model['K']), count($points));
    return ['refit_from_kmeans K=' . $model['K'] . ' type=' . $model['type'],
        'loglik ' . real($refit['loglik']) . ' bic ' . real($refit['bic']) . ' settled_at ' . $refit['settledAt'],
        'sizes ' . implode(' ', $refit['sizes']), 'ari_vs_selected ' . fractionText($ari)];
}

function crossValidationPart($points, $params, $model, $initial) {
    $lines = ['cross_validation K=' . $model['K'] . ' type=' . $model['type'] . ' folds ' . $params['folds']];
    $total = 0.0;
    for ($fold = 0; $fold < $params['folds']; $fold++) {
        $training = $test = [];
        foreach ($points as $i => $point) {
            if ($i % $params['folds'] === $fold) $test[] = $point;
            else $training[] = $point;
        }
        $fitted = emFit($training, $initial, $model['type'], $params['iterations'], $params['eps']);
        $trainLoglik = $fitted['loglik'] / count($training);
        $testResult = expectation($test, $fitted['components']);
        $testLoglik = $testResult['loglik'] / count($test);
        $total += $testLoglik;
        $lines[] = 'fold ' . ($fold + 1) . ' train ' . count($training) . ' test ' . count($test) . ' train_loglik ' . real($trainLoglik) . ' test_loglik ' . real($testLoglik);
    }
    $lines[] = 'mean_test_loglik ' . real($total / $params['folds']);
    return $lines;
}

function exceptionalParts($points, $params, $model, $quadratics) {
    $uncertain = $outliers = [];
    foreach ($points as $i => $point) {
        if ($model['maximum'][$i] < $params['uncertain']) $uncertain[] = $i;
        if ($model['logDensities'][$i] < $params['lowDensity']) $outliers[] = $i;
    }
    usort($uncertain, fn($i, $j) => (rounded($model['maximum'][$i]) <=> rounded($model['maximum'][$j])) ?: ($i <=> $j));
    usort($outliers, fn($i, $j) => (rounded($model['logDensities'][$i]) <=> rounded($model['logDensities'][$j])) ?: ($i <=> $j));
    $uncertainLines = ['uncertain threshold ' . real($params['uncertain'])];
    foreach ($uncertain as $i) $uncertainLines[] = $points[$i]['id'] . ' component ' . ($model['assignment'][$i] + 1) . ' max ' . real($model['maximum'][$i]) . ' responsibilities ' . reals($model['responsibilities'][$i]);
    $uncertainLines[] = 'count ' . count($uncertain);
    $outlierLines = ['outliers threshold ' . real($params['lowDensity'])];
    foreach ($outliers as $i) $outlierLines[] = $points[$i]['id'] . ' component ' . ($model['assignment'][$i] + 1) . ' log_density ' . real($model['logDensities'][$i]) . ' q ' . real($quadratics[$i][$model['assignment'][$i]]);
    $outlierLines[] = 'count ' . count($outliers);
    return [$uncertainLines, $outlierLines];
}

function modelKey($model) {
    return $model['K'] . ':' . $model['type'];
}

function selectionReport($points, $params, $initial, $models, $ranks, $comparisons) {
    $selected = $ranks['bic'][0];
    $aicRanks = $iclRanks = [];
    foreach ($ranks['aic'] as $i => $model) $aicRanks[modelKey($model)] = $i + 1;
    foreach ($ranks['icl'] as $i => $model) $iclRanks[modelKey($model)] = $i + 1;
    $ranking = ['ranking by bic', 'rank K type parameters loglik bic delta_bic aic aic_rank icl icl_rank'];
    foreach ($ranks['bic'] as $i => $model) {
        $delta = rounded($model['bic']) - rounded($selected['bic']);
        $ranking[] = ($i + 1) . ' ' . $model['K'] . ' ' . $model['type'] . ' ' . $model['p'] . ' ' . real($model['loglik']) . ' ' . real($model['bic'])
            . ' ' . real($delta) . ' ' . real($model['aic']) . ' ' . $aicRanks[modelKey($model)] . ' ' . real($model['icl']) . ' ' . $iclRanks[modelKey($model)];
    }
    $ranking[] = 'selected K=' . $selected['K'] . ' type=' . $selected['type'];
    $ranking[] = 'best_aic K=' . $ranks['aic'][0]['K'] . ' type=' . $ranks['aic'][0]['type'];
    $ranking[] = 'best_icl K=' . $ranks['icl'][0]['K'] . ' type=' . $ranks['icl'][0]['type'];
    $byType = ['best K per type'];
    foreach ($params['types'] as $type) {
        $best = [];
        foreach (['bic', 'aic', 'icl'] as $criterion) foreach ($ranks[$criterion] as $model) {
            if ($model['type'] === $type) {
                $best[$criterion] = $model['K'];
                break;
            }
        }
        $byType[] = $type . ' bic ' . $best['bic'] . ' aic ' . $best['aic'] . ' icl ' . $best['icl'];
    }
    $parts = [$ranking, $byType];
    foreach ($comparisons as $i => $comparison) $parts[] = comparisonPart($comparison, $comparisons[$i - 1] ?? null);
    $violations = ['violations'];
    foreach ($models as $model) foreach ($model['violations'] as $t) {
        $violations[] = 'K=' . $model['K'] . ' type=' . $model['type'] . ' iteration ' . $t . ' previous ' . real($model['trace'][$t - 1]) . ' current ' . real($model['trace'][$t]);
    }
    if (count($violations) === 1) $violations[] = 'none';
    $parts[] = $violations;
    foreach ($comparisons as $item) if ($item['K'] === $selected['K']) {
        $comparison = $item;
        break;
    }
    $quadratics = [];
    foreach ($points as $point) {
        $row = [];
        foreach ($selected['components'] as $component) $row[] = quadratic($point, $component);
        $quadratics[] = $row;
    }
    $parts[] = componentDetails($points, $selected, $comparison['gmmMetrics'], $params['edges'], $quadratics);
    $parts[] = overlapPart($selected);
    $parts[] = mergingPart($selected);
    $parts[] = kmeansPart($points, $selected, $comparison);
    $parts[] = refitPart($points, $params, $selected, $comparison['km']);
    $parts[] = crossValidationPart($points, $params, $selected, $initial[$selected['K']]);
    foreach (exceptionalParts($points, $params, $selected, $quadratics) as $part) $parts[] = $part;
    $lines = [];
    foreach ($parts as $i => $part) {
        if ($i > 0) $lines[] = '';
        foreach ($part as $line) $lines[] = $line;
    }
    return $lines;
}

function mapReport($points, $params, $model) {
    $xmin = $params['xmin'];
    $xmax = $params['xmax'];
    $ymin = $params['ymin'];
    $ymax = $params['ymax'];
    $width = $params['width'];
    $height = $params['height'];
    $stepX = ($xmax - $xmin) / $width;
    $stepY = ($ymax - $ymin) / $height;
    $levels = ' .:-=+*#%@';
    $cells = [];
    $fmax = $mass = 0.0;
    for ($r = 0; $r < $height; $r++) for ($c = 0; $c < $width; $c++) {
        $point = ['x' => $xmin + ($c + 0.5) * $stepX, 'y' => $ymax - ($r + 0.5) * $stepY];
        $logs = [];
        foreach ($model['components'] as $component) $logs[] = logWeighted($point, $component);
        $density = 0.0;
        $best = 0;
        foreach ($logs as $k => $value) {
            $density += exp($value);
            if ($value > $logs[$best]) $best = $k;
        }
        $fmax = max($fmax, $density);
        $mass += $density;
        $uncertainty = ' ';
        if ($model['K'] > 1) {
            $exponents = [];
            $total = 0.0;
            foreach ($logs as $value) {
                $exponent = exp($value - $logs[$best]);
                $exponents[] = $exponent;
                $total += $exponent;
            }
            $terms = 0.0;
            foreach ($exponents as $value) {
                $responsibility = $value / $total;
                if ($responsibility != 0.0) $terms += $responsibility * log($responsibility);
            }
            $level = max(0, min(9, (int)floor(10 * -$terms / log($model['K']))));
            $uncertainty = $levels[$level];
        }
        $q = [];
        foreach ($model['components'] as $component) $q[] = quadratic($point, $component);
        $cells[] = ['density' => $density, 'region' => (string)($best + 1), 'uncertainty' => $uncertainty, 'q' => $q];
    }
    $mass = $mass * $stepX * $stepY;
    $cellIndex = function($point) use ($xmin, $ymax, $stepX, $stepY, $width, $height) {
        $c = (int)floor(($point['x'] - $xmin) / $stepX);
        $r = (int)floor(($ymax - $point['y']) / $stepY);
        return $c >= 0 && $c < $width && $r >= 0 && $r < $height ? $r * $width + $c : -1;
    };
    $histogram = array_fill(0, 10, 0);
    $densityChars = [];
    foreach ($cells as $cell) {
        $level = min(9, (int)floor(10 * $cell['density'] / $fmax));
        $histogram[$level]++;
        $densityChars[] = $levels[$level];
    }
    foreach ($model['components'] as $k => $component) {
        $index = $cellIndex(['x' => $component['mx'], 'y' => $component['my']]);
        if ($index !== -1) $densityChars[$index] = (string)($k + 1);
    }
    $occupants = array_fill(0, count($cells), 0);
    $outside = 0;
    foreach ($points as $i => $point) {
        $index = $cellIndex($point);
        if ($index === -1) $outside++;
        else {
            $component = $model['assignment'][$i] + 1;
            if ($occupants[$index] === 0) $occupants[$index] = $component;
            elseif ($occupants[$index] !== $component) $occupants[$index] = -1;
        }
    }
    $pointChars = [];
    foreach ($cells as $index => $cell) {
        if ($occupants[$index] === -1) {
            $pointChars[] = '*';
            continue;
        }
        if ($occupants[$index] > 0) {
            $pointChars[] = (string)$occupants[$index];
            continue;
        }
        $r = intdiv($index, $width);
        $c = $index % $width;
        $neighbors = [];
        if ($r > 0) $neighbors[] = $index - $width;
        if ($r + 1 < $height) $neighbors[] = $index + $width;
        if ($c > 0) $neighbors[] = $index - 1;
        if ($c + 1 < $width) $neighbors[] = $index + 1;
        $contour = false;
        for ($k = 0; $k < $model['K']; $k++) if ($cell['q'][$k] <= 4) {
            foreach ($neighbors as $other) if ($cells[$other]['q'][$k] > 4) {
                $contour = true;
                break;
            }
            if ($contour) break;
        }
        $pointChars[] = $contour ? '.' : ' ';
    }
    $rows = function($characters) use ($height, $width) {
        $result = [];
        for ($r = 0; $r < $height; $r++) $result[] = array_slice($characters, $r * $width, $width);
        return $result;
    };
    $lines = ['density K=' . $model['K'] . ' type=' . $model['type'],
        'x ' . real($xmin) . ' ' . real($xmax) . ' y ' . real($ymin) . ' ' . real($ymax) . ' grid ' . $width . 'x' . $height,
        'max_density ' . real($fmax, 6) . ' mass_in_map ' . real($mass)];
    $lines = array_merge($lines, frame($rows($densityChars)));
    for ($level = 0; $level < 10; $level++) $lines[] = 'level ' . $level . ' "' . $levels[$level] . '" from ' . real($level * $fmax / 10, 6) . ' cells ' . $histogram[$level];
    $lines = array_merge($lines, ['', 'regions'], frame($rows(array_column($cells, 'region'))), ['', 'uncertainty'],
        frame($rows(array_column($cells, 'uncertainty'))), ['', 'points'], frame($rows($pointChars)), ['outside ' . $outside]);
    return $lines;
}

$data = readDataset();
$points = $data['points'];
$params = $data['params'];
$initial = $data['initial'];
$models = $kmeansModels = [];
foreach ($params['ks'] as $K) {
    foreach ($params['types'] as $typeIndex => $type) {
        $result = emFit($points, $initial[$K], $type, $params['iterations'], $params['eps']);
        $models[] = summarize($result, $K, $type, $typeIndex, count($points), $params['tau']);
    }
    $kmeansModels[$K] = kmeansFit($points, $initial[$K], $params['kmeansMax']);
}
$ranks = [];
foreach (['bic', 'aic', 'icl'] as $criterion) {
    $ranking = $models;
    usort($ranking, fn($a, $b) => compareModels($a, $b, $criterion));
    $ranks[$criterion] = $ranking;
}
$selected = $ranks['bic'][0];
$comparisons = [];
foreach ($params['ks'] as $K) {
    foreach ($ranks['bic'] as $model) if ($model['K'] === $K) break;
    $km = $kmeansModels[$K];
    $table = contingency($model['assignment'], $km['assignment'], $K, $K);
    $comparisons[] = ['K' => $K, 'model' => $model, 'km' => $km, 'table' => $table, 'ari' => adjustedRand($table, count($points)),
        'gmmMetrics' => evaluatePartition($points, $model['assignment'], $K), 'kmMetrics' => evaluatePartition($points, $km['assignment'], $K)];
}
$modelLines = [];
foreach ($models as $i => $model) {
    if ($i > 0) $modelLines[] = '';
    foreach (modelBlock($model) as $line) $modelLines[] = $line;
}
$traceLines = ['K,type,iteration,loglik'];
foreach ($models as $model) foreach ($model['trace'] as $t => $value) $traceLines[] = implode(',', [$model['K'], $model['type'], $t, real($value)]);
$assignmentLines = ['id,component,max_responsibility,log_density,kmeans_cluster'];
$selectedKmeans = $kmeansModels[$selected['K']];
foreach ($points as $i => $point) $assignmentLines[] = implode(',', [$point['id'], $selected['assignment'][$i] + 1, real($selected['maximum'][$i]), real($selected['logDensities'][$i]), $selectedKmeans['assignment'][$i] + 1]);
writeLines('models.txt', $modelLines);
writeLines('loglik_trace.csv', $traceLines);
writeLines('assignments.csv', $assignmentLines);
writeLines('selection.txt', selectionReport($points, $params, $initial, $models, $ranks, $comparisons));
writeLines('density_map.txt', mapReport($points, $params, $selected));
