<?php

declare(strict_types=1);

final class CommandError extends RuntimeException {}

function gcd(int $a, int $b): int
{
    $a = abs($a);
    $b = abs($b);
    while ($b !== 0) [$a, $b] = [$b, $a % $b];
    return $a;
}

final readonly class Fraction
{
    public int $numerator;
    public int $denominator;

    public function __construct(int $numerator, int $denominator = 1)
    {
        if ($denominator < 0) [$numerator, $denominator] = [-$numerator, -$denominator];
        $divisor = gcd($numerator, $denominator);
        $this->numerator = intdiv($numerator, $divisor);
        $this->denominator = intdiv($denominator, $divisor);
    }

    public static function zero(): self { static $value; return $value ??= new self(0); }
    public static function one(): self { static $value; return $value ??= new self(1); }
    public static function two(): self { static $value; return $value ??= new self(2); }
    public function add(self $other): self
    {
        return new self($this->numerator * $other->denominator + $other->numerator * $this->denominator,
                        $this->denominator * $other->denominator);
    }
    public function subtract(self $other): self
    {
        return new self($this->numerator * $other->denominator - $other->numerator * $this->denominator,
                        $this->denominator * $other->denominator);
    }
    public function multiply(self $other): self
    {
        return new self($this->numerator * $other->numerator, $this->denominator * $other->denominator);
    }
    public function divide(self $other): self
    {
        return new self($this->numerator * $other->denominator, $this->denominator * $other->numerator);
    }
    public function absolute(): self { return new self(abs($this->numerator), $this->denominator); }
    public function isZero(): bool { return $this->numerator === 0; }
    public function equals(self $other): bool
    {
        return $this->numerator === $other->numerator && $this->denominator === $other->denominator;
    }
    public function compareTo(self $other): int
    {
        return $this->numerator * $other->denominator <=> $other->numerator * $this->denominator;
    }
    public function __toString(): string { return "$this->numerator/$this->denominator"; }
    public function value(): string
    {
        $whole = intdiv($this->numerator, $this->denominator);
        $decimal = intdiv(($this->numerator % $this->denominator) * 1000000, $this->denominator);
        return $this . '(' . $whole . '.' . str_pad((string) $decimal, 6, '0', STR_PAD_LEFT) . ')';
    }
}

function probability(string $text): Fraction
{
    $parts = explode('/', $text);
    $numerator = (int) $parts[0];
    $denominator = isset($parts[1]) ? (int) $parts[1] : 1;
    if ($denominator === 0 || $numerator > $denominator) throw new CommandError('BAD PROBABILITY');
    return new Fraction($numerator, $denominator);
}

function vector(int $size): array { return array_fill(0, $size, Fraction::zero()); }

function matrix(int $rows, int $columns): array
{
    $result = [];
    for ($i = 0; $i < $rows; ++$i) $result[] = vector($columns);
    return $result;
}

function delta(int $i, int $j): Fraction { return $i === $j ? Fraction::one() : Fraction::zero(); }
function sum(iterable $values): Fraction
{
    $total = Fraction::zero();
    foreach ($values as $value) $total = $total->add($value);
    return $total;
}

function identity(int $size): array
{
    $result = matrix($size, $size);
    for ($i = 0; $i < $size; ++$i) $result[$i][$i] = Fraction::one();
    return $result;
}

function advance(array $distribution, array $transitions): array
{
    $size = count($distribution);
    $result = vector($size);
    for ($j = 0; $j < $size; ++$j)
        for ($i = 0; $i < $size; ++$i)
            $result[$j] = $result[$j]->add($distribution[$i]->multiply($transitions[$i][$j]));
    return $result;
}

function multiply(array $left, array $right): array
{
    $result = [];
    foreach ($left as $row) $result[] = advance($row, $right);
    return $result;
}

function solve(array $rows): array
{
    $size = count($rows);
    if ($size === 0) return [];
    $width = count($rows[0]);
    for ($column = 0; $column < $size; ++$column) {
        $pivotRow = $column;
        while ($rows[$pivotRow][$column]->isZero()) ++$pivotRow;
        [$rows[$column], $rows[$pivotRow]] = [$rows[$pivotRow], $rows[$column]];
        $pivot = $rows[$column][$column];
        for ($j = 0; $j < $width; ++$j) $rows[$column][$j] = $rows[$column][$j]->divide($pivot);
        for ($i = 0; $i < $size; ++$i) {
            if ($i === $column) continue;
            $factor = $rows[$i][$column];
            if ($factor->isZero()) continue;
            for ($j = 0; $j < $width; ++$j)
                $rows[$i][$j] = $rows[$i][$j]->subtract($factor->multiply($rows[$column][$j]));
        }
    }
    return array_map(static fn(array $row): array => array_slice($row, $size), $rows);
}

final readonly class Component
{
    public function __construct(public array $states, public bool $closed, public int $period, public array $levels) {}
}
final readonly class Graph
{
    public function __construct(public array $reach, public array $classes) {}
}
final readonly class Hitting
{
    public function __construct(public array $probability, public array $time) {}
}
final readonly class Absorption
{
    public function __construct(public array $transient, public array $absorbing, public array $fundamental,
        public array $probability, public array $mean, public array $variance) {}
}

final class Chain
{
    private readonly array $positions;
    public function __construct(public readonly array $names, public array $p)
    {
        $this->positions = array_flip($names);
    }
    public function size(): int { return count($this->names); }
    public function labels(array $states, string $separator = ' '): string
    {
        return implode($separator, array_map(fn(int $i): string => $this->names[$i], $states));
    }
    public function state(string $name): int
    {
        return $this->positions[$name] ?? throw new CommandError("UNKNOWN STATE $name");
    }
    public function stateSet(array $names): array
    {
        $seen = [];
        foreach ($names as $name) {
            $state = $this->state($name);
            if (isset($seen[$state])) throw new CommandError("DUPLICATE STATE $name");
            $seen[$state] = true;
        }
        $states = array_keys($seen);
        sort($states, SORT_NUMERIC);
        return $states;
    }
    public function stochastic(): void
    {
        foreach ($this->p as $i => $row)
            if (!sum($row)->equals(Fraction::one())) throw new CommandError('NOT STOCHASTIC ' . $this->names[$i]);
    }
    public function graph(): Graph
    {
        $size = $this->size();
        $reach = [];
        for ($i = 0; $i < $size; ++$i)
            for ($j = 0; $j < $size; ++$j) $reach[$i][$j] = $i === $j || !$this->p[$i][$j]->isZero();
        for ($k = 0; $k < $size; ++$k)
            for ($i = 0; $i < $size; ++$i)
                for ($j = 0; $j < $size; ++$j) $reach[$i][$j] = $reach[$i][$j] || $reach[$i][$k] && $reach[$k][$j];
        $assigned = [];
        $classes = [];
        for ($first = 0; $first < $size; ++$first) {
            if (isset($assigned[$first])) continue;
            $states = [];
            for ($j = 0; $j < $size; ++$j)
                if ($reach[$first][$j] && $reach[$j][$first]) $states[] = $j;
            $members = array_fill_keys($states, true);
            $closed = true;
            foreach ($states as $i) {
                $assigned[$i] = true;
                for ($j = 0; $j < $size; ++$j)
                    if (!isset($members[$j]) && !$this->p[$i][$j]->isZero()) $closed = false;
            }
            $levels = array_fill(0, $size, -1);
            $levels[$first] = 0;
            $queue = [$first];
            for ($head = 0; $head < count($queue); ++$head) {
                $i = $queue[$head];
                foreach ($states as $j)
                    if ($levels[$j] < 0 && !$this->p[$i][$j]->isZero()) {
                        $levels[$j] = $levels[$i] + 1;
                        $queue[] = $j;
                    }
            }
            $period = 0;
            foreach ($states as $i)
                foreach ($states as $j)
                    if (!$this->p[$i][$j]->isZero()) $period = gcd($period, $levels[$i] + 1 - $levels[$j]);
            $classes[] = new Component($states, $closed, $period, $levels);
        }
        return new Graph($reach, $classes);
    }
    public function stationary(array $states): array
    {
        $count = count($states);
        $equations = matrix($count, $count + 1);
        for ($row = 0; $row < $count - 1; ++$row)
            for ($col = 0; $col < $count; ++$col)
                $equations[$row][$col] = $this->p[$states[$col]][$states[$row]]->subtract(delta($col, $row));
        $equations[$count - 1] = array_fill(0, $count + 1, Fraction::one());
        $solution = solve($equations);
        $distribution = vector($this->size());
        foreach ($states as $i => $state) $distribution[$state] = $solution[$i][0];
        return $distribution;
    }
    public function uniqueStationary(): array
    {
        $classes = $this->graph()->classes;
        if (count($classes) !== 1) throw new CommandError('NOT IRREDUCIBLE');
        return $this->stationary($classes[0]->states);
    }
    public function blockSum(int $from, array $targets): Fraction
    {
        $total = Fraction::zero();
        foreach ($targets as $target) $total = $total->add($this->p[$from][$target]);
        return $total;
    }
    public function hitting(array $targets, bool $withTimes = true): Hitting
    {
        $reach = $this->graph()->reach;
        $inside = array_fill_keys($targets, true);
        $probability = vector($this->size());
        $time = array_fill(0, $this->size(), null);
        $unknown = [];
        for ($i = 0; $i < $this->size(); ++$i) {
            if (isset($inside[$i])) {
                $probability[$i] = Fraction::one();
                $time[$i] = Fraction::zero();
            } else {
                foreach ($targets as $j)
                    if ($reach[$i][$j]) { $unknown[] = $i; break; }
            }
        }
        if ($unknown !== []) {
            $count = count($unknown);
            $equations = matrix($count, $count + 1);
            foreach ($unknown as $i => $from) {
                foreach ($unknown as $j => $to) $equations[$i][$j] = delta($i, $j)->subtract($this->p[$from][$to]);
                $equations[$i][$count] = $this->blockSum($from, $targets);
            }
            $solution = solve($equations);
            foreach ($unknown as $i => $state) $probability[$state] = $solution[$i][0];
        }
        if ($withTimes) {
            $certain = [];
            foreach ($unknown as $i) if ($probability[$i]->equals(Fraction::one())) $certain[] = $i;
            if ($certain !== []) {
                $count = count($certain);
                $equations = matrix($count, $count + 1);
                foreach ($certain as $i => $from) {
                    foreach ($certain as $j => $to) $equations[$i][$j] = delta($i, $j)->subtract($this->p[$from][$to]);
                    $equations[$i][$count] = Fraction::one();
                }
                $solution = solve($equations);
                foreach ($certain as $i => $state) $time[$state] = $solution[$i][0];
            }
        }
        return new Hitting($probability, $time);
    }
    public function absorption(): Absorption
    {
        $absorbing = $transient = [];
        for ($i = 0; $i < $this->size(); ++$i) {
            if ($this->p[$i][$i]->equals(Fraction::one())) $absorbing[] = $i;
            else $transient[] = $i;
        }
        if ($absorbing === []) throw new CommandError('NO ABSORBING STATE');
        $reach = $this->graph()->reach;
        foreach ($transient as $i) {
            $found = false;
            foreach ($absorbing as $j) if ($reach[$i][$j]) { $found = true; break; }
            if (!$found) throw new CommandError('NOT ABSORBING ' . $this->names[$i]);
        }
        $count = count($transient);
        $equations = matrix($count, 2 * $count);
        foreach ($transient as $i => $from)
            foreach ($transient as $j => $to) {
                $equations[$i][$j] = delta($i, $j)->subtract($this->p[$from][$to]);
                $equations[$i][$count + $j] = delta($i, $j);
            }
        $fundamental = solve($equations);
        $mean = array_map('sum', $fundamental);
        $variance = vector($count);
        $probability = matrix($count, count($absorbing));
        for ($i = 0; $i < $count; ++$i) {
            for ($j = 0; $j < $count; ++$j)
                $variance[$i] = $variance[$i]->add(Fraction::two()->multiply($fundamental[$i][$j])
                    ->subtract(delta($i, $j))->multiply($mean[$j]));
            $variance[$i] = $variance[$i]->subtract($mean[$i]->multiply($mean[$i]));
            foreach ($absorbing as $j => $target)
                foreach ($transient as $k => $state)
                    $probability[$i][$j] = $probability[$i][$j]->add($fundamental[$i][$k]->multiply($this->p[$state][$target]));
        }
        return new Absorption($transient, $absorbing, $fundamental, $probability, $mean, $variance);
    }
}

final class Analyzer
{
    private array $chains = [];
    private array $output = [];

    private function emit(string|int ...$parts): void { $this->output[] = implode(' ', $parts); }
    private static function yes(bool $value): string { return $value ? 'yes' : 'no'; }
    public function result(): string { return implode("\n", $this->output) . "\n"; }

    private function display(Chain $chain, ?array $values = null, string $label = 'ROW'): void
    {
        $values ??= $chain->p;
        $this->emit('STATES', implode(' ', $chain->names));
        foreach ($values as $i => $row) $this->emit($label, $chain->names[$i], implode(' ', array_map('strval', $row)));
    }
    private function create(array $words): void
    {
        $names = array_slice($words, 2);
        if (count($names) > 10) throw new CommandError('TOO MANY STATES');
        $seen = [];
        foreach ($names as $name) {
            if (isset($seen[$name])) throw new CommandError("DUPLICATE STATE $name");
            $seen[$name] = true;
        }
        $this->chains[$words[1]] = new Chain($names, matrix(count($names), count($names)));
        $this->emit('CHAIN', $words[1], 'states=' . count($names));
    }
    private function build(array $words): void
    {
        $order = (int) $words[2];
        if ($order !== 1 && $order !== 2) throw new CommandError('BAD ORDER');
        $tokens = array_slice($words, 3);
        if (count($tokens) <= $order) throw new CommandError('TOO FEW TOKENS');
        $observations = [];
        for ($i = 0; $i < count($tokens) - $order + 1; ++$i)
            $observations[] = $order === 1 ? $tokens[$i] : $tokens[$i] . '.' . $tokens[$i + 1];
        $names = $positions = [];
        foreach ($observations as $state)
            if (!isset($positions[$state])) {
                $positions[$state] = count($names);
                $names[] = $state;
            }
        $size = count($names);
        if ($size > 10) throw new CommandError('TOO MANY STATES');
        $chain = new Chain($names, matrix($size, $size));
        $counts = array_fill(0, $size, array_fill(0, $size, 0));
        $totals = array_fill(0, $size, 0);
        for ($i = 1; $i < count($observations); ++$i) {
            $from = $positions[$observations[$i - 1]];
            $to = $positions[$observations[$i]];
            ++$counts[$from][$to];
            ++$totals[$from];
        }
        for ($i = 0; $i < $size; ++$i) {
            if ($totals[$i] === 0) $chain->p[$i][$i] = Fraction::one();
            else for ($j = 0; $j < $size; ++$j) $chain->p[$i][$j] = new Fraction($counts[$i][$j], $totals[$i]);
        }
        $this->chains[$words[1]] = $chain;
        $this->emit('BUILD', $words[1], 'order=' . $order, 'states=' . $size, 'transitions=' . (count($observations) - 1));
        for ($i = 0; $i < $size; ++$i) {
            $targets = [];
            for ($j = 0; $j < $size; ++$j) if ($counts[$i][$j] > 0) $targets[] = $names[$j] . ':' . $counts[$i][$j];
            $this->emit('FROM', $names[$i], 'total=' . $totals[$i], $totals[$i] === 0 ? 'absorbing' : implode(' ', $targets));
        }
    }
    private function gambler(array $words): void
    {
        $goal = (int) $words[2];
        $start = (int) $words[3];
        if ($goal === 0 || $goal > 9) throw new CommandError('BAD SIZE');
        if ($start > $goal) throw new CommandError('BAD START');
        $up = probability($words[4]);
        if ($up->isZero() || $up->equals(Fraction::one())) throw new CommandError('BAD PROBABILITY');
        $names = [];
        for ($i = 0; $i <= $goal; ++$i) $names[] = 's' . $i;
        $chain = new Chain($names, matrix($goal + 1, $goal + 1));
        $chain->p[0][0] = $chain->p[$goal][$goal] = Fraction::one();
        for ($i = 1; $i < $goal; ++$i) {
            $chain->p[$i][$i - 1] = Fraction::one()->subtract($up);
            $chain->p[$i][$i + 1] = $up;
        }
        $result = $chain->absorption();
        $ruin = $duration = vector($goal + 1);
        $ruin[0] = Fraction::one();
        foreach ($result->transient as $i => $state) {
            $ruin[$state] = $result->probability[$i][0];
            $duration[$state] = $result->mean[$i];
        }
        $this->chains[$words[1]] = $chain;
        $this->emit('GAMBLER', $words[1], 'g=' . $goal, 'p=' . $up, 'start=s' . $start,
            'ruin=' . $ruin[$start]->value(), 'duration=' . $duration[$start]->value());
        for ($i = 0; $i <= $goal; ++$i)
            $this->emit('CAPITAL', 's' . $i, 'ruin=' . $ruin[$i]->value(),
                'win=' . Fraction::one()->subtract($ruin[$i])->value(), 'duration=' . $duration[$i]->value());
    }
    private function classes(string $name, Chain $chain): void
    {
        $classes = $chain->graph()->classes;
        $this->emit('CLASSES', $name, 'count=' . count($classes));
        foreach ($classes as $i => $component) {
            $this->emit('CLASS', $i + 1, $component->closed ? 'RECURRENT' : 'TRANSIENT',
                'period=' . $component->period, 'size=' . count($component->states), $chain->labels($component->states));
            if ($component->period >= 2)
                for ($r = 0; $r < $component->period; ++$r) {
                    $states = [];
                    foreach ($component->states as $state)
                        if ($component->levels[$state] % $component->period === $r) $states[] = $state;
                    $this->emit('CYCLIC', $r, $chain->labels($states));
                }
        }
    }
    private function classify(string $name, Chain $chain): void
    {
        $graph = $chain->graph();
        $size = $chain->size();
        $absorbing = [];
        for ($i = 0; $i < $size; ++$i) if ($chain->p[$i][$i]->equals(Fraction::one())) $absorbing[] = $i;
        $allAbsorbed = $absorbing !== [];
        for ($i = 0; $i < $size; ++$i) {
            $found = false;
            foreach ($absorbing as $j) if ($graph->reach[$i][$j]) { $found = true; break; }
            if (!$found) $allAbsorbed = false;
        }
        $edges = [];
        for ($i = 0; $i < $size; ++$i)
            for ($j = 0; $j < $size; ++$j) $edges[$i][$j] = !$chain->p[$i][$j]->isZero();
        $power = $edges;
        $exponent = null;
        $bound = ($size - 1) * ($size - 1) + 1;
        for ($t = 1; $t <= $bound; ++$t) {
            $all = true;
            foreach ($power as $row) foreach ($row as $positive) if (!$positive) $all = false;
            if ($all) { $exponent = $t; break; }
            $next = array_fill(0, $size, array_fill(0, $size, false));
            for ($i = 0; $i < $size; ++$i)
                for ($j = 0; $j < $size; ++$j)
                    for ($k = 0; $k < $size; ++$k) $next[$i][$j] = $next[$i][$j] || $power[$i][$k] && $edges[$k][$j];
            $power = $next;
        }
        $this->emit('CLASSIFY', $name, 'absorbing_states=' . count($absorbing), 'absorbing=' . self::yes($allAbsorbed),
            'ergodic=' . self::yes(count($graph->classes) === 1), 'regular=' . self::yes($exponent !== null),
            'exponent=' . ($exponent ?? '-'));
    }
    private function step(array $words, Chain $chain): void
    {
        if (ctype_digit($words[2][0])) {
            $values = explode(',', $words[2]);
            if (count($values) !== $chain->size()) throw new CommandError('BAD LENGTH');
            $distribution = array_map('probability', $values);
            if (!sum($distribution)->equals(Fraction::one())) throw new CommandError('BAD DISTRIBUTION');
        } else {
            $distribution = vector($chain->size());
            $distribution[$chain->state($words[2])] = Fraction::one();
        }
        $steps = (int) $words[3];
        for ($t = 0; $t < $steps; ++$t) $distribution = advance($distribution, $chain->p);
        $this->emit('STEP', $words[1], 'k=' . $steps);
        foreach ($chain->names as $i => $name) $this->emit('PROB', $name, $distribution[$i]->value());
    }
    private function stationary(string $name, Chain $chain): void
    {
        $classes = $chain->graph()->classes;
        $count = count(array_filter($classes, static fn(Component $component): bool => $component->closed));
        $this->emit('STATIONARY', $name, 'count=' . $count);
        $number = 0;
        foreach ($classes as $i => $component) {
            if (!$component->closed) continue;
            $distribution = $chain->stationary($component->states);
            $this->emit('DIST', ++$number, 'class=' . ($i + 1), 'size=' . count($component->states));
            foreach ($component->states as $state) $this->emit('PI', $chain->names[$state], $distribution[$state]->value());
        }
    }
    private function recurrence(array $words, Chain $chain): void
    {
        $state = $chain->state($words[2]);
        foreach ($chain->graph()->classes as $component) {
            if (!in_array($state, $component->states, true)) continue;
            if (!$component->closed) throw new CommandError('TRANSIENT STATE ' . $words[2]);
            $rho = $chain->stationary($component->states)[$state];
            $this->emit('RECURRENCE', $words[1], $words[2], 'pi=' . $rho->value(),
                'mean=' . Fraction::one()->divide($rho)->value(), 'period=' . $component->period);
            return;
        }
    }
    private function absorb(string $name, Chain $chain): void
    {
        $result = $chain->absorption();
        $this->emit('ABSORB', $name, 'transient=' . count($result->transient), 'absorbing=' . count($result->absorbing));
        if ($result->transient === []) return;
        $this->emit('TRANSIENT', $chain->labels($result->transient));
        $this->emit('ABSORBING', $chain->labels($result->absorbing));
        foreach ($result->transient as $i => $state)
            $this->emit('N', $chain->names[$state], implode(' ', array_map('strval', $result->fundamental[$i])));
        foreach ($result->transient as $i => $state)
            $this->emit('STEPS', $chain->names[$state], 'mean=' . $result->mean[$i]->value(), 'var=' . $result->variance[$i]->value());
        foreach ($result->transient as $i => $state)
            $this->emit('B', $chain->names[$state], implode(' ', array_map('strval', $result->probability[$i])));
    }
    private function hitting(array $words, Chain $chain): void
    {
        $targets = $chain->stateSet(array_slice($words, 2));
        $result = $chain->hitting($targets);
        $this->emit('HITTING', $words[1], 'targets=' . $chain->labels($targets, ','));
        foreach ($chain->names as $i => $name)
            $this->emit('HIT', $name, 'prob=' . $result->probability[$i]->value(), 'time=' . ($result->time[$i]?->value() ?? 'inf'));
    }
    private function passage(string $name, Chain $chain): void
    {
        $pi = $chain->uniqueStationary();
        $size = $chain->size();
        $values = matrix($size, $size);
        for ($j = 0; $j < $size; ++$j) {
            $times = $chain->hitting([$j])->time;
            for ($i = 0; $i < $size; ++$i) $values[$i][$j] = $i === $j ? Fraction::one()->divide($pi[$j]) : $times[$i];
        }
        $kemeny = Fraction::zero();
        for ($j = 1; $j < $size; ++$j) $kemeny = $kemeny->add($pi[$j]->multiply($values[0][$j]));
        $this->emit('PASSAGE', $name, 'kemeny=' . $kemeny->value());
        $this->display($chain, $values, 'M');
    }
    private function firstPassage(array $words, Chain $chain): void
    {
        $from = $chain->state($words[2]);
        $target = $chain->state($words[3]);
        $steps = (int) $words[4];
        if ($steps === 0) throw new CommandError('BAD STEPS');
        $current = [];
        foreach ($chain->p as $row) $current[] = $row[$target];
        $entries = [];
        $total = Fraction::zero();
        for ($t = 1; $t <= $steps; ++$t) {
            $total = $total->add($current[$from]);
            $entries[] = [$current[$from], $total];
            if ($t < $steps) {
                $next = vector($chain->size());
                for ($i = 0; $i < $chain->size(); ++$i)
                    for ($j = 0; $j < $chain->size(); ++$j)
                        if ($j !== $target) $next[$i] = $next[$i]->add($chain->p[$i][$j]->multiply($current[$j]));
                $current = $next;
            }
        }
        $this->emit('FIRSTPASSAGE', $words[1], $words[2], $words[3], 'k=' . $steps, 'total=' . $total->value());
        foreach ($entries as $i => [$value, $cumulative]) $this->emit('FP', $i + 1, $value->value(), 'cum=' . $cumulative->value());
    }
    private function pathProbability(array $words, Chain $chain): void
    {
        $states = array_map([$chain, 'state'], array_slice($words, 2));
        $product = Fraction::one();
        $zeroAt = null;
        for ($i = 1; $i < count($states); ++$i) {
            $product = $product->multiply($chain->p[$states[$i - 1]][$states[$i]]);
            if ($product->isZero()) $zeroAt ??= $i;
        }
        $line = 'PATHPROB ' . $words[1] . ' steps=' . (count($states) - 1) . ' prob=' . $product->value();
        if ($zeroAt !== null) $line .= ' zero_at=' . $zeroAt;
        $this->emit($line);
    }
    private function mostLikely(array $words, Chain $chain): void
    {
        $start = $chain->state($words[2]);
        $steps = (int) $words[3];
        if ($steps === 0) throw new CommandError('BAD STEPS');
        $best = matrix($steps + 1, $chain->size());
        $best[$steps] = array_fill(0, $chain->size(), Fraction::one());
        for ($t = $steps - 1; $t >= 0; --$t)
            for ($i = 0; $i < $chain->size(); ++$i)
                for ($j = 0; $j < $chain->size(); ++$j) {
                    $candidate = $chain->p[$i][$j]->multiply($best[$t + 1][$j]);
                    if ($candidate->compareTo($best[$t][$i]) > 0) $best[$t][$i] = $candidate;
                }
        $path = [$start];
        $state = $start;
        for ($t = 0; $t < $steps; ++$t)
            for ($j = 0; $j < $chain->size(); ++$j)
                if ($chain->p[$state][$j]->multiply($best[$t + 1][$j])->equals($best[$t][$state])) {
                    $state = $j;
                    $path[] = $j;
                    break;
                }
        $this->emit('MOSTLIKELY', $words[1], $words[2], 'k=' . $steps, 'prob=' . $best[0][$start]->value());
        $this->emit('PATH', $chain->labels($path));
    }
    private function reversible(string $name, Chain $chain): void
    {
        $pi = $chain->uniqueStationary();
        $violations = [];
        for ($i = 0; $i < $chain->size(); ++$i)
            for ($j = $i + 1; $j < $chain->size(); ++$j) {
                $forward = $pi[$i]->multiply($chain->p[$i][$j]);
                $backward = $pi[$j]->multiply($chain->p[$j][$i]);
                if (!$forward->equals($backward)) $violations[] = [$i, $j, $forward, $backward];
            }
        $this->emit('REVERSIBLE', $name, $violations === [] ? 'yes' : 'no violations=' . count($violations));
        foreach ($violations as [$i, $j, $forward, $backward])
            $this->emit('VIOLATION', $chain->names[$i], $chain->names[$j], $forward->value(), $backward->value());
    }
    private function reverse(array $words, Chain $chain): void
    {
        $pi = $chain->uniqueStationary();
        $reversed = new Chain($chain->names, matrix($chain->size(), $chain->size()));
        $same = true;
        for ($i = 0; $i < $chain->size(); ++$i)
            for ($j = 0; $j < $chain->size(); ++$j) {
                $reversed->p[$i][$j] = $pi[$j]->multiply($chain->p[$j][$i])->divide($pi[$i]);
                if (!$reversed->p[$i][$j]->equals($chain->p[$i][$j])) $same = false;
            }
        $this->chains[$words[2]] = $reversed;
        $this->emit('REVERSE', $words[1], $words[2], 'reversible=' . self::yes($same));
        $this->display($reversed);
    }
    private function mixing(array $words, Chain $chain): void
    {
        $steps = (int) $words[2];
        if ($steps === 0) throw new CommandError('BAD STEPS');
        $epsilon = probability($words[3]);
        $pi = $chain->uniqueStationary();
        $power = identity($chain->size());
        $entries = [];
        $mixingTime = null;
        for ($t = 1; $t <= $steps; ++$t) {
            $power = multiply($power, $chain->p);
            $distance = Fraction::zero();
            $from = 0;
            for ($i = 0; $i < $chain->size(); ++$i) {
                $current = Fraction::zero();
                for ($j = 0; $j < $chain->size(); ++$j)
                    $current = $current->add($power[$i][$j]->subtract($pi[$j])->absolute());
                $current = $current->divide(Fraction::two());
                if ($current->compareTo($distance) > 0) [$distance, $from] = [$current, $i];
            }
            if ($distance->compareTo($epsilon) <= 0) $mixingTime ??= $t;
            $entries[] = [$distance, $from];
        }
        $this->emit('MIXING', $words[1], 'k=' . $steps, 'eps=' . $epsilon, 'time=' . ($mixingTime ?? 'none'));
        foreach ($entries as $i => [$distance, $from]) $this->emit('TV', $i + 1, $distance->value(), 'from=' . $chain->names[$from]);
    }
    private function lump(array $words, Chain $chain): void
    {
        $blocks = $seen = [];
        foreach (explode('|', $words[3]) as $group) {
            $block = [];
            foreach (explode(',', $group) as $name) {
                $state = $chain->state($name);
                if (isset($seen[$state])) throw new CommandError('BAD PARTITION');
                $seen[$state] = true;
                $block[] = $state;
            }
            sort($block, SORT_NUMERIC);
            $blocks[] = $block;
        }
        if (count($seen) !== $chain->size()) throw new CommandError('BAD PARTITION');
        usort($blocks, static fn(array $a, array $b): int => $a[0] <=> $b[0]);
        $names = array_map(fn(array $block): string => $chain->names[$block[0]], $blocks);
        $lumped = new Chain($names, matrix(count($blocks), count($blocks)));
        foreach ($blocks as $i => $block)
            foreach ($blocks as $j => $target) {
                $representative = $block[0];
                $baseline = $chain->blockSum($representative, $target);
                foreach ($block as $state) {
                    $value = $chain->blockSum($state, $target);
                    if (!$value->equals($baseline)) {
                        $this->emit('LUMP', $words[1], 'not lumpable', 'block=' . $chain->names[$representative],
                            'target=' . $chain->names[$target[0]], $chain->names[$representative] . '=' . $baseline->value(),
                            $chain->names[$state] . '=' . $value->value());
                        return;
                    }
                }
                $lumped->p[$i][$j] = $baseline;
            }
        $this->chains[$words[2]] = $lumped;
        $this->emit('LUMP', $words[1], $words[2], 'blocks=' . count($blocks));
        $this->display($lumped);
    }
    private function reward(array $words, Chain $chain): void
    {
        if (count($words) - 3 !== $chain->size()) throw new CommandError('BAD LENGTH');
        $discount = probability($words[2]);
        if ($discount->equals(Fraction::one())) throw new CommandError('BAD DISCOUNT');
        $rewards = array_map(static fn(string $text): Fraction => new Fraction((int) $text), array_slice($words, 3));
        $equations = matrix($chain->size(), $chain->size() + 1);
        for ($i = 0; $i < $chain->size(); ++$i) {
            for ($j = 0; $j < $chain->size(); ++$j)
                $equations[$i][$j] = delta($i, $j)->subtract($discount->multiply($chain->p[$i][$j]));
            $equations[$i][$chain->size()] = $rewards[$i];
        }
        $discounted = solve($equations);
        $gain = vector($chain->size());
        foreach ($chain->graph()->classes as $component) {
            if (!$component->closed) continue;
            $rho = $chain->stationary($component->states);
            $average = Fraction::zero();
            foreach ($component->states as $i) $average = $average->add($rho[$i]->multiply($rewards[$i]));
            $hitting = $chain->hitting($component->states, false)->probability;
            for ($i = 0; $i < $chain->size(); ++$i) $gain[$i] = $gain[$i]->add($hitting[$i]->multiply($average));
        }
        $this->emit('REWARD', $words[1], 'gamma=' . $discount);
        foreach ($chain->names as $i => $name)
            $this->emit('VALUE', $name, 'discounted=' . $discounted[$i][0]->value(), 'gain=' . $gain[$i]->value());
    }
    private function restrict(array $words, Chain $chain): void
    {
        $states = $chain->stateSet(array_slice($words, 3));
        $inside = array_fill_keys($states, true);
        foreach ($states as $i)
            for ($j = 0; $j < $chain->size(); ++$j)
                if (!isset($inside[$j]) && !$chain->p[$i][$j]->isZero()) throw new CommandError('NOT CLOSED ' . $chain->names[$i]);
        $names = $p = [];
        foreach ($states as $i) {
            $names[] = $chain->names[$i];
            $row = [];
            foreach ($states as $j) $row[] = $chain->p[$i][$j];
            $p[] = $row;
        }
        $restricted = new Chain($names, $p);
        $this->chains[$words[2]] = $restricted;
        $this->emit('RESTRICT', $words[1], $words[2], 'states=' . count($states));
        $this->display($restricted);
    }
    private function simulate(array $words, Chain $chain): void
    {
        $state = $chain->state($words[2]);
        $steps = (int) $words[3];
        if ($steps === 0) throw new CommandError('BAD STEPS');
        $seed = (int) $words[4];
        if ($seed === 0 || $seed >= 2147483647) throw new CommandError('BAD SEED');
        $random = $seed;
        $path = [$state];
        $visits = array_fill(0, $chain->size(), 0);
        ++$visits[$state];
        for ($t = 0; $t < $steps; ++$t) {
            $denominator = 1;
            foreach ($chain->p[$state] as $value)
                $denominator = intdiv($denominator, gcd($denominator, $value->denominator)) * $value->denominator;
            $random = 48271 * $random % 2147483647;
            $sample = $random % $denominator;
            $cumulative = Fraction::zero();
            for ($j = 0; $j < $chain->size(); ++$j) {
                $cumulative = $cumulative->add($chain->p[$state][$j]);
                if ($cumulative->numerator * intdiv($denominator, $cumulative->denominator) > $sample) {
                    $state = $j;
                    break;
                }
            }
            $path[] = $state;
            ++$visits[$state];
        }
        $this->emit('SIMULATE', $words[1], $words[2], 'steps=' . $steps, 'seed=' . $seed, 'end=' . $chain->names[$state]);
        $this->emit('PATH', $chain->labels($path));
        foreach ($chain->names as $i => $name) $this->emit('VISIT', $name, $visits[$i]);
    }
    public function execute(string $line): void
    {
        $words = explode(' ', $line);
        [$command, $name] = $words;
        try {
            if ($command === 'CHAIN') { $this->create($words); return; }
            if ($command === 'BUILD') { $this->build($words); return; }
            if ($command === 'GAMBLER') { $this->gambler($words); return; }
            $chain = $this->chains[$name] ?? throw new CommandError("UNKNOWN CHAIN $name");
            if (!in_array($command, ['P', 'ROW', 'SHOW', 'CHECK'], true)) $chain->stochastic();
            switch ($command) {
                case 'P':
                    $from = $chain->state($words[2]);
                    $to = $chain->state($words[3]);
                    $value = probability($words[4]);
                    $chain->p[$from][$to] = $value;
                    $this->emit('P', $name, $words[2], $words[3], (string) $value, 'rowsum=' . sum($chain->p[$from]));
                    break;
                case 'ROW':
                    $from = $chain->state($words[2]);
                    if (count($words) - 3 !== $chain->size()) throw new CommandError('BAD LENGTH');
                    $row = array_map('probability', array_slice($words, 3));
                    $chain->p[$from] = $row;
                    $this->emit('ROW', $name, $words[2], 'rowsum=' . sum($row));
                    break;
                case 'SHOW':
                    $this->emit('MATRIX', $name, 'states=' . $chain->size());
                    $this->display($chain);
                    break;
                case 'CHECK':
                    $sums = array_map('sum', $chain->p);
                    $bad = [];
                    foreach ($sums as $i => $value) if (!$value->equals(Fraction::one())) $bad[] = $i;
                    $this->emit('CHECK', $name, $bad === [] ? 'ok' : 'bad=' . count($bad));
                    foreach ($bad as $i) $this->emit('BADROW', $chain->names[$i], 'sum=' . $sums[$i]);
                    break;
                case 'CLASSES': $this->classes($name, $chain); break;
                case 'CLASSIFY': $this->classify($name, $chain); break;
                case 'STEP': $this->step($words, $chain); break;
                case 'POWER':
                    $steps = (int) $words[2];
                    $power = identity($chain->size());
                    for ($t = 0; $t < $steps; ++$t) $power = multiply($power, $chain->p);
                    $this->emit('POWER', $name, 'k=' . $steps);
                    $this->display($chain, $power);
                    break;
                case 'STATIONARY': $this->stationary($name, $chain); break;
                case 'RECURRENCE': $this->recurrence($words, $chain); break;
                case 'ABSORB': $this->absorb($name, $chain); break;
                case 'HITTING': $this->hitting($words, $chain); break;
                case 'PASSAGE': $this->passage($name, $chain); break;
                case 'FIRSTPASSAGE': $this->firstPassage($words, $chain); break;
                case 'PATHPROB': $this->pathProbability($words, $chain); break;
                case 'MOSTLIKELY': $this->mostLikely($words, $chain); break;
                case 'REVERSIBLE': $this->reversible($name, $chain); break;
                case 'REVERSE': $this->reverse($words, $chain); break;
                case 'MIXING': $this->mixing($words, $chain); break;
                case 'LUMP': $this->lump($words, $chain); break;
                case 'REWARD': $this->reward($words, $chain); break;
                case 'RESTRICT': $this->restrict($words, $chain); break;
                case 'SIMULATE': $this->simulate($words, $chain); break;
            }
        } catch (CommandError $error) {
            $this->emit('ERROR', $error->getMessage());
        }
    }
}

$count = (int) trim(fgets(STDIN));
$analyzer = new Analyzer();
for ($i = 0; $i < $count; ++$i) $analyzer->execute(rtrim(fgets(STDIN), "\r\n"));
echo $analyzer->result();
