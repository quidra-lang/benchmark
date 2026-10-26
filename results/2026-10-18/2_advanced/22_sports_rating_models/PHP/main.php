<?php
declare(strict_types=1);

namespace SportsRatings;

require_once __DIR__ . '/report.php';
require_once __DIR__ . '/season.php';
require_once __DIR__ . '/elo.php';
require_once __DIR__ . '/linear_models.php';
require_once __DIR__ . '/iterative_models.php';
require_once __DIR__ . '/evaluation.php';

const RATING_MODELS = ['elo', 'colley', 'massey', 'bt', 'od', 'winpct'];
const COMPARISON_MODELS = ['standings', 'elo', 'colley', 'massey', 'bt', 'od', 'winpct', 'rpi', 'pythag'];
const LINK_MODELS = ['colley', 'massey', 'od', 'winpct'];
const PREDICTION_MODELS = ['base', 'elo', 'colley', 'massey', 'bt', 'od', 'winpct', 'ensemble'];
const STANDINGS_HEADER = 'pos,team,name,played,won,drawn,lost,scored,conceded,diff,points,home,away,form,streak,close,longest_win,longest_unbeaten,winpct,sos,sos2,rpi,pythag,luck';
const RATINGS_HEADER = 'team,elo,elo_rank,colley,colley_rank,massey,massey_rank,bt,bt_rank,offense,defense,od,od_rank,winpct,winpct_rank,consensus,best_rank,worst_rank';
const HISTORY_HEADER = 'round,team,elo,change,elo_rank,points,position';
const PREDICTIONS_HEADER = 'round,home,away,home_score,away_score,result,base,elo,colley,massey,bt,od,winpct,ensemble';
const PROJECTION_HEADER = 'projected,team,points_now,position_now,remaining_opponent_elo,expected_points,title,top,bottom,final_points,final_position';

function sequentialSum(array $values): float
{
    $total = 0.0;
    foreach ($values as $value) {
        $total += $value;
    }
    return $total;
}

function mean(array $values): float { return sequentialSum($values) / count($values); }
function csvLine(array $fields): string { return implode(',', $fields); }

function joinParts(array $parts): array
{
    $lines = [];
    foreach ($parts as $part) {
        if ($lines !== []) {
            $lines[] = '';
        }
        array_push($lines, ...$part);
    }
    return $lines;
}

function competitionRanks(array $values): array
{
    $ranks = [];
    foreach ($values as $value) {
        $rank = 1;
        foreach ($values as $other) {
            $rank += (int)(compareValues($other, $value) > 0);
        }
        $ranks[] = $rank;
    }
    return $ranks;
}

final class Appearance
{
    public bool $home;
    public int $opponent;
    public int $scored;
    public int $conceded;
    public string $letter;

    public function __construct(public MatchResult $match, int $team)
    {
        $this->home = $match->home === $team;
        $this->opponent = $this->home ? $match->away : $match->home;
        $this->scored = $this->home ? $match->homeScore : $match->awayScore;
        $this->conceded = $this->home ? $match->awayScore : $match->homeScore;
        $this->letter = $this->scored > $this->conceded ? 'W' : ($this->scored === $this->conceded ? 'D' : 'L');
    }
}

function appearancesOf(int $team, array $matches): array
{
    $appearances = [];
    foreach ($matches as $match) {
        if ($match->home === $team || $match->away === $team) {
            $appearances[] = new Appearance($match, $team);
        }
    }
    return $appearances;
}

function recordText(array $appearances): string
{
    $counts = ['W' => 0, 'D' => 0, 'L' => 0];
    foreach ($appearances as $appearance) {
        $counts[$appearance->letter]++;
    }
    return $counts['W'] . '-' . $counts['D'] . '-' . $counts['L'];
}

final class Record
{
    public int $played = 0;
    public int $won = 0;
    public int $drawn = 0;
    public int $lost = 0;
    public int $scored = 0;
    public int $conceded = 0;
    public int $points = 0;

    public function add(int $scored, int $conceded, Settings $settings): void
    {
        $this->played++;
        $this->scored += $scored;
        $this->conceded += $conceded;
        if ($scored > $conceded) {
            $this->won++;
            $this->points += $settings->winPoints;
        } elseif ($scored === $conceded) {
            $this->drawn++;
            $this->points += $settings->drawPoints;
        } else {
            $this->lost++;
        }
    }

    public function difference(): int { return $this->scored - $this->conceded; }
    public function winPercentage(): Fraction { return new Fraction(2 * $this->won + $this->drawn, 2 * $this->played); }
}

function teamRecords(int $teamCount, array $matches, Settings $settings): array
{
    $records = [];
    for ($team = 0; $team < $teamCount; $team++) {
        $records[] = new Record();
    }
    foreach ($matches as $match) {
        $records[$match->home]->add($match->homeScore, $match->awayScore, $settings);
        $records[$match->away]->add($match->awayScore, $match->homeScore, $settings);
    }
    return $records;
}

final class Standings
{
    public array $records;
    public array $h2hPoints;
    public array $h2hDifference;
    public array $order;
    public array $positions;

    public function __construct(public array $teams, array $matches, Settings $settings)
    {
        $teamCount = count($teams);
        $this->records = teamRecords($teamCount, $matches, $settings);
        $inner = array_values(array_filter($matches, fn(MatchResult $match): bool =>
            $this->records[$match->home]->points === $this->records[$match->away]->points));
        $innerRecords = teamRecords($teamCount, $inner, $settings);
        $this->h2hPoints = array_map(static fn(Record $record): int => $record->points, $innerRecords);
        $this->h2hDifference = array_map(static fn(Record $record): int => $record->difference(), $innerRecords);
        $this->order = range(0, $teamCount - 1);
        usort($this->order, function (int $a, int $b): int {
            $first = $this->records[$a];
            $second = $this->records[$b];
            return ($second->points <=> $first->points)
                ?: ($this->h2hPoints[$b] <=> $this->h2hPoints[$a])
                ?: ($this->h2hDifference[$b] <=> $this->h2hDifference[$a])
                ?: ($second->difference() <=> $first->difference())
                ?: ($second->scored <=> $first->scored)
                ?: strcmp($this->teams[$a]->code, $this->teams[$b]->code);
        });
        $this->positions = array_fill(0, $teamCount, 0);
        foreach ($this->order as $index => $team) {
            $this->positions[$team] = $index + 1;
        }
    }

    public function tiedGroups(): array
    {
        $groups = [];
        foreach ($this->order as $team) {
            $last = count($groups) - 1;
            if ($last >= 0 && $this->records[$groups[$last][0]]->points === $this->records[$team]->points) {
                $groups[$last][] = $team;
            } else {
                $groups[] = [$team];
            }
        }
        return array_values(array_filter($groups, static fn(array $group): bool => count($group) > 1));
    }
}

final class Streak
{
    public function __construct(public int $length, public int $first, public int $last) {}
}

function longestStreak(array $appearances, string $letters): Streak
{
    $best = new Streak(0, 0, 0);
    $start = $length = 0;
    foreach ($appearances as $index => $appearance) {
        if (!str_contains($letters, $appearance->letter)) {
            $length = 0;
            continue;
        }
        if ($length === 0) {
            $start = $index;
        }
        $length++;
        if ($length > $best->length) {
            $best = new Streak($length, $appearances[$start]->match->round, $appearance->match->round);
        }
    }
    return $best;
}

function currentStreak(array $appearances): string
{
    $last = $appearances[count($appearances) - 1]->letter;
    $length = 0;
    for ($index = count($appearances) - 1; $index >= 0 && $appearances[$index]->letter === $last; $index--) {
        $length++;
    }
    return $last . $length;
}

final class ModelFit
{
    public EloRun $elo;
    public array $colley;
    public array $massey;
    public float $homeAdvantage;
    public array $strengths;
    public float $homeFactor;
    public array $offense;
    public array $defense;
    public array $od;
    public array $winPercentages;

    public function __construct(int $teamCount, array $matches, Settings $settings)
    {
        $this->elo = runElo($teamCount, $matches, $settings->eloK, $settings->eloHome, $settings->eloInitial);
        $this->colley = colleyRatings($teamCount, $matches);
        [$this->massey, $this->homeAdvantage] = masseyRatings($teamCount, $matches);
        [$this->strengths, $this->homeFactor] = bradleyTerry($teamCount, $matches, $settings->btIterations);
        [$this->offense, $this->defense, $this->od] = offenseDefense($teamCount, $matches, $settings->odIterations);
        $this->winPercentages = array_map(static fn(Record $record): Fraction => $record->winPercentage(), teamRecords($teamCount, $matches, $settings));
    }

    public function feature(string $model, MatchResult $match): float
    {
        $home = $match->home;
        $away = $match->away;
        return match ($model) {
            'colley' => $this->colley[$home] - $this->colley[$away],
            'massey' => $this->massey[$home] - $this->massey[$away],
            'od' => log($this->od[$home]) - log($this->od[$away]),
            default => $this->winPercentages[$home]->real() - $this->winPercentages[$away]->real(),
        };
    }

    public function btProbability(MatchResult $match): float
    {
        $home = $this->homeFactor * $this->strengths[$match->home];
        return $home / ($home + $this->strengths[$match->away]);
    }

    public function predictedMargin(MatchResult $match): float
    {
        return $this->massey[$match->home] - $this->massey[$match->away] + $this->homeAdvantage;
    }
}

final class Prediction
{
    public array $losses;
    public array $briers;
    public array $scores2;

    public function __construct(public MatchResult $match, public array $probabilities, public float $marginError)
    {
        $this->losses = array_map(static fn(float $p): float => logLoss($p, $match->y), $probabilities);
        $this->briers = array_map(static fn(float $p): float => brierScore($p, $match->y), $probabilities);
        $this->scores2 = array_map(static fn(float $p): int => correctness2($p, $match->y), $probabilities);
    }
}

final class ValidationRound
{
    public array $training;
    public ModelFit $fit;
    public float $base;
    public array $links = [];
    public array $predictions = [];

    public function __construct(public int $number, int $teamCount, array $matches, Settings $settings)
    {
        $this->training = matchesBefore($matches, $number);
        $this->fit = new ModelFit($teamCount, $this->training, $settings);
        $results = array_map(static fn(MatchResult $match): float => $match->y, $this->training);
        $total2 = 0;
        foreach ($this->training as $match) {
            $total2 += $match->y2;
        }
        $this->base = $total2 / (2 * count($this->training));
        foreach (LINK_MODELS as $model) {
            $features = array_map(fn(MatchResult $match): float => $this->fit->feature($model, $match), $this->training);
            $this->links[$model] = fitLink($features, $results, $settings->linkIterations);
        }
        foreach ($matches as $match) {
            if ($match->round === $number) {
                $this->predictions[] = $this->predict($match, $settings);
            }
        }
    }

    public function predict(MatchResult $match, Settings $settings): Prediction
    {
        $ratings = $this->fit->elo->ratings;
        $probabilities = ['base' => $this->base];
        $probabilities['elo'] = expectedScore($ratings[$match->home], $ratings[$match->away], $settings->eloHome);
        foreach (LINK_MODELS as $model) {
            [$alpha, $beta] = $this->links[$model];
            $probabilities[$model] = sigma($alpha + $beta * $this->fit->feature($model, $match));
        }
        $probabilities['bt'] = $this->fit->btProbability($match);
        $ensemble = 0.0;
        foreach (RATING_MODELS as $model) {
            $ensemble += $probabilities[$model];
        }
        $probabilities['ensemble'] = $ensemble / count(RATING_MODELS);
        $ordered = array_map(static fn(string $model): float => $probabilities[$model], PREDICTION_MODELS);
        return new Prediction($match, $ordered, $match->margin - $this->fit->predictedMargin($match));
    }
}

final class ModelScores
{
    public array $losses = [];
    public array $briers = [];
    public array $skills = [];
    public array $accuracies = [];
    public array $lossRanking;
    public array $brierRanking;
    public array $accuracyRanking;

    public function __construct(array $predictions)
    {
        foreach (PREDICTION_MODELS as $index => $model) {
            $this->losses[] = mean(array_map(static fn(Prediction $item): float => $item->losses[$index], $predictions));
            $this->briers[] = mean(array_map(static fn(Prediction $item): float => $item->briers[$index], $predictions));
            $correct2 = 0;
            foreach ($predictions as $prediction) {
                $correct2 += $prediction->scores2[$index];
            }
            $this->accuracies[] = new Fraction($correct2, 2 * count($predictions));
        }
        foreach ($this->briers as $brier) {
            $this->skills[] = 1 - $brier / $this->briers[0];
        }
        $this->lossRanking = $this->brierRanking = $this->accuracyRanking = range(0, count(PREDICTION_MODELS) - 1);
        usort($this->lossRanking, fn(int $a, int $b): int => (decimalValue($this->losses[$a], 4) <=> decimalValue($this->losses[$b], 4)) ?: ($a <=> $b));
        usort($this->brierRanking, fn(int $a, int $b): int => (decimalValue($this->briers[$a], 4) <=> decimalValue($this->briers[$b], 4)) ?: ($a <=> $b));
        usort($this->accuracyRanking, fn(int $a, int $b): int => $this->accuracies[$b]->compare($this->accuracies[$a]) ?: ($a <=> $b));
    }
}

final class RandomSequence
{
    public function __construct(private int $state) {}

    public function nextUniform(): float
    {
        $this->state = 48271 * $this->state % 2147483647;
        return $this->state / 2147483647;
    }
}

final class Projection
{
    public Standings $current;
    public array $ratings;
    public array $remaining;
    public array $totalPoints;
    public array $titles;
    public array $tops;
    public array $bottoms;
    public array $order;
    public array $ranks;

    public function __construct(array $teams, array $matches, Settings $settings)
    {
        $teamCount = count($teams);
        $currentMatches = matchesBefore($matches, $settings->holdoutRound);
        $this->current = new Standings($teams, $currentMatches, $settings);
        $this->ratings = runElo($teamCount, $currentMatches, $settings->eloK, $settings->eloHome, $settings->eloInitial)->ratings;
        $this->remaining = array_values(array_filter($matches, static fn(MatchResult $match): bool => $match->round >= $settings->holdoutRound));
        $this->totalPoints = $this->titles = $this->tops = $this->bottoms = array_fill(0, $teamCount, 0);
        $this->simulate($settings);
        $this->order = $this->orderedTeams($this->totalPoints);
        $this->ranks = array_fill(0, $teamCount, 0);
        foreach ($this->order as $index => $team) {
            $this->ranks[$team] = $index + 1;
        }
    }

    private function orderedTeams(array $points): array
    {
        $order = range(0, count($points) - 1);
        usort($order, fn(int $a, int $b): int => ($points[$b] <=> $points[$a]) ?: ($this->current->positions[$a] <=> $this->current->positions[$b]));
        return $order;
    }

    private function simulate(Settings $settings): void
    {
        $teamCount = count($this->totalPoints);
        $probabilities = array_map(fn(MatchResult $match): float => expectedScore($this->ratings[$match->home], $this->ratings[$match->away], $settings->eloHome), $this->remaining);
        $generator = new RandomSequence($settings->seed);
        $bottomPlace = $teamCount - $settings->bottomPositions + 1;
        for ($simulation = 0; $simulation < $settings->simulations; $simulation++) {
            $points = array_map(static fn(Record $record): int => $record->points, $this->current->records);
            foreach ($this->remaining as $index => $match) {
                $winner = $generator->nextUniform() < $probabilities[$index] ? $match->home : $match->away;
                $points[$winner] += $settings->winPoints;
            }
            foreach ($this->orderedTeams($points) as $index => $team) {
                $place = $index + 1;
                $this->totalPoints[$team] += $points[$team];
                $this->titles[$team] += (int)($place === 1);
                $this->tops[$team] += (int)($place <= $settings->topPositions);
                $this->bottoms[$team] += (int)($place >= $bottomPlace);
            }
        }
    }

    public function opponentStrength(int $team): float
    {
        $ratings = [];
        foreach ($this->remaining as $match) {
            if ($match->home === $team) {
                $ratings[] = $this->ratings[$match->away];
            } elseif ($match->away === $team) {
                $ratings[] = $this->ratings[$match->home];
            }
        }
        return mean($ratings);
    }
}

final class LeagueAnalysis
{
    public int $teamCount;
    public int $finalRound;
    public array $appearances = [];
    public Standings $final;
    public ModelFit $fit;
    public array $roundTables = [];
    public array $winStreaks = [];
    public array $unbeatenStreaks = [];
    public array $sos = [];
    public array $sos2 = [];
    public array $rpi = [];
    public array $pythag = [];
    public array $luck = [];
    public array $comparison;
    public array $ranks = [];
    public array $rounds = [];
    public array $predictions = [];
    public ModelScores $scores;
    public Projection $projection;

    public function __construct(public array $teams, public array $matches, public Settings $settings)
    {
        $this->teamCount = count($teams);
        $this->finalRound = $matches[count($matches) - 1]->round;
        foreach ($teams as $team) {
            $this->appearances[] = appearancesOf($team->index, $matches);
        }
        $this->final = new Standings($teams, $matches, $settings);
        $this->fit = new ModelFit($this->teamCount, $matches, $settings);
        for ($number = 1; $number <= $this->finalRound; $number++) {
            $this->roundTables[] = new Standings($teams, matchesBefore($matches, $number + 1), $settings);
        }
        foreach ($this->appearances as $appearances) {
            $this->winStreaks[] = longestStreak($appearances, 'W');
            $this->unbeatenStreaks[] = longestStreak($appearances, 'WD');
        }
        $this->computeIndicators();
        $this->comparison = $this->comparisonValues();
        foreach (RATING_MODELS as $model) {
            $this->ranks[$model] = competitionRanks($this->comparison[$model]);
        }
        for ($number = $settings->holdoutRound; $number <= $this->finalRound; $number++) {
            $validation = new ValidationRound($number, $this->teamCount, $matches, $settings);
            $this->rounds[] = $validation;
            array_push($this->predictions, ...$validation->predictions);
        }
        $this->scores = new ModelScores($this->predictions);
        $this->projection = new Projection($teams, $matches, $settings);
    }

    private function opponentAverage(int $team, array $values): Fraction
    {
        $total = new Fraction(0);
        foreach ($this->appearances[$team] as $appearance) {
            $total = $total->add($values[$appearance->opponent]);
        }
        return $total->divide(new Fraction(count($this->appearances[$team])));
    }

    private function computeIndicators(): void
    {
        for ($team = 0; $team < $this->teamCount; $team++) {
            $this->sos[] = $this->opponentAverage($team, $this->fit->winPercentages);
        }
        for ($team = 0; $team < $this->teamCount; $team++) {
            $this->sos2[] = $this->opponentAverage($team, $this->sos);
        }
        foreach ($this->final->records as $team => $record) {
            $this->rpi[] = $this->fit->winPercentages[$team]->add($this->sos[$team]->multiply(new Fraction(2)))->add($this->sos2[$team])->divide(new Fraction(4));
            $this->pythag[] = 1 / (1 + ($record->conceded / $record->scored) ** $this->settings->pythagoreanExponent);
            $this->luck[] = $this->fit->winPercentages[$team]->real() - $this->pythag[$team];
        }
    }

    private function comparisonValues(): array
    {
        $fit = $this->fit;
        return [
            'standings' => array_map(static fn(int $position): int => -$position, $this->final->positions),
            'elo' => array_map(static fn(float $value): int => decimalValue($value, 2), $fit->elo->ratings),
            'colley' => array_map(static fn(float $value): int => decimalValue($value, 4), $fit->colley),
            'massey' => array_map(static fn(float $value): int => decimalValue($value, 4), $fit->massey),
            'bt' => array_map(static fn(float $value): int => decimalValue($value, 4), $fit->strengths),
            'od' => array_map(static fn(float $value): int => decimalValue($value, 2), $fit->od),
            'winpct' => $fit->winPercentages,
            'rpi' => $this->rpi,
            'pythag' => array_map(static fn(float $value): int => decimalValue($value, 4), $this->pythag),
        ];
    }

    private function code(int $team): string { return $this->teams[$team]->code; }

    public function standingsLines(): array
    {
        $lines = [STANDINGS_HEADER];
        foreach ($this->final->order as $index => $team) {
            $record = $this->final->records[$team];
            $appearances = $this->appearances[$team];
            $home = array_filter($appearances, static fn(Appearance $item): bool => $item->home);
            $away = array_filter($appearances, static fn(Appearance $item): bool => !$item->home);
            $close = array_filter($appearances, fn(Appearance $item): bool => abs($item->scored - $item->conceded) <= $this->settings->closeMargin);
            $form = implode('', array_map(static fn(Appearance $item): string => $item->letter, array_slice($appearances, -$this->settings->formLength)));
            $lines[] = csvLine([
                $index + 1, $this->code($team), $this->teams[$team]->name, $record->played,
                $record->won, $record->drawn, $record->lost, $record->scored, $record->conceded,
                $record->difference(), $record->points, recordText($home), recordText($away),
                $form, currentStreak($appearances), recordText($close), $this->winStreaks[$team]->length,
                $this->unbeatenStreaks[$team]->length, fractionText($this->fit->winPercentages[$team]),
                fixed($this->sos[$team]), fixed($this->sos2[$team]), fixed($this->rpi[$team]),
                fixed($this->pythag[$team]), fixed($this->luck[$team]),
            ]);
        }
        return $lines;
    }

    public function ratingsLines(): array
    {
        $totals = array_fill(0, $this->teamCount, 0);
        foreach (RATING_MODELS as $model) {
            foreach ($this->ranks[$model] as $team => $rank) {
                $totals[$team] += $rank;
            }
        }
        $order = range(0, $this->teamCount - 1);
        usort($order, fn(int $a, int $b): int => ($totals[$a] <=> $totals[$b]) ?: strcmp($this->code($a), $this->code($b)));
        $fit = $this->fit;
        $lines = [RATINGS_HEADER];
        foreach ($order as $team) {
            $ranks = [];
            foreach (RATING_MODELS as $model) {
                $ranks[$model] = $this->ranks[$model][$team];
            }
            $lines[] = csvLine([
                $this->code($team), fixed($fit->elo->ratings[$team], 2), $ranks['elo'],
                fixed($fit->colley[$team]), $ranks['colley'], fixed($fit->massey[$team]), $ranks['massey'],
                fixed($fit->strengths[$team]), $ranks['bt'], fixed($fit->offense[$team], 2),
                fixed($fit->defense[$team]), fixed($fit->od[$team], 2), $ranks['od'],
                fixed($fit->winPercentages[$team]), $ranks['winpct'], $totals[$team], min($ranks), max($ranks),
            ]);
        }
        return $lines;
    }

    public function historyLines(): array
    {
        $lines = [HISTORY_HEADER];
        $previous = array_fill(0, $this->teamCount, (float)$this->settings->eloInitial);
        foreach ($this->roundTables as $index => $standings) {
            $ratings = $this->fit->elo->roundRatings[$index];
            $ranks = competitionRanks(array_map(static fn(float $value): int => decimalValue($value, 2), $ratings));
            foreach ($ratings as $team => $rating) {
                $lines[] = csvLine([
                    $index + 1, $this->code($team), fixed($rating, 2), fixed($rating - $previous[$team], 2),
                    $ranks[$team], $standings->records[$team]->points, $standings->positions[$team],
                ]);
            }
            $previous = $ratings;
        }
        return $lines;
    }

    private function summaryLines(): array
    {
        $won = $drawn = $lost = $total2 = 0;
        foreach ($this->matches as $match) {
            $won += (int)($match->y2 === 2);
            $drawn += (int)($match->y2 === 1);
            $lost += (int)($match->y2 === 0);
            $total2 += $match->y2;
        }
        $rate = fractionWithReal(new Fraction($total2, 2 * count($this->matches)));
        return [
            'season teams ' . $this->teamCount . ' matches ' . count($this->matches) . ' rounds ' . $this->finalRound,
            "home won $won drawn $drawn lost $lost rate $rate",
            'massey_home_advantage ' . fixed($this->fit->homeAdvantage),
            'bt_home_factor ' . fixed($this->fit->homeFactor),
        ];
    }

    private function upsetLines(): array
    {
        $elo = $this->fit->elo;
        $candidates = [];
        foreach ($this->matches as $index => $match) {
            if ($match->margin !== 0) {
                $expected = $match->margin > 0 ? $elo->expected[$index] : 1 - $elo->expected[$index];
                $candidates[] = [$index, $expected, abs($elo->changes[$index])];
            }
        }
        usort($candidates, static fn(array $a, array $b): int => (decimalValue($a[1], 4) <=> decimalValue($b[1], 4)) ?: ($a[0] <=> $b[0]));
        $lines = ['upsets top ' . $this->settings->upsets];
        foreach (array_slice($candidates, 0, $this->settings->upsets) as [$index, $expected, $gain]) {
            $match = $this->matches[$index];
            if ($match->margin > 0) {
                $winner = $match->home;
                $loser = $match->away;
                $side = 'home';
                $score = $match->homeScore . '-' . $match->awayScore;
            } else {
                $winner = $match->away;
                $loser = $match->home;
                $side = 'away';
                $score = $match->awayScore . '-' . $match->homeScore;
            }
            $lines[] = 'round ' . $match->round . ' ' . $this->code($winner) . ' beat ' . $this->code($loser)
                . " $score $side expected " . fixed($expected) . ' gain ' . fixed($gain, 2);
        }
        return $lines;
    }

    private function tiebreakLines(): array
    {
        $lines = ['tiebreaks'];
        foreach ($this->final->tiedGroups() as $group) {
            $points = $this->final->records[$group[0]]->points;
            $codes = array_map(fn(int $team): string => $this->code($team), $group);
            $h2hPoints = array_map(fn(int $team): int => $this->final->h2hPoints[$team], $group);
            $h2hDiff = array_map(fn(int $team): int => $this->final->h2hDifference[$team], $group);
            $lines[] = "points $points order " . implode(' ', $codes) . ' h2h_points ' . implode(' ', $h2hPoints) . ' h2h_diff ' . implode(' ', $h2hDiff);
        }
        if (count($lines) === 1) {
            $lines[] = 'none';
        }
        return $lines;
    }

    private function leaderLines(): array
    {
        $lines = ['leaders'];
        $previous = null;
        $recorded = 0;
        foreach ($this->roundTables as $index => $standings) {
            $leader = $standings->order[0];
            if ($leader !== $previous) {
                $lines[] = 'round ' . ($index + 1) . ' ' . $this->code($leader) . ' points ' . $standings->records[$leader]->points;
                $recorded++;
            }
            $previous = $leader;
        }
        $lines[] = 'lead_changes ' . ($recorded - 1);
        return $lines;
    }

    private function streakLines(): array
    {
        $lines = [];
        foreach ([['longest_win_streak', $this->winStreaks], ['longest_unbeaten_streak', $this->unbeatenStreaks]] as [$label, $streaks]) {
            $longest = max(array_map(static fn(Streak $streak): int => $streak->length, $streaks));
            foreach ($streaks as $team => $streak) {
                if ($streak->length === $longest) {
                    $lines[] = $label . ' ' . $this->code($team) . ' length ' . $streak->length . ' rounds ' . $streak->first . '-' . $streak->last;
                }
            }
        }
        return $lines;
    }

    private function crosstableLines(): array
    {
        $top = array_slice($this->final->order, 0, $this->settings->topPositions);
        $lines = ['crosstable top ' . $this->settings->topPositions, 'team ' . implode(' ', array_map(fn(int $team): string => $this->code($team), $top))];
        foreach ($top as $first) {
            $entries = [];
            foreach ($top as $second) {
                $entries[] = $first === $second ? '-' : recordText(array_filter($this->appearances[$first], static fn(Appearance $item): bool => $item->opponent === $second));
            }
            $lines[] = $this->code($first) . ' ' . implode(' ', $entries);
        }
        return $lines;
    }

    private function trajectoryLines(): array
    {
        $lines = ['trajectories'];
        for ($team = 0; $team < $this->teamCount; $team++) {
            $ratings = array_map(static fn(array $snapshot): float => $snapshot[$team], $this->fit->elo->roundRatings);
            $rounded = array_map(static fn(float $rating): int => decimalValue($rating, 2), $ratings);
            $positions = array_map(static fn(Standings $standings): int => $standings->positions[$team], $this->roundTables);
            $peak = $low = $best = $worst = 0;
            for ($index = 1; $index < $this->finalRound; $index++) {
                if ($rounded[$index] > $rounded[$peak]) {
                    $peak = $index;
                }
                if ($rounded[$index] < $rounded[$low]) {
                    $low = $index;
                }
                if ($positions[$index] < $positions[$best]) {
                    $best = $index;
                }
                if ($positions[$index] > $positions[$worst]) {
                    $worst = $index;
                }
            }
            $lines[] = $this->code($team) . ' elo_peak ' . fixed($ratings[$peak], 2) . ' round ' . ($peak + 1)
                . ' elo_low ' . fixed($ratings[$low], 2) . ' round ' . ($low + 1)
                . ' best_position ' . $positions[$best] . ' round ' . ($best + 1)
                . ' worst_position ' . $positions[$worst] . ' round ' . ($worst + 1);
        }
        return $lines;
    }

    private function correlationLines(string $title, callable $measure): array
    {
        $lines = [$title, 'model ' . implode(' ', COMPARISON_MODELS)];
        foreach (COMPARISON_MODELS as $first) {
            $values = [];
            foreach (COMPARISON_MODELS as $second) {
                $values[] = fractionText($measure($this->comparison[$first], $this->comparison[$second]));
            }
            $lines[] = $first . ' ' . implode(' ', $values);
        }
        return $lines;
    }

    private function similarityLines(): array
    {
        $most = $least = null;
        foreach (COMPARISON_MODELS as $index => $first) {
            foreach (array_slice(COMPARISON_MODELS, $index + 1) as $second) {
                $pair = [$first, $second, kendallTau($this->comparison[$first], $this->comparison[$second])];
                if ($most === null || $pair[2]->compare($most[2]) > 0) {
                    $most = $pair;
                }
                if ($least === null || $pair[2]->compare($least[2]) < 0) {
                    $least = $pair;
                }
            }
        }
        return [
            'most_similar ' . $most[0] . ' ' . $most[1] . ' tau ' . fractionWithReal($most[2]),
            'least_similar ' . $least[0] . ' ' . $least[1] . ' tau ' . fractionWithReal($least[2]),
        ];
    }

    public function seasonLines(): array
    {
        return joinParts([
            $this->summaryLines(), $this->upsetLines(), $this->tiebreakLines(), $this->leaderLines(),
            $this->streakLines(), $this->crosstableLines(), $this->trajectoryLines(),
            $this->correlationLines('kendall', __NAMESPACE__ . '\\kendallTau'),
            $this->correlationLines('spearman', __NAMESPACE__ . '\\spearmanRho'), $this->similarityLines(),
        ]);
    }

    public function predictionLines(): array
    {
        $lines = [PREDICTIONS_HEADER];
        foreach ($this->predictions as $prediction) {
            $match = $prediction->match;
            $result = $match->y2 === 2 ? 'H' : ($match->y2 === 0 ? 'A' : 'D');
            $fields = [$match->round, $this->code($match->home), $this->code($match->away), $match->homeScore, $match->awayScore, $result];
            array_push($fields, ...array_map(static fn(float $p): string => fixed($p), $prediction->probabilities));
            $lines[] = csvLine($fields);
        }
        return $lines;
    }

    private function linkLines(): array
    {
        $lines = ['links'];
        foreach ($this->rounds as $validation) {
            $parts = ['round ' . $validation->number . ' train ' . count($validation->training) . ' base ' . fixed($validation->base) . ' bt_home ' . fixed($validation->fit->homeFactor)];
            foreach (LINK_MODELS as $model) {
                [$alpha, $beta] = $validation->links[$model];
                $parts[] = $model . ' ' . fixed($alpha) . ' ' . fixed($beta);
            }
            $lines[] = implode(' ', $parts);
        }
        return $lines;
    }

    private function scoreLines(): array
    {
        $scores = $this->scores;
        $lines = ['scores', 'model log_loss brier skill accuracy'];
        foreach (PREDICTION_MODELS as $index => $model) {
            $lines[] = $model . ' ' . fixed($scores->losses[$index]) . ' ' . fixed($scores->briers[$index])
                . ' ' . fixed($scores->skills[$index]) . ' ' . fractionWithReal($scores->accuracies[$index]);
        }
        foreach ([['ranking_log_loss', $scores->lossRanking], ['ranking_brier', $scores->brierRanking], ['ranking_accuracy', $scores->accuracyRanking]] as [$label, $ranking]) {
            $lines[] = $label . ' ' . implode(' ', array_map(static fn(int $index): string => PREDICTION_MODELS[$index], $ranking));
        }
        return $lines;
    }

    private function pairedLines(): array
    {
        $reference = $this->scores->lossRanking[0];
        $count = count($this->predictions);
        $lines = ['paired_log_loss reference ' . PREDICTION_MODELS[$reference]];
        foreach (PREDICTION_MODELS as $index => $model) {
            if ($index === $reference) {
                continue;
            }
            $deltas = array_map(static fn(Prediction $item): float => $item->losses[$index] - $item->losses[$reference], $this->predictions);
            $average = mean($deltas);
            $squares = sequentialSum(array_map(static fn(float $delta): float => ($delta - $average) * ($delta - $average), $deltas));
            $spread = sqrt($squares / ($count - 1));
            $t = $average / ($spread / sqrt($count));
            $lines[] = $model . ' mean_diff ' . fixed($average) . ' sd ' . fixed($spread) . ' t ' . fixed($t, 2);
        }
        return $lines;
    }

    private function marginLines(): array
    {
        $errors = array_map(static fn(Prediction $item): float => $item->marginError, $this->predictions);
        $absolute = mean(array_map(static fn(float $error): float => abs($error), $errors));
        $rootSquared = sqrt(mean(array_map(static fn(float $error): float => $error * $error, $errors)));
        return ['massey_margin mae ' . fixed($absolute) . ' rmse ' . fixed($rootSquared) . ' bias ' . fixed(mean($errors))];
    }

    private function roundLossLines(): array
    {
        $lines = ['round_log_loss', 'round ' . implode(' ', PREDICTION_MODELS)];
        foreach ($this->rounds as $validation) {
            $losses = [];
            foreach (PREDICTION_MODELS as $index => $model) {
                $losses[] = fixed(mean(array_map(static fn(Prediction $item): float => $item->losses[$index], $validation->predictions)));
            }
            $lines[] = $validation->number . ' ' . implode(' ', $losses);
        }
        return $lines;
    }

    private function calibrationLines(): array
    {
        $bins = $this->settings->calibrationBins;
        $lines = ["calibration bins $bins"];
        foreach (PREDICTION_MODELS as $index => $model) {
            $members = array_fill(0, $bins, []);
            foreach ($this->predictions as $prediction) {
                $bin = min((int)floor($bins * $prediction->probabilities[$index]) + 1, $bins);
                $members[$bin - 1][] = $prediction;
            }
            foreach ($members as $indexBin => $group) {
                $number = $indexBin + 1;
                $count = count($group);
                if ($count === 0) {
                    $lines[] = "$model bin $number count 0 predicted - observed -";
                    continue;
                }
                $predicted = mean(array_map(static fn(Prediction $item): float => $item->probabilities[$index], $group));
                $total2 = 0;
                foreach ($group as $item) {
                    $total2 += $item->match->y2;
                }
                $lines[] = "$model bin $number count $count predicted " . fixed($predicted) . ' observed ' . fractionText(new Fraction($total2, 2 * $count));
            }
        }
        return $lines;
    }

    private function gridLines(): array
    {
        $settings = $this->settings;
        $validation = [];
        foreach ($this->matches as $index => $match) {
            if ($match->round >= $settings->holdoutRound) {
                $validation[] = $index;
            }
        }
        $lines = ['elo_grid', 'k ' . implode(' ', array_map(static fn(int $home): string => 'h' . $home, $settings->gridHome))];
        $best = null;
        foreach ($settings->gridK as $kFactor) {
            $row = [$kFactor];
            foreach ($settings->gridHome as $home) {
                $run = runElo($this->teamCount, $this->matches, $kFactor, $home, $settings->eloInitial);
                $loss = mean(array_map(fn(int $index): float => logLoss($run->expected[$index], $this->matches[$index]->y), $validation));
                $row[] = fixed($loss);
                if ($best === null || decimalValue($loss, 4) < decimalValue($best[2], 4)) {
                    $best = [$kFactor, $home, $loss];
                }
            }
            $lines[] = implode(' ', $row);
        }
        $lines[] = 'best k ' . $best[0] . ' home ' . $best[1] . ' log_loss ' . fixed($best[2]);
        return $lines;
    }

    private function projectionTau(): Fraction
    {
        $projected = array_map(static fn(int $rank): int => -$rank, $this->projection->ranks);
        $final = array_map(static fn(int $position): int => -$position, $this->final->positions);
        return kendallTau($projected, $final);
    }

    public function evaluationLines(): array
    {
        return joinParts([
            ['holdout rounds ' . $this->settings->holdoutRound . '-' . $this->finalRound . ' matches ' . count($this->predictions)],
            $this->linkLines(), $this->scoreLines(), $this->pairedLines(), $this->marginLines(),
            $this->roundLossLines(), $this->calibrationLines(), $this->gridLines(),
            ['projection simulations ' . $this->settings->simulations . ' kendall ' . fractionWithReal($this->projectionTau())],
        ]);
    }

    public function projectionLines(): array
    {
        $projection = $this->projection;
        $simulations = $this->settings->simulations;
        $lines = [PROJECTION_HEADER];
        foreach ($projection->order as $index => $team) {
            $lines[] = csvLine([
                $index + 1, $this->code($team), $projection->current->records[$team]->points,
                $projection->current->positions[$team], fixed($projection->opponentStrength($team), 2),
                fixed(new Fraction($projection->totalPoints[$team], $simulations)),
                fixed(new Fraction($projection->titles[$team], $simulations)),
                fixed(new Fraction($projection->tops[$team], $simulations)),
                fixed(new Fraction($projection->bottoms[$team], $simulations)),
                $this->final->records[$team]->points, $this->final->positions[$team],
            ]);
        }
        return $lines;
    }

    public function outputFiles(): array
    {
        return [
            'standings.csv' => $this->standingsLines(), 'ratings.csv' => $this->ratingsLines(),
            'history.csv' => $this->historyLines(), 'season.txt' => $this->seasonLines(),
            'predictions.csv' => $this->predictionLines(), 'evaluation.txt' => $this->evaluationLines(),
            'projection.csv' => $this->projectionLines(),
        ];
    }
}

[$teams, $matches, $settings] = loadSeason('input');
$analysis = new LeagueAnalysis($teams, $matches, $settings);
if (!is_dir('output')) {
    mkdir('output', 0777, true);
}
foreach ($analysis->outputFiles() as $name => $lines) {
    writeLines('output/' . $name, $lines);
}
