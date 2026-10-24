<?php

class AutomatonError extends Exception
{
}

class Automaton
{
    public array $alphabet;
    public array $accepting;
    public array $edges;

    public function __construct(
        public string $kind,
        public array $states,
        array $alphabet,
        public int $start,
        array $accepting,
        array $triples
    ) {
        sort($alphabet, SORT_STRING);
        $this->alphabet = $alphabet;
        $this->accepting = array_fill_keys($accepting, true);
        $this->edges = array_fill(0, count($states), []);
        foreach ($triples as [$p, $c, $q]) {
            $this->edges[$p][$c][$q] = true;
        }
        foreach ($this->edges as &$row) {
            foreach ($row as &$targets) {
                $targets = array_keys($targets);
                sort($targets, SORT_NUMERIC);
            }
            unset($targets);
        }
        unset($row);
    }

    public function triples(): array
    {
        $result = [];
        foreach ($this->edges as $p => $row) {
            foreach (array_merge($this->alphabet, ['e']) as $c) {
                foreach ($row[$c] ?? [] as $q) {
                    $result[] = [$p, $c, $q];
                }
            }
        }
        return $result;
    }

    public function summary(string $name): string
    {
        return $this->kind . ' ' . $name . ': alphabet=' . implode('', $this->alphabet)
            . ' states=' . count($this->states) . ' accepting=' . count($this->accepting)
            . ' transitions=' . count($this->triples());
    }

    public function setText(array $values): string
    {
        sort($values, SORT_NUMERIC);
        return '{' . implode(',', array_map(fn($p) => $this->states[$p], $values)) . '}';
    }

    public function listText(array $values): string
    {
        sort($values, SORT_NUMERIC);
        return $values === [] ? 'none' : implode(',', array_map(fn($p) => $this->states[$p], $values));
    }

    public function closure(array $values): array
    {
        $seen = array_fill_keys($values, true);
        $queue = array_keys($seen);
        for ($i = 0; $i < count($queue); $i++) {
            foreach ($this->edges[$queue[$i]]['e'] ?? [] as $q) {
                if (!isset($seen[$q])) {
                    $seen[$q] = true;
                    $queue[] = $q;
                }
            }
        }
        $result = array_keys($seen);
        sort($result, SORT_NUMERIC);
        return $result;
    }

    public function move(array $values, string $c): array
    {
        $targets = [];
        foreach ($values as $p) {
            foreach ($this->edges[$p][$c] ?? [] as $q) {
                $targets[$q] = true;
            }
        }
        return $this->closure(array_keys($targets));
    }

    public function acceptsSet(array $values): bool
    {
        foreach ($values as $p) {
            if (isset($this->accepting[$p])) {
                return true;
            }
        }
        return false;
    }

    public function reachable(array $seeds, bool $reverse = false): array
    {
        $graph = array_fill(0, count($this->states), []);
        foreach ($this->triples() as [$p, $c, $q]) {
            if ($reverse) {
                $graph[$q][] = $p;
            } else {
                $graph[$p][] = $q;
            }
        }
        $seen = array_fill_keys($seeds, true);
        $queue = array_keys($seen);
        for ($i = 0; $i < count($queue); $i++) {
            foreach ($graph[$queue[$i]] as $q) {
                if (!isset($seen[$q])) {
                    $seen[$q] = true;
                    $queue[] = $q;
                }
            }
        }
        $result = array_keys($seen);
        sort($result, SORT_NUMERIC);
        return $result;
    }

    public function determinize(): array
    {
        $subsets = [$this->closure([$this->start])];
        $indices = [implode(',', $subsets[0]) => 0];
        $triples = [];
        $accepting = [];
        for ($i = 0; $i < count($subsets); $i++) {
            if ($this->acceptsSet($subsets[$i])) {
                $accepting[] = $i;
            }
            foreach ($this->alphabet as $c) {
                $target = $this->move($subsets[$i], $c);
                $key = implode(',', $target);
                if (!array_key_exists($key, $indices)) {
                    $indices[$key] = count($subsets);
                    $subsets[] = $target;
                }
                $triples[] = [$i, $c, $indices[$key]];
            }
        }
        $states = array_map(fn($i) => 'D' . $i, array_keys($subsets));
        return [new Automaton('DFA', $states, $this->alphabet, 0, $accepting, $triples), $subsets];
    }

    public function minimize(): array
    {
        $reachable = $this->reachable([$this->start]);
        $yes = [];
        $no = [];
        foreach ($reachable as $p) {
            if (isset($this->accepting[$p])) {
                $yes[] = $p;
            } else {
                $no[] = $p;
            }
        }
        $blocks = array_values(array_filter([$yes, $no], fn($b) => $b !== []));
        usort($blocks, fn($a, $b) => $a[0] <=> $b[0]);
        $rounds = [$blocks];
        while (true) {
            $membership = [];
            foreach ($blocks as $i => $block) {
                foreach ($block as $p) {
                    $membership[$p] = $i;
                }
            }
            $groups = [];
            foreach ($reachable as $p) {
                $signature = [$membership[$p]];
                foreach ($this->alphabet as $c) {
                    $signature[] = $membership[$this->edges[$p][$c][0]];
                }
                $groups[implode(',', $signature)][] = $p;
            }
            $refined = array_values($groups);
            usort($refined, fn($a, $b) => $a[0] <=> $b[0]);
            if (count($refined) === count($blocks)) {
                break;
            }
            $blocks = $refined;
            $rounds[] = $blocks;
        }
        $membership = [];
        foreach ($blocks as $i => $block) {
            foreach ($block as $p) {
                $membership[$p] = $i;
            }
        }
        $order = [$membership[$this->start]];
        $named = [$order[0] => 0];
        $triples = [];
        $accepting = [];
        for ($i = 0; $i < count($order); $i++) {
            $p = $blocks[$order[$i]][0];
            if (isset($this->accepting[$p])) {
                $accepting[] = $i;
            }
            foreach ($this->alphabet as $c) {
                $target = $membership[$this->edges[$p][$c][0]];
                if (!array_key_exists($target, $named)) {
                    $named[$target] = count($order);
                    $order[] = $target;
                }
                $triples[] = [$i, $c, $named[$target]];
            }
        }
        $states = array_map(fn($i) => 'M' . $i, array_keys($order));
        $result = new Automaton('DFA', $states, $this->alphabet, 0, $accepting, $triples);
        $unreachable = array_values(array_diff(array_keys($this->states), $reachable));
        return [$result, $unreachable, $rounds, array_map(fn($i) => $blocks[$i], $order)];
    }

    public function shortestWord(): ?string
    {
        $queue = [[$this->start, '']];
        $seen = [$this->start => true];
        for ($i = 0; $i < count($queue); $i++) {
            [$p, $word] = $queue[$i];
            if (isset($this->accepting[$p])) {
                return $word;
            }
            foreach ($this->alphabet as $c) {
                $q = $this->edges[$p][$c][0];
                if (!isset($seen[$q])) {
                    $seen[$q] = true;
                    $queue[] = [$q, $word . $c];
                }
            }
        }
        return null;
    }

    public function finiteSize(bool $count = true): ?int
    {
        $live = array_fill_keys($this->reachable(array_keys($this->accepting), true), true);
        $color = array_fill(0, count($this->states), 0);
        $counts = array_fill(0, count($this->states), 0);
        $visit = function (int $p) use (&$visit, &$color, &$counts, $live, $count): ?int {
            if (!isset($live[$p])) {
                return 0;
            }
            if ($color[$p] === 1) {
                return null;
            }
            if ($color[$p] === 2) {
                return $counts[$p];
            }
            $color[$p] = 1;
            $total = isset($this->accepting[$p]) ? 1 : 0;
            foreach ($this->alphabet as $c) {
                $value = $visit($this->edges[$p][$c][0]);
                if ($value === null) {
                    return null;
                }
                $total = $count ? $total + $value : (int) ($total > 0 || $value > 0);
            }
            $color[$p] = 2;
            $counts[$p] = $total;
            return $total;
        };
        return $visit($this->start);
    }
}

class RegexParser
{
    private int $position = 0;

    public function __construct(private string $text)
    {
    }

    private function peek(): string
    {
        return $this->text[$this->position] ?? '';
    }

    private function failParse(): never
    {
        throw new AutomatonError('syntax error at ' . ($this->position + 1));
    }

    public function parse(): array
    {
        $result = $this->alternation();
        if ($this->peek() !== '') {
            $this->failParse();
        }
        return $result;
    }

    private function alternation(): array
    {
        $parts = [$this->concatenation()];
        while ($this->peek() === '|') {
            $this->position++;
            $parts[] = $this->concatenation();
        }
        return count($parts) === 1 ? $parts[0] : ['alternation', $parts];
    }

    private function concatenation(): array
    {
        $parts = [$this->factor()];
        while ($this->peek() !== '' && preg_match('/[a-z0-9(]/', $this->peek())) {
            $parts[] = $this->factor();
        }
        return count($parts) === 1 ? $parts[0] : ['concatenation', $parts];
    }

    private function factor(): array
    {
        $result = $this->atom();
        while (in_array($this->peek(), ['*', '+', '?'], true)) {
            $operator = $this->peek();
            $this->position++;
            $result = [$operator, $result];
        }
        return $result;
    }

    private function atom(): array
    {
        $c = $this->peek();
        if ($c !== '' && preg_match('/[a-z0-9]/', $c)) {
            $this->position++;
            return ['symbol', $c];
        }
        if ($c === '(') {
            $this->position++;
            $result = $this->alternation();
            if ($this->peek() !== ')') {
                $this->failParse();
            }
            $this->position++;
            return $result;
        }
        $this->failParse();
    }
}

class Toolkit
{
    private array $table = [];
    private const ROLES = [
        'ACCEPT' => ['ref', 'other'], 'CLOSURE' => ['ref', 'other'],
        'ENUM' => ['ref', 'other'], 'COUNT' => ['ref', 'other'],
        'TODFA' => ['ref', 'new'], 'EPSFREE' => ['ref', 'new'],
        'REVERSE' => ['ref', 'new'], 'STAR' => ['ref', 'new'],
        'MINIMIZE' => ['dfa', 'new'], 'COMPLEMENT' => ['dfa', 'new'],
        'EQUIV' => ['ref', 'ref'], 'UNION' => ['dfa', 'dfa', 'new'],
        'INTERSECT' => ['dfa', 'dfa', 'new'], 'DIFF' => ['dfa', 'dfa', 'new'],
        'CONCAT' => ['ref', 'ref', 'new'], 'EMPTY' => ['ref'], 'FINITE' => ['ref'],
        'INFO' => ['ref'], 'TABLE' => ['ref'], 'SHOW' => ['ref'], 'DELETE' => ['ref'],
        'SYNC' => ['dfa'], 'LIST' => []
    ];

    private function register(string $name, Automaton $automaton, array $details = []): array
    {
        $this->table[$name] = $automaton;
        return array_merge([$automaton->summary($name)], $details);
    }

    private function define(string $kind, array $args): array
    {
        if (count($args) < 5) {
            throw new AutomatonError('wrong number of arguments');
        }
        [$name, $stateWord, $alphabetWord, $start, $acceptWord] = $args;
        if (isset($this->table[$name])) {
            throw new AutomatonError($name . ' already exists');
        }
        $states = explode(',', $stateWord);
        $indices = [];
        foreach ($states as $i => $state) {
            if (array_key_exists($state, $indices)) {
                throw new AutomatonError('duplicate state ' . $state);
            }
            $indices[$state] = $i;
        }
        if (!array_key_exists($start, $indices)) {
            throw new AutomatonError('unknown state ' . $start);
        }
        $accepting = [];
        if ($acceptWord !== '-') {
            foreach (explode(',', $acceptWord) as $state) {
                if (!array_key_exists($state, $indices)) {
                    throw new AutomatonError('unknown state ' . $state);
                }
                if (in_array($indices[$state], $accepting, true)) {
                    throw new AutomatonError('duplicate state ' . $state);
                }
                $accepting[] = $indices[$state];
            }
        }
        $alphabet = str_split($alphabetWord);
        sort($alphabet, SORT_STRING);
        $triples = [];
        $seen = [];
        $pairs = [];
        foreach (array_slice($args, 5) as $word) {
            [$p, $c, $q] = explode(':', $word);
            if (!array_key_exists($p, $indices)) {
                throw new AutomatonError('unknown state ' . $p);
            }
            if ($c === 'e' && $kind === 'DFA') {
                throw new AutomatonError('epsilon transition in DFA');
            }
            if ($c !== 'e' && !in_array($c, $alphabet, true)) {
                throw new AutomatonError('unknown symbol ' . $c);
            }
            if (!array_key_exists($q, $indices)) {
                throw new AutomatonError('unknown state ' . $q);
            }
            if (isset($seen[$word])) {
                throw new AutomatonError('duplicate transition ' . $word);
            }
            $pair = $p . ':' . $c;
            if ($kind === 'DFA' && isset($pairs[$pair])) {
                throw new AutomatonError('conflicting transition ' . $word);
            }
            $seen[$word] = true;
            $pairs[$pair] = true;
            $triples[] = [$indices[$p], $c, $indices[$q]];
        }
        if ($kind === 'DFA') {
            foreach ($states as $p) {
                foreach ($alphabet as $c) {
                    if (!isset($pairs[$p . ':' . $c])) {
                        throw new AutomatonError('missing transition ' . $p . ':' . $c);
                    }
                }
            }
        }
        return $this->register($name, new Automaton($kind, $states, $alphabet, $indices[$start], $accepting, $triples));
    }

    private function regex(array $args): array
    {
        if (count($args) !== 3) {
            throw new AutomatonError('wrong number of arguments');
        }
        [$name, $alphabet, $text] = $args;
        if (isset($this->table[$name])) {
            throw new AutomatonError($name . ' already exists');
        }
        foreach (str_split($text) as $c) {
            if (preg_match('/[a-z0-9]/', $c) && $c !== 'e' && !str_contains($alphabet, $c)) {
                throw new AutomatonError('unknown symbol ' . $c);
            }
        }
        $tree = (new RegexParser($text))->parse();
        $states = [];
        $triples = [];
        $create = function () use (&$states): int {
            $index = count($states);
            $states[] = 'N' . $index;
            return $index;
        };
        $build = function (array $node) use (&$build, $create, &$triples): array {
            if ($node[0] === 'symbol') {
                $s = $create();
                $f = $create();
                $triples[] = [$s, $node[1], $f];
                return [$s, $f];
            }
            if ($node[0] === 'concatenation') {
                $parts = [];
                foreach ($node[1] as $part) {
                    $parts[] = $build($part);
                }
                for ($i = 1; $i < count($parts); $i++) {
                    $triples[] = [$parts[$i - 1][1], 'e', $parts[$i][0]];
                }
                return [$parts[0][0], $parts[count($parts) - 1][1]];
            }
            $s = $create();
            if ($node[0] === 'alternation') {
                $parts = [];
                foreach ($node[1] as $part) {
                    $parts[] = $build($part);
                }
                $f = $create();
                foreach ($parts as [$a, $b]) {
                    $triples[] = [$s, 'e', $a];
                    $triples[] = [$b, 'e', $f];
                }
            } else {
                [$a, $b] = $build($node[1]);
                $f = $create();
                $triples[] = [$s, 'e', $a];
                $triples[] = [$b, 'e', $f];
                if ($node[0] !== '?') {
                    $triples[] = [$b, 'e', $a];
                }
                if ($node[0] !== '+') {
                    $triples[] = [$s, 'e', $f];
                }
            }
            return [$s, $f];
        };
        [$start, $finish] = $build($tree);
        return $this->register($name, new Automaton('NFA', $states, str_split($alphabet), $start, [$finish], $triples));
    }

    private function product(Automaton $x, Automaton $z, string $operation): array
    {
        $pairs = [[$x->start, $z->start]];
        $indices = [implode(',', $pairs[0]) => 0];
        $triples = [];
        $accepting = [];
        for ($i = 0; $i < count($pairs); $i++) {
            [$p, $q] = $pairs[$i];
            $a = isset($x->accepting[$p]);
            $b = isset($z->accepting[$q]);
            $good = match ($operation) {
                'UNION' => $a || $b,
                'INTERSECT' => $a && $b,
                default => $a && !$b
            };
            if ($good) {
                $accepting[] = $i;
            }
            foreach ($x->alphabet as $c) {
                $target = [$x->edges[$p][$c][0], $z->edges[$q][$c][0]];
                $key = implode(',', $target);
                if (!array_key_exists($key, $indices)) {
                    $indices[$key] = count($pairs);
                    $pairs[] = $target;
                }
                $triples[] = [$i, $c, $indices[$key]];
            }
        }
        $states = array_map(fn($i) => 'P' . $i, array_keys($pairs));
        return [new Automaton('DFA', $states, $x->alphabet, 0, $accepting, $triples), $pairs];
    }

    private function equivalent(Automaton $x, Automaton $z, array $names): array
    {
        $a = $x->determinize()[0];
        $b = $z->determinize()[0];
        $queue = [[$a->start, $b->start, '']];
        $seen = [$a->start . ',' . $b->start => true];
        for ($i = 0; $i < count($queue); $i++) {
            [$p, $q, $word] = $queue[$i];
            if (isset($a->accepting[$p]) !== isset($b->accepting[$q])) {
                $owner = isset($a->accepting[$p]) ? $names[0] : $names[1];
                return ['NOT EQUIVALENT: ' . ($word === '' ? 'e' : $word) . ' is accepted only by ' . $owner];
            }
            foreach ($a->alphabet as $c) {
                $target = [$a->edges[$p][$c][0], $b->edges[$q][$c][0]];
                $key = implode(',', $target);
                if (!isset($seen[$key])) {
                    $seen[$key] = true;
                    $queue[] = [$target[0], $target[1], $word . $c];
                }
            }
        }
        return ['EQUIVALENT'];
    }

    private function synchronization(Automaton $x): array
    {
        $initial = array_keys($x->states);
        $queue = [[$initial, '']];
        $seen = [implode(',', $initial) => true];
        for ($i = 0; $i < count($queue); $i++) {
            [$subset, $word] = $queue[$i];
            if (count($subset) === 1) {
                return ['SYNCHRONIZING ' . ($word === '' ? 'e' : $word) . ' -> ' . $x->states[$subset[0]]];
            }
            foreach ($x->alphabet as $c) {
                $target = [];
                foreach ($subset as $p) {
                    $target[$x->edges[$p][$c][0]] = true;
                }
                $target = array_keys($target);
                sort($target, SORT_NUMERIC);
                $key = implode(',', $target);
                if (!isset($seen[$key])) {
                    $seen[$key] = true;
                    $queue[] = [$target, $word . $c];
                }
            }
        }
        return ['NOT SYNCHRONIZING'];
    }

    public function execute(string $command, array $args): array
    {
        if ($command === 'DFA' || $command === 'NFA') {
            return $this->define($command, $args);
        }
        if ($command === 'REGEX') {
            return $this->regex($args);
        }
        if (!array_key_exists($command, self::ROLES)) {
            throw new AutomatonError('unknown command ' . $command);
        }
        $roles = self::ROLES[$command];
        if (count($roles) !== count($args)) {
            throw new AutomatonError('wrong number of arguments');
        }
        $references = [];
        foreach ($roles as $i => $role) {
            if ($role === 'ref' || $role === 'dfa') {
                if (!isset($this->table[$args[$i]])) {
                    throw new AutomatonError('unknown automaton ' . $args[$i]);
                }
                $references[] = $i;
            }
        }
        foreach ($roles as $i => $role) {
            if ($role === 'new' && isset($this->table[$args[$i]])) {
                throw new AutomatonError($args[$i] . ' already exists');
            }
        }
        foreach ($roles as $i => $role) {
            if ($role === 'dfa' && $this->table[$args[$i]]->kind !== 'DFA') {
                throw new AutomatonError($args[$i] . ' is not a DFA');
            }
        }
        $x = $references === [] ? null : $this->table[$args[0]];
        $z = count($references) === 2 ? $this->table[$args[1]] : null;
        if ($z !== null && $x->alphabet !== $z->alphabet) {
            throw new AutomatonError('alphabets differ');
        }
        switch ($command) {
            case 'LIST':
                $lines = [];
                foreach ($this->table as $name => $automaton) {
                    $lines[] = $automaton->summary($name);
                }
                return $lines === [] ? ['(none)'] : $lines;
            case 'DELETE':
                unset($this->table[$args[0]]);
                return ['deleted ' . $args[0]];
            case 'ACCEPT':
                $word = $args[1] === 'e' ? '' : $args[1];
                foreach (str_split($word) as $c) {
                    if (!in_array($c, $x->alphabet, true)) {
                        throw new AutomatonError('unknown symbol ' . $c);
                    }
                }
                $current = $x->closure([$x->start]);
                $format = fn($s) => $x->kind === 'DFA' ? $x->states[$s[0]] : $x->setText($s);
                $trace = $format($current);
                foreach (str_split($word) as $c) {
                    $current = $x->move($current, $c);
                    $trace .= ' -' . $c . '-> ' . $format($current);
                }
                return [($x->acceptsSet($current) ? 'ACCEPT' : 'REJECT') . ' ' . $trace];
            case 'CLOSURE':
                $values = [];
                foreach (explode(',', $args[1]) as $name) {
                    $index = array_search($name, $x->states, true);
                    if ($index === false) {
                        throw new AutomatonError('unknown state ' . $name);
                    }
                    $values[] = $index;
                }
                return [$x->setText($x->closure($values))];
            case 'TODFA':
                [$result, $subsets] = $x->determinize();
                $details = [];
                foreach ($subsets as $i => $subset) {
                    $details[] = '  D' . $i . ' = ' . $x->setText($subset);
                }
                return $this->register($args[1], $result, $details);
            case 'EPSFREE':
                $triples = [];
                $accepting = [];
                foreach ($x->states as $p => $name) {
                    $initial = $x->closure([$p]);
                    if ($x->acceptsSet($initial)) {
                        $accepting[] = $p;
                    }
                    foreach ($x->alphabet as $c) {
                        foreach ($x->move($initial, $c) as $q) {
                            $triples[] = [$p, $c, $q];
                        }
                    }
                }
                return $this->register($args[1], new Automaton('NFA', $x->states, $x->alphabet, $x->start, $accepting, $triples));
            case 'MINIMIZE':
                [$result, $unreachable, $rounds, $blocks] = $x->minimize();
                $details = ['  unreachable: ' . $x->listText($unreachable)];
                foreach ($rounds as $i => $partition) {
                    $details[] = '  round ' . $i . ': ' . implode(' ', array_map(fn($b) => $x->setText($b), $partition));
                }
                foreach ($blocks as $i => $block) {
                    $details[] = '  M' . $i . ' = ' . $x->setText($block);
                }
                return $this->register($args[1], $result, $details);
            case 'EQUIV':
                return $this->equivalent($x, $z, $args);
            case 'UNION':
            case 'INTERSECT':
            case 'DIFF':
                [$result, $pairs] = $this->product($x, $z, $command);
                $details = [];
                foreach ($pairs as $i => [$p, $q]) {
                    $details[] = '  P' . $i . ' = (' . $x->states[$p] . ',' . $z->states[$q] . ')';
                }
                return $this->register($args[2], $result, $details);
            case 'COMPLEMENT':
                $accepting = array_values(array_diff(array_keys($x->states), array_keys($x->accepting)));
                return $this->register($args[1], new Automaton('DFA', $x->states, $x->alphabet, $x->start, $accepting, $x->triples()));
            case 'REVERSE':
                $triples = [];
                foreach ($x->triples() as [$p, $c, $q]) {
                    $triples[] = [$q + 1, $c, $p + 1];
                }
                foreach ($x->accepting as $p => $_) {
                    $triples[] = [0, 'e', $p + 1];
                }
                $states = array_map(fn($i) => 'N' . $i, range(0, count($x->states)));
                return $this->register($args[1], new Automaton('NFA', $states, $x->alphabet, 0, [$x->start + 1], $triples));
            case 'CONCAT':
                $offset = count($x->states);
                $triples = $x->triples();
                foreach ($z->triples() as [$p, $c, $q]) {
                    $triples[] = [$p + $offset, $c, $q + $offset];
                }
                foreach ($x->accepting as $p => $_) {
                    $triples[] = [$p, 'e', $z->start + $offset];
                }
                $accepting = array_map(fn($p) => $p + $offset, array_keys($z->accepting));
                $states = array_map(fn($i) => 'N' . $i, range(0, $offset + count($z->states) - 1));
                return $this->register($args[2], new Automaton('NFA', $states, $x->alphabet, $x->start, $accepting, $triples));
            case 'STAR':
                $triples = [];
                foreach ($x->triples() as [$p, $c, $q]) {
                    $triples[] = [$p + 1, $c, $q + 1];
                }
                $triples[] = [0, 'e', $x->start + 1];
                $accepting = [0];
                foreach ($x->accepting as $p => $_) {
                    $triples[] = [$p + 1, 'e', $x->start + 1];
                    $accepting[] = $p + 1;
                }
                $states = array_map(fn($i) => 'N' . $i, range(0, count($x->states)));
                return $this->register($args[1], new Automaton('NFA', $states, $x->alphabet, 0, $accepting, $triples));
            case 'ENUM':
                $dfa = $x->determinize()[0];
                $level = [[$dfa->start, '']];
                $total = 0;
                $examples = [];
                $limit = (int) $args[1];
                for ($length = 0; $length <= $limit; $length++) {
                    foreach ($level as [$p, $word]) {
                        if (isset($dfa->accepting[$p])) {
                            $total++;
                            if (count($examples) < 50) {
                                $examples[] = $word === '' ? 'e' : $word;
                            }
                        }
                    }
                    if ($length < $limit) {
                        $next = [];
                        foreach ($level as [$p, $word]) {
                            foreach ($dfa->alphabet as $c) {
                                $next[] = [$dfa->edges[$p][$c][0], $word . $c];
                            }
                        }
                        $level = $next;
                    }
                }
                $words = array_merge([(string) $total], $examples, $total > 50 ? ['...'] : []);
                return [implode(' ', $words)];
            case 'COUNT':
                $dfa = $x->determinize()[0];
                $counts = array_fill(0, count($dfa->states), 0);
                $counts[$dfa->start] = 1;
                for ($i = 0; $i < (int) $args[1]; $i++) {
                    $next = array_fill(0, count($counts), 0);
                    foreach ($counts as $p => $value) {
                        foreach ($dfa->alphabet as $c) {
                            $next[$dfa->edges[$p][$c][0]] += $value;
                        }
                    }
                    $counts = $next;
                }
                $total = 0;
                foreach ($dfa->accepting as $p => $_) {
                    $total += $counts[$p];
                }
                return [(string) $total];
            case 'EMPTY':
                $word = $x->determinize()[0]->shortestWord();
                return [$word === null ? 'EMPTY' : 'NOT EMPTY ' . ($word === '' ? 'e' : $word)];
            case 'FINITE':
                $size = $x->determinize()[0]->finiteSize();
                return [$size === null ? 'INFINITE' : 'FINITE ' . $size];
            case 'SYNC':
                return $this->synchronization($x);
            case 'INFO':
                $dfa = $x->determinize()[0];
                $size = $dfa->finiteSize(false);
                $epsilon = 0;
                foreach ($x->triples() as [$p, $c, $q]) {
                    if ($c === 'e') {
                        $epsilon++;
                    }
                }
                $deterministic = $epsilon === 0;
                $complete = true;
                foreach ($x->edges as $row) {
                    foreach ($x->alphabet as $c) {
                        $number = count($row[$c] ?? []);
                        $deterministic = $deterministic && $number <= 1;
                        $complete = $complete && $number >= 1;
                    }
                }
                $language = $size === null ? 'infinite' : ($size === 0 ? 'empty' : 'finite');
                return [$x->summary($args[0]), '  epsilon transitions: ' . $epsilon,
                    '  reachable: ' . $x->listText($x->reachable([$x->start])),
                    '  live: ' . $x->listText($x->reachable(array_keys($x->accepting), true)),
                    '  deterministic: ' . ($deterministic ? 'yes' : 'no'),
                    '  complete: ' . ($complete ? 'yes' : 'no'), '  language: ' . $language,
                    '  minimal DFA states: ' . count($dfa->minimize()[0]->states)];
            case 'TABLE':
                $hasEpsilon = false;
                foreach ($x->edges as $row) {
                    $hasEpsilon = $hasEpsilon || !empty($row['e']);
                }
                $symbols = array_merge($x->alphabet, $x->kind === 'NFA' && $hasEpsilon ? ['e'] : []);
                $rows = [array_merge([''], $symbols)];
                foreach ($x->states as $p => $name) {
                    $marker = ($p === $x->start ? '->' : '  ') . (isset($x->accepting[$p]) ? '*' : ' ') . $name;
                    $row = [$marker];
                    foreach ($symbols as $c) {
                        $values = $x->edges[$p][$c] ?? [];
                        $row[] = $x->kind === 'DFA' ? $x->states[$values[0]] : ($values === [] ? '-' : $x->setText($values));
                    }
                    $rows[] = $row;
                }
                $widths = array_fill(0, count($rows[0]), 0);
                foreach ($rows as $row) {
                    foreach ($row as $i => $cell) {
                        $widths[$i] = max($widths[$i], strlen($cell));
                    }
                }
                $lines = [];
                foreach ($rows as $row) {
                    $cells = [];
                    foreach ($row as $i => $cell) {
                        $cells[] = str_pad($cell, $widths[$i]);
                    }
                    $lines[] = rtrim(implode('  ', $cells), ' ');
                }
                return $lines;
            case 'SHOW':
                $accepting = array_keys($x->accepting);
                sort($accepting, SORT_NUMERIC);
                $acceptWord = $accepting === [] ? '-' : implode(',', array_map(fn($p) => $x->states[$p], $accepting));
                $words = [$x->kind, $args[0], implode(',', $x->states), implode('', $x->alphabet), $x->states[$x->start], $acceptWord];
                foreach ($x->triples() as [$p, $c, $q]) {
                    $words[] = $x->states[$p] . ':' . $c . ':' . $x->states[$q];
                }
                return [implode(' ', $words)];
        }
    }
}

$first = fgets(STDIN);
$toolkit = new Toolkit();
for ($i = 0; $i < (int) $first; $i++) {
    $line = rtrim(fgets(STDIN), "\r\n");
    if (str_starts_with($line, '#')) {
        continue;
    }
    $words = explode(' ', $line);
    $command = array_shift($words);
    try {
        foreach ($toolkit->execute($command, $words) as $output) {
            echo $output, "\n";
        }
    } catch (AutomatonError $error) {
        echo 'error: ', $error->getMessage(), "\n";
    }
}
