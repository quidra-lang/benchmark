<?php

function countPair(string $first, string $second, array $weights): object
{
    $n = $s = $v = 0;
    foreach ($weights as $c => $weight) {
        $a = strpos(LETTERS, $first[$c]);
        $b = strpos(LETTERS, $second[$c]);
        if ($a === false || $b === false) {
            continue;
        }
        $n += $weight;
        if ($a === $b) {
            continue;
        }
        if (($a === 0 && $b === 2) || ($a === 2 && $b === 0) || ($a === 1 && $b === 3) || ($a === 3 && $b === 1)) {
            $s += $weight;
        } else {
            $v += $weight;
        }
    }
    return (object) compact('n', 's', 'v');
}

function tallyPairs(array $taxa, array $weights): array
{
    $pairs = [];
    for ($i = 0; $i < count($taxa); $i++) {
        for ($j = $i + 1; $j < count($taxa); $j++) {
            $pair = countPair($taxa[$i]->sequence, $taxa[$j]->sequence, $weights);
            $pair->i = $i;
            $pair->j = $j;
            $pairs[] = $pair;
        }
    }
    return $pairs;
}

function distance(string $model, object $pair, float $saturation): object
{
    $n = $pair->n;
    $s = $pair->s;
    $v = $pair->v;
    $saturated = $n === 0 || ($model === 'JC' && 4 * ($s + $v) >= 3 * $n)
        || ($model === 'K2P' && (2 * $s + $v >= $n || 2 * $v >= $n));
    if ($saturated) {
        return (object) ['value' => $saturation, 'saturated' => true];
    }
    if ($model === 'P') {
        $value = ($s + $v) / $n;
    } elseif ($model === 'JC') {
        $value = -(3 / 4) * log(1 - (4 * ($s + $v)) / (3 * $n));
    } else {
        $value = -(1 / 2) * log(1 - (2 * $s) / $n - $v / $n) - (1 / 4) * log(1 - (2 * $v) / $n);
    }
    return (object) ['value' => $value, 'saturated' => false];
}

function buildMatrix(int $count, array $pairs, string $model, float $saturation): object
{
    $matrix = array_fill(0, $count, array_fill(0, $count, 0.0));
    $saturated = [];
    foreach ($pairs as $pair) {
        $result = distance($model, $pair, $saturation);
        $matrix[$pair->i][$pair->j] = $matrix[$pair->j][$pair->i] = $result->value;
        if ($result->saturated) {
            $saturated[] = $pair;
        }
    }
    return (object) compact('matrix', 'saturated');
}
