<?php
declare(strict_types=1);

final class CommandError extends Exception
{
    public function __construct(string $reason) { parent::__construct('ERROR ' . $reason); }
}
enum Method: string
{
    case Plurality = 'PLURALITY'; case Runoff = 'RUNOFF'; case Irv = 'IRV';
    case Coombs = 'COOMBS'; case Bucklin = 'BUCKLIN'; case Borda = 'BORDA';
    case Baldwin = 'BALDWIN'; case Nanson = 'NANSON'; case Black = 'BLACK';
    case Veto = 'VETO'; case Condorcet = 'CONDORCET'; case Copeland = 'COPELAND';
    case Minimax = 'MINIMAX'; case Schulze = 'SCHULZE'; case RankedPairs = 'RANKEDPAIRS';
    case Kemeny = 'KEMENY'; case Approval = 'APPROVAL'; case Stv = 'STV';
}
enum MinimaxKind: string { case Winning = 'WINNING'; case Margin = 'MARGIN'; case Opposition = 'OPPOSITION'; }
enum ScoreKind { case First; case Last; case Borda; }

final readonly class MethodSpec
{
    public function __construct(public Method $kind, public int $parameter = 0, public MinimaxKind $minimax = MinimaxKind::Winning) {}
    public function rankable(): bool { return $this->kind !== Method::Condorcet && $this->kind !== Method::Stv; }
    public function __toString(): string
    {
        return match ($this->kind) {
            Method::Minimax => 'MINIMAX ' . $this->minimax->value,
            Method::Approval, Method::Stv => $this->kind->value . ' ' . $this->parameter,
            default => $this->kind->value,
        };
    }
    public static function parse(array $words, int $start = 0): self
    {
        $kind = Method::from($words[$start]);
        return match ($kind) {
            Method::Minimax => new self($kind, 0, MinimaxKind::from($words[$start + 1])),
            Method::Approval, Method::Stv => new self($kind, (int)$words[$start + 1]),
            default => new self($kind),
        };
    }
}
final readonly class Ballot
{
    public function __construct(public int $votes, public array $ranking) {}
}
final readonly class TallyResult
{
    public function __construct(public array $standings, public bool $tie, public array $lines, public array $exhaustion = []) {}
}
final class Election
{
    public array $withdrawn;
    public array $tieOrder;
    public array $entries = [];
    public function __construct(public readonly int $number, public readonly array $names)
    {
        $this->withdrawn = array_fill(0, count($names), false);
        $this->tieOrder = array_keys($names);
        usort($this->tieOrder, fn(int $a, int $b): int => strcmp($names[$a], $names[$b]));
    }
    public function active(): array
    {
        return array_values(array_filter(array_keys($this->names), fn(int $c): bool => !$this->withdrawn[$c]));
    }
    public function groups(): iterable
    {
        foreach ($this->entries as $entry) foreach ($entry as $group) yield $group;
    }
    public function total(): int
    {
        $total = 0;
        foreach ($this->groups() as $group) $total += $group->votes;
        return $total;
    }
    public function candidate(string $name): int
    {
        $index = array_search($name, $this->names, true);
        if ($index === false) throw new CommandError('unknown candidate ' . $name);
        return $index;
    }
    public function checkNames(array $names): array
    {
        $result = [];
        foreach ($names as $name) {
            $candidate = $this->candidate($name);
            if (in_array($candidate, $result, true)) throw new CommandError('duplicate candidate ' . $name);
            $result[] = $candidate;
        }
        return $result;
    }
    public function nameList(array $candidates, string $separator = ', '): string
    {
        return implode($separator, array_map(fn(int $c): string => $this->names[$c], $candidates));
    }
}

final class Tally
{
    public readonly array $field;
    public readonly array $pairwise;
    public readonly int $total;
    private readonly array $priority;
    private readonly array $groups;
    private readonly int $candidateCount;
    public function __construct(public readonly Election $election, ?array $field = null)
    {
        $this->field = $field ?? $election->active();
        $this->candidateCount = count($election->names);
        $priority = array_fill(0, $this->candidateCount, 0);
        foreach ($election->tieOrder as $i => $candidate) $priority[$candidate] = $i;
        $this->priority = $priority;
        $groups = [];
        $pairwise = array_fill(0, $this->candidateCount, array_fill(0, $this->candidateCount, 0));
        $total = 0;
        foreach ($election->groups() as $group) {
            $ranking = array_values(array_intersect($group->ranking, $this->field));
            $groups[] = new Ballot($group->votes, $ranking);
            $total += $group->votes;
            $ranks = array_fill(0, $this->candidateCount, $this->candidateCount);
            foreach ($ranking as $i => $candidate) $ranks[$candidate] = $i;
            foreach ($this->field as $x) foreach ($this->field as $y) {
                if ($ranks[$x] < $ranks[$y]) $pairwise[$x][$y] += $group->votes;
            }
        }
        $this->groups = $groups;
        $this->pairwise = $pairwise;
        $this->total = $total;
    }
    public function name(int $candidate): string { return $this->election->names[$candidate]; }
    public function names(array $candidates): string { return $this->election->nameList($candidates); }
    public function ranking(array $candidates): string { return $this->election->nameList($candidates, ' > '); }
    private static function amount(int $value): string { return sprintf('%d.%02d', intdiv($value, 100), $value % 100); }
    public function values(array $candidates, array $scores, bool $amounts = false): string
    {
        return implode(', ', array_map(fn(int $c): string => $this->name($c) . ' ' . ($amounts ? self::amount($scores[$c]) : $scores[$c]), $candidates));
    }
    private function scores(array $candidates, ScoreKind $kind): array
    {
        $result = array_fill(0, $this->candidateCount, 0);
        foreach ($this->groups as $group) {
            $ranking = array_values(array_intersect($group->ranking, $candidates));
            switch ($kind) {
                case ScoreKind::First:
                    if ($ranking) $result[$ranking[0]] += $group->votes;
                    break;
                case ScoreKind::Last:
                    if (count($ranking) < count($candidates)) {
                        foreach (array_diff($candidates, $ranking) as $candidate) $result[$candidate] += $group->votes;
                    } else {
                        $result[$ranking[count($ranking) - 1]] += $group->votes;
                    }
                    break;
                case ScoreKind::Borda:
                    foreach ($ranking as $i => $candidate) $result[$candidate] += $group->votes * (count($candidates) - $i - 1);
                    break;
            }
        }
        return $result;
    }
    private function approval(int $depth): array
    {
        $result = array_fill(0, $this->candidateCount, 0);
        foreach ($this->groups as $group) foreach (array_slice($group->ranking, 0, $depth) as $candidate) $result[$candidate] += $group->votes;
        return $result;
    }
    private function order(array $candidates, array $scores, bool $descending = true): array
    {
        usort($candidates, fn(int $a, int $b): int =>
            ($descending ? $scores[$b] <=> $scores[$a] : $scores[$a] <=> $scores[$b]) ?: ($this->priority[$a] <=> $this->priority[$b]));
        return $candidates;
    }
    private function priorityOrder(array $candidates): array
    {
        usort($candidates, fn(int $a, int $b): int => $this->priority[$a] <=> $this->priority[$b]);
        return $candidates;
    }
    private static function topTie(array $standings, array $scores): bool
    {
        return count($standings) > 1 && $scores[$standings[0]] === $scores[$standings[1]];
    }
    private function eliminate(array $candidates, array $scores, array $history): array
    {
        $low = min(array_map(fn(int $c): int => $scores[$c], $candidates));
        $pool = array_values(array_filter($candidates, fn(int $c): bool => $scores[$c] === $low));
        $tie = count($pool) > 1;
        foreach (array_reverse($history) as $previous) {
            $low = min(array_map(fn(int $c): int => $previous[$c], $pool));
            $pool = array_values(array_filter($pool, fn(int $c): bool => $previous[$c] === $low));
        }
        $pool = $this->priorityOrder($pool);
        return [$pool[count($pool) - 1], $tie];
    }
    private function finish(array $standings, bool $tie, array $lines, array $exhaustion = []): TallyResult
    {
        $lines[] = 'winner: ' . $this->name($standings[0]) . ($tie ? ' (tie)' : '');
        return new TallyResult($standings, $tie, $lines, $exhaustion);
    }
    private function scored(array $scores, string $label, bool $descending = true): TallyResult
    {
        $standings = $this->order($this->field, $scores, $descending);
        return $this->finish($standings, self::topTie($standings, $scores), [$label . ': ' . $this->values($this->field, $scores)]);
    }
    private function condorcet(bool $loser = false): ?int
    {
        foreach ($this->field as $x) {
            foreach ($this->field as $y) {
                if ($x === $y) continue;
                if ($loser ? $this->pairwise[$x][$y] >= $this->pairwise[$y][$x] : $this->pairwise[$x][$y] <= $this->pairwise[$y][$x]) continue 2;
            }
            return $x;
        }
        return null;
    }
    public function pairLines(?array $table = null): array
    {
        $table ??= $this->pairwise;
        $lines = [];
        foreach ($this->field as $i => $x) foreach (array_slice($this->field, $i + 1) as $y) {
            $winner = $table[$x][$y] === $table[$y][$x] ? 'tie' : $this->name($table[$x][$y] > $table[$y][$x] ? $x : $y);
            $lines[] = $this->name($x) . ' vs ' . $this->name($y) . ': ' . $table[$x][$y] . '-' . $table[$y][$x] . ' (' . $winner . ')';
        }
        return $lines;
    }
    private function runoff(): TallyResult
    {
        $first = $this->scores($this->field, ScoreKind::First);
        $standings = $this->order($this->field, $first);
        $lines = ['round 1: ' . $this->values($this->field, $first)];
        if (2 * $first[$standings[0]] > array_sum($first)) return $this->finish($standings, false, $lines);
        $finalists = array_slice($standings, 0, 2);
        sort($finalists, SORT_NUMERIC);
        $advancement = count($standings) > 2 && $first[$standings[1]] === $first[$standings[2]];
        $second = $this->scores($finalists, ScoreKind::First);
        $tie = $second[$standings[0]] === $second[$standings[1]];
        if ($second[$standings[0]] < $second[$standings[1]]) [$standings[0], $standings[1]] = [$standings[1], $standings[0]];
        $lines[] = 'finalists: ' . $this->names($finalists) . ($advancement ? ' (tie)' : '');
        $lines[] = 'round 2: ' . $this->values($finalists, $second);
        return $this->finish($standings, $tie, $lines);
    }
    private function instantRunoff(bool $coombs = false): TallyResult
    {
        $remaining = $this->field;
        $removed = $history = $lines = $exhaustion = [];
        for ($round = 1; ; $round++) {
            $first = $this->scores($remaining, ScoreKind::First);
            $active = array_sum($first);
            $line = 'round ' . $round . ': ' . $this->values($remaining, $first);
            $exhaustion[] = 'round ' . $round . ': active ' . $active . ', exhausted ' . ($this->total - $active);
            if (count($remaining) === 1 || 2 * max($first) > $active) {
                $lines[] = $line;
                return $this->finish([...$this->order($remaining, $first), ...array_reverse($removed)], false, $lines, $exhaustion);
            }
            if ($coombs) {
                $last = $this->scores($remaining, ScoreKind::Last);
                $high = max(array_map(fn(int $c): int => $last[$c], $remaining));
                $pool = array_values(array_filter($remaining, fn(int $c): bool => $last[$c] === $high));
                $tie = count($pool) > 1;
                $pool = $this->order($pool, $first);
                $loser = $pool[count($pool) - 1];
                $line .= '; last ' . $this->values($remaining, $last);
            } else {
                [$loser, $tie] = $this->eliminate($remaining, $first, $history);
            }
            $lines[] = $line . '; eliminated ' . $this->name($loser) . ($tie ? ' (tie)' : '');
            $removed[] = $loser;
            $history[] = $first;
            $remaining = array_values(array_diff($remaining, [$loser]));
        }
    }
    private function bucklin(): TallyResult
    {
        $nonblank = 0;
        foreach ($this->groups as $group) if ($group->ranking) $nonblank += $group->votes;
        $majority = intdiv($nonblank, 2) + 1;
        $lines = ['majority: ' . $majority];
        $history = [];
        for ($round = 1; $round <= count($this->field); $round++) {
            $scores = $this->approval($round);
            $history[] = $scores;
            $lines[] = 'round ' . $round . ': ' . $this->values($this->field, $scores);
            if (max($scores) >= $majority) break;
        }
        $standings = $this->field;
        usort($standings, function(int $a, int $b) use ($history): int {
            foreach (array_reverse($history) as $scores) if ($scores[$a] !== $scores[$b]) return $scores[$b] <=> $scores[$a];
            return $this->priority[$a] <=> $this->priority[$b];
        });
        return $this->finish($standings, self::topTie($standings, $scores), $lines);
    }
    private function bordaElimination(bool $nanson): TallyResult
    {
        $remaining = $this->field;
        $removed = $history = $lines = [];
        for ($round = 1; count($remaining) > 1; $round++) {
            $scores = $this->scores($remaining, ScoreKind::Borda);
            $line = 'round ' . $round . ': ' . $this->values($remaining, $scores);
            if ($nanson) {
                $total = array_sum($scores);
                $losers = array_values(array_filter($remaining, fn(int $c): bool => $scores[$c] * count($remaining) < $total));
                if (!$losers) { $lines[] = $line; break; }
                $line .= '; eliminated ' . $this->names($losers);
            } else {
                [$loser, $tie] = $this->eliminate($remaining, $scores, $history);
                $losers = [$loser];
                $line .= '; eliminated ' . $this->name($loser) . ($tie ? ' (tie)' : '');
            }
            $lines[] = $line;
            $history[] = $scores;
            $removed = [...$this->order($losers, $scores), ...$removed];
            $remaining = array_values(array_diff($remaining, $losers));
        }
        return $this->finish([...$this->priorityOrder($remaining), ...$removed], $nanson && count($remaining) > 1, $lines);
    }
    private function black(): TallyResult
    {
        $scores = $this->scores($this->field, ScoreKind::Borda);
        $winner = $this->condorcet();
        $standings = $this->order($this->field, $scores);
        $tie = $winner === null && self::topTie($standings, $scores);
        if ($winner !== null) $standings = [$winner, ...array_values(array_diff($standings, [$winner]))];
        return $this->finish($standings, $tie, [
            'condorcet: ' . ($winner === null ? 'NONE' : $this->name($winner)),
            'scores: ' . $this->values($this->field, $scores),
        ]);
    }
    private function condorcetReport(): TallyResult
    {
        $weak = $strong = array_fill(0, $this->candidateCount, array_fill(0, $this->candidateCount, false));
        foreach ($this->field as $x) foreach ($this->field as $y) {
            $weak[$x][$y] = $this->pairwise[$x][$y] >= $this->pairwise[$y][$x];
            $strong[$x][$y] = $this->pairwise[$x][$y] > $this->pairwise[$y][$x];
        }
        foreach ($this->field as $k) foreach ($this->field as $x) foreach ($this->field as $y) {
            $weak[$x][$y] = $weak[$x][$y] || ($weak[$x][$k] && $weak[$k][$y]);
            $strong[$x][$y] = $strong[$x][$y] || ($strong[$x][$k] && $strong[$k][$y]);
        }
        $smith = $schwartz = [];
        foreach ($this->field as $x) {
            $inSmith = $inSchwartz = true;
            foreach ($this->field as $y) {
                if (!$weak[$x][$y]) $inSmith = false;
                if ($strong[$y][$x] && !$strong[$x][$y]) $inSchwartz = false;
            }
            if ($inSmith) $smith[] = $x;
            if ($inSchwartz) $schwartz[] = $x;
        }
        $winner = $this->condorcet();
        $loser = $this->condorcet(true);
        return new TallyResult([], false, [
            'winner: ' . ($winner === null ? 'NONE' : $this->name($winner)),
            'loser: ' . ($loser === null ? 'NONE' : $this->name($loser)),
            'smith: ' . $this->names($smith), 'schwartz: ' . $this->names($schwartz),
        ]);
    }
    private function copeland(): TallyResult
    {
        $scores = array_fill(0, $this->candidateCount, 0);
        $items = [];
        foreach ($this->field as $x) {
            $wins = $draws = $losses = 0;
            foreach ($this->field as $y) {
                if ($x === $y) continue;
                if ($this->pairwise[$x][$y] > $this->pairwise[$y][$x]) $wins++;
                elseif ($this->pairwise[$x][$y] === $this->pairwise[$y][$x]) $draws++;
                else $losses++;
            }
            $scores[$x] = 2 * $wins + $draws;
            $items[] = $this->name($x) . ' ' . intdiv($scores[$x], 2) . '.' . (5 * ($scores[$x] % 2))
                . ' (' . $wins . '-' . $draws . '-' . $losses . ')';
        }
        $standings = $this->order($this->field, $scores);
        return $this->finish($standings, self::topTie($standings, $scores), ['scores: ' . implode(', ', $items)]);
    }
    private function minimax(MinimaxKind $kind): TallyResult
    {
        $scores = array_fill(0, $this->candidateCount, 0);
        foreach ($this->field as $x) foreach ($this->field as $y) {
            if ($x === $y) continue;
            $against = $this->pairwise[$y][$x];
            $margin = $against - $this->pairwise[$x][$y];
            if ($kind === MinimaxKind::Opposition || $margin > 0) {
                $scores[$x] = max($scores[$x], $kind === MinimaxKind::Margin ? $margin : $against);
            }
        }
        return $this->scored($scores, 'scores', false);
    }
    private function dominanceOrder(Closure $dominates): array
    {
        $remaining = $this->field;
        $standings = [];
        $tie = false;
        while ($remaining) {
            $eligible = [];
            foreach ($remaining as $x) {
                foreach ($remaining as $y) if ($x !== $y && $dominates($y, $x)) continue 2;
                $eligible[] = $x;
            }
            if (!$standings) $tie = count($eligible) > 1;
            $chosen = $this->priorityOrder($eligible)[0];
            $standings[] = $chosen;
            $remaining = array_values(array_diff($remaining, [$chosen]));
        }
        return [$standings, $tie];
    }
    private function schulze(): TallyResult
    {
        $paths = array_fill(0, $this->candidateCount, array_fill(0, $this->candidateCount, 0));
        foreach ($this->field as $x) foreach ($this->field as $y) {
            if ($this->pairwise[$x][$y] > $this->pairwise[$y][$x]) $paths[$x][$y] = $this->pairwise[$x][$y];
        }
        foreach ($this->field as $i) foreach ($this->field as $j) {
            if ($j === $i) continue;
            foreach ($this->field as $k) if ($k !== $i && $k !== $j) {
                $paths[$j][$k] = max($paths[$j][$k], min($paths[$j][$i], $paths[$i][$k]));
            }
        }
        [$standings, $tie] = $this->dominanceOrder(fn(int $x, int $y): bool => $paths[$x][$y] > $paths[$y][$x]);
        return $this->finish($standings, $tie, [...$this->pairLines($paths), 'ranking: ' . $this->ranking($standings)]);
    }
    private function reachable(array $edges, int $from, int $to): bool
    {
        $pending = [$from];
        $seen = array_fill(0, $this->candidateCount, false);
        while ($pending) {
            $x = array_pop($pending);
            if ($x === $to) return true;
            if ($seen[$x]) continue;
            $seen[$x] = true;
            foreach ($this->field as $y) if ($edges[$x][$y]) $pending[] = $y;
        }
        return false;
    }
    private function rankedPairs(): TallyResult
    {
        $pairs = [];
        foreach ($this->field as $x) foreach ($this->field as $y) {
            if ($this->pairwise[$x][$y] > $this->pairwise[$y][$x]) $pairs[] = [$x, $y];
        }
        usort($pairs, fn(array $a, array $b): int =>
            ($this->pairwise[$b[0]][$b[1]] <=> $this->pairwise[$a[0]][$a[1]])
            ?: ($this->pairwise[$a[1]][$a[0]] <=> $this->pairwise[$b[1]][$b[0]])
            ?: ($this->priority[$a[0]] <=> $this->priority[$b[0]])
            ?: ($this->priority[$a[1]] <=> $this->priority[$b[1]]));
        $edges = array_fill(0, $this->candidateCount, array_fill(0, $this->candidateCount, false));
        $lines = [];
        foreach ($pairs as [$x, $y]) {
            $skip = $this->reachable($edges, $y, $x);
            if (!$skip) $edges[$x][$y] = true;
            $lines[] = ($skip ? 'skip ' : 'lock ') . $this->name($x) . '>' . $this->name($y)
                . ' ' . $this->pairwise[$x][$y] . '-' . $this->pairwise[$y][$x];
        }
        [$standings, $tie] = $this->dominanceOrder(fn(int $x, int $y): bool => $edges[$x][$y]);
        return $this->finish($standings, $tie, $lines);
    }
    private function kemeny(): TallyResult
    {
        $candidates = $this->priorityOrder($this->field);
        $path = $standings = $firsts = [];
        $used = array_fill(0, $this->candidateCount, false);
        $best = -1;
        $optimal = 0;
        $visit = function(int $score) use (&$visit, &$path, &$standings, &$firsts, &$used, &$best, &$optimal, $candidates): void {
            if (count($path) === count($candidates)) {
                if ($score > $best) {
                    $best = $score;
                    $optimal = 0;
                    $firsts = [];
                    $standings = $path;
                }
                if ($score === $best) { $optimal++; $firsts[$path[0]] = true; }
                return;
            }
            foreach ($candidates as $candidate) {
                if ($used[$candidate]) continue;
                $extra = 0;
                foreach ($path as $earlier) $extra += $this->pairwise[$earlier][$candidate];
                $used[$candidate] = true;
                $path[] = $candidate;
                $visit($score + $extra);
                array_pop($path);
                $used[$candidate] = false;
            }
        };
        $visit(0);
        return $this->finish($standings, count($firsts) > 1, [
            'score: ' . $best, 'optimal: ' . $optimal, 'ranking: ' . $this->ranking($standings),
        ]);
    }
    private function stv(int $seats): TallyResult
    {
        $groups = array_values(array_filter($this->groups, fn(Ballot $group): bool => (bool)$group->ranking));
        $nonblank = 0;
        foreach ($groups as $group) $nonblank += $group->votes;
        $quota = intdiv($nonblank * 100, $seats + 1) + 1;
        $voteValues = array_fill(0, count($groups), 100);
        $remaining = $this->field;
        $elected = $history = [];
        $lines = ['quota: ' . self::amount($quota)];
        for ($round = 1; ; $round++) {
            $scores = array_fill(0, $this->candidateCount, 0);
            $owners = array_fill(0, count($groups), null);
            $exhausted = 0;
            foreach ($groups as $i => $group) {
                foreach ($group->ranking as $candidate) if (in_array($candidate, $remaining, true)) {
                    $owners[$i] = $candidate;
                    break;
                }
                $amount = $group->votes * $voteValues[$i];
                if ($owners[$i] === null) $exhausted += $amount;
                else $scores[$owners[$i]] += $amount;
            }
            $line = 'round ' . $round . ': ' . $this->values($remaining, $scores, true) . '; exhausted ' . self::amount($exhausted);
            $order = $this->order($remaining, $scores);
            if (count($remaining) === $seats - count($elected)) {
                $elected = [...$elected, ...$order];
                $lines[] = $line . '; elected ' . $this->names($order);
                break;
            }
            $chosen = $order[0];
            if ($scores[$chosen] >= $quota) {
                $elected[] = $chosen;
                $surplus = $scores[$chosen] - $quota;
                foreach ($owners as $i => $owner) if ($owner === $chosen) {
                    $voteValues[$i] = intdiv($voteValues[$i] * $surplus, $scores[$chosen]);
                }
                $line .= '; elected ' . $this->name($chosen) . ' (surplus ' . self::amount($surplus) . ')';
            } else {
                [$chosen, $tie] = $this->eliminate($remaining, $scores, $history);
                $line .= '; excluded ' . $this->name($chosen) . ($tie ? ' (tie)' : '');
            }
            $lines[] = $line;
            $history[] = $scores;
            $remaining = array_values(array_diff($remaining, [$chosen]));
            if (count($elected) === $seats) break;
        }
        $lines[] = 'elected: ' . $this->names($elected);
        return new TallyResult([], false, $lines);
    }
    public function run(MethodSpec $method): TallyResult
    {
        return match ($method->kind) {
            Method::Plurality => $this->scored($this->scores($this->field, ScoreKind::First), 'votes'),
            Method::Runoff => $this->runoff(), Method::Irv => $this->instantRunoff(),
            Method::Coombs => $this->instantRunoff(true), Method::Bucklin => $this->bucklin(),
            Method::Borda => $this->scored($this->scores($this->field, ScoreKind::Borda), 'scores'),
            Method::Baldwin => $this->bordaElimination(false), Method::Nanson => $this->bordaElimination(true),
            Method::Black => $this->black(),
            Method::Veto => $this->scored($this->scores($this->field, ScoreKind::Last), 'vetoes', false),
            Method::Condorcet => $this->condorcetReport(), Method::Copeland => $this->copeland(),
            Method::Minimax => $this->minimax($method->minimax), Method::Schulze => $this->schulze(),
            Method::RankedPairs => $this->rankedPairs(), Method::Kemeny => $this->kemeny(),
            Method::Approval => $this->scored($this->approval($method->parameter), 'approvals'),
            Method::Stv => $this->stv($method->parameter),
        };
    }
    public function ballotsReport(): array
    {
        $counts = [];
        $blank = 0;
        foreach ($this->groups as $group) {
            $notation = $group->ranking ? $this->election->nameList($group->ranking, '>') : '-';
            $counts[$notation] = ($counts[$notation] ?? 0) + $group->votes;
            if (!$group->ranking) $blank += $group->votes;
        }
        $notations = array_keys($counts);
        usort($notations, fn(string $a, string $b): int => ($counts[$b] <=> $counts[$a]) ?: strcmp($a, $b));
        $lines = ['total ' . $this->total . ', blank ' . $blank . ', distinct ' . count($counts)];
        foreach ($notations as $notation) $lines[] = $counts[$notation] . ' ' . $notation;
        return $lines;
    }
    public function profile(): array
    {
        $lines = [];
        foreach ($this->field as $candidate) {
            $counts = array_fill(0, count($this->field), 0);
            $unranked = 0;
            foreach ($this->groups as $group) {
                $rank = array_search($candidate, $group->ranking, true);
                if ($rank === false) $unranked += $group->votes;
                else $counts[$rank] += $group->votes;
            }
            $lines[] = $this->name($candidate) . ': ' . implode(' ', $counts) . ' unranked ' . $unranked;
        }
        return $lines;
    }
    public function exhausted(): array { return $this->instantRunoff()->exhaustion; }
}

final class Counter
{
    private ?Election $current = null;
    private int $count = 0;
    private const SUMMARY_METHODS = [
        Method::Plurality, Method::Runoff, Method::Irv, Method::Coombs, Method::Bucklin,
        Method::Borda, Method::Baldwin, Method::Nanson, Method::Black, Method::Veto,
        Method::Copeland, Method::Minimax, Method::Schulze, Method::RankedPairs, Method::Kemeny,
    ];
    public function execute(string $line): array
    {
        $words = explode(' ', $line);
        $command = $words[0];
        if ($command === 'CANDIDATES') {
            $names = array_slice($words, 1);
            if (count($names) < 2) throw new CommandError('too few candidates');
            $seen = [];
            foreach ($names as $name) {
                if (in_array($name, $seen, true)) throw new CommandError('duplicate candidate ' . $name);
                $seen[] = $name;
            }
            $this->current = new Election(++$this->count, $names);
            return ['election ' . $this->count . ': ' . count($names) . ' candidates'];
        }
        $election = $this->current ?? throw new CommandError('no election');
        switch ($command) {
            case 'BALLOT':
                $ranking = $words[2] === '-' ? [] : $election->checkNames(explode('>', $words[2]));
                $election->entries[] = [new Ballot((int)$words[1], $ranking)];
                return [];
            case 'RANDOM':
                $state = (int)$words[2];
                $entry = [];
                for ($group = 0; $group < (int)$words[1]; $group++) {
                    $ranking = $election->active();
                    for ($i = count($ranking) - 1; $i > 0; $i--) {
                        $state = (48271 * $state) % 2147483647;
                        $j = $state % ($i + 1);
                        [$ranking[$i], $ranking[$j]] = [$ranking[$j], $ranking[$i]];
                    }
                    $state = (48271 * $state) % 2147483647;
                    $entry[] = new Ballot(1, array_slice($ranking, 0, $state % count($ranking) + 1));
                }
                $election->entries[] = $entry;
                return [];
            case 'UNDO':
                if (!$election->entries) throw new CommandError('nothing to undo');
                array_pop($election->entries);
                return [];
            case 'WITHDRAW':
            case 'RESTORE':
                $candidate = $election->candidate($words[1]);
                if ($command === 'WITHDRAW') {
                    if ($election->withdrawn[$candidate]) throw new CommandError('already withdrawn ' . $words[1]);
                    if (count($election->active()) <= 2) throw new CommandError('too few candidates');
                    $election->withdrawn[$candidate] = true;
                } else {
                    if (!$election->withdrawn[$candidate]) throw new CommandError('not withdrawn ' . $words[1]);
                    $election->withdrawn[$candidate] = false;
                }
                return [];
            case 'TIEBREAK':
                $order = $election->checkNames(array_slice($words, 1));
                if (count($order) !== count($election->names)) throw new CommandError('incomplete tiebreak');
                $election->tieOrder = $order;
                return [];
            case 'STATUS':
                $withdrawn = array_values(array_filter(array_keys($election->names), fn(int $c): bool => $election->withdrawn[$c]));
                return ['[' . $line . ']', 'election ' . $election->number,
                    'active: ' . $election->nameList($election->active()),
                    'withdrawn: ' . ($withdrawn ? $election->nameList($withdrawn) : 'none'),
                    'tiebreak: ' . $election->nameList($election->tieOrder),
                    'ballots: ' . $election->total() . ' in ' . count($election->entries) . ' entries'];
        }
        if (!$election->entries) throw new CommandError('no ballots');
        $tally = new Tally($election);
        $lines = [];
        switch ($command) {
            case 'BALLOTS': $lines = $tally->ballotsReport(); break;
            case 'PROFILE': $lines = $tally->profile(); break;
            case 'PAIRWISE': $lines = $tally->pairLines(); break;
            case 'EXHAUSTED': $lines = $tally->exhausted(); break;
            case 'RANKING':
            case 'SPOILERS':
                $method = MethodSpec::parse($words, 1);
                if (!$method->rankable()) throw new CommandError('not rankable');
                if ($command === 'SPOILERS' && count($tally->field) < 3) throw new CommandError('too few candidates');
                $standings = $tally->run($method)->standings;
                if ($command === 'RANKING') { $lines[] = $tally->ranking($standings); break; }
                $winner = $standings[0];
                $lines[] = 'winner: ' . $tally->name($winner);
                foreach ($tally->field as $removed) {
                    if ($removed === $winner) continue;
                    $reduced = new Tally($election, array_values(array_diff($tally->field, [$removed])));
                    $other = $reduced->run($method)->standings[0];
                    $lines[] = 'without ' . $tally->name($removed) . ': ' . $tally->name($other) . ($other !== $winner ? ' (changed)' : '');
                }
                break;
            case 'SUMMARY':
                $wins = array_fill(0, count($election->names), 0);
                foreach (self::SUMMARY_METHODS as $kind) {
                    $method = new MethodSpec($kind);
                    $winner = $tally->run($method)->standings[0];
                    $wins[$winner]++;
                    $lines[] = $method . ': ' . $tally->name($winner);
                }
                $lines[] = 'wins: ' . $tally->values($tally->field, $wins);
                break;
            case 'COMPARE':
                $x = $election->candidate($words[1]);
                if ($election->withdrawn[$x]) throw new CommandError('withdrawn candidate ' . $words[1]);
                $y = $election->candidate($words[2]);
                if ($election->withdrawn[$y]) throw new CommandError('withdrawn candidate ' . $words[2]);
                if ($x === $y) throw new CommandError('same candidate');
                $xAhead = $yAhead = [];
                foreach (self::SUMMARY_METHODS as $kind) {
                    $method = new MethodSpec($kind);
                    $standings = $tally->run($method)->standings;
                    if (array_search($x, $standings, true) < array_search($y, $standings, true)) $xAhead[] = (string)$method;
                    else $yAhead[] = (string)$method;
                }
                $lines = [
                    $tally->name($x) . ' ' . $tally->pairwise[$x][$y] . ', ' . $tally->name($y) . ' ' . $tally->pairwise[$y][$x]
                        . ', neither ' . ($tally->total - $tally->pairwise[$x][$y] - $tally->pairwise[$y][$x]),
                    $tally->name($x) . ' ahead: ' . ($xAhead ? implode(', ', $xAhead) : 'none'),
                    $tally->name($y) . ' ahead: ' . ($yAhead ? implode(', ', $yAhead) : 'none'),
                ];
                break;
            default:
                $method = MethodSpec::parse($words);
                if ($method->kind === Method::Stv && $method->parameter >= count($tally->field)) throw new CommandError('too many seats');
                $lines = $tally->run($method)->lines;
                break;
        }
        return ['[' . $line . ']', ...$lines];
    }
}

$counter = new Counter();
$commands = (int)fgets(STDIN);
for ($i = 0; $i < $commands; $i++) {
    $line = rtrim(fgets(STDIN), "\r\n");
    try {
        foreach ($counter->execute($line) as $output) echo $output, "\n";
    } catch (CommandError $error) {
        echo $error->getMessage(), "\n";
    }
}
