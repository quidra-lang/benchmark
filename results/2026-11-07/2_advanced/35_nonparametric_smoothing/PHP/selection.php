<?php

function crossValidation(array $actual, array $predictions): ?float
{
    if (in_array(null, $predictions, true)) {
        return null;
    }
    $total = 0.0;
    foreach ($actual as $index => $value) {
        $error = $value - $predictions[$index];
        $total += $error * $error;
    }
    return $total / count($actual);
}

function generalized(array $actual, array $fitted, float $edf): float
{
    $rss = 0.0;
    foreach ($actual as $index => $value) {
        $error = $value - $fitted[$index];
        $rss += $error * $error;
    }
    $tau = 1 - $edf / count($actual);
    return $rss / count($actual) / ($tau * $tau);
}

function selectCandidate(array $candidates): int
{
    $best = -1;
    foreach ($candidates as $index => $candidate) {
        if ($candidate->score !== null && ($best < 0 || $candidate->score < $candidates[$best]->score)) {
            $best = $index;
        }
    }
    return $best;
}
