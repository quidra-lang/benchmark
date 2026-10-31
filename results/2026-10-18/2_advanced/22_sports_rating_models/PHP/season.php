<?php
declare(strict_types=1);

namespace SportsRatings;

final class Team
{
    public function __construct(public int $index, public string $code, public string $name) {}
}

final class MatchResult
{
    public int $margin;
    public int $y2;
    public float $y;

    public function __construct(public int $round, public int $home, public int $away, public int $homeScore, public int $awayScore, public int $order)
    {
        $this->margin = $homeScore - $awayScore;
        $this->y2 = $homeScore > $awayScore ? 2 : ($homeScore === $awayScore ? 1 : 0);
        $this->y = $this->y2 / 2;
    }
}

final class Settings
{
    public int $winPoints;
    public int $drawPoints;
    public int $formLength;
    public int $closeMargin;
    public float $pythagoreanExponent;
    public int $eloK;
    public int $eloHome;
    public int $eloInitial;
    public array $gridK;
    public array $gridHome;
    public int $btIterations;
    public int $odIterations;
    public int $linkIterations;
    public int $holdoutRound;
    public int $upsets;
    public int $calibrationBins;
    public int $simulations;
    public int $seed;
    public int $topPositions;
    public int $bottomPositions;

    public function __construct(array $values)
    {
        $this->winPoints = (int)$values['WIN_POINTS'][0];
        $this->drawPoints = (int)$values['DRAW_POINTS'][0];
        $this->formLength = (int)$values['FORM_LENGTH'][0];
        $this->closeMargin = (int)$values['CLOSE_MARGIN'][0];
        $this->pythagoreanExponent = (float)$values['PYTHAGOREAN_EXPONENT'][0];
        $this->eloK = (int)$values['ELO_K'][0];
        $this->eloHome = (int)$values['ELO_HOME'][0];
        $this->eloInitial = (int)$values['ELO_INITIAL'][0];
        $this->gridK = array_map('intval', $values['ELO_GRID_K']);
        $this->gridHome = array_map('intval', $values['ELO_GRID_HOME']);
        $this->btIterations = (int)$values['BT_ITERATIONS'][0];
        $this->odIterations = (int)$values['OD_ITERATIONS'][0];
        $this->linkIterations = (int)$values['LINK_ITERATIONS'][0];
        $this->holdoutRound = (int)$values['HOLDOUT_ROUND'][0];
        $this->upsets = (int)$values['UPSETS'][0];
        $this->calibrationBins = (int)$values['CALIBRATION_BINS'][0];
        $this->simulations = (int)$values['SIMULATIONS'][0];
        $this->seed = (int)$values['SIM_SEED'][0];
        $this->topPositions = (int)$values['TOP_POSITIONS'][0];
        $this->bottomPositions = (int)$values['BOTTOM_POSITIONS'][0];
    }
}

function matchesBefore(array $matches, int $round): array
{
    return array_values(array_filter($matches, static fn(MatchResult $match): bool => $match->round < $round));
}

function loadSeason(string $folder): array
{
    $teams = $indices = $matches = $values = [];
    foreach (array_slice(file($folder . '/teams.csv', FILE_IGNORE_NEW_LINES), 1) as $line) {
        [$code, $name] = explode(',', $line);
        $index = count($teams);
        $teams[] = new Team($index, $code, $name);
        $indices['#' . $code] = $index;
    }
    foreach (array_slice(file($folder . '/matches.csv', FILE_IGNORE_NEW_LINES), 1) as $order => $line) {
        [$round, $home, $away, $homeScore, $awayScore] = explode(',', $line);
        $matches[] = new MatchResult((int)$round, $indices['#' . $home], $indices['#' . $away], (int)$homeScore, (int)$awayScore, $order);
    }
    usort($matches, static fn(MatchResult $a, MatchResult $b): int => ($a->round <=> $b->round) ?: ($a->order <=> $b->order));
    foreach (file($folder . '/params.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $fields = explode(' ', $line);
        $values[$fields[0]] = array_slice($fields, 1);
    }
    return [$teams, $matches, new Settings($values)];
}
