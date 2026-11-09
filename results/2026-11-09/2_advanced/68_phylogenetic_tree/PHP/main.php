<?php

require_once __DIR__ . '/alignment.php';
require_once __DIR__ . '/distances.php';
require_once __DIR__ . '/tree_building.php';
require_once __DIR__ . '/parsimony.php';
require_once __DIR__ . '/tree_io.php';

const MODELS = ['P', 'JC', 'K2P'];
const METHODS = ['NJ_P', 'NJ_JC', 'NJ_K2P', 'ME', 'MP', 'CONSENSUS'];

function parameters(): object
{
    $fields = [];
    foreach (file('input/params.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $values = explode(' ', $line);
        $key = array_shift($values);
        $fields[$key] = $values;
    }
    return (object) ['model' => $fields['model'][0], 'outgroup' => $fields['outgroup'][0],
        'replicates' => (int) $fields['replicates'][0], 'seed' => (int) $fields['seed'][0],
        'missing' => (int) $fields['max_missing_percent'][0], 'saturation' => (float) $fields['saturation_distance'][0],
        'exhaustive' => $fields['exhaustive_taxa'], 'lowSites' => (int) $fields['low_sites'][0]];
}

function acceptRecords(array $records, object $params): object
{
    $length = strlen($records[0]->sequence);
    $taxa = [];
    $rejected = [];
    $seen = [];
    foreach ($records as $record) {
        $reason = isset($seen[$record->name]) ? 'duplicate name' : null;
        $seen[$record->name] = true;
        if ($reason === null) {
            for ($c = 0; $c < strlen($record->sequence); $c++) {
                if (!isset(BASES[$record->sequence[$c]])) {
                    $reason = 'invalid character ' . $record->sequence[$c] . ' at column ' . ($c + 1);
                    break;
                }
            }
        }
        if ($reason === null && strlen($record->sequence) !== $length) {
            $reason = 'length mismatch ' . strlen($record->sequence);
        }
        if ($reason === null) {
            $missing = substr_count($record->sequence, 'N') + substr_count($record->sequence, '-');
            if (100 * $missing > $params->missing * $length) {
                $reason = 'too many missing ' . $missing;
            }
        }
        if ($reason === null) {
            $taxa[] = $record;
        } else {
            $record->reason = $reason;
            $rejected[] = $record;
        }
    }
    return (object) compact('taxa', 'rejected', 'length');
}

function alignmentSummary(array $records, object $data, object $patterns, array $columns): array
{
    $taxa = $data->taxa;
    $length = $data->length;
    $lines = ['INPUT records ' . count($records) . ' accepted ' . count($taxa) . ' rejected ' . count($data->rejected) . ' columns ' . $length];
    foreach ($data->rejected as $record) {
        $lines[] = 'REJECT line ' . $record->line . ' ' . $record->name . ' ' . $record->reason;
    }
    $composition = [0, 0, 0, 0];
    $totalBases = 0;
    foreach ($taxa as $taxon) {
        $bases = $ambiguous = $missing = $unique = $gc = 0;
        for ($c = 0; $c < $length; $c++) {
            $character = $taxon->sequence[$c];
            $index = strpos(LETTERS, $character);
            if ($index !== false) {
                $bases++;
                $totalBases++;
                $composition[$index]++;
                if ($character === 'C' || $character === 'G') {
                    $gc++;
                }
                if ($columns[$c]->counts[$index] === 1 && $columns[$c]->kinds >= 2) {
                    $unique++;
                }
            } elseif ($character === 'N' || $character === '-') {
                $missing++;
            } else {
                $ambiguous++;
            }
        }
        $lines[] = 'TAXON ' . $taxon->name . ' bases ' . $bases . ' ambiguous ' . $ambiguous . ' missing ' . $missing . ' unique ' . $unique . ' gc ' . realNumber($gc / $bases, 4);
    }
    $constant = $variable = $informative = $gapped = $empty = 0;
    foreach ($columns as $column) {
        if ($column->kinds === 0) {
            $empty++;
        } elseif ($column->kinds === 1) {
            $constant++;
        } else {
            $variable++;
        }
        $informative += (int) $column->informative;
        $gapped += (int) $column->gapped;
    }
    $lines[] = 'COLUMNS constant ' . $constant . ' variable ' . $variable . ' informative ' . $informative . ' gapped ' . $gapped . ' empty ' . $empty;
    $lines[] = 'PATTERNS ' . count($patterns->distinct);
    $parts = [];
    for ($i = 0; $i < 4; $i++) {
        $parts[] = LETTERS[$i] . ' ' . realNumber($composition[$i] / $totalBases, 4);
    }
    $lines[] = 'COMPOSITION ' . implode(' ', $parts);
    return $lines;
}

function scoreBounds(array $encoded): object
{
    $minima = [];
    $minimum = $maximum = 0;
    for ($c = 0; $c < count($encoded[0]); $c++) {
        $lower = 4;
        for ($mask = 1; $mask <= 15; $mask++) {
            $size = bitCount($mask);
            if ($size >= $lower) {
                continue;
            }
            $covers = true;
            foreach ($encoded as $sequence) {
                if (($sequence[$c] & $mask) === 0) {
                    $covers = false;
                    break;
                }
            }
            if ($covers) {
                $lower = $size;
            }
        }
        $minima[] = $lower - 1;
        $minimum += $lower - 1;
        $upper = count($encoded);
        foreach ([1, 2, 4, 8] as $bit) {
            $excludes = 0;
            foreach ($encoded as $sequence) {
                if (($sequence[$c] & $bit) === 0) {
                    $excludes++;
                }
            }
            $upper = min($upper, $excludes);
        }
        $maximum += $upper;
    }
    return (object) compact('minimum', 'maximum', 'minima');
}

function bme(object $tree, array $matrix): float
{
    $taxa = leaves($tree);
    $total = 0.0;
    for ($i = 0; $i < count($taxa); $i++) {
        for ($j = $i + 1; $j < count($taxa); $j++) {
            $edges = count(treePath($tree, $taxa[$i], $taxa[$j]));
            $total += $matrix[$taxa[$i]][$taxa[$j]] / (1 << ($edges - 1));
        }
    }
    return $total;
}

function stepwise(array $taxa, int $count, int $outgroup, callable $objective): object
{
    $tree = star(array_slice($taxa, 0, 3), $count);
    $initial = $objective($tree);
    $value = $initial;
    $evaluated = 0;
    $additions = [];
    foreach (array_slice($taxa, 3) as $taxon) {
        $best = null;
        $ties = 0;
        foreach (branches($tree, $outgroup) as $edge) {
            $candidate = insertTaxon($tree, $edge, $taxon);
            $score = $objective($candidate);
            $evaluated++;
            if ($best === null || $score < $best->value) {
                $best = (object) ['tree' => $candidate, 'value' => $score, 'mask' => $edge->mask];
                $ties = 1;
            } elseif ($score === $best->value) {
                $ties++;
            }
        }
        $tree = $best->tree;
        $value = $best->value;
        $additions[] = (object) ['taxon' => $taxon, 'mask' => $best->mask, 'value' => $value, 'ties' => $ties];
    }
    $first = array_slice($taxa, 0, 3);
    return (object) compact('tree', 'value', 'initial', 'first', 'additions', 'evaluated');
}

function hillClimb(object $start, $initial, int $outgroup, callable $objective): object
{
    $tree = $start;
    $value = $initial;
    $evaluated = 0;
    $moves = [];
    while (true) {
        $improvement = null;
        foreach (nniCandidates($tree, $outgroup) as $candidate) {
            $nextValue = $objective($candidate->tree);
            $evaluated++;
            if ($nextValue < $value) {
                $improvement = $candidate;
                $value = $nextValue;
                break;
            }
        }
        if ($improvement === null) {
            return (object) compact('tree', 'value', 'moves', 'evaluated');
        }
        $tree = $improvement->tree;
        $moves[] = (object) ['mask' => $improvement->mask, 'swap' => $improvement->swap, 'value' => $value];
    }
}

function parentMask(int $mask, bool $strict, array $masks, int $ingroup): int
{
    $best = $ingroup;
    foreach ($masks as $candidate) {
        if ((!$strict || $candidate !== $mask) && ($candidate & $mask) === $mask && bitCount($candidate) < bitCount($best)) {
            $best = $candidate;
        }
    }
    return $best;
}

function consensus(array $clades, array $taxa, int $count, int $outgroup): object
{
    $tree = emptyTree($count);
    $root = $tree->next++;
    $ingroup = 0;
    foreach ($taxa as $taxon) {
        if ($taxon !== $outgroup) {
            $ingroup |= 1 << $taxon;
        }
    }
    $masks = array_keys($clades);
    sort($masks, SORT_NUMERIC);
    $nodes = [];
    foreach ($masks as $mask) {
        $nodes[$mask] = $tree->next++;
    }
    foreach ($masks as $mask) {
        $parent = parentMask($mask, true, $masks, $ingroup);
        connect($tree, $parent === $ingroup ? $root : $nodes[$parent], $nodes[$mask]);
    }
    foreach ($taxa as $taxon) {
        $parent = $taxon === $outgroup ? $ingroup : parentMask(1 << $taxon, false, $masks, $ingroup);
        connect($tree, $parent === $ingroup ? $root : $nodes[$parent], $taxon);
    }
    return $tree;
}

function exhaustiveSearch(array $taxa, int $count, int $outgroup, array $names, callable $objective, array $matrix): object
{
    $trees = [star(array_slice($taxa, 0, 3), $count)];
    foreach (array_slice($taxa, 3) as $taxon) {
        $next = [];
        foreach ($trees as $tree) {
            foreach (branches($tree, $outgroup) as $edge) {
                $next[] = insertTaxon($tree, $edge, $taxon);
            }
        }
        $trees = $next;
    }
    $entries = [];
    $histogram = [];
    $bestScore = null;
    $bestBme = null;
    foreach ($trees as $tree) {
        $entry = (object) ['tree' => $tree, 'score' => $objective($tree), 'bme' => bme($tree, $matrix),
            'newick' => newick($tree, $outgroup, $names), 'splits' => splitSet($tree, $outgroup)];
        $entries[] = $entry;
        $histogram[$entry->score] = ($histogram[$entry->score] ?? 0) + 1;
        $bestScore = $bestScore === null ? $entry->score : min($bestScore, $entry->score);
        if ($bestBme === null || $entry->bme < $bestBme->bme || ($entry->bme === $bestBme->bme && strcmp($entry->newick, $bestBme->newick) < 0)) {
            $bestBme = $entry;
        }
    }
    $optimal = array_values(array_filter($entries, fn($entry) => $entry->score === $bestScore));
    usort($optimal, fn($a, $b) => strcmp($a->newick, $b->newick));
    $strict = $optimal[0]->splits;
    foreach ($optimal as $entry) {
        $strict = array_intersect_key($strict, $entry->splits);
    }
    $second = null;
    foreach ($entries as $entry) {
        if ($entry !== $bestBme && ($second === null || $entry->bme < $second)) {
            $second = $entry->bme;
        }
    }
    $heuristicStart = stepwise($taxa, $count, $outgroup, $objective);
    $heuristic = hillClimb($heuristicStart->tree, $heuristicStart->value, $outgroup, $objective);
    $strictTree = consensus($strict, $taxa, $count, $outgroup);
    return (object) ['taxa' => $taxa, 'entries' => $entries, 'histogram' => $histogram, 'bestScore' => $bestScore,
        'optimal' => $optimal, 'bestBme' => $bestBme, 'second' => $second, 'heuristic' => $heuristic, 'strict' => $strictTree];
}

function likelihood(object $tree, int $outgroup, array $names, array $encoded): object
{
    $rooted = orderedRoot($tree, $outgroup, $names);
    $transitions = [];
    foreach ($rooted->order as $node) {
        if ($node !== $rooted->root) {
            $e = exp(-(4 * $rooted->lengths[$node]) / 3);
            $transitions[$node] = [1 / 4 + (3 / 4) * $e, 1 / 4 - (1 / 4) * $e];
        }
    }
    $sites = [];
    $total = 0.0;
    for ($c = 0; $c < count($encoded[0]); $c++) {
        $partial = [];
        $rootValues = [];
        for ($i = count($rooted->order) - 1; $i >= 0; $i--) {
            $node = $rooted->order[$i];
            $values = [1.0, 1.0, 1.0, 1.0];
            for ($x = 0; $x < 4; $x++) {
                if ($node < $tree->count) {
                    $values[$x] = ($encoded[$node][$c] & (1 << $x)) !== 0 ? 1.0 : 0.0;
                } else {
                    foreach ($rooted->children[$node] as $child) {
                        $values[$x] *= $partial[$child][$x];
                    }
                }
            }
            if ($node === $rooted->root) {
                $rootValues = $values;
            } else {
                [$same, $different] = $transitions[$node];
                $adjusted = [0.0, 0.0, 0.0, 0.0];
                for ($x = 0; $x < 4; $x++) {
                    for ($y = 0; $y < 4; $y++) {
                        $adjusted[$x] += ($x === $y ? $same : $different) * $values[$y];
                    }
                }
                $partial[$node] = $adjusted;
            }
        }
        $probability = 0.0;
        for ($x = 0; $x < 4; $x++) {
            $probability += (1 / 4) * $rootValues[$x];
        }
        $value = log($probability);
        $sites[] = $value;
        $total += $value;
    }
    return (object) compact('sites', 'total');
}

function rf(array $first, array $second): int
{
    return count(array_diff_key($first, $second)) + count(array_diff_key($second, $first));
}

function resample(array $taxa, array $all, object $main, object $params, int $outgroup, int $length): object
{
    $support = [];
    $replicates = [];
    $state = $params->seed;
    for ($b = 1; $b <= $params->replicates; $b++) {
        $weights = array_fill(0, $length, 0);
        for ($c = 0; $c < $length; $c++) {
            $state = (48271 * $state) % 2147483647;
            $weights[$state % $length]++;
        }
        $pairs = tallyPairs($taxa, $weights);
        $matrix = buildMatrix(count($taxa), $pairs, $params->model, $params->saturation)->matrix;
        $tree = neighborJoining($matrix, $all, count($taxa));
        $splits = splitSet($tree, $outgroup);
        foreach ($splits as $mask => $unused) {
            $support[$mask] = ($support[$mask] ?? 0) + 1;
        }
        $replicates[] = (object) ['number' => $b, 'distinct' => count(array_filter($weights, fn($weight) => $weight > 0)), 'rf' => rf($splits, $main->splits)];
    }
    $majority = [];
    foreach ($support as $mask => $value) {
        if (2 * $value > $params->replicates) {
            $majority[$mask] = true;
        }
    }
    $jackknife = [];
    foreach ($all as $taxon) {
        if ($taxon === $outgroup) {
            continue;
        }
        $remaining = array_values(array_filter($all, fn($i) => $i !== $taxon));
        $tree = neighborJoining($main->matrix, $remaining, count($taxa));
        $restricted = [];
        foreach ($main->splits as $mask => $unused) {
            $reduced = $mask & ~(1 << $taxon);
            $size = bitCount($reduced);
            if ($size >= 2 && $size <= count($taxa) - 3) {
                $restricted[$reduced] = true;
            }
        }
        $jackknife[] = (object) ['taxon' => $taxon, 'rf' => rf(splitSet($tree, $outgroup), $restricted)];
    }
    $tree = consensus($majority, $all, count($taxa), $outgroup);
    return (object) compact('support', 'replicates', 'jackknife', 'tree');
}

function quartetTopologies(array $splits, int $count): array
{
    $result = [];
    for ($a = 0; $a < $count; $a++) {
        for ($b = $a + 1; $b < $count; $b++) {
            for ($c = $b + 1; $c < $count; $c++) {
                for ($d = $c + 1; $d < $count; $d++) {
                    $partitions = [[$a, $b, $c, $d], [$a, $c, $b, $d], [$a, $d, $b, $c]];
                    $topology = 0;
                    foreach ($partitions as $i => [$p, $q, $r, $s]) {
                        $first = (1 << $p) | (1 << $q);
                        $second = (1 << $r) | (1 << $s);
                        foreach ($splits as $mask => $unused) {
                            if ((($mask & $first) === $first && ($mask & $second) === 0)
                                || (($mask & $second) === $second && ($mask & $first) === 0)) {
                                $topology = $i + 1;
                                break 2;
                            }
                        }
                    }
                    $result[] = $topology;
                }
            }
        }
    }
    return $result;
}

function sortedMasks(array $masks, int $count): array
{
    $values = array_keys($masks);
    usort($values, fn($a, $b) => strcmp(symbols($a, $count), symbols($b, $count)));
    return $values;
}

function matrixLines(array $matrix, array $names): array
{
    $width = max(array_map('strlen', $names));
    $lines = [];
    foreach ($names as $i => $name) {
        $values = array_map(fn($value) => realNumber($value, 5), $matrix[$i]);
        $lines[] = str_pad($name, $width, ' ') . ' ' . implode(' ', $values);
    }
    return $lines;
}

function distanceReport(array $pairs, array $models, object $chosen, object $me, object $exhaustive, array $names): array
{
    $lines = [];
    $sites = $transitions = $transversions = 0;
    foreach ($pairs as $pair) {
        $lines[] = 'PAIR ' . $names[$pair->i] . ' ' . $names[$pair->j] . ' sites ' . $pair->n . ' transitions ' . $pair->s . ' transversions ' . $pair->v;
        $sites += $pair->n;
        $transitions += $pair->s;
        $transversions += $pair->v;
    }
    $lines[] = 'TOTAL sites ' . $sites . ' transitions ' . $transitions . ' transversions ' . $transversions;
    foreach ($models as $model) {
        $lines[] = '';
        $lines[] = 'MODEL ' . $model->model;
        $lines = array_merge($lines, matrixLines($model->matrix, $names));
        foreach ($model->saturated as $pair) {
            $lines[] = 'SATURATED ' . $names[$pair->i] . ' ' . $names[$pair->j] . ' sites ' . $pair->n;
        }
    }
    $lines[] = '';
    $lines[] = 'PATRISTIC ' . $chosen->name;
    $lines = array_merge($lines, matrixLines($chosen->patristic, $names));
    $lines[] = '';
    $lines[] = 'ME start ' . $chosen->name . ' length ' . realNumber($chosen->bme, 5);
    foreach ($me->moves as $move) {
        $lines[] = 'NNI edge ' . symbols($move->mask, count($names)) . ' swap ' . $move->swap . ' length ' . realNumber($move->value, 5);
    }
    $lines[] = 'ME moves ' . count($me->moves) . ' evaluated ' . $me->evaluated . ' length ' . realNumber($me->value, 5);
    $lines[] = 'EXHAUSTIVE taxa ' . count($exhaustive->taxa) . ' trees ' . count($exhaustive->entries) . ' best ' . realNumber($exhaustive->bestBme->bme, 5) . ' second ' . realNumber($exhaustive->second, 5);
    $lines[] = 'BEST ' . $exhaustive->bestBme->newick . ' parsimony ' . $exhaustive->bestBme->score;
    return $lines;
}

function parsimonyReport(array $models, object $bounds, object $added, object $mp, object $ancestors, object $exhaustive, array $names, int $outgroup, int $length): array
{
    $M = $bounds->minimum;
    $G = $bounds->maximum;
    $statistics = fn($score) => 'score ' . $score . ' ci ' . realNumber($M / $score, 4) . ' ri ' . realNumber(($G - $score) / ($G - $M), 4);
    $lines = ['BOUNDS minimum ' . $M . ' maximum ' . $G];
    foreach ($models as $model) {
        $lines[] = 'TREE ' . $model->name . ' ' . $statistics($model->parsimony->total);
    }
    $lines[] = 'START ' . implode(' ', array_map(fn($i) => $names[$i], $added->first)) . ' score ' . $added->initial;
    foreach ($added->additions as $addition) {
        $lines[] = 'ADD ' . $names[$addition->taxon] . ' edge ' . symbols($addition->mask, count($names)) . ' score ' . $addition->value . ' ties ' . $addition->ties;
    }
    $lines[] = 'STEPWISE score ' . $added->value . ' evaluated ' . $added->evaluated;
    foreach ($mp->moves as $move) {
        $lines[] = 'NNI edge ' . symbols($move->mask, count($names)) . ' swap ' . $move->swap . ' score ' . $move->value;
    }
    $lines[] = 'SEARCH moves ' . count($mp->moves) . ' evaluated ' . $mp->evaluated . ' score ' . $mp->value;
    $lines[] = 'TREE MP ' . $statistics($mp->value);
    $lines[] = 'MP ' . newick($mp->tree, $outgroup, $names, true);
    $histogram = array_fill(0, max($ancestors->columns) + 1, 0);
    $homoplasy = 0;
    for ($c = 0; $c < $length; $c++) {
        $histogram[$ancestors->columns[$c]]++;
        if ($ancestors->columns[$c] > $bounds->minima[$c]) {
            $homoplasy++;
        }
    }
    foreach ($histogram as $changes => $columns) {
        $lines[] = 'CHANGES ' . $changes . ' columns ' . $columns;
    }
    $lines[] = 'HOMOPLASY columns ' . $homoplasy . ' extra ' . ($mp->value - $M);
    $nodes = array_keys($ancestors->ancestors);
    usort($nodes, fn($a, $b) => strcmp(symbols($ancestors->rooted->masks[$a], count($names)), symbols($ancestors->rooted->masks[$b], count($names))));
    foreach ($nodes as $node) {
        $lines[] = 'ANCESTOR ' . symbols($ancestors->rooted->masks[$node], count($names)) . ' ' . $ancestors->ancestors[$node];
    }
    $lines[] = '';
    $lines[] = 'EXHAUSTIVE taxa ' . count($exhaustive->taxa) . ' trees ' . count($exhaustive->entries) . ' best ' . $exhaustive->bestScore . ' optimal ' . count($exhaustive->optimal);
    $scores = $exhaustive->histogram;
    ksort($scores, SORT_NUMERIC);
    foreach ($scores as $score => $trees) {
        $lines[] = 'SCORE ' . $score . ' trees ' . $trees;
    }
    foreach ($exhaustive->optimal as $entry) {
        $lines[] = 'OPTIMAL ' . $entry->newick . ' bme ' . realNumber($entry->bme, 5);
    }
    $lines[] = 'STRICT ' . newick($exhaustive->strict, $outgroup, $names);
    $lines[] = 'HEURISTIC score ' . $exhaustive->heuristic->value . ' optimal ' . ($exhaustive->heuristic->value === $exhaustive->bestScore ? 'yes' : 'no');
    return $lines;
}

function likelihoodReport(array $models, object $chosen, object $patterns, int $length, int $lowSites): array
{
    $lines = ['LIKELIHOOD columns ' . $length . ' patterns ' . count($patterns->distinct)];
    foreach ($models as $model) {
        $lines[] = 'TREE ' . $model->name . ' loglik ' . realNumber($model->likelihood->total, 4) . ' per_site ' . realNumber($model->likelihood->total / $length, 4);
    }
    for ($a = 0; $a < count($models); $a++) {
        for ($b = $a + 1; $b < count($models); $b++) {
            $deltas = [];
            $difference = 0.0;
            for ($c = 0; $c < $length; $c++) {
                $delta = $models[$a]->likelihood->sites[$c] - $models[$b]->likelihood->sites[$c];
                $deltas[] = $delta;
                $difference += $delta;
            }
            $mean = $difference / $length;
            $squares = 0.0;
            foreach ($deltas as $delta) {
                $error = $delta - $mean;
                $squares += $error * $error;
            }
            $se = sqrt(($length / ($length - 1)) * $squares);
            $lines[] = 'KH ' . $models[$a]->name . ' ' . $models[$b]->name . ' difference ' . realNumber($difference, 4) . ' se ' . realNumber($se, 4) . ' z ' . realNumber($difference / $se, 4);
        }
    }
    $selected = range(0, $length - 1);
    usort($selected, fn($a, $b) => ((float) realNumber($chosen->likelihood->sites[$a], 4) <=> (float) realNumber($chosen->likelihood->sites[$b], 4)) ?: ($a <=> $b));
    $lines[] = 'LOWEST ' . $chosen->name . ' sites ' . $lowSites;
    foreach (array_slice($selected, 0, $lowSites) as $c) {
        $lines[] = 'SITE ' . ($c + 1) . ' loglik ' . realNumber($chosen->likelihood->sites[$c], 4) . ' changes ' . $chosen->parsimony->columns[$c] . ' pattern ' . $patterns->columns[$c];
    }
    return $lines;
}

function bootstrapReport(object $sampled, object $chosen, object $params, array $names, int $outgroup): array
{
    $lines = ['BOOTSTRAP model ' . $params->model . ' replicates ' . $params->replicates . ' seed ' . $params->seed];
    $identical = 0;
    foreach ($sampled->replicates as $replicate) {
        $lines[] = 'REPLICATE ' . $replicate->number . ' distinct ' . $replicate->distinct . ' rf ' . $replicate->rf;
        $identical += (int) ($replicate->rf === 0);
    }
    $lines[] = 'IDENTICAL ' . $identical;
    foreach (sortedMasks($chosen->splits, count($names)) as $mask) {
        $lines[] = 'SUPPORT ' . symbols($mask, count($names)) . ' ' . ($sampled->support[$mask] ?? 0);
    }
    $splits = array_keys($sampled->support);
    usort($splits, fn($a, $b) => ($sampled->support[$b] <=> $sampled->support[$a]) ?: strcmp(symbols($a, count($names)), symbols($b, count($names))));
    foreach ($splits as $mask) {
        $lines[] = 'SPLIT ' . symbols($mask, count($names)) . ' ' . $sampled->support[$mask];
    }
    $lines[] = 'CONSENSUS ' . newick($sampled->tree, $outgroup, $names, false, $sampled->support);
    foreach ($sampled->jackknife as $item) {
        $lines[] = 'JACKKNIFE ' . $names[$item->taxon] . ' rf ' . $item->rf;
    }
    return $lines;
}

function clockReport(array $taxa, array $ingroup, int $outgroup, object $chosen, int $length): array
{
    $pairs = [];
    $rejected = 0;
    for ($a = 0; $a < count($ingroup); $a++) {
        for ($b = $a + 1; $b < count($ingroup); $b++) {
            $i = $ingroup[$a];
            $j = $ingroup[$b];
            $m1 = $m2 = 0;
            for ($c = 0; $c < $length; $c++) {
                $x = $taxa[$i]->sequence[$c];
                $y = $taxa[$j]->sequence[$c];
                $o = $taxa[$outgroup]->sequence[$c];
                if (strpos(LETTERS, $x) === false || strpos(LETTERS, $y) === false || strpos(LETTERS, $o) === false || $x === $y) {
                    continue;
                }
                if ($y === $o) {
                    $m1++;
                }
                if ($x === $o) {
                    $m2++;
                }
            }
            $difference = $m1 - $m2;
            $reject = 1000 * $difference * $difference > 3841 * ($m1 + $m2);
            $rejected += (int) $reject;
            $chi = $m1 + $m2 > 0 ? realNumber($difference * $difference / ($m1 + $m2), 4) : '-';
            $pairs[] = 'RRT ' . $taxa[$i]->name . ' ' . $taxa[$j]->name . ' m1 ' . $m1 . ' m2 ' . $m2 . ' chi2 ' . $chi . ' ' . ($reject ? 'reject' : 'ok');
        }
    }
    $root = rootTree($chosen->tree, $outgroup)->root;
    $tips = [];
    $total = 0.0;
    foreach ($ingroup as $taxon) {
        $distance = pathDistance($chosen->tree, $root, $taxon);
        $tips[] = $distance;
        $total += $distance;
    }
    $mean = $total / count($tips);
    $squares = 0.0;
    foreach ($tips as $distance) {
        $difference = $distance - $mean;
        $squares += $difference * $difference;
    }
    $sd = sqrt($squares / (count($tips) - 1));
    $lines = array_merge(['RELATIVE_RATE outgroup ' . $taxa[$outgroup]->name . ' pairs ' . count($pairs) . ' rejected ' . $rejected], $pairs);
    $lines[] = 'ROOT_TO_TIP ' . $chosen->name . ' mean ' . realNumber($mean, 5) . ' sd ' . realNumber($sd, 5) . ' cv ' . realNumber($sd / $mean, 4);
    foreach ($ingroup as $i => $taxon) {
        $lines[] = 'TIP ' . $taxa[$taxon]->name . ' ' . realNumber($tips[$i], 5);
    }
    return $lines;
}

function comparisonReport(array $methods, object $chosen, object $mp, object $sampled, int $outgroup, array $names, int $length): array
{
    $lines = [];
    $clades = [];
    foreach ($methods as $i => $method) {
        $supported = 0;
        foreach ($method->splits as $mask => $unused) {
            $clades[$mask] = true;
            if (2 * ($sampled->support[$mask] ?? 0) > count($sampled->replicates)) {
                $supported++;
            }
        }
        $treeLength = $negative = $sse = $loglik = '-';
        if ($i < 3) {
            $total = 0.0;
            foreach (branches($method->tree, $outgroup) as $edge) {
                $total += $edge->length;
            }
            $treeLength = realNumber($total, 5);
            $negative = $method->tree->negative;
            $residual = 0.0;
            for ($a = 0; $a < count($names); $a++) {
                for ($b = $a + 1; $b < count($names); $b++) {
                    $difference = $method->matrix[$a][$b] - $method->patristic[$a][$b];
                    $residual += $difference * $difference;
                }
            }
            $sse = realNumber($residual, 6);
            $loglik = realNumber($method->likelihood->total, 4);
        } elseif ($i === 4) {
            $treeLength = realNumber($method->parsimony->total / $length, 5);
        }
        $parsimony = $i === 5 ? '-' : $method->parsimony->total;
        $bmeValue = $i === 5 ? '-' : realNumber($method->bme, 5);
        $lines[] = 'TREE ' . $method->name . ' splits ' . count($method->splits) . ' supported ' . $supported . ' parsimony ' . $parsimony
            . ' bme ' . $bmeValue . ' length ' . $treeLength . ' negative ' . $negative . ' sse ' . $sse . ' loglik ' . $loglik;
    }
    $lines[] = 'RF ' . implode(' ', METHODS);
    foreach ($methods as $method) {
        $distances = [];
        foreach ($methods as $other) {
            $distances[] = rf($method->splits, $other->splits);
        }
        $lines[] = $method->name . ' ' . implode(' ', $distances);
    }
    $quartets = array_map(fn($method) => quartetTopologies($method->splits, count($names)), $methods);
    $lines[] = 'QUARTET ' . implode(' ', METHODS);
    foreach ($methods as $i => $method) {
        $counts = [];
        foreach ($quartets as $other) {
            $count = 0;
            foreach ($other as $q => $topology) {
                if ($quartets[$i][$q] !== $topology) {
                    $count++;
                }
            }
            $counts[] = $count;
        }
        $lines[] = $method->name . ' ' . implode(' ', $counts);
    }
    $lengths = [];
    foreach (branches($chosen->tree, $outgroup) as $edge) {
        $lengths[$edge->mask] = $edge->length;
    }
    foreach (sortedMasks($clades, count($names)) as $mask) {
        $marks = '';
        foreach ($methods as $method) {
            $marks .= isset($method->splits[$mask]) ? '+' : '-';
        }
        $branchLength = isset($lengths[$mask]) ? realNumber($lengths[$mask], 5) : '-';
        $changes = $mp->branchChanges[$mask] ?? '-';
        $lines[] = 'CLADE ' . symbols($mask, count($names)) . ' support ' . ($sampled->support[$mask] ?? 0) . ' trees ' . $marks . ' length ' . $branchLength . ' changes ' . $changes;
    }
    return $lines;
}

function hypothesisReport(array $methods, object $sampled, object $exhaustive, array $names, array $ingroup, int $outgroup): array
{
    $lines = [];
    $indices = [];
    foreach ($names as $i => $name) {
        $indices[$name] = $i;
    }
    $allIngroup = $exhaustiveIngroup = 0;
    foreach ($ingroup as $taxon) {
        $allIngroup |= 1 << $taxon;
    }
    foreach ($exhaustive->taxa as $taxon) {
        if ($taxon !== $outgroup) {
            $exhaustiveIngroup |= 1 << $taxon;
        }
    }
    foreach (file('input/clades.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $taxa = explode(' ', $line);
        $name = array_shift($taxa);
        $unknown = null;
        foreach ($taxa as $taxon) {
            if (!array_key_exists($taxon, $indices)) {
                $unknown = $taxon;
                break;
            }
        }
        if ($unknown !== null) {
            $lines[] = 'INVALID ' . $name . ' unknown taxon ' . $unknown;
            continue;
        }
        if (in_array($names[$outgroup], $taxa, true)) {
            $lines[] = 'INVALID ' . $name . ' contains outgroup';
            continue;
        }
        $mask = 0;
        foreach ($taxa as $taxon) {
            $mask |= 1 << $indices[$taxon];
        }
        $lines[] = 'CLADE ' . $name . ' taxa ' . count($taxa) . ' support ' . ($sampled->support[$mask] ?? 0);
        foreach ($methods as $method) {
            $common = $allIngroup;
            foreach ($method->splits as $candidate => $unused) {
                if (($candidate & $mask) === $mask && bitCount($candidate) < bitCount($common)) {
                    $common = $candidate;
                }
            }
            $intruders = [];
            foreach ($ingroup as $taxon) {
                if (($common & (1 << $taxon)) !== 0 && ($mask & (1 << $taxon)) === 0) {
                    $intruders[] = $names[$taxon];
                }
            }
            $lines[] = 'TEST ' . $name . ' ' . $method->name . ' monophyletic ' . ($common === $mask ? 'yes' : 'no')
                . ' mrca ' . bitCount($common) . ' intruders ' . (count($intruders) ? implode(',', $intruders) : '-');
        }
        $subset = $mask & $exhaustiveIngroup;
        $count = bitCount($subset);
        if ($count < 2 || $count >= bitCount($exhaustiveIngroup)) {
            $lines[] = 'SUBSET ' . $name . ' untestable';
            continue;
        }
        $minima = [(object) ['score' => null, 'bme' => null], (object) ['score' => null, 'bme' => null]];
        foreach ($exhaustive->entries as $entry) {
            $bucket = $minima[isset($entry->splits[$subset]) ? 0 : 1];
            if ($bucket->score === null || $entry->score < $bucket->score) {
                $bucket->score = $entry->score;
            }
            if ($bucket->bme === null || $entry->bme < $bucket->bme) {
                $bucket->bme = $entry->bme;
            }
        }
        $lines[] = 'SUBSET ' . $name . ' taxa ' . $count . ' with ' . $minima[0]->score . ' without ' . $minima[1]->score
            . ' bme_with ' . realNumber($minima[0]->bme, 5) . ' bme_without ' . realNumber($minima[1]->bme, 5);
    }
    return $lines;
}

function main(): void
{
    $params = parameters();
    $records = readFasta('input/alignment.fasta');
    $data = acceptRecords($records, $params);
    $taxa = $data->taxa;
    $length = $data->length;
    $names = array_map(fn($taxon) => $taxon->name, $taxa);
    $count = count($taxa);
    $all = range(0, $count - 1);
    $outgroup = array_search($params->outgroup, $names, true);
    $ingroup = array_values(array_filter($all, fn($i) => $i !== $outgroup));
    $encoded = encode($taxa);
    $patterns = patterns($taxa, $length);
    $columns = classifyColumns($taxa, $length);
    $pairs = tallyPairs($taxa, array_fill(0, $length, 1));
    $models = [];
    foreach (MODELS as $model) {
        $result = buildMatrix($count, $pairs, $model, $params->saturation);
        $tree = neighborJoining($result->matrix, $all, $count);
        $models[] = (object) ['matrix' => $result->matrix, 'saturated' => $result->saturated, 'model' => $model, 'name' => 'NJ_' . $model,
            'tree' => $tree, 'splits' => splitSet($tree, $outgroup), 'parsimony' => parsimonyScore($tree, $encoded, $outgroup),
            'patristic' => patristic($tree), 'likelihood' => likelihood($tree, $outgroup, $names, $encoded)];
    }
    $chosen = $models[array_search($params->model, MODELS, true)];
    foreach ($models as $model) {
        $model->bme = bme($model->tree, $chosen->matrix);
    }
    $objective = fn($tree) => parsimonyScore($tree, $encoded, $outgroup)->total;
    $me = hillClimb($chosen->tree, $chosen->bme, $outgroup, fn($tree) => bme($tree, $chosen->matrix));
    $added = stepwise(array_merge([$outgroup], $ingroup), $count, $outgroup, $objective);
    $mp = hillClimb($added->tree, $added->value, $outgroup, $objective);
    $ancestors = reconstruct($mp->tree, $encoded, $outgroup);
    $exhaustiveTaxa = [$outgroup];
    foreach ($ingroup as $taxon) {
        if (in_array($names[$taxon], $params->exhaustive, true)) {
            $exhaustiveTaxa[] = $taxon;
        }
    }
    $exhaustive = exhaustiveSearch($exhaustiveTaxa, $count, $outgroup, $names, $objective, $chosen->matrix);
    $sampled = resample($taxa, $all, $chosen, $params, $outgroup, $length);
    $methods = array_merge($models, [
        (object) ['name' => 'ME', 'tree' => $me->tree, 'parsimony' => parsimonyScore($me->tree, $encoded, $outgroup), 'bme' => $me->value],
        (object) ['name' => 'MP', 'tree' => $mp->tree, 'parsimony' => $ancestors, 'bme' => bme($mp->tree, $chosen->matrix)],
        (object) ['name' => 'CONSENSUS', 'tree' => $sampled->tree],
    ]);
    for ($i = 3; $i < count($methods); $i++) {
        $methods[$i]->splits = splitSet($methods[$i]->tree, $outgroup);
    }
    writeLines('summary.txt', alignmentSummary($records, $data, $patterns, $columns));
    writeLines('distances.txt', distanceReport($pairs, $models, $chosen, $me, $exhaustive, $names));
    $newicks = [];
    foreach ($methods as $i => $method) {
        $newicks[] = $method->name . ' ' . newick($method->tree, $outgroup, $names, $i < 3 || $i === 4, $i === 5 ? $sampled->support : null);
    }
    writeLines('trees.nwk', $newicks);
    $diagrams = [];
    foreach ($methods as $method) {
        if (count($diagrams)) {
            $diagrams[] = '';
        }
        $diagrams[] = 'TREE ' . $method->name;
        $diagrams = array_merge($diagrams, cladogram($method->tree, $outgroup, $names, $sampled->support));
    }
    writeLines('cladograms.txt', $diagrams);
    writeLines('parsimony.txt', parsimonyReport($models, scoreBounds($encoded), $added, $mp, $ancestors, $exhaustive, $names, $outgroup, $length));
    writeLines('likelihood.txt', likelihoodReport($models, $chosen, $patterns, $length, $params->lowSites));
    writeLines('bootstrap.txt', bootstrapReport($sampled, $chosen, $params, $names, $outgroup));
    writeLines('clock.txt', clockReport($taxa, $ingroup, $outgroup, $chosen, $length));
    writeLines('comparison.txt', comparisonReport($methods, $chosen, $ancestors, $sampled, $outgroup, $names, $length));
    writeLines('hypotheses.txt', hypothesisReport($methods, $sampled, $exhaustive, $names, $ingroup, $outgroup));
}

main();
