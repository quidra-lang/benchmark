<?php
class Edge
{
    public function __construct(public int $u, public int $v, public int $capacity,
        public int $cost = 0, public int $lower = 0, public int $flow = 0) {}
}

class FlowNetwork
{
    public array $edges;
    public function __construct(public int $n, array $edges = [])
    {
        $this->edges = array_map(fn($e) => clone $e, $edges);
    }

    public function arcs(?int $vertex = null): array
    {
        $result = [];
        foreach ($this->edges as $i => $edge) {
            if ($vertex === null || $edge->u === $vertex) {
                $result[] = $i + 1;
            }
        }
        foreach ($this->edges as $i => $edge) {
            if ($vertex === null || $edge->v === $vertex) {
                $result[] = -$i - 1;
            }
        }
        return $result;
    }

    public function edge(int $arc): Edge
    {
        return $this->edges[abs($arc) - 1];
    }

    public function from(int $arc): int
    {
        return $arc > 0 ? $this->edge($arc)->u : $this->edge($arc)->v;
    }

    public function to(int $arc): int
    {
        return $arc > 0 ? $this->edge($arc)->v : $this->edge($arc)->u;
    }

    public function residual(int $arc): int
    {
        $e = $this->edge($arc);
        return $arc > 0 ? $e->capacity - $e->flow : $e->flow;
    }

    public function arcCost(int $arc): int
    {
        return $arc > 0 ? $this->edge($arc)->cost : -$this->edge($arc)->cost;
    }

    public function push(array $path, int $amount): void
    {
        foreach ($path as $arc) {
            $this->edge($arc)->flow += $arc > 0 ? $amount : -$amount;
        }
    }

    public function bottleneck(array $path): int
    {
        return min(array_map(fn($arc) => $this->residual($arc), $path));
    }

    public function bfs(int $source, int $threshold = 1): array
    {
        $levels = array_fill(0, $this->n, null);
        $parents = array_fill(0, $this->n, null);
        $levels[$source] = 0;
        $queue = [$source];
        for ($i = 0; $i < count($queue); $i++) {
            $u = $queue[$i];
            foreach ($this->arcs($u) as $arc) {
                $v = $this->to($arc);
                if ($this->residual($arc) >= $threshold && $levels[$v] === null) {
                    $levels[$v] = $levels[$u] + 1;
                    $parents[$v] = $arc;
                    $queue[] = $v;
                }
            }
        }
        return [$levels, $parents];
    }

    private function pathTo(int $source, int $target, array $parents): array
    {
        $path = [];
        while ($target !== $source) {
            $arc = $parents[$target];
            $path[] = $arc;
            $target = $this->from($arc);
        }
        return array_reverse($path);
    }

    public function augment(int $source, int $target, int $threshold = 1): ?array
    {
        [$levels, $parents] = $this->bfs($source, $threshold);
        if ($levels[$target] === null) {
            return null;
        }
        $path = $this->pathTo($source, $target, $parents);
        $amount = $this->bottleneck($path);
        $this->push($path, $amount);
        return ['path' => $path, 'amount' => $amount, 'delta' => $threshold];
    }

    public function maxflow(int $source, int $target, string $method = 'MAXFLOW'): array
    {
        $records = [];
        $phases = 0;
        if ($method === 'DINIC') {
            while (true) {
                [$levels] = $this->bfs($source);
                if ($levels[$target] === null) {
                    break;
                }
                $phases++;
                $lists = [];
                for ($v = 0; $v < $this->n; $v++) {
                    $lists[] = $this->arcs($v);
                }
                $pointers = array_fill(0, $this->n, 0);
                $path = [];
                $u = $source;
                while (true) {
                    if ($u === $target) {
                        $amount = $this->bottleneck($path);
                        $this->push($path, $amount);
                        $records[] = ['path' => $path, 'amount' => $amount, 'phase' => $phases];
                        $path = [];
                        $u = $source;
                    } elseif ($pointers[$u] >= count($lists[$u])) {
                        if ($u === $source) {
                            break;
                        }
                        $u = $this->from(array_pop($path));
                        $pointers[$u]++;
                    } else {
                        $arc = $lists[$u][$pointers[$u]];
                        $v = $this->to($arc);
                        if ($this->residual($arc) > 0 && $levels[$v] !== null && $levels[$v] === $levels[$u] + 1) {
                            $path[] = $arc;
                            $u = $v;
                        } else {
                            $pointers[$u]++;
                        }
                    }
                }
            }
        } else {
            $threshold = 1;
            $maximum = $this->edges ? max(array_map(fn($e) => $e->capacity, $this->edges)) : 0;
            while ($method === 'SCALING' && $threshold * 2 <= $maximum) {
                $threshold *= 2;
            }
            while ($threshold >= 1) {
                while (($record = $this->augment($source, $target, $threshold)) !== null) {
                    $records[] = $record;
                }
                $threshold = $method === 'SCALING' ? intdiv($threshold, 2) : 0;
            }
        }
        return [$records, $phases];
    }

    public function negativeCycle(): bool
    {
        $distance = array_fill(0, $this->n, 0);
        for ($pass = 0; $pass < $this->n; $pass++) {
            $changed = false;
            foreach ($this->edges as $e) {
                if ($e->capacity > 0 && $distance[$e->u] + $e->cost < $distance[$e->v]) {
                    $distance[$e->v] = $distance[$e->u] + $e->cost;
                    $changed = true;
                }
            }
            if (!$changed) {
                return false;
            }
        }
        return $this->n > 0;
    }

    public function mincost(int $source, int $target, ?int $limit = null): array
    {
        $amount = 0;
        $cost = 0;
        $records = [];
        while ($limit === null || $amount < $limit) {
            $usable = array_filter($this->arcs(), fn($arc) => $this->residual($arc) > 0);
            $distance = array_fill(0, $this->n, null);
            $parents = array_fill(0, $this->n, null);
            $distance[$source] = 0;
            do {
                $changed = false;
                foreach ($usable as $arc) {
                    $u = $this->from($arc);
                    $v = $this->to($arc);
                    if ($distance[$u] === null) {
                        continue;
                    }
                    $value = $distance[$u] + $this->arcCost($arc);
                    if ($distance[$v] === null || $value < $distance[$v]) {
                        $distance[$v] = $value;
                        $parents[$v] = $arc;
                        $changed = true;
                    }
                }
            } while ($changed);
            if ($distance[$target] === null) {
                break;
            }
            $path = $this->pathTo($source, $target, $parents);
            $delta = $this->bottleneck($path);
            if ($limit !== null) {
                $delta = min($delta, $limit - $amount);
            }
            $this->push($path, $delta);
            $amount += $delta;
            $cost += $delta * $distance[$target];
            $records[] = ['path' => $path, 'amount' => $delta, 'cost' => $distance[$target]];
        }
        return [$amount, $cost, $records];
    }

    public function balance(): array
    {
        $result = array_fill(0, $this->n, 0);
        foreach ($this->edges as $e) {
            $result[$e->u] += $e->flow;
            $result[$e->v] -= $e->flow;
        }
        return $result;
    }

    public function totalCost(): int
    {
        return array_sum(array_map(fn($e) => $e->flow * $e->cost, $this->edges));
    }

    public function decompose(): array
    {
        $remaining = array_map(fn($e) => $e->flow, $this->edges);
        $balances = $this->balance();
        $result = [];
        while (true) {
            $positive = array_keys(array_filter($remaining, fn($g) => $g > 0));
            if (!$positive) {
                break;
            }
            $supplies = array_keys(array_filter($balances, fn($b) => $b > 0));
            $start = $supplies ? $supplies[0] : $this->edges[$positive[0]]->u;
            $vertices = [$start];
            $path = [];
            while (true) {
                $u = $vertices[count($vertices) - 1];
                foreach ($this->edges as $i => $edge) {
                    if ($edge->u === $u && $remaining[$i] > 0) {
                        break;
                    }
                }
                $v = $this->edges[$i]->v;
                $path[] = $i + 1;
                $q = array_search($v, $vertices, true);
                if ($q !== false) {
                    $cycle = array_slice($path, $q);
                    $delta = min(array_map(fn($arc) => $remaining[$arc - 1], $cycle));
                    foreach ($cycle as $arc) {
                        $remaining[$arc - 1] -= $delta;
                    }
                    $result[] = ['kind' => 'CYCLE', 'start' => $v, 'path' => $cycle, 'amount' => $delta];
                    break;
                }
                $vertices[] = $v;
                if ($balances[$v] < 0) {
                    $delta = min(min(array_map(fn($arc) => $remaining[$arc - 1], $path)), $balances[$start], -$balances[$v]);
                    foreach ($path as $arc) {
                        $remaining[$arc - 1] -= $delta;
                    }
                    $balances[$start] -= $delta;
                    $balances[$v] += $delta;
                    $result[] = ['kind' => 'PATH', 'start' => $start, 'path' => $path, 'amount' => $delta];
                    break;
                }
            }
        }
        return $result;
    }
}

class FlowError extends Exception {}

class FlowSolver
{
    private array $names = [];
    private array $demands = [];
    private FlowNetwork $network;
    private ?array $owner = null;

    public function __construct()
    {
        $this->network = new FlowNetwork(0);
    }

    private function vertex(string $name): int
    {
        $v = array_search($name, $this->names, true);
        if ($v === false) {
            throw new FlowError("UNKNOWN NODE $name");
        }
        return $v;
    }

    private function endpoints(string $s, string $t): array
    {
        $source = $this->vertex($s);
        $target = $this->vertex($t);
        if ($source === $target) {
            throw new FlowError('SAME NODE');
        }
        return [$source, $target];
    }

    private function checkedEdge(string $text): Edge
    {
        $number = (int)$text;
        if ($number < 1 || $number > count($this->network->edges)) {
            throw new FlowError("UNKNOWN EDGE $text");
        }
        return $this->network->edges[$number - 1];
    }

    private function fresh(): FlowNetwork
    {
        $copy = new FlowNetwork(count($this->names), $this->network->edges);
        foreach ($copy->edges as $e) {
            $e->flow = 0;
        }
        return $copy;
    }

    private function startFlow(int $source, int $target): int
    {
        if ($this->owner !== ['flow', $source, $target]) {
            foreach ($this->network->edges as $e) {
                $e->flow = 0;
            }
        }
        $this->owner = ['flow', $source, $target];
        return $this->network->balance()[$source];
    }

    private function notation(FlowNetwork $network, int $start, array $path, ?int $originalOnly = null): string
    {
        $words = [$this->names[$start]];
        foreach ($path as $arc) {
            if ($originalOnly !== null && abs($arc) > $originalOnly) {
                continue;
            }
            $words[] = ($arc > 0 ? '+' : '-') . abs($arc);
            $v = $originalOnly !== null ? $this->network->edges[abs($arc) - 1]->v : $network->to($arc);
            $words[] = $this->names[$v];
        }
        return implode(' ', $words);
    }

    private function flowList(): void
    {
        foreach ($this->network->edges as $i => $e) {
            echo 'FLOW ', $i + 1, " {$this->names[$e->u]} {$this->names[$e->v]} {$e->flow}/{$e->capacity}\n";
        }
    }

    private function circulation(string $mode): void
    {
        $work = $this->fresh();
        foreach ($work->edges as $e) {
            $e->capacity -= $e->lower;
        }
        if ($mode === 'MINCOST' && $work->negativeCycle()) {
            throw new FlowError('NEGATIVE CYCLE');
        }
        $total = array_sum($this->demands);
        if ($total !== 0) {
            echo "CIRCULATION infeasible unbalanced=$total\n";
            return;
        }
        $residual = $this->demands;
        foreach ($this->network->edges as $e) {
            $residual[$e->v] -= $e->lower;
            $residual[$e->u] += $e->lower;
        }
        $source = count($this->names);
        $target = $source + 1;
        foreach ($residual as $v => $r) {
            if ($r < 0) {
                $work->edges[] = new Edge($source, $v, -$r);
            }
        }
        $sinks = [];
        foreach ($residual as $v => $r) {
            if ($r > 0) {
                $sinks[] = count($work->edges);
                $work->edges[] = new Edge($v, $target, $r);
            }
        }
        $work->n = $target + 1;
        if ($mode === 'ANY') {
            $work->maxflow($source, $target);
        } else {
            $work->mincost($source, $target);
        }
        $required = array_sum(array_filter($residual, fn($r) => $r > 0));
        $achieved = array_sum(array_map(fn($i) => $work->edges[$i]->flow, $sinks));
        if ($achieved < $required) {
            echo "CIRCULATION infeasible required=$required achieved=$achieved\n";
            [$reachable] = $work->bfs($source);
            $cut = [];
            foreach ($this->names as $v => $name) {
                if ($reachable[$v] !== null) {
                    $cut[] = $name;
                }
            }
            echo 'CUT ', implode(' ', $cut), "\n";
        } else {
            foreach ($this->network->edges as $i => $e) {
                $e->flow = $e->lower + $work->edges[$i]->flow;
            }
            $this->owner = ['circulation'];
            echo "CIRCULATION feasible required=$required cost=", $this->network->totalCost(), "\n";
            $this->flowList();
        }
    }

    private function matching(string $leftText, string $rightText, string $pairText): void
    {
        $left = explode(',', $leftText);
        $right = explode(',', $rightText);
        $seen = [];
        foreach (array_merge($left, $right) as $name) {
            if (isset($seen[$name])) {
                throw new FlowError("DUPLICATE VERTEX $name");
            }
            $seen[$name] = true;
        }
        $pairs = $pairText === '-' ? [] : array_map(fn($p) => explode('-', $p), explode(',', $pairText));
        $seenPairs = [];
        foreach ($pairs as [$a, $b]) {
            if (!in_array($a, $left, true)) {
                throw new FlowError("UNKNOWN VERTEX $a");
            }
            if (!in_array($b, $right, true)) {
                throw new FlowError("UNKNOWN VERTEX $b");
            }
            if (isset($seenPairs["$a-$b"])) {
                throw new FlowError("DUPLICATE PAIR $a-$b");
            }
            $seenPairs["$a-$b"] = true;
        }
        $lp = [];
        $rp = [];
        $examined = [];
        $attempt = function (string $a) use (&$attempt, &$lp, &$rp, &$examined, $pairs): bool {
            foreach ($pairs as [$x, $b]) {
                if ($x !== $a || isset($examined[$b])) {
                    continue;
                }
                $examined[$b] = true;
                if (!isset($rp[$b]) || $attempt($rp[$b])) {
                    $rp[$b] = $a;
                    $lp[$a] = $b;
                    return true;
                }
            }
            return false;
        };
        foreach ($left as $a) {
            $examined = [];
            $attempt($a);
        }
        $freeLeft = array_values(array_filter($left, fn($a) => !isset($lp[$a])));
        $freeRight = array_values(array_filter($right, fn($b) => !isset($rp[$b])));
        $zl = array_fill_keys($freeLeft, true);
        $zr = [];
        $queue = $freeLeft;
        for ($i = 0; $i < count($queue); $i++) {
            $a = $queue[$i];
            foreach ($pairs as [$x, $b]) {
                if ($x === $a && ($lp[$a] ?? null) !== $b && !isset($zr[$b])) {
                    $zr[$b] = true;
                    if (isset($rp[$b]) && !isset($zl[$rp[$b]])) {
                        $zl[$rp[$b]] = true;
                        $queue[] = $rp[$b];
                    }
                }
            }
        }
        $cover = array_merge(array_filter($left, fn($a) => !isset($zl[$a])), array_filter($right, fn($b) => isset($zr[$b])));
        echo 'MATCH size=', count($lp), ' left=', count($left), ' right=', count($right), "\n";
        foreach ($left as $a) {
            if (isset($lp[$a])) {
                echo "PAIR $a {$lp[$a]}\n";
            }
        }
        echo 'FREE ', $freeLeft ? implode(',', $freeLeft) : '-', ' ', $freeRight ? implode(',', $freeRight) : '-', "\n";
        echo 'COVER size=', count($cover), $cover ? ' ' . implode(' ', $cover) : '', "\n";
        if ($freeLeft) {
            echo 'HALL ', implode(',', array_filter($left, fn($a) => isset($zl[$a]))), ' ',
                $zr ? implode(',', array_filter($right, fn($b) => isset($zr[$b]))) : '-', "\n";
        }
    }

    private function assignment(string $mode, int $n, array $values): void
    {
        if ($n < 1 || $n > 8) {
            throw new FlowError('BAD SIZE');
        }
        if (count($values) !== $n * $n) {
            throw new FlowError('BAD LENGTH');
        }
        $best = null;
        $count = 0;
        $chosen = [];
        $search = function (array $columns, int $total) use (&$search, &$best, &$count, &$chosen, $mode, $n, $values): void {
            $row = count($columns);
            if ($row === $n) {
                if ($best === null || ($mode === 'MIN' ? $total < $best : $total > $best)) {
                    $best = $total;
                    $count = 1;
                    $chosen = $columns;
                } elseif ($total === $best) {
                    $count++;
                }
                return;
            }
            for ($column = 0; $column < $n; $column++) {
                $value = $values[$row * $n + $column];
                if (!in_array($column, $columns, true) && $value !== 'x') {
                    $search([...$columns, $column], $total + (int)$value);
                }
            }
        };
        $search([], 0);
        if ($best === null) {
            echo "ASSIGN $mode n=$n infeasible\n";
        } else {
            echo "ASSIGN $mode n=$n total=$best optimal=$count\n";
            foreach ($chosen as $row => $column) {
                echo 'MATE ', $row + 1, ' ', $column + 1, ' ', $values[$row * $n + $column], "\n";
            }
        }
    }

    public function execute(string $line): void
    {
        $args = explode(' ', $line);
        $command = array_shift($args);
        try {
            switch ($command) {
                case 'NODE':
                    $seen = $this->names;
                    foreach ($args as $name) {
                        if (in_array($name, $seen, true)) {
                            throw new FlowError("DUPLICATE NODE $name");
                        }
                        $seen[] = $name;
                    }
                    if (count($seen) > 20) {
                        throw new FlowError('TOO MANY NODES');
                    }
                    $this->names = $seen;
                    $this->demands = array_merge($this->demands, array_fill(0, count($args), 0));
                    $this->network->n = count($seen);
                    echo 'NODE added=', count($args), ' total=', count($seen), "\n";
                    break;
                case 'EDGE':
                    $u = $this->vertex($args[0]);
                    $v = $this->vertex($args[1]);
                    if ($u === $v) {
                        throw new FlowError('SELF LOOP');
                    }
                    if (count($this->network->edges) === 60) {
                        throw new FlowError('TOO MANY EDGES');
                    }
                    $e = new Edge($u, $v, (int)$args[2], (int)($args[3] ?? 0));
                    $this->network->edges[] = $e;
                    echo 'EDGE ', count($this->network->edges), " {$args[0]} {$args[1]} cap={$e->capacity} cost={$e->cost}\n";
                    break;
                case 'LOWER':
                case 'CAP':
                case 'COST':
                    $e = $this->checkedEdge($args[0]);
                    $value = (int)$args[1];
                    if ($command === 'LOWER') {
                        if ($value > $e->capacity) {
                            throw new FlowError('BAD BOUND');
                        }
                        $e->lower = $value;
                        echo "LOWER {$args[0]} low=$value cap={$e->capacity}\n";
                    } elseif ($command === 'CAP') {
                        if ($value < $e->lower) {
                            throw new FlowError('BAD BOUND');
                        }
                        if ($value < $e->flow) {
                            throw new FlowError('BELOW FLOW');
                        }
                        $e->capacity = $value;
                        echo "CAP {$args[0]} low={$e->lower} cap=$value\n";
                    } else {
                        $e->cost = $value;
                        echo "COST {$args[0]} cost=$value\n";
                    }
                    break;
                case 'DEMAND':
                    $v = $this->vertex($args[0]);
                    $this->demands[$v] = (int)$args[1];
                    echo "DEMAND {$args[0]} {$args[1]} total=", array_sum($this->demands), "\n";
                    break;
                case 'RESET':
                    echo 'RESET edges=', count(array_filter($this->network->edges, fn($e) => $e->flow !== 0)), "\n";
                    foreach ($this->network->edges as $e) {
                        $e->flow = 0;
                    }
                    $this->owner = null;
                    break;
                case 'CLEAR':
                    echo 'CLEAR nodes=', count($this->names), ' edges=', count($this->network->edges), "\n";
                    $this->names = [];
                    $this->demands = [];
                    $this->network = new FlowNetwork(0);
                    $this->owner = null;
                    break;
                case 'SHOW':
                    $balance = $this->network->balance();
                    echo 'NETWORK nodes=', count($this->names), ' edges=', count($this->network->edges), "\n";
                    if ($this->owner === null) {
                        echo "STATE none\n";
                    } elseif ($this->owner[0] === 'circulation') {
                        echo 'STATE circulation cost=', $this->network->totalCost(), "\n";
                    } else {
                        echo "STATE flow {$this->names[$this->owner[1]]} {$this->names[$this->owner[2]]} value={$balance[$this->owner[1]]} cost=",
                            $this->network->totalCost(), "\n";
                    }
                    foreach ($this->names as $v => $name) {
                        $out = 0;
                        foreach ($this->network->edges as $e) {
                            if ($e->u === $v) {
                                $out += $e->flow;
                            }
                        }
                        echo "NODE $name demand={$this->demands[$v]} out=$out in=", $out - $balance[$v], "\n";
                    }
                    foreach ($this->network->edges as $i => $e) {
                        echo 'EDGE ', $i + 1, " {$this->names[$e->u]} {$this->names[$e->v]} cap={$e->capacity} cost={$e->cost} low={$e->lower} flow={$e->flow}\n";
                    }
                    break;
                case 'DECOMPOSE':
                    $records = $this->network->decompose();
                    $paths = count(array_filter($records, fn($r) => $r['kind'] === 'PATH'));
                    echo "DECOMPOSE paths=$paths cycles=", count($records) - $paths, "\n";
                    $counters = ['PATH' => 0, 'CYCLE' => 0];
                    foreach ($records as $r) {
                        $number = ++$counters[$r['kind']];
                        echo "{$r['kind']} $number amount={$r['amount']} ", $this->notation($this->network, $r['start'], $r['path']), "\n";
                    }
                    break;
                case 'VERIFY':
                    $violations = [];
                    foreach ($this->network->edges as $i => $e) {
                        if ($e->flow < $e->lower) {
                            $violations[] = 'LOW ' . ($i + 1) . " flow={$e->flow} low={$e->lower}";
                        }
                    }
                    $balance = $this->network->balance();
                    foreach ($this->names as $v => $name) {
                        $isFlow = $this->owner !== null && $this->owner[0] === 'flow';
                        if ($isFlow && ($v === $this->owner[1] || $v === $this->owner[2])) {
                            continue;
                        }
                        $required = $isFlow ? 0 : $this->demands[$v];
                        if (-$balance[$v] !== $required) {
                            $violations[] = "BALANCE $name net=" . (-$balance[$v]) . " need=$required";
                        }
                    }
                    echo $violations ? 'VERIFY violations=' . count($violations) . "\n" . implode("\n", $violations) : 'VERIFY ok', "\n";
                    break;
                case 'CIRCULATION':
                    $this->circulation($args[0]);
                    break;
                case 'MATCH':
                    $this->matching(...$args);
                    break;
                case 'ASSIGN':
                    $this->assignment($args[0], (int)$args[1], array_slice($args, 2));
                    break;
                default:
                    [$source, $target] = $this->endpoints($args[0], $args[1]);
                    $this->flowCommand($command, $args, $source, $target);
            }
        } catch (FlowError $error) {
            echo 'ERROR ', $error->getMessage(), "\n";
        }
    }

    private function flowCommand(string $command, array $args, int $source, int $target): void
    {
        $prefix = "$command {$args[0]} {$args[1]}";
        if ($command === 'SENSITIVITY') {
            $maximum = function (?int $index, int $delta) use ($source, $target): int {
                $work = $this->fresh();
                if ($index !== null) {
                    $work->edges[$index]->capacity += $delta;
                }
                $work->maxflow($source, $target);
                return $work->balance()[$source];
            };
            $value = $maximum(null, 0);
            $critical = [];
            foreach ($this->network->edges as $i => $e) {
                $critical[] = [$i, $maximum($i, 1) > $value, $e->capacity > 0 && $maximum($i, -1) < $value];
            }
            echo "$prefix value=$value up=", count(array_filter($critical, fn($r) => $r[1])),
                ' down=', count(array_filter($critical, fn($r) => $r[2])), "\n";
            foreach ($critical as [$i, $up, $down]) {
                if ($up || $down) {
                    $e = $this->network->edges[$i];
                    echo 'CRITICAL ', $i + 1, " {$this->names[$e->u]} {$this->names[$e->v]} up=", $up ? 'yes' : 'no',
                        ' down=', $down ? 'yes' : 'no', "\n";
                }
            }
        } elseif ($command === 'MINCOST') {
            $work = $this->fresh();
            if ($work->negativeCycle()) {
                throw new FlowError('NEGATIVE CYCLE');
            }
            $limit = $args[2] === 'MAX' ? null : (int)$args[2];
            [$amount, $cost, $records] = $work->mincost($source, $target, $limit);
            if ($limit !== null && $amount < $limit) {
                echo "$prefix k={$args[2]} infeasible max=$amount\n";
                return;
            }
            foreach ($this->network->edges as $i => $e) {
                $e->flow = $work->edges[$i]->flow;
            }
            $this->owner = ['flow', $source, $target];
            echo "$prefix k={$args[2]} flow=$amount cost=$cost\n";
            foreach ($records as $i => $r) {
                echo 'AUG ', $i + 1, " amount={$r['amount']} cost={$r['cost']} ", $this->notation($work, $source, $r['path']), "\n";
            }
            $this->flowList();
        } elseif ($command === 'DISJOINT') {
            $edges = array_map(fn($e) => new Edge($e->u, $e->v, $e->capacity > 0 ? 1 : 0), $this->network->edges);
            $n = count($this->names);
            if ($args[2] === 'VERTEX') {
                $exits = range(0, $n - 1);
                for ($v = 0; $v < count($this->names); $v++) {
                    if ($v !== $source && $v !== $target) {
                        $exits[$v] = $n++;
                    }
                }
                foreach ($edges as $e) {
                    $e->u = $exits[$e->u];
                }
                for ($v = 0; $v < count($this->names); $v++) {
                    if ($v !== $source && $v !== $target) {
                        $edges[] = new Edge($v, $exits[$v], 1);
                    }
                }
            }
            $work = new FlowNetwork($n, $edges);
            $work->maxflow($source, $target);
            $records = array_values(array_filter($work->decompose(), fn($r) => $r['kind'] === 'PATH'));
            echo "$prefix {$args[2]} count=", count($records), "\n";
            foreach ($records as $i => $r) {
                echo 'PATH ', $i + 1, ' ', $this->notation($work, $source, $r['path'], count($this->network->edges)), "\n";
            }
        } else {
            $start = $this->startFlow($source, $target);
            if ($command === 'AUGMENT') {
                $r = $this->network->augment($source, $target);
                echo "$prefix value=", $this->network->balance()[$source], ' ',
                    $r === null ? 'none' : "amount={$r['amount']} " . $this->notation($this->network, $source, $r['path']), "\n";
                return;
            }
            [$records, $phases] = $this->network->maxflow($source, $target, $command);
            $value = $this->network->balance()[$source];
            if ($command === 'MINCUT') {
                [$reachable] = $this->network->bfs($source);
                $cut = [];
                foreach ($this->network->edges as $i => $e) {
                    if ($reachable[$e->u] !== null && $reachable[$e->v] === null) {
                        $cut[] = $i;
                    }
                }
                echo "$prefix value=$value edges=", count($cut), "\n";
                $s = [];
                $t = [];
                foreach ($this->names as $v => $name) {
                    if ($reachable[$v] === null) {
                        $t[] = $name;
                    } else {
                        $s[] = $name;
                    }
                }
                echo 'SOURCE ', implode(' ', $s), "\nSINK ", implode(' ', $t), "\n";
                foreach ($cut as $i) {
                    $e = $this->network->edges[$i];
                    echo 'CUT ', $i + 1, " {$this->names[$e->u]} {$this->names[$e->v]} {$e->capacity}\n";
                }
            } else {
                echo "$prefix value=$value start=$start", $command === 'DINIC' ? " phases=$phases" : '',
                    ' paths=', count($records), "\n";
                foreach ($records as $i => $r) {
                    $extra = match ($command) {
                        'DINIC' => "phase={$r['phase']} ",
                        'SCALING' => "delta={$r['delta']} ",
                        default => ''
                    };
                    echo 'AUG ', $i + 1, " {$extra}amount={$r['amount']} ", $this->notation($this->network, $source, $r['path']), "\n";
                }
                $this->flowList();
            }
        }
    }
}

$solver = new FlowSolver();
$count = (int)fgets(STDIN);
for ($i = 0; $i < $count; $i++) {
    $solver->execute(rtrim(fgets(STDIN), "\r\n"));
}
