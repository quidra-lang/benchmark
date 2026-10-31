<?php

require_once __DIR__ . '/network_io.php';
require_once __DIR__ . '/learning.php';
require_once __DIR__ . '/factors.php';
require_once __DIR__ . '/elimination.php';
require_once __DIR__ . '/sampling.php';

function ordered($values)
{
    $values = array_values(array_unique($values));
    sort($values, SORT_NUMERIC);
    return $values;
}

function sumValues($values)
{
    $result = 0.0;
    foreach ($values as $value) {
        $result += $value;
    }
    return $result;
}

function formatReal($value)
{
    $text = number_format(abs($value), 4, '.', '');
    return $value < 0 && $text !== '0.0000' ? '-' . $text : $text;
}

function variableNames($network, $variables)
{
    return $variables ? implode(' ', array_map(fn($variable) => $network->variables[$variable]->name, $variables)) : '-';
}

function assignmentText($network, $variables, $assignment)
{
    $parts = [];
    foreach ($variables as $index) {
        $variable = $network->variables[$index];
        $parts[] = $variable->name . '=' . $variable->states[$assignment[$index]];
    }
    return $parts ? implode(' ', $parts) : '-';
}

function closure($adjacency, $seeds)
{
    $found = array_fill_keys($seeds, true);
    $queue = array_keys($found);
    for ($index = 0; $index < count($queue); $index++) {
        foreach ($adjacency[$queue[$index]] as $next) {
            if (!isset($found[$next])) {
                $found[$next] = true;
                $queue[] = $next;
            }
        }
    }
    return $found;
}

function prepare($network)
{
    $network->all = range(0, count($network->variables) - 1);
    $network->parents = array_map(fn($variable) => $variable->parents, $network->variables);
    $network->children = array_fill(0, count($network->variables), []);
    foreach ($network->all as $index) {
        foreach ($network->parents[$index] as $parent) {
            $network->children[$parent][] = $index;
        }
    }
    $selected = [];
    $network->topological = [];
    $network->depth = array_fill(0, count($network->variables), 0);
    while (count($selected) < count($network->all)) {
        foreach ($network->all as $index) {
            if (isset($selected[$index])) {
                continue;
            }
            $ready = true;
            foreach ($network->parents[$index] as $parent) {
                if (!isset($selected[$parent])) {
                    $ready = false;
                    break;
                }
            }
            if ($ready) {
                $next = $index;
                break;
            }
        }
        $selected[$next] = true;
        $network->topological[] = $next;
        foreach ($network->parents[$next] as $parent) {
            $network->depth[$next] = max($network->depth[$next], $network->depth[$parent] + 1);
        }
    }
    $network->ancestors = $network->descendants = $network->spouses = $network->blankets = [];
    foreach ($network->all as $index) {
        $ancestors = closure($network->parents, [$index]);
        $descendants = closure($network->children, [$index]);
        unset($ancestors[$index], $descendants[$index]);
        $network->ancestors[] = $ancestors;
        $network->descendants[] = $descendants;
        $excluded = array_fill_keys(array_merge([$index], $network->parents[$index], $network->children[$index]), true);
        $spouses = [];
        foreach ($network->children[$index] as $child) {
            foreach ($network->parents[$child] as $parent) {
                if (!isset($excluded[$parent])) {
                    $spouses[] = $parent;
                }
            }
        }
        $spouses = ordered($spouses);
        $network->spouses[] = $spouses;
        $network->blankets[] = ordered(array_merge($network->parents[$index], $network->children[$index], $spouses));
    }
    $logLikelihood = 0.0;
    $parameters = 0;
    foreach ($network->all as $index) {
        $variable = $network->variables[$index];
        $variable->counts = countsFor($network, $index, $variable->parents);
        $variable->learned = learnedTable($variable->counts, $network->params['alpha']);
        $variable->cpt = $variable->source === 'GIVEN' ? $variable->given : $variable->learned;
        $variable->logLikelihood = logLikelihood($variable->counts, $variable->cpt);
        $variable->parameters = parameterCount($variable->counts);
        $variable->bic = $variable->logLikelihood - $variable->parameters * log(count($network->samples)) / 2;
        $logLikelihood += $variable->logLikelihood;
        $parameters += $variable->parameters;
    }
    $network->logLikelihood = $logLikelihood;
    $network->parameters = $parameters;
    $network->bic = $logLikelihood - $parameters * log(count($network->samples)) / 2;
    $network->cptFactors = [];
    foreach ($network->all as $index) {
        $network->cptFactors[] = cptFactor($network, $index);
    }
    return $network;
}

function makeProblem($network, $query, $evidence, $complete = false)
{
    $relevantSet = $complete ? array_fill_keys($network->all, true) : closure($network->parents, array_merge($query, array_keys($evidence)));
    $relevant = $pruned = $variables = $initial = [];
    $kept = array_fill_keys(array_merge($query, array_keys($evidence)), true);
    foreach ($network->all as $variable) {
        if (isset($relevantSet[$variable])) {
            $relevant[] = $variable;
            if (!isset($kept[$variable])) {
                $variables[] = $variable;
            }
            $initial[] = reduceFactor($network->cptFactors[$variable], $evidence, $network->sizes);
        } else {
            $pruned[] = $variable;
        }
    }
    $plans = [];
    foreach (['minfill', 'given'] as $method) {
        $plans[$method] = eliminationPlan($initial, $variables, $method, $network->params['order'], $network->sizes);
    }
    return ['relevant' => $relevant, 'pruned' => $pruned, 'variables' => $variables, 'initial' => $initial, 'plans' => $plans];
}

function posteriorFrom($network, $query, $problem, $method)
{
    $factor = executePlan($problem['initial'], $problem['plans'][$method], $network->sizes)['factor'];
    $normalizer = sumValues($factor['values']);
    $probabilities = array_map(fn($value) => $value / $normalizer, $factor['values']);
    $marginals = [];
    foreach ($query as $variable) {
        $marginals[$variable] = array_fill(0, $network->sizes[$variable], 0.0);
    }
    $index = 0;
    foreach (assignments($factor['variables'], $network->sizes) as $assignment) {
        foreach ($query as $variable) {
            $marginals[$variable][$assignment[$variable]] += $probabilities[$index];
        }
        $index++;
    }
    return ['factor' => $factor, 'normalizer' => $normalizer, 'logEvidence' => log($normalizer),
        'probabilities' => $probabilities, 'marginals' => $marginals];
}

function posterior($network, $query, $evidence)
{
    return posteriorFrom($network, $query, makeProblem($network, $query, $evidence), $network->params['method']);
}

function jointProbability($network, $variables, $assignment)
{
    $probability = 1.0;
    foreach ($variables as $index) {
        $variable = $network->variables[$index];
        $row = combinationIndex($variable->parents, $assignment, $network->sizes);
        $probability *= $variable->cpt[$row][$assignment[$index]];
    }
    return $probability;
}

function posteriorAgreement($first, $second)
{
    if (abs($first['logEvidence'] - $second['logEvidence']) > 1e-9) {
        return false;
    }
    foreach ($first['probabilities'] as $index => $value) {
        if (abs($value - $second['probabilities'][$index]) > 1e-9) {
            return false;
        }
    }
    return true;
}

function enumerateQuery($network, $problem, $evidence, $result)
{
    $free = array_values(array_filter($problem['relevant'], fn($variable) => !isset($evidence[$variable])));
    $count = assignmentCount($free, $network->sizes);
    if ($count > $network->params['limit']) {
        return ['count' => $count, 'status' => 'skipped'];
    }
    $values = array_fill(0, count($result['probabilities']), 0.0);
    foreach (assignments($free, $network->sizes) as $assignment) {
        foreach ($evidence as $variable => $state) {
            $assignment[$variable] = $state;
        }
        $index = combinationIndex($result['factor']['variables'], $assignment, $network->sizes);
        $values[$index] += jointProbability($network, $problem['relevant'], $assignment);
    }
    $normalizer = sumValues($values);
    $agrees = abs(log($normalizer) - $result['logEvidence']) <= 1e-9;
    foreach ($values as $index => $value) {
        if (abs($value / $normalizer - $result['probabilities'][$index]) > 1e-9) {
            $agrees = false;
        }
    }
    return ['count' => $count, 'status' => $agrees ? 'agree' : 'disagree'];
}

function eliminationLines($network, $problem, $agree, $enumeration)
{
    $lines = ['relevant ' . variableNames($network, $problem['relevant']), 'pruned ' . variableNames($network, $problem['pruned']),
        'eliminate ' . variableNames($network, $problem['variables'])];
    foreach (['minfill', 'given'] as $method) {
        $lines[] = 'order ' . $method;
        foreach ($problem['plans'][$method]['steps'] as $step) {
            $lines[] = 'step ' . $network->variables[$step['variable']]->name . ' fill ' . $step['fill'] .
                ' scope ' . variableNames($network, $step['variables']) . ' entries ' . $step['size'];
        }
        $lines[] = 'cost max ' . $problem['plans'][$method]['maximum'] . ' total ' . $problem['plans'][$method]['total'];
    }
    $lines[] = 'used ' . $network->params['method'];
    $lines[] = 'orders_agree ' . ($agree ? 'yes' : 'no');
    $lines[] = 'enumeration ' . $enumeration['count'] . ' ' . $enumeration['status'];
    return $lines;
}

function distributionLine($network, $prefix, $variable, $probabilities)
{
    $tokens = [$prefix, $network->variables[$variable]->name];
    foreach ($probabilities as $state => $value) {
        $tokens[] = $network->variables[$variable]->states[$state];
        $tokens[] = formatReal($value);
    }
    return implode(' ', $tokens);
}

function queryAnswer($network, $query, $evidence)
{
    $problem = makeProblem($network, $query, $evidence);
    $minfill = posteriorFrom($network, $query, $problem, 'minfill');
    $given = posteriorFrom($network, $query, $problem, 'given');
    $result = $network->params['method'] === 'minfill' ? $minfill : $given;
    $lines = ['log_evidence ' . formatReal($result['logEvidence'])];
    if ($evidence) {
        $conflict = 0.0;
        foreach ($evidence as $variable => $state) {
            $conflict += posterior($network, [], [$variable => $state])['logEvidence'];
        }
        $lines[] = 'conflict ' . formatReal($conflict - $result['logEvidence']);
    }
    if (count($query) >= 2) {
        $index = 0;
        foreach (assignments($result['factor']['variables'], $network->sizes) as $assignment) {
            $lines[] = 'joint ' . assignmentText($network, $result['factor']['variables'], $assignment) . ' ' . formatReal($result['probabilities'][$index++]);
        }
    }
    foreach ($query as $variable) {
        $lines[] = distributionLine($network, 'marginal', $variable, $result['marginals'][$variable]);
    }
    foreach ($evidence as $removed => $state) {
        $reduced = $evidence;
        unset($reduced[$removed]);
        $without = posterior($network, $query, $reduced);
        $influence = 0.0;
        foreach ($query as $variable) {
            for ($s = 0; $s < $network->sizes[$variable]; $s++) {
                $influence = max($influence, abs($result['marginals'][$variable][$s] - $without['marginals'][$variable][$s]));
            }
        }
        $lines[] = 'drop ' . $network->variables[$removed]->name . '=' . $network->variables[$removed]->states[$state] . ' shift ' . formatReal($influence);
    }
    $enumeration = enumerateQuery($network, $problem, $evidence, $result);
    return ['lines' => $lines, 'elimination' => eliminationLines($network, $problem, posteriorAgreement($minfill, $given), $enumeration)];
}

function enumerateMpe($network, $problem, $evidence, $assignment, $probability)
{
    $count = assignmentCount($problem['variables'], $network->sizes);
    if ($count > $network->params['limit']) {
        return ['count' => $count, 'status' => 'skipped'];
    }
    $maximum = -INF;
    $best = null;
    foreach (assignments($problem['variables'], $network->sizes) as $candidate) {
        foreach ($evidence as $variable => $state) {
            $candidate[$variable] = $state;
        }
        $value = jointProbability($network, $network->all, $candidate);
        if ($value > $maximum) {
            $maximum = $value;
            $best = $candidate;
        }
    }
    $agrees = $best === $assignment && abs(log($maximum) - log($probability)) <= 1e-9;
    return ['count' => $count, 'status' => $agrees ? 'agree' : 'disagree'];
}

function mpeAnswer($network, $evidence)
{
    $problem = makeProblem($network, [], $evidence, true);
    $results = [];
    foreach (['minfill', 'given'] as $method) {
        $result = executePlan($problem['initial'], $problem['plans'][$method], $network->sizes, true);
        $results[$method] = ['assignment' => traceback($result, $evidence, $network->sizes), 'probability' => $result['factor']['values'][0]];
    }
    $result = $results[$network->params['method']];
    $evidenceProbability = !$evidence ? 1.0 : posterior($network, [], $evidence)['normalizer'];
    $logJoint = log($result['probability']);
    $lines = ['assignment ' . assignmentText($network, $network->all, $result['assignment']), 'log_joint ' . formatReal($logJoint),
        'log_evidence ' . formatReal(log($evidenceProbability)), 'posterior ' . formatReal($result['probability'] / $evidenceProbability)];
    foreach ($problem['variables'] as $variable) {
        $eliminated = array_values(array_filter($problem['variables'], fn($index) => $index !== $variable));
        $plan = eliminationPlan($problem['initial'], $eliminated, $network->params['method'], $network->params['order'], $network->sizes);
        $factor = executePlan($problem['initial'], $plan, $network->sizes, true)['factor'];
        $second = null;
        for ($state = 0; $state < $network->sizes[$variable]; $state++) {
            if ($state !== $result['assignment'][$variable] && ($second === null || $factor['values'][$state] > $factor['values'][$second])) {
                $second = $state;
            }
        }
        $lines[] = 'margin ' . $network->variables[$variable]->name . ' ' . $network->variables[$variable]->states[$second] .
            ' ' . formatReal($logJoint - log($factor['values'][$second]));
    }
    $agree = $results['minfill']['assignment'] === $results['given']['assignment'] &&
        abs(log($results['minfill']['probability']) - log($results['given']['probability'])) <= 1e-9;
    $enumeration = enumerateMpe($network, $problem, $evidence, $result['assignment'], $result['probability']);
    return ['lines' => $lines, 'elimination' => eliminationLines($network, $problem, $agree, $enumeration)];
}

function sampleAnswer($network, $query, $evidence, $counts, $random, $number, &$csv)
{
    $exact = posterior($network, $query, $evidence);
    $lines = $totals = [];
    foreach ($query as $variable) {
        $lines[] = distributionLine($network, 'exact', $variable, $exact['marginals'][$variable]);
        $totals[$variable] = array_fill(0, $network->sizes[$variable], 0.0);
    }
    $weight = $squaredWeight = 0.0;
    $checkpoint = 0;
    for ($count = 1; $count <= $counts[count($counts) - 1]; $count++) {
        $sample = weightedSample($network, $evidence, $random);
        $weight += $sample['weight'];
        $squaredWeight += $sample['weight'] * $sample['weight'];
        foreach ($query as $variable) {
            $totals[$variable][$sample['assignment'][$variable]] += $sample['weight'];
        }
        if ($count !== $counts[$checkpoint]) {
            continue;
        }
        $maximumError = 0.0;
        foreach ($query as $variable) {
            for ($state = 0; $state < $network->sizes[$variable]; $state++) {
                $estimate = $totals[$variable][$state] / $weight;
                $truth = $exact['marginals'][$variable][$state];
                $error = abs($estimate - $truth);
                $maximumError = max($maximumError, $error);
                $csv[] = implode(',', [$number, $count, $network->variables[$variable]->name,
                    $network->variables[$variable]->states[$state], formatReal($estimate), formatReal($truth), formatReal($error)]);
            }
        }
        $lines[] = 'after ' . $count . ' weight ' . formatReal($weight) . ' ess ' . formatReal($weight * $weight / $squaredWeight) . ' max_error ' . formatReal($maximumError);
        $checkpoint++;
    }
    return $lines;
}

function predictAnswer($network, $index)
{
    $variable = $network->variables[$index];
    $confusion = array_fill(0, $network->sizes[$index], array_fill(0, $network->sizes[$index], 0));
    $logProbability = 0.0;
    foreach ($network->samples as $sample) {
        $assignment = $sample;
        $values = [];
        for ($state = 0; $state < $network->sizes[$index]; $state++) {
            $assignment[$index] = $state;
            $value = $variable->cpt[combinationIndex($variable->parents, $assignment, $network->sizes)][$state];
            foreach ($network->children[$index] as $child) {
                $model = $network->variables[$child];
                $value *= $model->cpt[combinationIndex($model->parents, $assignment, $network->sizes)][$assignment[$child]];
            }
            $values[] = $value;
        }
        $normalizer = sumValues($values);
        $probabilities = array_map(fn($value) => $value / $normalizer, $values);
        $best = 0;
        for ($state = 1; $state < count($probabilities); $state++) {
            if ($probabilities[$state] > $probabilities[$best]) {
                $best = $state;
            }
        }
        $confusion[$sample[$index]][$best]++;
        $logProbability += log($probabilities[$sample[$index]]);
    }
    $correct = 0;
    foreach ($confusion as $state => $row) {
        $correct += $row[$state];
    }
    $lines = ['blanket ' . variableNames($network, $network->blankets[$index]),
        'accuracy ' . $correct . '/' . count($network->samples) . ' ' . formatReal($correct / count($network->samples)),
        'log_loss ' . formatReal(-$logProbability / count($network->samples)), 'predicted ' . implode(' ', $variable->states)];
    foreach ($confusion as $state => $row) {
        $lines[] = 'actual ' . $variable->states[$state] . ' ' . implode(' ', $row);
    }
    return $lines;
}

function bayesBall($network, $x, $y, $z)
{
    $observed = array_fill_keys($z, true);
    $sources = array_fill_keys($x, true);
    $ancestors = closure($network->parents, $z);
    $visited = $queue = [];
    $add = function ($variable, $direction) use (&$visited, &$queue) {
        $position = 2 * $variable + $direction;
        if (!isset($visited[$position])) {
            $visited[$position] = true;
            $queue[] = [$variable, $direction];
        }
    };
    foreach ($x as $variable) {
        $add($variable, 0);
    }
    for ($index = 0; $index < count($queue); $index++) {
        [$variable, $direction] = $queue[$index];
        if ($direction === 0 && !isset($observed[$variable])) {
            foreach ($network->parents[$variable] as $parent) {
                $add($parent, 0);
            }
            foreach ($network->children[$variable] as $child) {
                $add($child, 1);
            }
        }
        if ($direction === 1) {
            if (!isset($observed[$variable])) {
                foreach ($network->children[$variable] as $child) {
                    $add($child, 1);
                }
            }
            if (isset($ancestors[$variable])) {
                foreach ($network->parents[$variable] as $parent) {
                    $add($parent, 0);
                }
            }
        }
    }
    $reachable = [];
    foreach ($network->all as $variable) {
        if (!isset($sources[$variable]) && !isset($observed[$variable]) &&
            (isset($visited[2 * $variable]) || isset($visited[2 * $variable + 1]))) {
            $reachable[] = $variable;
        }
    }
    $separated = true;
    foreach ($y as $variable) {
        if (in_array($variable, $reachable, true)) {
            $separated = false;
            break;
        }
    }
    return ['reachable' => $reachable, 'separated' => $separated];
}

function observedCounts($network, $variables)
{
    $counts = [];
    foreach ($network->samples as $sample) {
        $index = combinationIndex($variables, $sample, $network->sizes);
        $counts[$index] = ($counts[$index] ?? 0) + 1;
    }
    return $counts;
}

function conditionalInformation($network, $x, $y, $z)
{
    $all = ordered(array_merge($x, $y, $z));
    $xz = ordered(array_merge($x, $z));
    $yz = ordered(array_merge($y, $z));
    $counts = observedCounts($network, $all);
    $countsXz = observedCounts($network, $xz);
    $countsYz = observedCounts($network, $yz);
    $countsZ = observedCounts($network, $z);
    ksort($counts, SORT_NUMERIC);
    $information = 0.0;
    foreach ($counts as $index => $count) {
        $assignment = decodeAssignment($all, $index, $network->sizes);
        $countXz = $countsXz[combinationIndex($xz, $assignment, $network->sizes)];
        $countYz = $countsYz[combinationIndex($yz, $assignment, $network->sizes)];
        $countZ = $countsZ[combinationIndex($z, $assignment, $network->sizes)];
        $information += $count / count($network->samples) * log(($count * $countZ) / ($countXz * $countYz));
    }
    $df = (assignmentCount($x, $network->sizes) - 1) * (assignmentCount($y, $network->sizes) - 1) * assignmentCount($z, $network->sizes);
    return ['cmi' => $information, 'g2' => 2 * count($network->samples) * $information, 'df' => $df];
}

function dsepAnswer($network, $x, $y, $z)
{
    $result = bayesBall($network, $x, $y, $z);
    $information = conditionalInformation($network, $x, $y, $z);
    return ['result ' . ($result['separated'] ? 'separated' : 'connected'), 'reachable ' . variableNames($network, $result['reachable']),
        'data cmi ' . formatReal($information['cmi']) . ' g2 ' . formatReal($information['g2']) . ' df ' . $information['df']];
}

function blanketAnswer($network, $variable)
{
    $blanket = $network->blankets[$variable];
    $rest = array_values(array_filter($network->all, fn($index) => $index !== $variable && !in_array($index, $blanket, true)));
    $separated = bayesBall($network, [$variable], $rest, $blanket)['separated'];
    return ['parents ' . variableNames($network, $network->parents[$variable]), 'children ' . variableNames($network, $network->children[$variable]),
        'spouses ' . variableNames($network, $network->spouses[$variable]), 'blanket ' . variableNames($network, $blanket),
        'rest ' . variableNames($network, $rest), 'rest_separated ' . ($separated ? 'yes' : 'no')];
}

function directedPath($network, $start, $target, $ignored = null)
{
    $marked = [$start => true];
    $queue = [$start];
    $previous = [];
    for ($index = 0; $index < count($queue); $index++) {
        $current = $queue[$index];
        foreach ($network->children[$current] as $child) {
            if ($ignored !== null && $current === $ignored[0] && $child === $ignored[1]) {
                continue;
            }
            if (isset($marked[$child])) {
                continue;
            }
            $marked[$child] = true;
            $previous[$child] = $current;
            if ($child === $target) {
                $path = [$target];
                while ($path[count($path) - 1] !== $start) {
                    $last = $path[count($path) - 1];
                    $path[] = $previous[$last];
                }
                return array_reverse($path);
            }
            $queue[] = $child;
        }
    }
    return null;
}

function edgeAnswer($network, $operation, $x, $y)
{
    $exists = in_array($x, $network->parents[$y], true);
    if ($operation === 'ADD' && $exists) {
        return ['result exists'];
    }
    if ($operation !== 'ADD' && !$exists) {
        return ['result missing'];
    }
    $cycle = null;
    if ($operation === 'ADD') {
        $path = directedPath($network, $y, $x);
        if ($path !== null) {
            $cycle = array_merge([$x], $path);
        }
    } elseif ($operation === 'REVERSE') {
        $path = directedPath($network, $x, $y, [$x, $y]);
        if ($path !== null) {
            $cycle = array_merge([$y], $path);
        }
    }
    if ($cycle !== null) {
        return ['result cycle ' . implode(' -> ', array_map(fn($index) => $network->variables[$index]->name, $cycle))];
    }
    $before = familyScore($network, $y, $network->parents[$y]);
    $changedParents = $operation === 'ADD' ? array_merge($network->parents[$y], [$x]) :
        array_values(array_filter($network->parents[$y], fn($parent) => $parent !== $x));
    $after = familyScore($network, $y, $changedParents);
    $change = $after - $before;
    $lines = ['result ok', 'family ' . $network->variables[$y]->name . ' before ' . formatReal($before) . ' after ' . formatReal($after)];
    if ($operation === 'REVERSE') {
        $beforeX = familyScore($network, $x, $network->parents[$x]);
        $afterX = familyScore($network, $x, array_merge($network->parents[$x], [$y]));
        $change += $afterX - $beforeX;
        $lines[] = 'family ' . $network->variables[$x]->name . ' before ' . formatReal($beforeX) . ' after ' . formatReal($afterX);
    }
    $lines[] = 'delta ' . formatReal($change) . ' ' . ($change > 0 ? 'improves' : 'worsens');
    return $lines;
}

function joinBlocks($blocks)
{
    $lines = [];
    foreach ($blocks as $block) {
        if ($lines) {
            $lines[] = '';
        }
        foreach ($block as $line) {
            $lines[] = $line;
        }
    }
    return $lines;
}

function cptLines($network)
{
    $blocks = [];
    foreach ($network->all as $index) {
        $variable = $network->variables[$index];
        $lines = ['variable ' . $variable->name . ' source ' . $variable->source, 'states ' . implode(' ', $variable->states),
            'parents ' . variableNames($network, $variable->parents)];
        foreach ($variable->counts as $row => $counts) {
            $assignment = decodeAssignment($variable->parents, $row, $network->sizes);
            $lines[] = 'row ' . assignmentText($network, $variable->parents, $assignment) . ' counts ' . implode(' ', $counts) .
                ' probs ' . implode(' ', array_map('formatReal', $variable->cpt[$row]));
        }
        $lines[] = 'loglik ' . formatReal($variable->logLikelihood) . ' parameters ' . $variable->parameters . ' bic ' . formatReal($variable->bic);
        $marginal = posterior($network, [$index], [])['marginals'][$index];
        $frequencies = array_fill(0, $network->sizes[$index], 0);
        foreach ($network->samples as $sample) {
            $frequencies[$sample[$index]]++;
        }
        $lines[] = 'marginal model ' . implode(' ', array_map('formatReal', $marginal)) . ' data ' .
            implode(' ', array_map(fn($count) => formatReal($count / count($network->samples)), $frequencies));
        if ($variable->source === 'LEARNED') {
            $difference = 0.0;
            if ($variable->given !== null) {
                foreach ($variable->learned as $row => $values) {
                    foreach ($values as $state => $value) {
                        $difference = max($difference, abs($value - $variable->given[$row][$state]));
                    }
                }
            }
            $lines[] = 'given_difference ' . ($variable->given === null ? '-' : formatReal($difference));
        }
        $blocks[] = $lines;
    }
    $blocks[] = ['network samples ' . count($network->samples) . ' pseudocount ' . formatReal($network->params['alpha']) .
        ' loglik ' . formatReal($network->logLikelihood) . ' parameters ' . $network->parameters . ' bic ' . formatReal($network->bic)];
    return joinBlocks($blocks);
}

function structureLines($network)
{
    $graph = interactionGraph($network->cptFactors);
    $moralEdges = 0;
    foreach ($graph as $neighbors) {
        $moralEdges += count($neighbors);
    }
    $widths = [];
    foreach (['minfill', 'given'] as $method) {
        $plan = eliminationPlan($network->cptFactors, $network->all, $method, $network->params['order'], $network->sizes);
        $width = 0;
        foreach ($plan['steps'] as $step) {
            $width = max($width, count($step['variables']) - 1);
        }
        $widths[$method] = $width;
    }
    $roots = $leaves = [];
    $edges = 0;
    foreach ($network->all as $index) {
        $edges += count($network->parents[$index]);
        if (!$network->parents[$index]) {
            $roots[] = $index;
        }
        if (!$network->children[$index]) {
            $leaves[] = $index;
        }
    }
    $lines = ['variables ' . count($network->all) . ' edges ' . $edges, 'topological_order ' . variableNames($network, $network->topological),
        'roots ' . variableNames($network, $roots), 'leaves ' . variableNames($network, $leaves),
        'moral_edges ' . intdiv($moralEdges, 2) . ' width minfill ' . $widths['minfill'] . ' given ' . $widths['given']];
    foreach ($network->all as $index) {
        $lines[] = 'variable ' . $network->variables[$index]->name . ' states ' . $network->sizes[$index] .
            ' parents ' . count($network->parents[$index]) . ' children ' . count($network->children[$index]) .
            ' depth ' . $network->depth[$index] . ' ancestors ' . count($network->ancestors[$index]) .
            ' descendants ' . count($network->descendants[$index]) . ' blanket ' . count($network->blankets[$index]);
    }
    return $lines;
}

function parseEvidence($network, $tokens)
{
    $evidence = [];
    foreach ($tokens as $token) {
        [$name, $state] = explode('=', $token);
        $variable = $network->names[$name];
        $evidence[$variable] = $network->stateNames[$variable][$state];
    }
    return $evidence;
}

function parsePosterior($network, $tokens)
{
    $separator = array_search('|', $tokens, true);
    $names = $separator === false ? $tokens : array_slice($tokens, 0, $separator);
    $query = array_map(fn($name) => $network->names[$name], $names);
    $evidence = parseEvidence($network, $separator === false ? [] : array_slice($tokens, $separator + 1));
    return [$query, $evidence];
}

function main()
{
    $network = readInputs();
    $random = new Minstd($network->params['seed']);
    prepare($network);
    $structure = [structureLines($network)];
    $answers = $plans = [];
    $sampling = ['query,samples,variable,state,estimate,exact,abs_error'];
    foreach ($network->queries as $index => $line) {
        $tokens = explode(' ', $line);
        $header = 'query ' . ($index + 1) . ' ' . $line;
        if ($tokens[0] === 'QUERY') {
            [$query, $evidence] = parsePosterior($network, array_slice($tokens, 1));
            $result = queryAnswer($network, $query, $evidence);
            $answers[] = array_merge([$header], $result['lines']);
            $plans[] = array_merge([$header], $result['elimination']);
        } elseif ($tokens[0] === 'MPE') {
            $result = mpeAnswer($network, parseEvidence($network, array_slice($tokens, 1)));
            $answers[] = array_merge([$header], $result['lines']);
            $plans[] = array_merge([$header], $result['elimination']);
        } elseif ($tokens[0] === 'SAMPLE') {
            $separator = array_search('COUNTS', $tokens, true);
            [$query, $evidence] = parsePosterior($network, array_slice($tokens, 1, $separator - 1));
            $counts = array_map('intval', array_slice($tokens, $separator + 1));
            $answers[] = array_merge([$header], sampleAnswer($network, $query, $evidence, $counts, $random, $index + 1, $sampling));
        } elseif ($tokens[0] === 'PREDICT') {
            $answers[] = array_merge([$header], predictAnswer($network, $network->names[$tokens[1]]));
        } elseif ($tokens[0] === 'DSEP') {
            $groups = [[]];
            foreach (array_slice($tokens, 1) as $token) {
                if ($token === '|') {
                    $groups[] = [];
                } else {
                    $groups[count($groups) - 1][] = $network->names[$token];
                }
            }
            $x = ordered($groups[0]);
            $y = ordered($groups[1]);
            $z = ordered($groups[2] ?? []);
            $structure[] = array_merge([$header], dsepAnswer($network, $x, $y, $z));
        } elseif ($tokens[0] === 'BLANKET') {
            $structure[] = array_merge([$header], blanketAnswer($network, $network->names[$tokens[1]]));
        } else {
            $structure[] = array_merge([$header], edgeAnswer($network, $tokens[1], $network->names[$tokens[2]], $network->names[$tokens[3]]));
        }
    }
    $files = ['cpts.txt' => cptLines($network), 'structure.txt' => joinBlocks($structure), 'answers.txt' => joinBlocks($answers),
        'elimination.txt' => joinBlocks($plans), 'sampling.csv' => $sampling];
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    foreach ($files as $name => $lines) {
        file_put_contents('output/' . $name, $lines ? implode("\n", $lines) . "\n" : '');
    }
}

main();
