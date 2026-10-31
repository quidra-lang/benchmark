<?php
declare(strict_types=1);

namespace SportsRatings;

final class EloRun
{
    public array $expected = [];
    public array $changes = [];
    public array $roundRatings = [];
    public function __construct(public array $ratings) {}
}

function expectedScore(float $home, float $away, int $advantage): float
{
    return 1 / (1 + 10 ** (($away - $home - $advantage) / 400));
}

function runElo(int $teamCount, array $matches, int $kFactor, int $advantage, int $initial): EloRun
{
    $run = new EloRun(array_fill(0, $teamCount, (float)$initial));
    foreach ($matches as $position => $match) {
        $home = $run->ratings[$match->home];
        $away = $run->ratings[$match->away];
        $expected = expectedScore($home, $away, $advantage);
        $goals = abs($match->margin);
        $weight = 1.0;
        if ($goals > 0) {
            $difference = $match->margin > 0 ? $home + $advantage - $away : $away - $home - $advantage;
            $weight = log($goals + 1) * 2.2 / (0.001 * $difference + 2.2);
        }
        $change = $kFactor * $weight * ($match->y - $expected);
        $run->ratings[$match->home] = $home + $change;
        $run->ratings[$match->away] = $away - $change;
        $run->expected[] = $expected;
        $run->changes[] = $change;
        if ($position + 1 === count($matches) || $matches[$position + 1]->round !== $match->round) {
            $run->roundRatings[] = $run->ratings;
        }
    }
    return $run;
}
