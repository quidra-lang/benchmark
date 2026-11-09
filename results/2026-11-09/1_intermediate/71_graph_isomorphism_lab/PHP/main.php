<?php
function compare_sequences(array $a, array $b): int
{
    for ($i = 0; $i < min(count($a), count($b)); $i++) {
        if ($a[$i] !== $b[$i]) {
            return $a[$i] <=> $b[$i];
        }
    }
    return count($a) <=> count($b);
}

class Graph
{
    public array $adj;
    private ?array $edgeCache = null;
    private ?array $degreeCache = null;
    private ?array $stableCache = null;
    private ?array $canonicalCache = null;
    private ?array $invariantCache = null;

    public function __construct(public int $n)
    {
        $this->adj = array_fill(0, $n, array_fill(0, $n, false));
    }

    public function join(int $u, int $v): void
    {
        $this->adj[$u][$v] = true;
        $this->adj[$v][$u] = true;
    }

    public function vertices(): array
    {
        return range(0, $this->n - 1);
    }

    public function neighbors(int $v): array
    {
        return array_keys(array_filter($this->adj[$v]));
    }

    public function edges(): array
    {
        if ($this->edgeCache === null) {
            $this->edgeCache = [];
            for ($u = 0; $u < $this->n; $u++) {
                for ($v = $u + 1; $v < $this->n; $v++) {
                    if ($this->adj[$u][$v]) {
                        $this->edgeCache[] = [$u, $v];
                    }
                }
            }
        }
        return $this->edgeCache;
    }

    public function degrees(): array
    {
        return $this->degreeCache ??= array_map(fn($v) => count($this->neighbors($v)), $this->vertices());
    }

    public function refine(array $colors): array
    {
        $rounds = 0;
        while (true) {
            $signatures = [];
            foreach ($this->vertices() as $v) {
                $neighbors = array_map(fn($w) => $colors[$w], $this->neighbors($v));
                sort($neighbors, SORT_NUMERIC);
                $signatures[] = [$colors[$v], $neighbors];
            }
            $ordered = $signatures;
            usort($ordered, fn($a, $b) => ($a[0] <=> $b[0]) ?: compare_sequences($a[1], $b[1]));
            $unique = [];
            foreach ($ordered as $signature) {
                if (!$unique || $unique[count($unique) - 1] !== $signature) {
                    $unique[] = $signature;
                }
            }
            $fresh = array_map(fn($s) => array_search($s, $unique, true), $signatures);
            if (count($unique) === count(array_unique($colors))) {
                return [$colors, $rounds];
            }
            $colors = $fresh;
            $rounds++;
        }
    }

    public function stable(): array
    {
        if ($this->stableCache === null) {
            $degrees = $this->degrees();
            $ordered = array_values(array_unique($degrees));
            sort($ordered, SORT_NUMERIC);
            $this->stableCache = $this->refine(array_map(fn($d) => array_search($d, $ordered, true), $degrees));
        }
        return $this->stableCache;
    }

    public function individualize(array $colors, int $v): array
    {
        $result = [];
        foreach ($colors as $w => $color) {
            $result[] = $color < $colors[$v] || $w === $v ? $color : $color + 1;
        }
        return $result;
    }

    private function leafString(array $labels): string
    {
        $inverse = array_flip($labels);
        $string = '';
        for ($u = 0; $u < $this->n; $u++) {
            for ($v = $u + 1; $v < $this->n; $v++) {
                $string .= $this->adj[$inverse[$u]][$inverse[$v]] ? '1' : '0';
            }
        }
        return $string;
    }

    public function canonical(): array
    {
        if ($this->canonicalCache !== null) {
            return $this->canonicalCache;
        }
        $nodes = 0;
        $leaves = 0;
        $best = null;
        $labels = [];
        $winners = [];
        $visit = function (array $colors) use (&$visit, &$nodes, &$leaves, &$best, &$labels, &$winners): void {
            $nodes++;
            if (count(array_unique($colors)) === $this->n) {
                $leaves++;
                $string = $this->leafString($colors);
                if ($best === null || strcmp($string, $best) > 0) {
                    $best = $string;
                    $labels = $colors;
                    $winners = [$colors];
                } elseif ($string === $best) {
                    $winners[] = $colors;
                }
                return;
            }
            $cells = [];
            foreach ($colors as $v => $color) {
                $cells[$color][] = $v;
            }
            ksort($cells, SORT_NUMERIC);
            $chosen = null;
            foreach ($cells as $cell) {
                if (count($cell) > 1 && ($chosen === null || count($cell) < count($chosen))) {
                    $chosen = $cell;
                }
            }
            foreach ($chosen as $v) {
                $visit($this->refine($this->individualize($colors, $v))[0]);
            }
        };
        $visit($this->stable()[0]);
        return $this->canonicalCache = compact('nodes', 'leaves', 'best', 'labels', 'winners');
    }

    public function invariants(): array
    {
        if ($this->invariantCache !== null) {
            return $this->invariantCache;
        }
        $components = [];
        $seen = [];
        foreach ($this->vertices() as $start) {
            if (isset($seen[$start])) {
                continue;
            }
            $queue = [$start];
            $seen[$start] = true;
            for ($i = 0; $i < count($queue); $i++) {
                foreach ($this->neighbors($queue[$i]) as $v) {
                    if (!isset($seen[$v])) {
                        $seen[$v] = true;
                        $queue[] = $v;
                    }
                }
            }
            $components[] = count($queue);
        }
        $girth = null;
        $eccentricities = [];
        $bipartite = true;
        foreach ($this->vertices() as $start) {
            $distance = [$start => 0];
            $parent = [];
            $queue = [$start];
            for ($i = 0; $i < count($queue); $i++) {
                $u = $queue[$i];
                foreach ($this->neighbors($u) as $v) {
                    if (!isset($distance[$v])) {
                        $distance[$v] = $distance[$u] + 1;
                        $parent[$v] = $u;
                        $queue[] = $v;
                    } elseif (($parent[$u] ?? null) !== $v) {
                        $length = $distance[$u] + $distance[$v] + 1;
                        $girth = $girth === null ? $length : min($girth, $length);
                    }
                    if ($distance[$u] % 2 === $distance[$v] % 2) {
                        $bipartite = false;
                    }
                }
            }
            $eccentricities[] = max($distance);
        }
        $triangles = 0;
        for ($a = 0; $a < $this->n; $a++) {
            for ($b = $a + 1; $b < $this->n; $b++) {
                for ($c = $b + 1; $c < $this->n; $c++) {
                    if ($this->adj[$a][$b] && $this->adj[$a][$c] && $this->adj[$b][$c]) {
                        $triangles++;
                    }
                }
            }
        }
        $degrees = $this->degrees();
        rsort($degrees, SORT_NUMERIC);
        rsort($components, SORT_NUMERIC);
        return $this->invariantCache = [
            'degrees' => $degrees, 'triangles' => $triangles, 'sizes' => $components,
            'components' => count($components), 'girth' => $girth ?? 'none',
            'diameter' => count($components) === 1 ? max($eccentricities) : 'INF',
            'radius' => count($components) === 1 ? min($eccentricities) : 'INF',
            'bipartite' => $bipartite ? 'yes' : 'no'
        ];
    }

    public function clique(): array
    {
        $best = [];
        for ($mask = 1; $mask < (1 << $this->n); $mask++) {
            $set = [];
            foreach ($this->vertices() as $v) {
                if ($mask & (1 << $v)) {
                    foreach ($set as $w) {
                        if (!$this->adj[$v][$w]) {
                            continue 3;
                        }
                    }
                    $set[] = $v;
                }
            }
            if (count($set) > count($best) || (count($set) === count($best) && compare_sequences($set, $best) < 0)) {
                $best = $set;
            }
        }
        return $best;
    }

    public function coloring(): array
    {
        for ($limit = 1; $limit <= $this->n; $limit++) {
            $colors = array_fill(0, $this->n, -1);
            $search = function (int $v, int $maximum) use (&$search, &$colors, $limit): bool {
                if ($v === $this->n) {
                    return true;
                }
                for ($color = 0; $color <= min($limit - 1, $maximum + 1); $color++) {
                    for ($w = 0; $w < $v; $w++) {
                        if ($this->adj[$v][$w] && $colors[$w] === $color) {
                            continue 2;
                        }
                    }
                    $colors[$v] = $color;
                    if ($search($v + 1, max($maximum, $color))) {
                        return true;
                    }
                }
                $colors[$v] = -1;
                return false;
            };
            if ($search(0, -1)) {
                return [$limit, $colors];
            }
        }
    }
}

class GraphError extends Exception {}

class GraphLab
{
    private array $graphs = [];
    private array $classes = [];
    private const SCHEMAS = [
        'GRAPH' => [2, null, ['name', 'num'], 'edge'], 'CYCLE' => [2, 2, ['name', 'num']],
        'PATH' => [2, 2, ['name', 'num']], 'COMPLETE' => [2, 2, ['name', 'num']],
        'BIPARTITE' => [3, 3, ['name', 'num', 'num']], 'STAR' => [2, 2, ['name', 'num']],
        'WHEEL' => [2, 2, ['name', 'num']], 'PETERSEN' => [1, 1, ['name']],
        'HYPERCUBE' => [2, 2, ['name', 'num']], 'CIRCULANT' => [3, null, ['name', 'num'], 'num'],
        'GRID' => [3, 3, ['name', 'num', 'num']], 'COMPLEMENT' => [2, 2, ['name', 'graph']],
        'LINE' => [2, 2, ['name', 'graph']], 'PRODUCT' => [3, 3, ['name', 'graph', 'graph']],
        'UNION' => [3, 3, ['name', 'graph', 'graph']], 'RELABEL' => [2, null, ['name', 'graph'], 'num'],
        'INDUCED' => [3, null, ['name', 'graph'], 'num'], 'CANONIZE' => [2, 2, ['name', 'graph']],
        'DELETE' => [1, 1, ['graph']], 'LIST' => [0, 0, []], 'SHOW' => [1, 1, ['graph']],
        'INVARIANTS' => [1, 1, ['graph']], 'REFINE' => [1, null, ['graph'], 'num'],
        'CANON' => [1, 1, ['graph']], 'ISO' => [2, 2, ['graph', 'graph']],
        'AUT' => [1, 1, ['graph']], 'SUBISO' => [2, 2, ['graph', 'graph']],
        'CLASSIFY' => [1, 1, ['num']]
    ];

    private function validate(string $command, array $args): array
    {
        if (!isset(self::SCHEMAS[$command])) {
            throw new GraphError("unknown command $command");
        }
        $schema = self::SCHEMAS[$command];
        [$minimum, $maximum, $types] = $schema;
        if (count($args) < $minimum || ($maximum !== null && count($args) > $maximum)) {
            throw new GraphError('bad arguments');
        }
        foreach ($args as $i => $word) {
            $type = $types[$i] ?? $schema[3];
            $pattern = match ($type) {
                'num' => '~\A(?:0|[1-9][0-9]{0,2})\z~',
                'edge' => '~\A(?:0|[1-9][0-9]{0,2})-(?:0|[1-9][0-9]{0,2})\z~',
                default => '~\A[a-z][a-z0-9]{0,7}\z~'
            };
            if (!preg_match($pattern, $word)) {
                throw new GraphError('bad arguments');
            }
        }
        foreach ($types as $i => $type) {
            if ($type === 'graph' && !isset($this->graphs[$args[$i]])) {
                throw new GraphError("no graph {$args[$i]}");
            }
        }
        return $schema;
    }

    private function sizeCheck(int $n, int $minimum = 1, int $maximum = 16): void
    {
        if ($n < $minimum) {
            throw new GraphError('bad value');
        }
        if ($n > $maximum) {
            throw new GraphError('too large');
        }
    }

    private function define(string $command, array $args): void
    {
        $name = $args[0];
        $number = (int)($args[1] ?? 0);
        $source = $this->graphs[$args[1] ?? ''] ?? null;
        switch ($command) {
            case 'GRAPH':
                $this->sizeCheck($number);
                $graph = new Graph($number);
                foreach (array_slice($args, 2) as $word) {
                    [$u, $v] = array_map('intval', explode('-', $word));
                    if ($u >= $number || $v >= $number || $u === $v) {
                        throw new GraphError("bad edge $word");
                    }
                    if ($graph->adj[$u][$v]) {
                        throw new GraphError("duplicate edge $word");
                    }
                    $graph->join($u, $v);
                }
                break;
            case 'PATH':
            case 'CYCLE':
            case 'COMPLETE':
            case 'STAR':
            case 'WHEEL':
            case 'CIRCULANT':
                $this->sizeCheck($number, in_array($command, ['CYCLE', 'WHEEL', 'CIRCULANT']) ? 3 : 1,
                    in_array($command, ['STAR', 'WHEEL']) ? 15 : 16);
                $n = $number + (in_array($command, ['STAR', 'WHEEL']) ? 1 : 0);
                $graph = new Graph($n);
                if ($command === 'PATH' || $command === 'CYCLE') {
                    for ($v = 0; $v + 1 < $n; $v++) {
                        $graph->join($v, $v + 1);
                    }
                    if ($command === 'CYCLE') {
                        $graph->join($n - 1, 0);
                    }
                } elseif ($command === 'COMPLETE') {
                    for ($u = 0; $u < $n; $u++) {
                        for ($v = $u + 1; $v < $n; $v++) {
                            $graph->join($u, $v);
                        }
                    }
                } elseif ($command === 'STAR' || $command === 'WHEEL') {
                    for ($v = 1; $v < $n; $v++) {
                        $graph->join(0, $v);
                    }
                    if ($command === 'WHEEL') {
                        for ($v = 1; $v + 1 < $n; $v++) {
                            $graph->join($v, $v + 1);
                        }
                        $graph->join($n - 1, 1);
                    }
                } else {
                    $jumps = array_map('intval', array_slice($args, 2));
                    $previous = 0;
                    foreach ($jumps as $jump) {
                        if ($jump <= $previous || 2 * $jump > $n) {
                            throw new GraphError('bad value');
                        }
                        $previous = $jump;
                    }
                    foreach ($graph->vertices() as $v) {
                        foreach ($jumps as $jump) {
                            $graph->join($v, ($v + $jump) % $n);
                        }
                    }
                }
                break;
            case 'BIPARTITE':
            case 'GRID':
                $a = (int)$args[1];
                $b = (int)$args[2];
                if ($a === 0 || $b === 0) {
                    throw new GraphError('bad value');
                }
                $n = $command === 'GRID' ? $a * $b : $a + $b;
                $this->sizeCheck($n);
                $graph = new Graph($n);
                for ($x = 0; $x < $a; $x++) {
                    for ($y = 0; $y < $b; $y++) {
                        if ($command === 'BIPARTITE') {
                            $graph->join($x, $a + $y);
                        } else {
                            if ($y + 1 < $b) {
                                $graph->join($x * $b + $y, $x * $b + $y + 1);
                            }
                            if ($x + 1 < $a) {
                                $graph->join($x * $b + $y, ($x + 1) * $b + $y);
                            }
                        }
                    }
                }
                break;
            case 'PETERSEN':
                $graph = new Graph(10);
                for ($i = 0; $i < 5; $i++) {
                    $graph->join($i, ($i + 1) % 5);
                    $graph->join($i, $i + 5);
                    $graph->join(5 + $i, 5 + ($i + 2) % 5);
                }
                break;
            case 'HYPERCUBE':
                $this->sizeCheck($number, 1, 4);
                $graph = new Graph(1 << $number);
                foreach ($graph->vertices() as $v) {
                    for ($bit = 0; $bit < $number; $bit++) {
                        $graph->join($v, $v ^ (1 << $bit));
                    }
                }
                break;
            case 'COMPLEMENT':
                $graph = new Graph($source->n);
                for ($u = 0; $u < $source->n; $u++) {
                    for ($v = $u + 1; $v < $source->n; $v++) {
                        if (!$source->adj[$u][$v]) {
                            $graph->join($u, $v);
                        }
                    }
                }
                break;
            case 'LINE':
                $edges = $source->edges();
                if (!$edges) {
                    throw new GraphError('no edges');
                }
                $this->sizeCheck(count($edges));
                $graph = new Graph(count($edges));
                for ($u = 0; $u < count($edges); $u++) {
                    for ($v = $u + 1; $v < count($edges); $v++) {
                        if (array_intersect($edges[$u], $edges[$v])) {
                            $graph->join($u, $v);
                        }
                    }
                }
                break;
            case 'PRODUCT':
            case 'UNION':
                $other = $this->graphs[$args[2]];
                $this->sizeCheck($command === 'PRODUCT' ? $source->n * $other->n : $source->n + $other->n);
                $graph = new Graph($command === 'PRODUCT' ? $source->n * $other->n : $source->n + $other->n);
                if ($command === 'PRODUCT') {
                    foreach ($source->vertices() as $x) {
                        foreach ($other->edges() as [$u, $v]) {
                            $graph->join($x * $other->n + $u, $x * $other->n + $v);
                        }
                    }
                    foreach ($other->vertices() as $y) {
                        foreach ($source->edges() as [$u, $v]) {
                            $graph->join($u * $other->n + $y, $v * $other->n + $y);
                        }
                    }
                } else {
                    foreach ($source->edges() as [$u, $v]) {
                        $graph->join($u, $v);
                    }
                    foreach ($other->edges() as [$u, $v]) {
                        $graph->join($source->n + $u, $source->n + $v);
                    }
                }
                break;
            case 'RELABEL':
            case 'CANONIZE':
                $labels = $command === 'CANONIZE' ? $source->canonical()['labels'] : array_map('intval', array_slice($args, 2));
                $ordered = $labels;
                sort($ordered, SORT_NUMERIC);
                if ($ordered !== $source->vertices()) {
                    throw new GraphError('bad permutation');
                }
                $graph = new Graph($source->n);
                foreach ($source->edges() as [$u, $v]) {
                    $graph->join($labels[$u], $labels[$v]);
                }
                break;
            case 'INDUCED':
                $selected = array_map('intval', array_slice($args, 2));
                if (count(array_unique($selected)) !== count($selected) || max($selected) >= $source->n) {
                    throw new GraphError('bad vertices');
                }
                $graph = new Graph(count($selected));
                for ($u = 0; $u < count($selected); $u++) {
                    for ($v = $u + 1; $v < count($selected); $v++) {
                        if ($source->adj[$selected[$u]][$selected[$v]]) {
                            $graph->join($u, $v);
                        }
                    }
                }
                break;
        }
        $verb = isset($this->graphs[$name]) ? 'redefined' : 'defined';
        $this->graphs[$name] = $graph;
        echo "$verb $name n {$graph->n} m ", count($graph->edges()), "\n";
    }

    private function showInvariants(string $name, Graph $graph): void
    {
        $inv = $graph->invariants();
        echo "invariants $name\n";
        echo 'degrees ', implode(' ', $inv['degrees']), "\n";
        echo 'edges ', count($graph->edges()), " triangles {$inv['triangles']}\n";
        echo "components {$inv['components']} sizes ", implode(' ', $inv['sizes']), "\n";
        echo "girth {$inv['girth']} diameter {$inv['diameter']} radius {$inv['radius']}\n";
        echo "bipartite {$inv['bipartite']}\n";
        if ($graph->n > 12) {
            echo "clique -\nchromatic -\n";
        } else {
            $clique = $graph->clique();
            [$count, $colors] = $graph->coloring();
            echo 'clique ', count($clique), ' ', implode(' ', $clique), "\n";
            echo "chromatic $count ", implode(' ', $colors), "\n";
        }
    }

    private function isomorphism(Graph $a, Graph $b): void
    {
        $av = $a->invariants();
        $bv = $b->invariants();
        $tests = [['vertices', $a->n, $b->n], ['edges', count($a->edges()), count($b->edges())],
            ['degrees', $av['degrees'], $bv['degrees']], ['triangles', $av['triangles'], $bv['triangles']],
            ['components', $av['components'], $bv['components']], ['girth', $av['girth'], $bv['girth']],
            ['diameter', $av['diameter'], $bv['diameter']], ['bipartite', $av['bipartite'], $bv['bipartite']]];
        foreach ($tests as [$kind, $x, $y]) {
            if ($x !== $y) {
                echo "not isomorphic $kind", $kind === 'degrees' ? '' : " $x $y", "\n";
                return;
            }
        }
        $profile = function (Graph $graph): array {
            [$colors, $rounds] = $graph->stable();
            $sizes = array_count_values($colors);
            ksort($sizes, SORT_NUMERIC);
            return [$rounds, array_values($sizes)];
        };
        if ($profile($a) !== $profile($b)) {
            echo "not isomorphic refinement\n";
        } elseif ($a->canonical()['best'] !== $b->canonical()['best']) {
            echo "not isomorphic canonical\n";
        } else {
            $inverse = array_flip($b->canonical()['labels']);
            $mapping = array_map(fn($label) => $inverse[$label], $a->canonical()['labels']);
            echo "isomorphic\nmapping ", implode(' ', $mapping), "\n";
        }
    }

    private function automorphisms(string $name, Graph $graph): void
    {
        $canon = $graph->canonical();
        $inverse = array_flip($canon['labels']);
        $vertexParent = $graph->vertices();
        $edgeParent = [];
        $edgeIndex = [];
        foreach ($graph->edges() as $i => [$u, $v]) {
            $edgeParent[] = $i;
            $edgeIndex["$u-$v"] = $i;
        }
        $find = function (array $parents, int $x): int {
            while ($parents[$x] !== $x) {
                $x = $parents[$x];
            }
            return $x;
        };
        $unite = function (array &$parents, int $x, int $y) use ($find): void {
            $parents[$find($parents, $x)] = $find($parents, $y);
        };
        foreach ($canon['winners'] as $labels) {
            $mapping = array_map(fn($label) => $inverse[$label], $labels);
            foreach ($graph->vertices() as $v) {
                $unite($vertexParent, $v, $mapping[$v]);
            }
            foreach ($graph->edges() as $i => [$u, $v]) {
                $a = min($mapping[$u], $mapping[$v]);
                $b = max($mapping[$u], $mapping[$v]);
                $unite($edgeParent, $i, $edgeIndex["$a-$b"]);
            }
        }
        $vertexOrbits = [];
        foreach ($graph->vertices() as $v) {
            $vertexOrbits[$find($vertexParent, $v)][] = $v;
        }
        $edgeOrbits = [];
        foreach ($graph->edges() as $i => $_) {
            $edgeOrbits[$find($edgeParent, $i)][] = $i;
        }
        usort($vertexOrbits, fn($a, $b) => $a[0] <=> $b[0]);
        usort($edgeOrbits, fn($a, $b) => $a[0] <=> $b[0]);
        echo "aut $name order ", count($canon['winners']), "\nvertex orbits ", count($vertexOrbits), "\n";
        foreach ($vertexOrbits as $orbit) {
            echo 'orbit ', implode(' ', $orbit), "\n";
        }
        echo 'edge orbits ', count($edgeOrbits), "\n";
        foreach ($edgeOrbits as $orbit) {
            echo 'orbit ', implode(' ', array_map(fn($i) => implode('-', $graph->edges()[$i]), $orbit)), "\n";
        }
        echo 'transitive vertex ', count($vertexOrbits) === 1 ? 'yes' : 'no',
            ' edge ', count($edgeOrbits) === 1 ? 'yes' : 'no', "\n";
    }

    private function subiso(string $pn, string $tn, Graph $pattern, Graph $target): void
    {
        $count = 0;
        $inducedCount = 0;
        $examples = [];
        $mapping = [];
        $search = function (int $depth, bool $induced) use (&$search, &$count, &$inducedCount, &$examples, &$mapping, $pattern, $target): void {
            if ($depth === $pattern->n) {
                $count++;
                if ($induced) {
                    $inducedCount++;
                }
                if (count($examples) < 5) {
                    $examples[] = [$mapping, $induced];
                }
                return;
            }
            foreach ($target->vertices() as $v) {
                if (in_array($v, $mapping, true)) {
                    continue;
                }
                $stillInduced = $induced;
                for ($u = 0; $u < $depth; $u++) {
                    if ($pattern->adj[$depth][$u] && !$target->adj[$v][$mapping[$u]]) {
                        continue 2;
                    }
                    if ($pattern->adj[$depth][$u] !== $target->adj[$v][$mapping[$u]]) {
                        $stillInduced = false;
                    }
                }
                $mapping[] = $v;
                $search($depth + 1, $stillInduced);
                array_pop($mapping);
            }
        };
        if ($pattern->n <= $target->n) {
            $search(0, true);
        }
        $order = count($pattern->canonical()['winners']);
        echo "subiso $pn $tn embeddings $count induced $inducedCount\n";
        echo 'copies ', intdiv($count, $order), ' induced ', intdiv($inducedCount, $order), "\n";
        foreach ($examples as [$map, $induced]) {
            echo 'embedding ', implode(' ', $map), $induced ? ' induced' : '', "\n";
        }
    }

    private function classify(int $n): void
    {
        $this->sizeCheck($n, 1, 5);
        if (!isset($this->classes[$n])) {
            $edgePairs = [];
            for ($u = 0; $u < $n; $u++) {
                for ($v = $u + 1; $v < $n; $v++) {
                    $edgePairs[] = [$u, $v];
                }
            }
            $levels = [[str_repeat('0', count($edgePairs))]];
            for ($m = 0; $m < count($edgePairs); $m++) {
                $next = [];
                foreach ($levels[$m] as $string) {
                    foreach ($edgePairs as $extra => $_) {
                        if ($string[$extra] !== '0') {
                            continue;
                        }
                        $graph = new Graph($n);
                        foreach ($edgePairs as $i => [$u, $v]) {
                            if ($string[$i] === '1' || $i === $extra) {
                                $graph->join($u, $v);
                            }
                        }
                        $value = $graph->canonical()['best'];
                        $next['s' . $value] = $value;
                    }
                }
                $levels[] = array_values($next);
            }
            $this->classes[$n] = $levels;
        }
        $levels = $this->classes[$n];
        echo "classify $n total ", array_sum(array_map('count', $levels)), "\n";
        foreach ($levels as $m => $strings) {
            sort($strings, SORT_STRING);
            echo "edges $m count ", count($strings), ' ',
                implode(' ', array_map(fn($s) => $s === '' ? '-' : $s, $strings)), "\n";
        }
    }

    public function execute(string $line): void
    {
        $words = explode(' ', $line);
        $command = array_shift($words);
        $args = $words;
        try {
            $schema = $this->validate($command, $args);
            if (($schema[2][0] ?? null) === 'name') {
                $this->define($command, $args);
                return;
            }
            $name = $args[0] ?? null;
            $graph = $this->graphs[$name ?? ''] ?? null;
            switch ($command) {
                case 'DELETE':
                    unset($this->graphs[$name]);
                    echo "deleted $name\n";
                    break;
                case 'LIST':
                    echo 'graphs ', count($this->graphs), "\n";
                    $names = array_keys($this->graphs);
                    sort($names, SORT_STRING);
                    foreach ($names as $key) {
                        echo "$key n {$this->graphs[$key]->n} m ", count($this->graphs[$key]->edges()), "\n";
                    }
                    break;
                case 'SHOW':
                    echo "graph $name n {$graph->n} m ", count($graph->edges()), "\n";
                    foreach ($graph->vertices() as $v) {
                        $neighbors = $graph->neighbors($v);
                        echo "$v:", $neighbors ? ' ' . implode(' ', $neighbors) : '', "\n";
                    }
                    break;
                case 'INVARIANTS':
                    $this->showInvariants($name, $graph);
                    break;
                case 'REFINE':
                    $selected = array_map('intval', array_slice($args, 1));
                    foreach ($selected as $v) {
                        if ($v >= $graph->n) {
                            throw new GraphError('bad vertices');
                        }
                    }
                    [$colors, $rounds] = $graph->stable();
                    foreach ($selected as $v) {
                        if (count(array_keys($colors, $colors[$v], true)) === 1) {
                            throw new GraphError("singleton $v");
                        }
                        [$colors, $added] = $graph->refine($graph->individualize($colors, $v));
                        $rounds += $added;
                    }
                    echo "refine $name rounds $rounds cells ", count(array_unique($colors)), "\n";
                    for ($c = 0; $c < count(array_unique($colors)); $c++) {
                        echo "$c: ", implode(' ', array_keys($colors, $c, true)), "\n";
                    }
                    break;
                case 'CANON':
                    $result = $graph->canonical();
                    echo "canon $name nodes {$result['nodes']} leaves {$result['leaves']}\n";
                    echo 'labels ', implode(' ', $result['labels']), "\n";
                    echo 'string ', $result['best'] === '' ? '-' : $result['best'], "\n";
                    break;
                case 'ISO':
                    $this->isomorphism($graph, $this->graphs[$args[1]]);
                    break;
                case 'AUT':
                    $this->automorphisms($name, $graph);
                    break;
                case 'SUBISO':
                    $this->subiso($name, $args[1], $graph, $this->graphs[$args[1]]);
                    break;
                case 'CLASSIFY':
                    $this->classify((int)$name);
                    break;
            }
        } catch (GraphError $error) {
            echo 'error: ', $error->getMessage(), "\n";
        }
    }
}

$lab = new GraphLab();
$count = (int)fgets(STDIN);
for ($i = 0; $i < $count; $i++) {
    $lab->execute(rtrim(fgets(STDIN), "\r\n"));
}
