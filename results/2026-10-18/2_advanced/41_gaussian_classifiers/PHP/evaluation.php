<?php

function ev_fraction($numerator, $denominator)
{
    if ($denominator === 0) return null;
    $a = abs($numerator);
    $b = $denominator;
    while ($b !== 0) {
        $next = $a % $b;
        $a = $b;
        $b = $next;
    }
    return [intdiv($numerator, $a), intdiv($denominator, $a)];
}

function ev_add_fractions($first, $second)
{
    return ev_fraction($first[0] * $second[1] + $second[0] * $first[1], $first[1] * $second[1]);
}

function ev_confusion($rows, $predicted, $classCount)
{
    $table = array_fill(0, $classCount, array_fill(0, $classCount, 0));
    foreach ($rows as $i => $row) $table[$row['class']][$predicted[$i]]++;
    $support = array_fill(0, $classCount, 0);
    $decided = array_fill(0, $classCount, 0);
    $correct = 0;
    for ($a = 0; $a < $classCount; $a++) {
        for ($b = 0; $b < $classCount; $b++) {
            $support[$a] += $table[$a][$b];
            $decided[$b] += $table[$a][$b];
        }
        $correct += $table[$a][$a];
    }
    $classes = [];
    $recalls = [0, 1];
    $macro = 0.0;
    $expected = 0;
    for ($k = 0; $k < $classCount; $k++) {
        $tp = $table[$k][$k];
        $recall = ev_fraction($tp, $support[$k]);
        $classes[] = ['support' => $support[$k], 'recall' => $recall,
            'precision' => ev_fraction($tp, $decided[$k]), 'f1' => ev_fraction(2 * $tp, $support[$k] + $decided[$k])];
        $recalls = ev_add_fractions($recalls, $recall);
        $macro += (2 * $tp) / ($support[$k] + $decided[$k]);
        $expected += $support[$k] * $decided[$k];
    }
    $count = count($rows);
    return ['table' => $table, 'classes' => $classes, 'correct' => $correct,
        'accuracy' => ev_fraction($correct, $count), 'balanced' => ev_fraction($recalls[0], $recalls[1] * $classCount),
        'kappa' => ev_fraction($count * $correct - $expected, $count * $count - $expected), 'macroF1' => $macro / $classCount];
}

function ev_mcnemar($rows, $first, $second)
{
    $b01 = 0;
    $b10 = 0;
    foreach ($rows as $i => $row) {
        $a = $first[$i] === $row['class'];
        $b = $second[$i] === $row['class'];
        if ($a && !$b) $b01++;
        elseif (!$a && $b) $b10++;
    }
    $difference = abs($b01 - $b10) - 1;
    $chi2 = $b01 === $b10 ? 0.0 : $difference * $difference / ($b01 + $b10);
    return ['b01' => $b01, 'b10' => $b10, 'chi2' => $chi2, 'significant' => $chi2 > 3.841];
}

class RandomGenerator
{
    private $state;

    public function __construct($seed)
    {
        $this->state = $seed;
    }

    public function next()
    {
        $this->state = (48271 * $this->state) % 2147483647;
        return $this->state;
    }
}
