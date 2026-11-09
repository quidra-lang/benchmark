<?php
declare(strict_types=1);

namespace SportsRatings;

function zeroMatrix(int $size): array { return array_fill(0, $size, array_fill(0, $size, 0.0)); }

function choleskySolve(array $matrix, array $vector): array
{
    $size = count($vector);
    $lower = zeroMatrix($size);
    for ($i = 0; $i < $size; $i++) {
        for ($j = 0; $j <= $i; $j++) {
            $total = 0.0;
            for ($k = 0; $k < $j; $k++) {
                $total += $lower[$i][$k] * $lower[$j][$k];
            }
            $lower[$i][$j] = $j < $i ? ($matrix[$i][$j] - $total) / $lower[$j][$j] : sqrt($matrix[$i][$i] - $total);
        }
    }
    $forward = $solution = array_fill(0, $size, 0.0);
    for ($i = 0; $i < $size; $i++) {
        $total = 0.0;
        for ($k = 0; $k < $i; $k++) {
            $total += $lower[$i][$k] * $forward[$k];
        }
        $forward[$i] = ($vector[$i] - $total) / $lower[$i][$i];
    }
    for ($i = $size - 1; $i >= 0; $i--) {
        $total = 0.0;
        for ($k = $i + 1; $k < $size; $k++) {
            $total += $lower[$k][$i] * $solution[$k];
        }
        $solution[$i] = ($forward[$i] - $total) / $lower[$i][$i];
    }
    return $solution;
}

function gaussianSolve(array $matrix, array $vector): array
{
    $size = count($vector);
    for ($k = 0; $k < $size; $k++) {
        $pivot = $k;
        for ($row = $k + 1; $row < $size; $row++) {
            if (abs($matrix[$row][$k]) > abs($matrix[$pivot][$k])) {
                $pivot = $row;
            }
        }
        [$matrix[$k], $matrix[$pivot]] = [$matrix[$pivot], $matrix[$k]];
        [$vector[$k], $vector[$pivot]] = [$vector[$pivot], $vector[$k]];
        for ($i = $k + 1; $i < $size; $i++) {
            $factor = $matrix[$i][$k] / $matrix[$k][$k];
            for ($j = $k; $j < $size; $j++) {
                $matrix[$i][$j] -= $factor * $matrix[$k][$j];
            }
            $vector[$i] -= $factor * $vector[$k];
        }
    }
    $solution = array_fill(0, $size, 0.0);
    for ($i = $size - 1; $i >= 0; $i--) {
        $total = 0.0;
        for ($j = $i + 1; $j < $size; $j++) {
            $total += $matrix[$i][$j] * $solution[$j];
        }
        $solution[$i] = ($vector[$i] - $total) / $matrix[$i][$i];
    }
    return $solution;
}

function colleyRatings(int $teamCount, array $matches): array
{
    $matrix = zeroMatrix($teamCount);
    $balance = array_fill(0, $teamCount, 0);
    for ($team = 0; $team < $teamCount; $team++) {
        $matrix[$team][$team] = 2.0;
    }
    foreach ($matches as $match) {
        $i = $match->home;
        $j = $match->away;
        $matrix[$i][$i]++;
        $matrix[$j][$j]++;
        $matrix[$i][$j]--;
        $matrix[$j][$i]--;
        if ($match->margin > 0) {
            $balance[$i]++;
            $balance[$j]--;
        } elseif ($match->margin < 0) {
            $balance[$i]--;
            $balance[$j]++;
        }
    }
    $vector = array_map(static fn(int $value): float => 1 + $value / 2, $balance);
    return choleskySolve($matrix, $vector);
}

function masseyRatings(int $teamCount, array $matches): array
{
    $size = $teamCount + 1;
    $last = $teamCount;
    $matrix = zeroMatrix($size);
    $vector = array_fill(0, $size, 0.0);
    foreach ($matches as $match) {
        $i = $match->home;
        $j = $match->away;
        $matrix[$i][$i]++;
        $matrix[$j][$j]++;
        $matrix[$i][$j]--;
        $matrix[$j][$i]--;
        $matrix[$i][$last]++;
        $matrix[$last][$i]++;
        $matrix[$j][$last]--;
        $matrix[$last][$j]--;
        $matrix[$last][$last]++;
        $vector[$i] += $match->margin;
        $vector[$j] -= $match->margin;
        $vector[$last] += $match->margin;
    }
    $matrix[$teamCount - 1] = array_merge(array_fill(0, $teamCount, 1.0), [0.0]);
    $vector[$teamCount - 1] = 0.0;
    $solution = gaussianSolve($matrix, $vector);
    return [array_slice($solution, 0, $teamCount), $solution[$last]];
}
