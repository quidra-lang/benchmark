<?php
declare(strict_types=1);

namespace SportsRatings;

function bradleyTerry(int $teamCount, array $matches, int $iterations): array
{
    $wins = array_fill(0, $teamCount, 0.0);
    $homeWins = 0.0;
    foreach ($matches as $match) {
        $wins[$match->home] += $match->y;
        $wins[$match->away] += 1 - $match->y;
        $homeWins += $match->y;
    }
    $strengths = array_fill(0, $teamCount, 1.0);
    $theta = 1.0;
    for ($iteration = 0; $iteration < $iterations; $iteration++) {
        $zeta = array_fill(0, $teamCount, 0.0);
        foreach ($matches as $match) {
            $q = $theta * $strengths[$match->home] + $strengths[$match->away];
            $zeta[$match->home] += $theta / $q;
            $zeta[$match->away] += 1 / $q;
        }
        for ($team = 0; $team < $teamCount; $team++) {
            $strengths[$team] = $wins[$team] / $zeta[$team];
        }
        $sum = 0.0;
        foreach ($strengths as $strength) {
            $sum += $strength;
        }
        for ($team = 0; $team < $teamCount; $team++) {
            $strengths[$team] = $strengths[$team] * $teamCount / $sum;
        }
        $denominator = 0.0;
        foreach ($matches as $match) {
            $home = $strengths[$match->home];
            $denominator += $home / ($theta * $home + $strengths[$match->away]);
        }
        $theta = $homeWins / $denominator;
    }
    return [$strengths, $theta];
}

function offenseDefense(int $teamCount, array $matches, int $iterations): array
{
    $points = array_fill(0, $teamCount, array_fill(0, $teamCount, 0));
    foreach ($matches as $match) {
        $points[$match->home][$match->away] += $match->awayScore;
        $points[$match->away][$match->home] += $match->homeScore;
    }
    $offense = array_fill(0, $teamCount, 0.0);
    $defense = array_fill(0, $teamCount, 1.0);
    for ($iteration = 0; $iteration < $iterations; $iteration++) {
        for ($j = 0; $j < $teamCount; $j++) {
            $total = 0.0;
            for ($i = 0; $i < $teamCount; $i++) {
                $total += $points[$i][$j] / $defense[$i];
            }
            $offense[$j] = $total;
        }
        for ($i = 0; $i < $teamCount; $i++) {
            $total = 0.0;
            for ($j = 0; $j < $teamCount; $j++) {
                $total += $points[$i][$j] / $offense[$j];
            }
            $defense[$i] = $total;
        }
    }
    $ratings = [];
    for ($team = 0; $team < $teamCount; $team++) {
        $ratings[] = $offense[$team] / $defense[$team];
    }
    return [$offense, $defense, $ratings];
}
