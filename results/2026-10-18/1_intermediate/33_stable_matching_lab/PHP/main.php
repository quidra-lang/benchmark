<?php
declare(strict_types=1);

final class CommandError extends Exception
{
    public function __construct(string $message) { parent::__construct('ERROR ' . $message); }
}

enum MarketKind { case TwoSided; case Roommates; case Housing; }

final class Market
{
    public readonly int $count;
    public array $preferences;
    public array $capacities;
    public ?array $current = null;
    public string $source = '-';

    public function __construct(
        public readonly string $name,
        public readonly MarketKind $kind,
        public readonly array $agents,
        public readonly int $proposerCount = 0,
        public readonly array $houses = [],
    ) {
        $this->count = count($agents);
        $this->preferences = array_fill(0, $this->count, []);
        $this->capacities = array_fill(0, $this->count, 1);
    }

    public function proposers(): array { return range(0, $this->proposerCount - 1); }
    public function receivers(): array { return range($this->proposerCount, $this->count - 1); }
    public function agent(string $name): int
    {
        $agent = array_search($name, $this->agents, true);
        if ($agent === false) throw new CommandError("UNKNOWN AGENT $name");
        return $agent;
    }
    public function proposer(string $name): int
    {
        $agent = $this->agent($name);
        if ($agent >= $this->proposerCount) throw new CommandError("NOT PROPOSER $name");
        return $agent;
    }
    public function receiver(string $name): int
    {
        $agent = $this->agent($name);
        if ($agent < $this->proposerCount) throw new CommandError("NOT RECEIVER $name");
        return $agent;
    }
    public function choice(int $agent, string $name): int
    {
        $choice = array_search($name, $this->kind === MarketKind::Housing ? $this->houses : $this->agents, true);
        $valid = $choice !== false && match ($this->kind) {
            MarketKind::TwoSided => ($agent < $this->proposerCount) !== ($choice < $this->proposerCount),
            MarketKind::Roommates => $agent !== $choice,
            MarketKind::Housing => true,
        };
        if (!$valid) throw new CommandError("BAD CHOICE $name");
        return $choice;
    }
    public function clearMatching(): void { $this->current = null; $this->source = '-'; }
    public function setMatching(array $partners, string $source): void
    {
        $this->current = $partners;
        $this->source = $source;
    }
    public function partner(int $agent): string { return $agent < 0 ? '*' : $this->agents[$agent]; }
    public function pairs(array $partners): string
    {
        $pairs = [];
        foreach ($this->proposers() as $p) $pairs[] = $this->agents[$p] . '-' . $this->partner($partners[$p]);
        return implode(' ', $pairs);
    }
    public function allocation(array $allocation): string
    {
        $pairs = [];
        foreach ($allocation as $a => $house)
            $pairs[] = $this->agents[$a] . '-' . ($house < 0 ? '*' : $this->houses[$house]);
        return implode(' ', $pairs);
    }
    public function effective(int $agent): array
    {
        $list = $this->preferences[$agent];
        $own = array_search($agent, $list, true);
        return $own === false ? [...$list, $agent] : array_slice($list, 0, $own + 1);
    }
}

final readonly class MatchingResult
{
    public function __construct(public array $partners, public int $count, public array $log = []) {}
}
final readonly class Candidate
{
    public function __construct(
        public array $partners, public int $origin, public int $via, public int $cost, public int $regret,
    ) {}
}
final readonly class Enumeration
{
    public function __construct(public array $matchings, public array $rotations) {}
}

function listText(array $values): string { return $values === [] ? '-' : implode(' ', $values); }
function rankOf(array $preference, int $partner): int
{
    $position = array_search($partner, $preference, true);
    return $position === false ? count($preference) + 1 : $position + 1;
}
function acceptable(array $preferences, int $a, int $b): bool
{
    return in_array($b, $preferences[$a], true) && in_array($a, $preferences[$b], true);
}
function residents(Market $market, array $partners, int $receiver): array
{
    $result = [];
    foreach ($market->proposers() as $p) if ($partners[$p] === $receiver) $result[] = $p;
    return $result;
}
function deferred(Market $market, bool $reverse = false, bool $verbose = false, ?array $preferences = null): MatchingResult
{
    $lists = $preferences ?? $market->preferences;
    $next = $counts = array_fill(0, $market->count, 0);
    $queued = array_fill(0, $market->count, false);
    $holding = array_fill(0, $market->count, []);
    $queue = [];
    $enqueue = function (int $agent) use (&$queue, &$queued, &$next, &$counts, $lists, $market): void {
        if (!$queued[$agent] && $counts[$agent] < $market->capacities[$agent]
            && $next[$agent] < count($lists[$agent])) {
            $queue[] = $agent;
            $queued[$agent] = true;
        }
    };
    foreach ($reverse ? $market->receivers() : $market->proposers() as $agent) $enqueue($agent);
    $proposals = 0;
    $log = [];
    for ($head = 0; $head < count($queue); $head++) {
        $x = $queue[$head];
        $queued[$x] = false;
        $y = $lists[$x][$next[$x]++];
        $proposals++;
        $action = 'REJECT';
        if (in_array($x, $lists[$y], true)) {
            if (count($holding[$y]) < $market->capacities[$y]) {
                $holding[$y][] = $x;
                $counts[$x]++;
                $action = 'HOLD';
            } else {
                $worst = 0;
                for ($i = 1; $i < count($holding[$y]); $i++)
                    if (rankOf($lists[$y], $holding[$y][$i]) > rankOf($lists[$y], $holding[$y][$worst])) $worst = $i;
                $rejected = $holding[$y][$worst];
                if (rankOf($lists[$y], $x) < rankOf($lists[$y], $rejected)) {
                    $holding[$y][$worst] = $x;
                    $counts[$rejected]--;
                    $counts[$x]++;
                    $action = 'HOLD REJECT ' . $market->agents[$rejected];
                    $enqueue($rejected);
                }
            }
        }
        if ($verbose) $log[] = "PROPOSE {$market->agents[$x]} {$market->agents[$y]} $action";
        $enqueue($x);
    }
    $partners = array_fill(0, $market->proposerCount, -1);
    foreach ($reverse ? $market->proposers() : $market->receivers() as $y)
        foreach ($holding[$y] as $x) $partners[$reverse ? $y : $x] = $reverse ? $x : $y;
    return new MatchingResult($partners, $proposals, $log);
}
function boston(Market $market, ?array $preferences = null): MatchingResult
{
    $lists = $preferences ?? $market->preferences;
    $partners = array_fill(0, $market->proposerCount, -1);
    $remaining = $market->capacities;
    $rounds = $applications = 0;
    foreach ($market->proposers() as $p) $rounds = max($rounds, count($lists[$p]));
    for ($round = 0; $round < $rounds; $round++) {
        $applicants = array_fill(0, $market->count, []);
        foreach ($market->proposers() as $p) {
            if ($partners[$p] >= 0 || $round >= count($lists[$p])) continue;
            $applicants[$lists[$p][$round]][] = $p;
            $applications++;
        }
        foreach ($market->receivers() as $r)
            foreach ($lists[$r] as $p)
                if ($remaining[$r] > 0 && in_array($p, $applicants[$r], true)) {
                    $partners[$p] = $r;
                    $remaining[$r]--;
                }
    }
    return new MatchingResult($partners, $applications);
}
function checkMatching(Market $market, array $partners): array
{
    $unacceptable = $blocking = [];
    $lists = $market->preferences;
    if ($market->kind === MarketKind::Roommates) {
        for ($a = 0; $a < $market->count; $a++)
            for ($b = $a + 1; $b < $market->count; $b++) {
                $mutual = acceptable($lists, $a, $b);
                if ($partners[$a] === $b) {
                    if (!$mutual) $unacceptable[] = [$a, $b];
                } elseif ($mutual && rankOf($lists[$a], $b) < rankOf($lists[$a], $partners[$a])
                    && rankOf($lists[$b], $a) < rankOf($lists[$b], $partners[$b])) $blocking[] = [$a, $b];
            }
    } else {
        foreach ($market->proposers() as $p) {
            if ($partners[$p] >= 0 && !acceptable($lists, $p, $partners[$p])) $unacceptable[] = [$p, $partners[$p]];
            foreach ($market->receivers() as $r) {
                if ($partners[$p] === $r || !acceptable($lists, $p, $r)
                    || rankOf($lists[$p], $r) >= rankOf($lists[$p], $partners[$p])) continue;
                $held = residents($market, $partners, $r);
                $worst = 0;
                foreach ($held as $a) $worst = max($worst, rankOf($lists[$r], $a));
                if (count($held) < $market->capacities[$r] || rankOf($lists[$r], $p) < $worst)
                    $blocking[] = [$p, $r];
            }
        }
    }
    return [$unacceptable, $blocking];
}
function candidateFor(Market $market, array $partners, int $origin, int $via): Candidate
{
    $cost = $regret = 0;
    foreach ($partners as $p => $r) {
        if ($r < 0) continue;
        $a = rankOf($market->preferences[$p], $r);
        $b = rankOf($market->preferences[$r], $p);
        $cost += $a + $b;
        $regret = max($regret, $a, $b);
    }
    return new Candidate($partners, $origin, $via, $cost, $regret);
}
function exposedRotations(Market $market, array $partners): array
{
    $owners = array_fill(0, $market->count, -1);
    foreach ($partners as $p => $r) if ($r >= 0) $owners[$r] = $p;
    $successors = array_fill(0, $market->proposerCount, -1);
    foreach ($partners as $p => $r) {
        if ($r < 0) continue;
        $preference = $market->preferences[$p];
        for ($i = array_search($r, $preference, true) + 1; $i < count($preference); $i++) {
            $w = $preference[$i];
            $owner = $owners[$w];
            if (in_array($p, $market->preferences[$w], true) && ($owner < 0
                || rankOf($market->preferences[$w], $p) < rankOf($market->preferences[$w], $owner))) {
                $successors[$p] = $owner;
                break;
            }
        }
    }
    $rotations = [];
    $covered = array_fill(0, $market->proposerCount, false);
    foreach ($market->proposers() as $start) {
        if ($covered[$start]) continue;
        $path = [];
        $seen = array_fill(0, $market->proposerCount, false);
        $current = $start;
        while ($current >= 0 && !$seen[$current]) {
            $seen[$current] = true;
            $path[] = $current;
            $current = $successors[$current];
        }
        if ($current !== $start) continue;
        $rotations[] = $path;
        foreach ($path as $p) $covered[$p] = true;
    }
    return $rotations;
}
function enumerateStable(Market $market): Enumeration
{
    foreach ($market->receivers() as $r)
        if ($market->capacities[$r] !== 1) throw new CommandError('NOT ONE TO ONE');
    $matchings = [candidateFor($market, deferred($market)->partners, 0, 0)];
    $rotations = $numbers = [];
    for ($index = 0; $index < count($matchings); $index++) {
        $partners = $matchings[$index]->partners;
        foreach (exposedRotations($market, $partners) as $rotation) {
            $parts = [];
            foreach ($rotation as $p) $parts[] = $market->agents[$p] . '-' . $market->agents[$partners[$p]];
            $notation = implode(' ', $parts);
            if (!isset($numbers[$notation])) {
                $rotations[] = $notation;
                $numbers[$notation] = count($rotations);
            }
            $next = $partners;
            foreach ($rotation as $i => $p) $next[$p] = $partners[$rotation[($i + 1) % count($rotation)]];
            $duplicate = false;
            foreach ($matchings as $candidate) if ($candidate->partners === $next) { $duplicate = true; break; }
            if ($duplicate) continue;
            if (count($matchings) === 50) throw new CommandError('TOO MANY MATCHINGS');
            $matchings[] = candidateFor($market, $next, $index + 1, $numbers[$notation]);
        }
    }
    return new Enumeration($matchings, $rotations);
}
function removePair(array &$lists, int $a, int $b): void
{
    $index = array_search($b, $lists[$a], true);
    if ($index !== false) array_splice($lists[$a], $index, 1);
    $index = array_search($a, $lists[$b], true);
    if ($index !== false) array_splice($lists[$b], $index, 1);
}
function firstEmpty(array $lists): int
{
    foreach ($lists as $a => $list) if ($list === []) return $a;
    return -1;
}
function tableLines(Market $market, array $lists): array
{
    $output = [];
    foreach ($lists as $a => $list)
        $output[] = "TABLE {$market->agents[$a]} " . listText(array_map(fn(int $b): string => $market->agents[$b], $list));
    return $output;
}
function roommates(Market $market, bool $verbose): array
{
    foreach ($market->preferences as $a => $list)
        if (count($list) < $market->count - 1) throw new CommandError("INCOMPLETE {$market->agents[$a]}");
    $lists = $market->preferences;
    $held = array_fill(0, $market->count, -1);
    $queue = range(0, $market->count - 1);
    $trace = [];
    $proposals = $rotations = 0;
    $failure = -1;
    for ($head = 0; $head < count($queue); $head++) {
        $x = $queue[$head];
        $y = $lists[$x][0];
        $proposals++;
        if ($held[$y] >= 0) $queue[] = $held[$y];
        $held[$y] = $x;
        $removed = array_slice($lists[$y], array_search($x, $lists[$y], true) + 1);
        foreach ($removed as $w) removePair($lists, $y, $w);
        $failure = firstEmpty($lists);
        if ($failure >= 0) break;
    }
    if ($failure < 0) {
        if ($verbose) array_push($trace, ...tableLines($market, $lists));
        while (true) {
            $p = -1;
            foreach ($lists as $a => $list) if (count($list) > 1) { $p = $a; break; }
            if ($p < 0) break;
            $seen = array_fill(0, $market->count, -1);
            $path = [];
            while ($seen[$p] < 0) {
                $seen[$p] = count($path);
                $path[] = $p;
                $q = $lists[$p][1];
                $p = $lists[$q][count($lists[$q]) - 1];
            }
            $xs = array_slice($path, $seen[$p]);
            $ys = array_map(fn(int $x): int => $lists[$x][0], $xs);
            $parts = [];
            foreach ($xs as $i => $x) $parts[] = $market->agents[$x] . '-' . $market->agents[$ys[$i]];
            $trace[] = 'ROTATION ' . ++$rotations . ' ' . implode(' ', $parts);
            $removals = [];
            foreach ($xs as $i => $x) {
                $u = $ys[($i + 1) % count($ys)];
                foreach (array_slice($lists[$u], array_search($x, $lists[$u], true) + 1) as $w)
                    $removals[] = [$u, $w];
            }
            foreach ($removals as [$a, $b]) removePair($lists, $a, $b);
            if ($verbose) array_push($trace, ...tableLines($market, $lists));
            $failure = firstEmpty($lists);
            if ($failure >= 0) break;
        }
    }
    $output = ["ROOMMATES {$market->name} proposals=$proposals", ...$trace];
    if ($failure >= 0) $output[] = "NO STABLE MATCHING {$market->agents[$failure]}";
    else {
        $pairs = [];
        foreach ($lists as $a => $list) if ($a < $list[0]) $pairs[] = $market->agents[$a] . '-' . $market->agents[$list[0]];
        $output[] = 'MATCHING ' . implode(' ', $pairs);
    }
    return $output;
}
function tradingCycles(Market $market): array
{
    $remaining = array_fill(0, $market->count, true);
    $allocation = array_fill(0, $market->count, -1);
    $effective = [];
    for ($a = 0; $a < $market->count; $a++) $effective[] = $market->effective($a);
    $cycles = [];
    while (($start = array_search(true, $remaining, true)) !== false) {
        $pointers = array_fill(0, $market->count, -1);
        foreach ($remaining as $a => $present) {
            if (!$present) continue;
            foreach ($effective[$a] as $h) if ($remaining[$h]) { $pointers[$a] = $h; break; }
        }
        $seen = array_fill(0, $market->count, -1);
        $path = [];
        $current = $start;
        while ($seen[$current] < 0) {
            $seen[$current] = count($path);
            $path[] = $current;
            $current = $pointers[$current];
        }
        $cycle = array_slice($path, $seen[$current]);
        $parts = [];
        foreach ($cycle as $a) {
            $allocation[$a] = $pointers[$a];
            $remaining[$a] = false;
            $parts[] = $market->agents[$a] . ':' . $market->houses[$allocation[$a]];
        }
        $cycles[] = 'CYCLE ' . (count($cycles) + 1) . ' ' . implode(' ', $parts);
    }
    return ['TTC ' . $market->name . ' cycles=' . count($cycles), ...$cycles, 'ALLOCATION ' . $market->allocation($allocation)];
}

final class Lab
{
    private array $markets = [];

    private function get(string $name, ?MarketKind $kind = null): Market
    {
        $market = $this->markets[$name] ?? throw new CommandError("UNKNOWN MARKET $name");
        if ($kind !== null && $market->kind !== $kind) throw new CommandError("WRONG TYPE $name");
        return $market;
    }
    private function newName(string $name): void
    {
        if (isset($this->markets[$name])) throw new CommandError("DUPLICATE MARKET $name");
    }
    private static function distinctAgents(array $agents): void
    {
        $seen = [];
        foreach ($agents as $agent) {
            if (isset($seen[$agent])) throw new CommandError("DUPLICATE AGENT $agent");
            $seen[$agent] = true;
        }
    }
    private static function show(Market $market): array
    {
        $preferences = [];
        $names = $market->kind === MarketKind::Housing ? $market->houses : $market->agents;
        foreach ($market->preferences as $list) $preferences[] = listText(array_map(fn(int $c): string => $names[$c], $list));
        if ($market->kind === MarketKind::TwoSided) {
            $output = ["SHOW {$market->name} MARKET proposers={$market->proposerCount} receivers=" . ($market->count - $market->proposerCount)];
            foreach ($market->proposers() as $p) $output[] = "PROPOSER {$market->agents[$p]} {$preferences[$p]}";
            foreach ($market->receivers() as $r)
                $output[] = "RECEIVER {$market->agents[$r]} cap={$market->capacities[$r]} {$preferences[$r]}";
            $output[] = "CURRENT {$market->source}";
        } else {
            $kind = $market->kind === MarketKind::Roommates ? 'ROOMS' : 'HOUSES';
            $output = ["SHOW {$market->name} $kind agents={$market->count}"];
            foreach ($market->agents as $a => $name)
                $output[] = "AGENT $name " . ($market->kind === MarketKind::Housing ? "house={$market->houses[$a]} " : '') . $preferences[$a];
        }
        return $output;
    }
    private static function check(Market $market, array $words): array
    {
        if ($market->kind === MarketKind::Housing) throw new CommandError("WRONG TYPE {$market->name}");
        $partners = array_fill(0, $market->kind === MarketKind::TwoSided ? $market->proposerCount : $market->count, -1);
        $used = array_fill(0, $market->count, false);
        $counts = array_fill(0, $market->count, 0);
        foreach (array_slice($words, 2) as $word) {
            [$first, $second] = explode('-', $word);
            if ($market->kind === MarketKind::TwoSided) {
                $p = $market->proposer($first);
                $r = $market->receiver($second);
                if ($used[$p]) throw new CommandError("DUPLICATE AGENT $first");
                if ($counts[$r] + 1 > $market->capacities[$r]) throw new CommandError("OVER CAPACITY $second");
                $used[$p] = true;
                $counts[$r]++;
                $partners[$p] = $r;
            } else {
                $a = $market->agent($first);
                $b = $market->agent($second);
                if ($used[$a]) throw new CommandError("DUPLICATE AGENT $first");
                if ($a === $b || $used[$b]) throw new CommandError("DUPLICATE AGENT $second");
                $used[$a] = $used[$b] = true;
                $partners[$a] = $b;
                $partners[$b] = $a;
            }
        }
        [$unacceptable, $blocking] = checkMatching($market, $partners);
        if ($unacceptable === [] && $blocking === []) return ["CHECK {$market->name} STABLE"];
        $output = ["CHECK {$market->name} UNSTABLE unacceptable=" . count($unacceptable) . ' blocking=' . count($blocking)];
        foreach ($unacceptable as [$a, $b]) $output[] = "UNACCEPTABLE {$market->agents[$a]} {$market->agents[$b]}";
        foreach ($blocking as [$a, $b]) $output[] = "BLOCKING {$market->agents[$a]} {$market->agents[$b]}";
        return $output;
    }
    private static function hospitals(Market $market): array
    {
        $a = deferred($market)->partners;
        $h = deferred($market, true)->partners;
        $unmatched = [];
        $rural = true;
        foreach ($market->proposers() as $p) {
            if ($a[$p] < 0) $unmatched[] = $market->agents[$p];
            if (($a[$p] >= 0) !== ($h[$p] >= 0)) $rural = false;
        }
        $output = ["HR {$market->name} residents={$market->proposerCount} hospitals=" . ($market->count - $market->proposerCount),
            'RESIDENT-OPTIMAL ' . $market->pairs($a), 'HOSPITAL-OPTIMAL ' . $market->pairs($h), 'UNMATCHED ' . listText($unmatched)];
        foreach ($market->receivers() as $r) {
            $first = residents($market, $a, $r);
            $second = residents($market, $h, $r);
            $same = $first === $second;
            $output[] = "HOSPITAL {$market->agents[$r]} cap={$market->capacities[$r]} resident=" . count($first)
                . ' hospital=' . count($second) . ' same=' . ($same ? 'YES' : 'NO');
            $rural = $rural && count($first) === count($second) && (count($first) === $market->capacities[$r] || $same);
        }
        $output[] = $rural ? 'RURAL HOLDS' : 'RURAL FAILS';
        return $output;
    }
    private static function serial(Market $market, array $words): array
    {
        $order = $seen = [];
        foreach (array_slice($words, 2) as $name) {
            $agent = $market->agent($name);
            if (isset($seen[$agent])) throw new CommandError("DUPLICATE AGENT $name");
            $seen[$agent] = true;
            $order[] = $agent;
        }
        if (count($order) !== $market->count) throw new CommandError('BAD ORDER');
        $allocation = array_fill(0, $market->count, -1);
        $remaining = array_fill(0, $market->count, true);
        $assigned = 0;
        foreach ($order as $a)
            foreach ($market->preferences[$a] as $house)
                if ($remaining[$house]) {
                    $allocation[$a] = $house;
                    $remaining[$house] = false;
                    $assigned++;
                    break;
                }
        $worse = [];
        foreach ($allocation as $a => $house)
            if ($house < 0 || !in_array($house, $market->effective($a), true)) $worse[] = $market->agents[$a];
        return ["SERIAL {$market->name} assigned=$assigned", 'ALLOCATION ' . $market->allocation($allocation), 'WORSE ' . listText($worse)];
    }
    private static function manipulate(Market $market, int $agent): array
    {
        $truth = $market->preferences[$agent];
        $b0 = boston($market)->partners[$agent];
        $g0 = deferred($market)->partners[$agent];
        $output = ["MANIPULATE {$market->name} {$market->agents[$agent]} boston=" . $market->partner($b0)
            . ' gs=' . $market->partner($g0) . ' swaps=' . max(0, count($truth) - 1)];
        for ($i = 0; $i + 1 < count($truth); $i++) {
            $preferences = $market->preferences;
            $preferences[$agent] = $truth;
            $preferences[$agent][$i] = $truth[$i + 1];
            $preferences[$agent][$i + 1] = $truth[$i];
            $b = boston($market, $preferences)->partners[$agent];
            $g = deferred($market, preferences: $preferences)->partners[$agent];
            $swap = ($i + 1) . " {$market->agents[$truth[$i]]} {$market->agents[$truth[$i + 1]]}";
            if (rankOf($truth, $b) < rankOf($truth, $b0)) $output[] = "IMPROVE BOSTON $swap result=" . $market->partner($b);
            if (rankOf($truth, $g) < rankOf($truth, $g0)) $output[] = "IMPROVE GS $swap result=" . $market->partner($g);
        }
        if (count($output) === 1) $output[] = 'NO IMPROVEMENT';
        return $output;
    }
    private static function rankSummary(array $ranks): string
    {
        $sum = array_sum($ranks);
        $first = count(array_filter($ranks, fn(int $rank): bool => $rank === 1));
        $average = $truncated = '-';
        if ($ranks !== []) {
            $a = $sum;
            $b = count($ranks);
            while ($b !== 0) [$a, $b] = [$b, $a % $b];
            $average = intdiv($sum, $a) . '/' . intdiv(count($ranks), $a);
            $cents = intdiv($sum * 100, count($ranks));
            $truncated = intdiv($cents, 100) . '.' . str_pad((string)($cents % 100), 2, '0', STR_PAD_LEFT);
        }
        return "sum=$sum average=$average truncated=$truncated first=$first";
    }
    private static function stats(Market $market): array
    {
        $partners = $market->current ?? throw new CommandError('NO MATCHING');
        $proposerRanks = $receiverRanks = $occupied = [];
        foreach ($partners as $p => $r) {
            if ($r < 0) continue;
            $proposerRanks[] = rankOf($market->preferences[$p], $r);
            $receiverRanks[] = rankOf($market->preferences[$r], $p);
            $occupied[$r] = true;
        }
        $pairs = count($proposerRanks);
        return ["STATS {$market->name} source={$market->source} pairs=$pairs",
            'PROPOSERS ' . self::rankSummary($proposerRanks) . ' unmatched=' . ($market->proposerCount - $pairs),
            'RECEIVERS ' . self::rankSummary($receiverRanks) . ' unmatched=' . ($market->count - $market->proposerCount - count($occupied))];
    }
    public function execute(string $line): array
    {
        $words = explode(' ', $line);
        [$command, $name] = $words;
        switch ($command) {
            case 'MARKET':
                $this->newName($name);
                $bar = array_search('|', $words, true);
                $proposers = array_slice($words, 2, $bar - 2);
                $receivers = array_slice($words, $bar + 1);
                $agents = [...$proposers, ...$receivers];
                self::distinctAgents($agents);
                $this->markets[$name] = new Market($name, MarketKind::TwoSided, $agents, count($proposers));
                return ["MARKET $name proposers=" . count($proposers) . ' receivers=' . count($receivers)];
            case 'ROOMS':
                $this->newName($name);
                $agents = array_slice($words, 2);
                self::distinctAgents($agents);
                $this->markets[$name] = new Market($name, MarketKind::Roommates, $agents);
                return ["ROOMS $name agents=" . count($agents)];
            case 'HOUSES':
                $this->newName($name);
                $agents = $houses = [];
                foreach (array_slice($words, 2) as $word) {
                    [$agent, $house] = explode(':', $word);
                    if (in_array($agent, $agents, true)) throw new CommandError("DUPLICATE AGENT $agent");
                    if (in_array($house, $houses, true)) throw new CommandError("DUPLICATE HOUSE $house");
                    $agents[] = $agent;
                    $houses[] = $house;
                }
                $this->markets[$name] = new Market($name, MarketKind::Housing, $agents, houses: $houses);
                return ["HOUSES $name agents=" . count($agents)];
            case 'RANDOM':
                $this->newName($name);
                $n = (int)$words[2];
                $seed = (int)$words[3];
                $agents = [];
                for ($i = 1; $i <= $n; $i++) $agents[] = 'P' . $i;
                for ($i = 1; $i <= $n; $i++) $agents[] = 'R' . $i;
                $market = new Market($name, MarketKind::TwoSided, $agents, $n);
                $state = $seed;
                for ($a = 0; $a < $market->count; $a++) {
                    $list = $a < $n ? $market->receivers() : $market->proposers();
                    for ($i = $n - 1; $i > 0; $i--) {
                        $state = 48271 * $state % 2147483647;
                        $j = $state % ($i + 1);
                        [$list[$i], $list[$j]] = [$list[$j], $list[$i]];
                    }
                    $market->preferences[$a] = $list;
                }
                $this->markets[$name] = $market;
                return ["RANDOM $name n=$n seed=$seed"];
            case 'PREF':
                $market = $this->get($name);
                $agent = $market->agent($words[2]);
                $choices = [];
                foreach (array_slice($words, 3) as $word) {
                    $choice = $market->choice($agent, $word);
                    if (in_array($choice, $choices, true)) throw new CommandError("DUPLICATE CHOICE $word");
                    $choices[] = $choice;
                }
                $market->preferences[$agent] = $choices;
                if ($market->kind === MarketKind::TwoSided) $market->clearMatching();
                return ["PREF $name {$words[2]} length=" . count($choices)];
            case 'CAPACITY':
                $market = $this->get($name, MarketKind::TwoSided);
                $receiver = $market->receiver($words[2]);
                $capacity = (int)$words[3];
                $market->capacities[$receiver] = $capacity;
                $market->clearMatching();
                return ["CAPACITY $name {$words[2]} $capacity"];
            case 'SHOW': return self::show($this->get($name));
            case 'GS': case 'GSR':
                $market = $this->get($name, MarketKind::TwoSided);
                $result = deferred($market, $command === 'GSR', count($words) === 3);
                $market->setMatching($result->partners, $command);
                return ["$command $name proposals={$result->count}", ...$result->log, 'MATCHING ' . $market->pairs($result->partners)];
            case 'CHECK': return self::check($this->get($name), $words);
            case 'LATTICE': case 'EGALITARIAN': case 'MINREGRET':
                $market = $this->get($name, MarketKind::TwoSided);
                $enumeration = enumerateStable($market);
                if ($command === 'LATTICE') {
                    $output = ["LATTICE $name matchings=" . count($enumeration->matchings) . ' rotations=' . count($enumeration->rotations)];
                    foreach ($enumeration->matchings as $i => $candidate) {
                        $from = $candidate->origin === 0 ? '-' : (string)$candidate->origin;
                        $via = $candidate->via === 0 ? '-' : (string)$candidate->via;
                        $output[] = 'MATCHING ' . ($i + 1) . " from=$from via=$via cost={$candidate->cost} regret={$candidate->regret} "
                            . $market->pairs($candidate->partners);
                    }
                    foreach ($enumeration->rotations as $i => $notation) $output[] = 'ROTATION ' . ($i + 1) . ' ' . $notation;
                    return $output;
                }
                $field = $command === 'EGALITARIAN' ? 'cost' : 'regret';
                $best = 0;
                foreach ($enumeration->matchings as $i => $candidate)
                    if ($candidate->$field < $enumeration->matchings[$best]->$field) $best = $i;
                $chosen = $enumeration->matchings[$best];
                $market->setMatching($chosen->partners, $command);
                return ["$command $name matching=" . ($best + 1) . " $field=" . $chosen->$field, 'MATCHING ' . $market->pairs($chosen->partners)];
            case 'HR': return self::hospitals($this->get($name, MarketKind::TwoSided));
            case 'ROOMMATES': return roommates($this->get($name, MarketKind::Roommates), count($words) === 3);
            case 'TTC': return tradingCycles($this->get($name, MarketKind::Housing));
            case 'SERIAL': return self::serial($this->get($name, MarketKind::Housing), $words);
            case 'BOSTON':
                $market = $this->get($name, MarketKind::TwoSided);
                $result = boston($market);
                $market->setMatching($result->partners, $command);
                return ["BOSTON $name applications={$result->count}", 'MATCHING ' . $market->pairs($result->partners)];
            case 'MANIPULATE':
                $market = $this->get($name, MarketKind::TwoSided);
                return self::manipulate($market, $market->proposer($words[2]));
            case 'STATS': return self::stats($this->get($name, MarketKind::TwoSided));
        }
        throw new LogicException('Unreachable command');
    }
}

$lab = new Lab();
$count = (int)trim(fgets(STDIN));
for ($i = 0; $i < $count; $i++) {
    $line = rtrim(fgets(STDIN), "\r\n");
    try {
        $output = $lab->execute($line);
        echo implode("\n", $output), "\n";
    } catch (CommandError $error) {
        echo $error->getMessage(), "\n";
    }
}
