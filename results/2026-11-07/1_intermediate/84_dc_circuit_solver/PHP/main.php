<?php
class CircuitError extends Exception {}

class Fraction
{
    public int $p;
    public int $q;

    public function __construct(int $p = 0, int $q = 1)
    {
        if ($q < 0) {
            $p = -$p;
            $q = -$q;
        }
        $a = abs($p);
        $b = $q;
        while ($b !== 0) {
            [$a, $b] = [$b, $a % $b];
        }
        $this->p = intdiv($p, $a);
        $this->q = intdiv($q, $a);
    }

    public function add(Fraction $other): Fraction
    {
        return new Fraction($this->p * $other->q + $other->p * $this->q, $this->q * $other->q);
    }

    public function sub(Fraction $other): Fraction
    {
        return new Fraction($this->p * $other->q - $other->p * $this->q, $this->q * $other->q);
    }

    public function mul(Fraction $other): Fraction
    {
        return new Fraction($this->p * $other->p, $this->q * $other->q);
    }

    public function div(Fraction $other): Fraction
    {
        return new Fraction($this->p * $other->q, $this->q * $other->p);
    }

    public function neg(): Fraction
    {
        return new Fraction(-$this->p, $this->q);
    }

    public function compare(Fraction $other): int
    {
        return ($this->p * $other->q) <=> ($other->p * $this->q);
    }

    public function fraction(): string
    {
        return $this->q === 1 ? (string)$this->p : $this->p . '/' . $this->q;
    }

    public function formatted(): string
    {
        $scaled = intdiv(abs($this->p) * 1000000, $this->q);
        $decimal = ($this->p < 0 ? '-' : '') . intdiv($scaled, 1000000) . '.' . str_pad((string)($scaled % 1000000), 6, '0', STR_PAD_LEFT);
        return $this->fraction() . ' (' . $decimal . ')';
    }
}

class Element
{
    public function __construct(
        public string $name,
        public string $type,
        public array $nodes,
        public Fraction $value,
        public ?string $reference = null
    ) {}
}

function rationalNumber(string $text): ?Fraction
{
    $multiplier = new Fraction(1);
    foreach (['meg' => new Fraction(1000000), 'k' => new Fraction(1000), 'm' => new Fraction(1, 1000), 'u' => new Fraction(1, 1000000)] as $suffix => $value) {
        if (str_ends_with($text, $suffix)) {
            $text = substr($text, 0, -strlen($suffix));
            $multiplier = $value;
            break;
        }
    }
    if (!preg_match('/\A-?[0-9]+(?:\.[0-9]+|\/[0-9]+)?\z/', $text)) {
        return null;
    }
    if (str_contains($text, '/')) {
        [$p, $q] = explode('/', $text);
        if ((int)$q === 0) {
            return null;
        }
        $number = new Fraction((int)$p, (int)$q);
    } elseif (str_contains($text, '.')) {
        [$whole, $digits] = explode('.', $text);
        $q = 10 ** strlen($digits);
        $negative = str_starts_with($text, '-');
        $p = abs((int)$whole) * $q + (int)$digits;
        $number = new Fraction($negative ? -$p : $p, $q);
    } else {
        $number = new Fraction((int)$text);
    }
    return $number->mul($multiplier);
}

function solve(array $matrix, array $rhs): ?array
{
    $n = count($rhs);
    $rows = [];
    foreach ($matrix as $i => $row) {
        $rows[] = array_merge($row, [$rhs[$i]]);
    }
    for ($k = 0; $k < $n; $k++) {
        $pivot = null;
        for ($i = $k; $i < $n; $i++) {
            if ($rows[$i][$k]->p !== 0) {
                $pivot = $i;
                break;
            }
        }
        if ($pivot === null) {
            return null;
        }
        if ($pivot !== $k) {
            [$rows[$k], $rows[$pivot]] = [$rows[$pivot], $rows[$k]];
        }
        $divisor = $rows[$k][$k];
        for ($j = 0; $j <= $n; $j++) {
            $rows[$k][$j] = $rows[$k][$j]->div($divisor);
        }
        for ($i = 0; $i < $n; $i++) {
            if ($i === $k || $rows[$i][$k]->p === 0) {
                continue;
            }
            $factor = $rows[$i][$k];
            for ($j = 0; $j <= $n; $j++) {
                $rows[$i][$j] = $rows[$i][$j]->sub($factor->mul($rows[$k][$j]));
            }
        }
    }
    return array_map(fn(array $row) => $row[$n], $rows);
}

function reachable(string $start, array $edges): array
{
    $seen = [$start => true];
    $queue = [$start];
    while ($queue !== []) {
        $node = array_shift($queue);
        foreach ($edges as [$a, $b]) {
            if ($a !== $node && $b !== $node) {
                continue;
            }
            $other = $a === $node ? $b : $a;
            if (!isset($seen[$other])) {
                $seen[$other] = true;
                $queue[] = $other;
            }
        }
    }
    return $seen;
}

class Groups
{
    private array $parent = [];

    public function __construct(array $nodes)
    {
        foreach ($nodes as $node) {
            $this->parent[$node] = $node;
        }
    }

    public function find(string $node): string
    {
        if ($this->parent[$node] !== $node) {
            $this->parent[$node] = $this->find($this->parent[$node]);
        }
        return $this->parent[$node];
    }

    public function join(string $a, string $b): void
    {
        $a = $this->find($a);
        $b = $this->find($b);
        if (strcmp($a, $b) < 0) {
            $this->parent[$b] = $a;
        } else {
            $this->parent[$a] = $b;
        }
    }
}

class Circuit
{
    private const COUNTS = ['.OP' => 0, '.CURRENT' => 1, '.VOLTAGE' => 2, '.POWER' => 0, '.KCL' => 1,
        '.THEVENIN' => 2, '.NORTON' => 2, '.MAXPOWER' => 2, '.TF' => 2, '.SENS' => 1,
        '.ZPARAM' => 4, '.SUPERPOSITION' => 1, '.SWEEP' => 5, '.MATRIX' => 0, '.REQ' => 2,
        '.REDUCE' => 2, '.CHECK' => 0, '.ALTER' => 2, '.DELETE' => 1, '.CLEAR' => 0, '.NODES' => 0, '.PRINT' => 0];
    private const ANALYSES = ['.OP', '.CURRENT', '.VOLTAGE', '.POWER', '.KCL', '.THEVENIN', '.NORTON', '.MAXPOWER', '.TF', '.SENS', '.ZPARAM', '.SUPERPOSITION'];
    private array $elements = [];

    private function nodes(): array
    {
        $names = [];
        foreach ($this->elements as $element) {
            foreach ($element->nodes as $node) {
                if ($node !== '0') {
                    $names[$node] = true;
                }
            }
        }
        $result = array_keys($names);
        sort($result, SORT_STRING);
        return $result;
    }

    private function sources(): array
    {
        return array_values(array_filter($this->elements, fn(Element $item) => in_array($item->type, ['V', 'E', 'H'], true)));
    }

    private function element(string $name): Element
    {
        foreach ($this->elements as $item) {
            if ($item->name === $name) {
                return $item;
            }
        }
        throw new CircuitError('unknown element ' . $name);
    }

    private function node(string $name): void
    {
        if ($name !== '0' && !in_array($name, $this->nodes(), true)) {
            throw new CircuitError('unknown node ' . $name);
        }
    }

    private function number(string $text): Fraction
    {
        return rationalNumber($text) ?? throw new CircuitError('invalid value ' . $text);
    }

    private function add(array $words): array
    {
        $name = $words[0];
        $type = $name[0];
        if (!in_array($type, ['R', 'V', 'I', 'E', 'G', 'F', 'H'], true)) {
            throw new CircuitError('unknown element type ' . $name);
        }
        $count = in_array($type, ['E', 'G'], true) ? 6 : (in_array($type, ['F', 'H'], true) ? 5 : 4);
        if (count($words) !== $count) {
            throw new CircuitError('wrong field count for ' . $name);
        }
        foreach ($this->elements as $item) {
            if ($item->name === $name) {
                throw new CircuitError('duplicate element ' . $name);
            }
        }
        $terminals = array_slice($words, 1, in_array($type, ['E', 'G'], true) ? 4 : 2);
        foreach ($terminals as $terminal) {
            if (!preg_match('/\A(?:0|[a-z][a-z0-9]{0,7})\z/', $terminal)) {
                throw new CircuitError('invalid node ' . $terminal);
            }
        }
        $reference = in_array($type, ['F', 'H'], true) ? $words[3] : null;
        if ($reference !== null) {
            $found = false;
            foreach ($this->elements as $item) {
                if ($item->name === $reference && $item->type === 'V') {
                    $found = true;
                    break;
                }
            }
            if (!$found) {
                throw new CircuitError('unknown voltage source ' . $reference);
            }
        }
        $value = $this->number($words[array_key_last($words)]);
        if ($type === 'R' && $value->p <= 0) {
            throw new CircuitError('nonpositive resistance ' . $name);
        }
        $this->elements[] = new Element($name, $type, $terminals, $value, $reference);
        return [];
    }

    private function grounding(): array
    {
        $edges = [];
        foreach ($this->elements as $item) {
            if (in_array($item->type, ['R', 'V', 'E', 'H'], true)) {
                $edges[] = array_slice($item->nodes, 0, 2);
            }
        }
        return reachable('0', $edges);
    }

    private function voltageLoops(): array
    {
        $groups = new Groups(array_merge(['0'], $this->nodes()));
        $result = [];
        foreach ($this->sources() as $item) {
            [$a, $b] = $item->nodes;
            if ($groups->find($a) === $groups->find($b)) {
                $result[] = $item->name;
            }
            $groups->join($a, $b);
        }
        return $result;
    }

    private function structureCheck(): void
    {
        $nodes = $this->nodes();
        if ($nodes === []) {
            throw new CircuitError('no nodes');
        }
        $grounded = $this->grounding();
        foreach ($nodes as $name) {
            if (!isset($grounded[$name])) {
                throw new CircuitError('floating node ' . $name);
            }
        }
        $loops = $this->voltageLoops();
        if ($loops !== []) {
            throw new CircuitError('voltage source loop at ' . $loops[0]);
        }
    }

    private function equations(array $overrides = []): array
    {
        $labels = array_merge($this->nodes(), array_map(fn(Element $item) => $item->name, $this->sources()));
        $index = array_flip($labels);
        $n = count($labels);
        $matrix = array_fill(0, $n, array_fill(0, $n, new Fraction()));
        $rhs = array_fill(0, $n, new Fraction());
        $put = function (string $row, string $column, Fraction $value) use (&$matrix, $index): void {
            if ($row !== '0' && $column !== '0') {
                $i = $index[$row];
                $j = $index[$column];
                $matrix[$i][$j] = $matrix[$i][$j]->add($value);
            }
        };
        $putRhs = function (string $row, Fraction $value) use (&$rhs, $index): void {
            if ($row !== '0') {
                $i = $index[$row];
                $rhs[$i] = $rhs[$i]->add($value);
            }
        };
        foreach ($this->elements as $item) {
            [$a, $b] = $item->nodes;
            $c = $item->nodes[2] ?? null;
            $d = $item->nodes[3] ?? null;
            $value = $overrides[$item->name] ?? $item->value;
            $s = $item->name;
            if ($item->type === 'R') {
                $g = (new Fraction(1))->div($value);
                $put($a, $a, $g);
                $put($b, $b, $g);
                $put($a, $b, $g->neg());
                $put($b, $a, $g->neg());
            } elseif ($item->type === 'I') {
                $putRhs($a, $value->neg());
                $putRhs($b, $value);
            } elseif ($item->type === 'G') {
                $put($a, $c, $value);
                $put($b, $d, $value);
                $put($a, $d, $value->neg());
                $put($b, $c, $value->neg());
            } elseif ($item->type === 'F') {
                $put($a, $item->reference, $value);
                $put($b, $item->reference, $value->neg());
            } else {
                $put($a, $s, new Fraction(1));
                $put($s, $a, new Fraction(1));
                $put($b, $s, new Fraction(-1));
                $put($s, $b, new Fraction(-1));
                if ($item->type === 'V') {
                    $putRhs($s, $value);
                } elseif ($item->type === 'E') {
                    $put($s, $c, $value->neg());
                    $put($s, $d, $value);
                } else {
                    $put($s, $item->reference, $value->neg());
                }
            }
        }
        return [$matrix, $rhs, $labels, $index];
    }

    private function potential(array $solution, array $index, string $name): Fraction
    {
        return $name === '0' ? new Fraction() : $solution[$index[$name]];
    }

    private function current(Element $item, array $solution, array $index): Fraction
    {
        [$a, $b] = $item->nodes;
        return match ($item->type) {
            'R' => $this->potential($solution, $index, $a)->sub($this->potential($solution, $index, $b))->div($item->value),
            'V', 'E', 'H' => $solution[$index[$item->name]],
            'I' => $item->value,
            'G' => $item->value->mul($this->potential($solution, $index, $item->nodes[2])->sub($this->potential($solution, $index, $item->nodes[3]))),
            'F' => $item->value->mul($solution[$index[$item->reference]])
        };
    }

    private function injection(array $matrix, array $index, string $a, string $b): array
    {
        $rhs = array_fill(0, count($matrix), new Fraction());
        if ($a !== '0') {
            $rhs[$index[$a]] = $rhs[$index[$a]]->add(new Fraction(1));
        }
        if ($b !== '0') {
            $rhs[$index[$b]] = $rhs[$index[$b]]->sub(new Fraction(1));
        }
        return solve($matrix, $rhs);
    }

    private function sourceSolution(array $matrix, array $index, Element $item, bool $unit = false): array
    {
        $rhs = array_fill(0, count($matrix), new Fraction());
        $value = $unit ? new Fraction(1) : $item->value;
        if ($item->type === 'V') {
            $rhs[$index[$item->name]] = $value;
        } else {
            [$a, $b] = $item->nodes;
            if ($a !== '0') {
                $rhs[$index[$a]] = $rhs[$index[$a]]->sub($value);
            }
            if ($b !== '0') {
                $rhs[$index[$b]] = $rhs[$index[$b]]->add($value);
            }
        }
        return solve($matrix, $rhs);
    }

    private function analysis(string $command, array $args): array
    {
        if ($command === '.CURRENT') {
            $this->element($args[0]);
        } elseif (in_array($command, ['.VOLTAGE', '.THEVENIN', '.NORTON', '.MAXPOWER', '.ZPARAM'], true)) {
            foreach ($args as $name) {
                $this->node($name);
            }
        } elseif (in_array($command, ['.KCL', '.SENS', '.SUPERPOSITION'], true)) {
            $this->node($args[0]);
        } elseif ($command === '.TF') {
            $this->node($args[0]);
            $source = $this->element($args[1]);
            if (!in_array($source->type, ['V', 'I'], true)) {
                throw new CircuitError('not an independent source ' . $source->name);
            }
        }
        $this->structureCheck();
        [$matrix, $rhs, , $index] = $this->equations();
        $solution = solve($matrix, $rhs) ?? throw new CircuitError('singular matrix');
        $voltage = fn(string $name, ?array $values = null) => $this->potential($values ?? $solution, $index, $name);
        $lines = [];
        switch ($command) {
            case '.OP':
                foreach ($this->nodes() as $name) {
                    $lines[] = 'V(' . $name . ') = ' . $voltage($name)->formatted();
                }
                foreach ($this->sources() as $item) {
                    $lines[] = 'I(' . $item->name . ') = ' . $solution[$index[$item->name]]->formatted();
                }
                break;
            case '.CURRENT':
                $lines[] = 'I(' . $args[0] . ') = ' . $this->current($this->element($args[0]), $solution, $index)->formatted();
                break;
            case '.VOLTAGE':
                $lines[] = 'V(' . $args[0] . ',' . $args[1] . ') = ' . $voltage($args[0])->sub($voltage($args[1]))->formatted();
                break;
            case '.POWER':
                $absorbed = new Fraction();
                $delivered = new Fraction();
                $total = new Fraction();
                foreach ($this->elements as $item) {
                    $power = $voltage($item->nodes[0])->sub($voltage($item->nodes[1]))->mul($this->current($item, $solution, $index));
                    if ($power->p > 0) {
                        $absorbed = $absorbed->add($power);
                    }
                    if ($power->p < 0) {
                        $delivered = $delivered->sub($power);
                    }
                    $total = $total->add($power);
                    $lines[] = 'P(' . $item->name . ') = ' . $power->formatted();
                }
                $lines[] = 'absorbed = ' . $absorbed->formatted();
                $lines[] = 'delivered = ' . $delivered->formatted();
                $lines[] = 'total = ' . $total->formatted();
                break;
            case '.KCL':
                $a = $args[0];
                $total = new Fraction();
                foreach ($this->elements as $item) {
                    [$x, $y] = $item->nodes;
                    if ($x !== $a && $y !== $a) {
                        continue;
                    }
                    $value = $x === $y ? new Fraction() : $this->current($item, $solution, $index)->mul(new Fraction($x === $a ? 1 : -1));
                    $total = $total->add($value);
                    $lines[] = 'I(' . $item->name . ') leaving ' . $a . ' = ' . $value->formatted();
                }
                $lines[] = 'sum = ' . $total->formatted();
                break;
            case '.THEVENIN':
            case '.NORTON':
            case '.MAXPOWER':
                [$a, $b] = $args;
                $vth = $voltage($a)->sub($voltage($b));
                $z = $this->injection($matrix, $index, $a, $b);
                $rth = $voltage($a, $z)->sub($voltage($b, $z));
                if ($command === '.NORTON') {
                    if ($rth->p === 0) {
                        throw new CircuitError('zero thevenin resistance');
                    }
                    $lines = ['In = ' . $vth->div($rth)->formatted(), 'Rn = ' . $rth->formatted()];
                } elseif ($command === '.MAXPOWER') {
                    if ($rth->p <= 0) {
                        throw new CircuitError('nonpositive thevenin resistance');
                    }
                    $lines = ['RL = ' . $rth->formatted(), 'Pmax = ' . $vth->mul($vth)->div((new Fraction(4))->mul($rth))->formatted()];
                } else {
                    $lines = ['Vth = ' . $vth->formatted(), 'Rth = ' . $rth->formatted()];
                }
                break;
            case '.TF':
                [$a, $name] = $args;
                $item = $this->element($name);
                $z = $this->sourceSolution($matrix, $index, $item, true);
                $lines[] = 'gain = ' . $voltage($a, $z)->formatted();
                if ($item->type === 'V') {
                    $j = $z[$index[$name]];
                    $lines[] = $j->p === 0 ? 'input resistance = INFINITE' : 'input resistance = ' . (new Fraction(-1))->div($j)->formatted();
                } else {
                    $lines[] = 'input resistance = ' . $voltage($item->nodes[1], $z)->sub($voltage($item->nodes[0], $z))->formatted();
                }
                $lines[] = 'output resistance = ' . $voltage($a, $this->injection($matrix, $index, $a, '0'))->formatted();
                break;
            case '.SENS':
                $a = $args[0];
                foreach ($this->elements as $item) {
                    $d = array_fill(0, count($matrix), new Fraction());
                    $add = function (string $row, Fraction $value) use (&$d, $index): void {
                        if ($row !== '0') {
                            $d[$index[$row]] = $d[$index[$row]]->add($value);
                        }
                    };
                    [$x, $y] = $item->nodes;
                    if ($item->type === 'R') {
                        $t = $this->current($item, $solution, $index)->div($item->value);
                        $add($x, $t);
                        $add($y, $t->neg());
                    } elseif ($item->type === 'I') {
                        $add($x, new Fraction(-1));
                        $add($y, new Fraction(1));
                    } elseif ($item->type === 'G' || $item->type === 'F') {
                        $t = $item->type === 'G' ? $voltage($item->nodes[2])->sub($voltage($item->nodes[3])) : $solution[$index[$item->reference]];
                        $add($x, $t->neg());
                        $add($y, $t);
                    } elseif ($item->type === 'V') {
                        $add($item->name, new Fraction(1));
                    } elseif ($item->type === 'E') {
                        $add($item->name, $voltage($item->nodes[2])->sub($voltage($item->nodes[3])));
                    } else {
                        $add($item->name, $solution[$index[$item->reference]]);
                    }
                    $lines[] = 'dV(' . $a . ')/d' . $item->name . ' = ' . $voltage($a, solve($matrix, $d))->formatted();
                }
                break;
            case '.ZPARAM':
                [$a, $b, $c, $d] = $args;
                $z1 = $this->injection($matrix, $index, $a, $b);
                $z2 = $this->injection($matrix, $index, $c, $d);
                $lines = ['z11 = ' . $voltage($a, $z1)->sub($voltage($b, $z1))->formatted(),
                    'z12 = ' . $voltage($a, $z2)->sub($voltage($b, $z2))->formatted(),
                    'z21 = ' . $voltage($c, $z1)->sub($voltage($d, $z1))->formatted(),
                    'z22 = ' . $voltage($c, $z2)->sub($voltage($d, $z2))->formatted()];
                break;
            case '.SUPERPOSITION':
                $a = $args[0];
                $total = new Fraction();
                foreach ($this->elements as $item) {
                    if (!in_array($item->type, ['V', 'I'], true)) {
                        continue;
                    }
                    $value = $voltage($a, $this->sourceSolution($matrix, $index, $item));
                    $total = $total->add($value);
                    $lines[] = $item->name . ': V(' . $a . ') = ' . $value->formatted();
                }
                $lines[] = 'total: V(' . $a . ') = ' . $total->formatted();
                break;
        }
        return $lines;
    }

    private function equivalent(string $a, string $b): array
    {
        $groups = new Groups(array_merge(['0'], $this->nodes()));
        foreach ($this->elements as $item) {
            if ($item->type === 'V') {
                $groups->join($item->nodes[0], $item->nodes[1]);
            }
        }
        $a = $groups->find($a);
        $b = $groups->find($b);
        if ($a === $b) {
            return ['Req = 0 (0.000000)'];
        }
        $edges = [];
        foreach ($this->elements as $item) {
            if ($item->type !== 'R') {
                continue;
            }
            $x = $groups->find($item->nodes[0]);
            $y = $groups->find($item->nodes[1]);
            if ($x !== $y) {
                $edges[] = [$x, $y, (new Fraction(1))->div($item->value)];
            }
        }
        $connected = reachable($a, $edges);
        if (!isset($connected[$b])) {
            return ['Req = INFINITE'];
        }
        $labels = array_values(array_filter(array_keys($connected), fn($name) => (string)$name !== $b));
        sort($labels, SORT_STRING);
        $index = array_flip($labels);
        $matrix = array_fill(0, count($labels), array_fill(0, count($labels), new Fraction()));
        $rhs = array_fill(0, count($labels), new Fraction());
        $rhs[$index[$a]] = new Fraction(1);
        foreach ($edges as [$x, $y, $g]) {
            if (!isset($connected[$x])) {
                continue;
            }
            if ($x !== $b) {
                $matrix[$index[$x]][$index[$x]] = $matrix[$index[$x]][$index[$x]]->add($g);
            }
            if ($y !== $b) {
                $matrix[$index[$y]][$index[$y]] = $matrix[$index[$y]][$index[$y]]->add($g);
            }
            if ($x !== $b && $y !== $b) {
                $matrix[$index[$x]][$index[$y]] = $matrix[$index[$x]][$index[$y]]->sub($g);
                $matrix[$index[$y]][$index[$x]] = $matrix[$index[$y]][$index[$x]]->sub($g);
            }
        }
        return ['Req = ' . solve($matrix, $rhs)[$index[$a]]->formatted()];
    }

    private function reduceResistors(string $a, string $b): array
    {
        if ($a === $b) {
            return ['Req = 0 (0.000000)'];
        }
        $list = array_values(array_filter($this->elements, fn(Element $item) => $item->type === 'R'));
        $connected = reachable($a, array_map(fn(Element $item) => $item->nodes, $list));
        if (!isset($connected[$b])) {
            return ['Req = INFINITE'];
        }
        $list = array_values(array_filter($list, fn(Element $item) => isset($connected[$item->nodes[0]])));
        $lines = [];
        $serial = 0;
        while (true) {
            $self = null;
            foreach ($list as $i => $item) {
                if ($item->nodes[0] === $item->nodes[1]) {
                    $self = $i;
                    break;
                }
            }
            if ($self !== null) {
                $lines[] = 'remove ' . $list[$self]->name;
                array_splice($list, $self, 1);
                continue;
            }
            $degree = [];
            foreach ($list as $item) {
                foreach ($item->nodes as $name) {
                    $degree[$name] = ($degree[$name] ?? 0) + 1;
                }
            }
            $internal = array_values(array_filter(array_keys($degree), fn($name) => (string)$name !== $a && (string)$name !== $b));
            sort($internal, SORT_STRING);
            $leaf = null;
            foreach ($internal as $name) {
                if ($degree[$name] === 1) {
                    $leaf = (string)$name;
                    break;
                }
            }
            if ($leaf !== null) {
                foreach ($list as $i => $item) {
                    if (in_array($leaf, $item->nodes, true)) {
                        $lines[] = 'remove ' . $item->name;
                        array_splice($list, $i, 1);
                        break;
                    }
                }
                continue;
            }
            $pair = null;
            for ($i = 0; $i < count($list); $i++) {
                for ($j = $i + 1; $j < count($list); $j++) {
                    $x = $list[$i]->nodes;
                    $y = $list[$j]->nodes;
                    if (($x[0] === $y[0] && $x[1] === $y[1]) || ($x[0] === $y[1] && $x[1] === $y[0])) {
                        $pair = [$i, $j];
                        break 2;
                    }
                }
            }
            if ($pair !== null) {
                $x = $list[$pair[0]];
                $y = $list[$pair[1]];
                $value = $x->value->mul($y->value)->div($x->value->add($y->value));
                $terminals = $x->nodes;
                $operator = '||';
            } else {
                $middle = null;
                foreach ($internal as $name) {
                    if ($degree[$name] === 2) {
                        $middle = (string)$name;
                        break;
                    }
                }
                if ($middle === null) {
                    break;
                }
                $pair = [];
                foreach ($list as $i => $item) {
                    if (in_array($middle, $item->nodes, true)) {
                        $pair[] = $i;
                    }
                }
                $x = $list[$pair[0]];
                $y = $list[$pair[1]];
                $terminals = [$x->nodes[0] === $middle ? $x->nodes[1] : $x->nodes[0], $y->nodes[0] === $middle ? $y->nodes[1] : $y->nodes[0]];
                $value = $x->value->add($y->value);
                $operator = '+';
            }
            $name = '#' . ++$serial;
            $lines[] = $name . ' = ' . $x->name . ' ' . $operator . ' ' . $y->name . ' = ' . $value->formatted();
            $list = array_values(array_filter($list, fn($i) => !in_array($i, $pair, true), ARRAY_FILTER_USE_KEY));
            $list[] = new Element($name, 'R', $terminals, $value);
        }
        $lines[] = count($list) === 1 ? 'Req = ' . $list[0]->value->formatted() : 'not series-parallel: ' . count($list) . ' resistors remain';
        return $lines;
    }

    private function command(array $words): array
    {
        $cmd = array_shift($words);
        $args = $words;
        if (!array_key_exists($cmd, self::COUNTS)) {
            throw new CircuitError('unknown command ' . $cmd);
        }
        if (count($args) !== self::COUNTS[$cmd]) {
            throw new CircuitError('wrong argument count for ' . $cmd);
        }
        if (in_array($cmd, self::ANALYSES, true)) {
            return $this->analysis($cmd, $args);
        }
        switch ($cmd) {
            case '.REQ':
            case '.REDUCE':
                foreach ($args as $name) {
                    $this->node($name);
                }
                return $cmd === '.REQ' ? $this->equivalent($args[0], $args[1]) : $this->reduceResistors($args[0], $args[1]);
            case '.SWEEP':
                $item = $this->element($args[0]);
                $from = $this->number($args[1]);
                $to = $this->number($args[2]);
                $step = $this->number($args[3]);
                $this->node($args[4]);
                if ($step->p <= 0) {
                    throw new CircuitError('invalid sweep step');
                }
                if ($from->compare($to) > 0) {
                    throw new CircuitError('invalid sweep range');
                }
                $range = $to->sub($from)->div($step);
                $count = intdiv($range->p, $range->q) + 1;
                if ($count > 20) {
                    throw new CircuitError('too many sweep points');
                }
                if ($item->type === 'R' && $from->p <= 0) {
                    throw new CircuitError('nonpositive resistance ' . $item->name);
                }
                $this->structureCheck();
                $lines = [];
                for ($k = 0; $k < $count; $k++) {
                    $x = $from->add((new Fraction($k))->mul($step));
                    [$matrix, $rhs, , $index] = $this->equations([$item->name => $x]);
                    $solution = solve($matrix, $rhs);
                    $lines[] = $item->name . ' = ' . $x->fraction() . ': ' . ($solution === null ? 'singular matrix' : 'V(' . $args[4] . ') = ' . $this->potential($solution, $index, $args[4])->formatted());
                }
                return $lines;
            case '.MATRIX':
                $this->structureCheck();
                [$matrix, $rhs, $labels] = $this->equations();
                $unknowns = array_merge(array_map(fn($name) => 'V(' . $name . ')', $this->nodes()), array_map(fn(Element $item) => 'I(' . $item->name . ')', $this->sources()));
                $lines = ['unknowns: ' . implode(' ', $unknowns)];
                foreach ($matrix as $i => $row) {
                    $lines[] = $labels[$i] . ': ' . implode(' ', array_map(fn(Fraction $value) => $value->fraction(), $row)) . ' | ' . $rhs[$i]->fraction();
                }
                return $lines;
            case '.CHECK':
                if ($this->nodes() === []) {
                    return ['no nodes'];
                }
                $lines = [];
                foreach ($this->nodes() as $name) {
                    $degree = 0;
                    foreach ($this->elements as $item) {
                        $degree += (int)($item->nodes[0] === $name) + (int)($item->nodes[1] === $name);
                    }
                    if ($degree < 2) {
                        $lines[] = 'dangling node ' . $name;
                    }
                }
                $grounded = $this->grounding();
                foreach ($this->nodes() as $name) {
                    if (!isset($grounded[$name])) {
                        $lines[] = 'floating node ' . $name;
                    }
                }
                foreach ($this->voltageLoops() as $name) {
                    $lines[] = 'voltage source loop at ' . $name;
                }
                if ($lines === []) {
                    [$matrix, $rhs] = $this->equations();
                    if (solve($matrix, $rhs) === null) {
                        $lines[] = 'singular matrix';
                    }
                }
                return $lines === [] ? ['ok'] : $lines;
            case '.ALTER':
                $item = $this->element($args[0]);
                $value = $this->number($args[1]);
                if ($item->type === 'R' && $value->p <= 0) {
                    throw new CircuitError('nonpositive resistance ' . $item->name);
                }
                $line = 'altered ' . $item->name . ': ' . $item->value->fraction() . ' -> ' . $value->fraction();
                $item->value = $value;
                return [$line];
            case '.DELETE':
                $item = $this->element($args[0]);
                foreach ($this->elements as $other) {
                    if (in_array($other->type, ['F', 'H'], true) && $other->reference === $item->name) {
                        throw new CircuitError($item->name . ' is referenced by ' . $other->name);
                    }
                }
                $this->elements = array_values(array_filter($this->elements, fn(Element $other) => $other !== $item));
                return ['deleted ' . $item->name];
            case '.CLEAR':
                $line = 'cleared ' . count($this->elements) . ' elements';
                $this->elements = [];
                return [$line];
            case '.NODES':
                if ($this->elements === []) {
                    return ['no nodes'];
                }
                $all = [];
                foreach ($this->elements as $item) {
                    foreach ($item->nodes as $name) {
                        $all[$name] = true;
                    }
                }
                $names = array_keys($all);
                sort($names, SORT_STRING);
                $lines = [];
                foreach ($names as $name) {
                    $name = (string)$name;
                    $users = array_filter($this->elements, fn(Element $item) => in_array($name, $item->nodes, true));
                    $lines[] = $name . ': ' . implode(' ', array_map(fn(Element $item) => $item->name, $users));
                }
                return $lines;
            case '.PRINT':
                if ($this->elements === []) {
                    return ['empty netlist'];
                }
                return array_map(function (Element $item): string {
                    $words = array_merge([$item->name], $item->nodes);
                    if ($item->reference !== null) {
                        $words[] = $item->reference;
                    }
                    $words[] = $item->value->fraction();
                    return implode(' ', $words);
                }, $this->elements);
        }
        return [];
    }

    public function run(): void
    {
        $number = 0;
        while (($input = fgets(STDIN)) !== false) {
            $number++;
            $line = str_ends_with($input, "\n") ? substr($input, 0, -1) : $input;
            if ($line === '.END') {
                break;
            }
            if (str_starts_with($line, '*')) {
                continue;
            }
            try {
                $words = explode(' ', $line);
                $output = str_starts_with($line, '.') ? $this->command($words) : $this->add($words);
                foreach ($output as $text) {
                    echo $text, "\n";
                }
            } catch (CircuitError $error) {
                echo 'error: line ', $number, ': ', $error->getMessage(), "\n";
            }
        }
    }
}

(new Circuit())->run();
