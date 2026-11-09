<?php

foreach (['graph_io', 'acyclic_layering', 'crossing', 'coordinates', 'canvas'] as $module)
    require_once __DIR__ . "/$module.php";
function reachable(int $start, array $neighbors): array
{
    $found = [$start => true];
    $pending = [$start];
    while ($pending) {
        $v = array_pop($pending);
        foreach ($neighbors[$v] as $w)
            if (!isset($found[$w])) {
                $found[$w] = true;
                $pending[] = $w;
            }
    }
    return $found;
}

final class GraphLayout
{
    public array
        $ids,
        $nodeNumber,
        $labels,
        $edges = [],
        $names,
        $widths,
        $drawn = [],
        $acyclic,
        $vertexLayer,
        $upper,
        $lower,
        $gaps,
        $initialOrder,
        $orders,
        $sweepRecords = [],
        $siftRecords = [],
        $position,
        $crossingsByGap,
        $promotions,
        $trackCounts = [],
        $gapWidths = [],
        $offsets = [],
        $thickness,
        $bands,
        $strongComponents = []
    ;
    public int
        $nodeCount,
        $vertexCount,
        $layerCount,
        $sources,
        $sinks,
        $isolated,
        $components,
        $dummiesBefore,
        $promotionRounds,
        $initialCrossings,
        $finalCrossings,
        $bruteCrossings,
        $mainLength,
        $secondaryLength
    ;
    public ?array $coffmanLabels = null, $path = null;
    public ?int $bestRun = null, $bestSweep = null, $bestCrossings = null;
    public object $coordinates;
    public Canvas $canvas;
    private array $settings;
    private int $randomState;

    public function __construct(
        public object $graph,
    ) {
        $this->settings = $graph->settings;
        $this->ids = array_keys($graph->nodes);
        sort($this->ids, SORT_NUMERIC);
        $this->nodeNumber = array_flip($this->ids);
        $this->labels = array_map(fn($id) => $graph->nodes[$id], $this->ids);
        $this->nodeCount = count($this->ids);
        $this->names = array_map(strval(...), $this->ids);
        $this->widths = array_map(fn($s) => strlen($s) + 2, $this->labels);
        $this->randomState = $this->settings['seed'];
        foreach ($graph->edges as $number => [$from, $to]) {
            $a = $this->nodeNumber[$from];
            $b = $this->nodeNumber[$to];
            $this->edges[] = (object) [
                'number' => $number,
                'source' => $a,
                'target' => $b,
                'upper' => $a,
                'lower' => $b,
                'reversed' => false,
                'transitive' => false,
                'chain' => [],
                'span' => 0,
                'crossings' => 0,
                'route' => [],
                'bends' => 0,
                'length' => 0,
                'upperEndpoint' => null,
                'lowerEndpoint' => null,
            ];
        }
    }

    private function analyzeGraph(): void
    {
        [$upper, $lower] = neighbors($this->nodeCount, array_map(fn($e) => [
            $e->source,
            $e->target,
        ], $this->edges));
        $undirected = array_fill(0, $this->nodeCount, []);
        $this->sources = $this->sinks = $this->isolated = 0;
        for ($v = 0; $v < $this->nodeCount; ++$v) {
            $this->sources += (int) (!$upper[$v] && (bool) $lower[$v]);
            $this->sinks += (int) (!$lower[$v] && (bool) $upper[$v]);
            $this->isolated += (int) (!$upper[$v] && !$lower[$v]);
            $undirected[$v] = array_values(array_unique([...$upper[$v], ...$lower[$v]]));
        }
        $remaining = array_fill(0, $this->nodeCount, true);
        $this->components = 0;
        while ($remaining) {
            $component = reachable(min(array_keys($remaining)), $undirected);
            $remaining = array_diff_key($remaining, $component);
            ++$this->components;
        }
        $closure = [];
        for ($v = 0; $v < $this->nodeCount; ++$v)
            $closure[$v] = reachable($v, $lower);
        $remaining = array_fill(0, $this->nodeCount, true);
        while ($remaining) {
            $first = min(array_keys($remaining));
            $component = [];
            foreach ($remaining as $v => $unused)
                if (isset($closure[$first][$v], $closure[$v][$first]))
                    $component[] = $v;
            foreach ($component as $v)
                unset($remaining[$v]);
            if (count($component) >= 2)
                $this->strongComponents[] = $component;
        }
    }

    private function prepareDAG(): void
    {
        $original = array_map(fn($e) => [$e->source, $e->target], $this->edges);
        $this->acyclic = acyclicOrder($this->nodeCount, $original);
        $position = array_flip($this->acyclic);
        foreach ($this->edges as $e)
            if ($position[$e->source] > $position[$e->target]) {
                $e->reversed = true;
                [$e->upper, $e->lower] = [$e->target, $e->source];
            }
        [, $lower] = neighbors($this->nodeCount, array_map(fn($e) => [$e->upper, $e->lower], $this->edges));
        if ($this->settings['reduce'] === 'on') {
            $closure = [];
            for ($v = 0; $v < $this->nodeCount; ++$v)
                $closure[$v] = reachable($v, $lower);
            foreach ($this->edges as $e)
                if (!$e->reversed)
                    $e->transitive = array_any(
                        $lower[$e->upper],
                        fn($w) => $w !== $e->lower && isset($closure[$w][$e->lower]),
                    );
        }
        $this->drawn = array_values(array_filter($this->edges, fn($e) => !$e->transitive));
    }

    private function assignLayers(): void
    {
        $dag = array_map(fn($e) => [$e->upper, $e->lower], $this->drawn);
        [$heights, $this->coffmanLabels, $this->dummiesBefore, $this->promotionRounds, $this->promotions] =
            assignHeights($this->nodeCount, $dag, $this->settings);
        $highest = max($heights);
        $levels = array_map(fn($h) => $highest - $h, $heights);
        $used = array_fill_keys($levels, true);
        foreach ($this->drawn as $e)
            for ($i = $levels[$e->upper] + 1; $i < $levels[$e->lower]; ++$i)
                $used[$i] = true;
        $keys = array_keys($used);
        sort($keys, SORT_NUMERIC);
        $number = array_flip($keys);
        $this->vertexLayer = array_map(fn($level) => $number[$level], $levels);
        $this->layerCount = count($used);
    }

    private function insertDummies(): void
    {
        foreach ($this->drawn as $e) {
            $first = $this->vertexLayer[$e->upper];
            $last = $this->vertexLayer[$e->lower];
            $e->span = $last - $first;
            $e->chain = [$e->upper];
            for ($i = $first + 1; $i < $last; ++$i) {
                $v = count($this->vertexLayer);
                $this->vertexLayer[] = $i;
                $this->names[] = 'd' . ($v - $this->nodeCount + 1);
                $this->widths[] = 1;
                $e->chain[] = $v;
            }
            $e->chain[] = $e->lower;
        }
        $this->vertexCount = count($this->vertexLayer);
        $this->upper = $this->lower = array_fill(0, $this->vertexCount, []);
        $this->gaps = array_fill(0, $this->layerCount - 1, []);
        foreach ($this->drawn as $e)
            for ($i = 1; $i < count($e->chain); ++$i) {
                $a = $e->chain[$i - 1];
                $b = $e->chain[$i];
                $this->gaps[$this->vertexLayer[$a]][] = [$a, $b, $e->number];
                $this->lower[$a][] = $b;
                $this->upper[$b][] = $a;
            }
    }

    private function makeInitialOrder(): void
    {
        $this->initialOrder = array_fill(0, $this->layerCount, []);
        $visited = [];
        $visit = function (int $v) use (&$visit, &$visited): void {
            if (isset($visited[$v]))
                return;
            $visited[$v] = true;
            $this->initialOrder[$this->vertexLayer[$v]][] = $v;
            foreach ($this->lower[$v] as $w)
                $visit($w);
        };
        for ($v = 0; $v < $this->nodeCount; ++$v)
            $visit($v);
        $this->initialCrossings = totalCrossings($this->gaps, $this->initialOrder);
    }

    private function reorderLayer(array &$orders, int $layer, array $reference): void
    {
        $position = positions($orders);
        $current = $orders[$layer];
        $movable = $keys = $previous = [];
        foreach ($current as $index => $v)
            if ($reference[$v]) {
                $movable[] = $v;
                $previous[$v] = $index;
                $neighbors = array_map(fn($u) => $position[$u], $reference[$v]);
                sort($neighbors, SORT_NUMERIC);
                $n = count($neighbors);
                $keys[$v] = $this->settings['heuristic'] === 'barycenter'
                    ? [array_sum($neighbors), $n]
                    : [$neighbors[intdiv($n - 1, 2)] + $neighbors[intdiv($n, 2)], 1];
            }
        usort(
            $movable,
            fn($a, $b) => (
                ($keys[$a][0] * $keys[$b][1]) <=> ($keys[$b][0] * $keys[$a][1])
                ?: $previous[$a] <=> $previous[$b]
            ),
        );
        $i = 0;
        foreach ($current as $index => $v)
            if ($reference[$v])
                $orders[$layer][$index] = $movable[$i++];
    }

    private function adjacentExchanges(array &$orders): int
    {
        $swaps = 0;
        $position = positions($orders);
        do {
            $changed = false;
            foreach ($orders as &$layer)
                for ($j = 0; $j < (count($layer) - 1); ++$j) {
                    $a = $layer[$j];
                    $b = $layer[$j + 1];
                    if (
                        adjacentCost($a, $b, $this->upper, $this->lower, $position) > adjacentCost(
                            $b,
                            $a,
                            $this->upper,
                            $this->lower,
                            $position,
                        )
                    ) {
                        [$layer[$j], $layer[$j + 1]] = [$b, $a];
                        $position[$a] = $j + 1;
                        $position[$b] = $j;
                        ++$swaps;
                        $changed = true;
                    }
                }
            unset($layer);
        } while ($changed);
        return $swaps;
    }

    private function sweep(array &$orders, int $sweep): array
    {
        $before = positions($orders);
        $down = ($sweep % 2) === 1;
        $reference = $down ? $this->upper : $this->lower;
        if ($down)
            for ($i = 1; $i < $this->layerCount; ++$i)
                $this->reorderLayer($orders, $i, $reference);
        else
            for ($i = $this->layerCount - 2; $i >= 0; --$i)
                $this->reorderLayer($orders, $i, $reference);
        $after = positions($orders);
        $moved = 0;
        for ($v = 0; $v < $this->vertexCount; ++$v)
            $moved += (int) ($before[$v] !== $after[$v]);
        $swaps = $this->adjacentExchanges($orders);
        return [$moved, $swaps, totalCrossings($this->gaps, $orders)];
    }

    private function reduceCrossings(): void
    {
        for ($run = 0; $run <= $this->settings['restarts']; ++$run) {
            $orders = $this->initialOrder;
            if ($run > 0) {
                foreach ($orders as &$layer)
                    for ($j = count($layer) - 1; $j >= 1; --$j) {
                        $this->randomState = (48271 * $this->randomState) % 2147483647;
                        $k = $this->randomState % ($j + 1);
                        [$layer[$j], $layer[$k]] = [$layer[$k], $layer[$j]];
                    }
                unset($layer);
            }
            $count = totalCrossings($this->gaps, $orders);
            $this->sweepRecords[] = [$run, 0, 'initial', 0, 0, $count];
            $history = [$orders];
            $bestOrder = $orders;
            $bestCount = $count;
            $bestSweep = 0;
            $sweep = 1;
            while ($count !== 0 && ($sweep - 1) !== $this->settings['sweeps']) {
                $n = count($history);
                if (($sweep - 1) >= 2 && $history[$n - 1] === $history[$n - 3])
                    break;
                [$moved, $swaps, $count] = $this->sweep($orders, $sweep);
                $this->sweepRecords[] = [$run, $sweep, $sweep % 2 ? 'down' : 'up', $moved, $swaps, $count];
                $history[] = $orders;
                if ($count < $bestCount) {
                    $bestCount = $count;
                    $bestOrder = $orders;
                    $bestSweep = $sweep;
                }
                ++$sweep;
            }
            if ($this->bestCrossings === null || $bestCount < $this->bestCrossings) {
                $this->bestCrossings = $bestCount;
                $this->bestRun = $run;
                $this->bestSweep = $bestSweep;
                $this->orders = $bestOrder;
            }
        }
        if ($this->settings['sifting'] === 'on') {
            $round = 0;
            do {
                ++$round;
                $moves = 0;
                for ($v = 0; $v < $this->vertexCount; ++$v) {
                    $layer = $this->vertexLayer[$v];
                    $original = array_search($v, $this->orders[$layer], true);
                    $remaining = array_values(array_filter($this->orders[$layer], fn($w) => $w !== $v));
                    $costs = [];
                    for ($p = 0; $p <= count($remaining); ++$p) {
                        $this->orders[$layer] = [
                            ...array_slice($remaining, 0, $p),
                            $v,
                            ...array_slice($remaining, $p),
                        ];
                        $costs[] = localCost($this->gaps, $this->orders, $layer);
                    }
                    $minimum = min($costs);
                    $chosen = $costs[$original] === $minimum
                        ? $original
                        : array_search($minimum, $costs, true);
                    $this->orders[$layer] = [
                        ...array_slice($remaining, 0, $chosen),
                        $v,
                        ...array_slice($remaining, $chosen),
                    ];
                    $moves += (int) ($chosen !== $original);
                }
                $this->siftRecords[] = [$round, $moves, totalCrossings($this->gaps, $this->orders)];
            } while ($moves);
        }
    }

    private function finishCrossingCounts(): void
    {
        $this->position = positions($this->orders);
        $this->crossingsByGap = gapCounts($this->gaps, $this->orders);
        $this->finalCrossings = array_sum($this->crossingsByGap);
        $this->bruteCrossings = 0;
        foreach ($this->gaps as $segments) {
            $this->bruteCrossings += bruteForce($segments, $this->position);
            foreach ($segments as $i => $a)
                for ($j = $i + 1; $j < count($segments); ++$j) {
                    $b = $segments[$j];
                    if (
                        (
                            ($this->position[$a[0]] - $this->position[$b[0]])
                            * ($this->position[$a[1]] - $this->position[$b[1]])
                        )
                        < 0
                    ) {
                        ++$this->edges[$a[2]]->crossings;
                        ++$this->edges[$b[2]]->crossings;
                    }
                }
        }
    }

    private function assignTracks(array $segments): array
    {
        $bent = array_values(array_filter(
            $segments,
            fn($s) => $this->coordinates->x[$s[0]] !== $this->coordinates->x[$s[1]],
        ));
        $counts = array_count_values(array_column($bent, 0));
        $buses = [];
        $x = $this->coordinates->x;
        foreach ($bent as $s) {
            [$p, $q] = $s;
            $key = $counts[$p] >= 2 ? 'u:' . $p : 'l:' . $q;
            $buses[$key][] = $s;
        }
        $details = [];
        foreach ($buses as $key => $members) {
            [$kind, $v] = explode(':', $key);
            $values = [];
            foreach ($members as [$p, $q]) {
                $values[] = $x[$p];
                $values[] = $x[$q];
            }
            $details[] = [min($values), max($values), $kind === 'u' ? 0 : 1, $x[(int) $v], $members];
        }
        usort($details, fn($a, $b) => array_slice($a, 0, 4) <=> array_slice($b, 0, 4));
        $ends = $tracks = [];
        foreach ($details as [$lo, $hi, $kind, $coordinate, $members]) {
            $chosen = count($ends);
            foreach ($ends as $i => $end)
                if (($end + 1) < $lo) {
                    $chosen = $i;
                    break;
                }
            $ends[$chosen] = $hi;
            foreach ($members as [$p, $q])
                $tracks[$p . ':' . $q] = $chosen + 1;
        }
        $total = count($ends);
        $gap = max($this->settings['layer_gap'], $total + 2);
        $offsets = [];
        foreach ($tracks as $key => $track)
            $offsets[$key] = $track + intdiv($gap - 2 - $total, 2);
        return [$total, $gap, $offsets];
    }

    private function routeGeometry(): void
    {
        foreach ($this->gaps as $segments) {
            [$tracks, $gap, $offsets] = $this->assignTracks($segments);
            $this->trackCounts[] = $tracks;
            $this->gapWidths[] = $gap;
            $this->offsets += $offsets;
        }
        $vertical = in_array($this->settings['direction'], ['TB', 'BT'], true);
        $this->thickness = [];
        foreach ($this->orders as $layer)
            $this->thickness[] = $vertical ? 1 : max(array_map(fn($v) => $this->widths[$v], $layer));
        $this->bands = [0];
        for ($i = 0; $i < ($this->layerCount - 1); ++$i)
            $this->bands[] = $this->bands[$i] + $this->thickness[$i] + $this->gapWidths[$i];
        $last = $this->layerCount - 1;
        $this->mainLength = $this->bands[$last] + $this->thickness[$last];
        $high = 0;
        foreach ($this->coordinates->x as $v => $x)
            $high = max($high, $x + $this->coordinates->right[$v]);
        $this->secondaryLength = $high + 1;
        $this->canvas = new Canvas($this->settings['direction'], $this->mainLength, $this->secondaryLength);
        foreach ($this->drawn as $e) {
            $size = $vertical ? 1 : $this->widths[$e->upper];
            $e->upperEndpoint = [
                $this->bands[$this->vertexLayer[$e->upper]] + $size,
                $this->coordinates->x[$e->upper],
            ];
            $e->lowerEndpoint = [
                $this->bands[$this->vertexLayer[$e->lower]] - 1,
                $this->coordinates->x[$e->lower],
            ];
        }
    }

    private function drawLinesAndRoutes(): void
    {
        $x = $this->coordinates->x;
        $vertical = $this->canvas->vertical;
        for ($v = 0; $v < $this->vertexCount; ++$v) {
            $layer = $this->vertexLayer[$v];
            $start = $this->bands[$layer];
            $end = $start + $this->thickness[$layer] - 1;
            if ($v >= $this->nodeCount)
                $this->canvas->mainLine($start, $end, $x[$v]);
            elseif (!$vertical && $this->lower[$v])
                $this->canvas->mainLine($start + $this->widths[$v], $end, $x[$v]);
        }
        foreach ($this->gaps as $layer => $segments)
            foreach ($segments as [$a, $b])
                $this->canvas->segment(
                    $this->bands[$layer] + $this->thickness[$layer],
                    $this->gapWidths[$layer],
                    $x[$a],
                    $x[$b],
                    $this->offsets[$a . ':' . $b] ?? null,
                );
        foreach ($this->drawn as $e) {
            $this->canvas->arrow($e->reversed ? $e->upperEndpoint : $e->lowerEndpoint, $e->reversed);
            $points = [$e->upperEndpoint];
            $bent = 0;
            for ($j = 1; $j < count($e->chain); ++$j) {
                $a = $e->chain[$j - 1];
                $b = $e->chain[$j];
                if ($x[$a] === $x[$b])
                    continue;
                $layer = $this->vertexLayer[$a];
                $main = $this->bands[$layer] + $this->thickness[$layer] + $this->offsets[$a . ':' . $b];
                $points[] = [$main, $x[$a]];
                $points[] = [$main, $x[$b]];
                ++$bent;
            }
            $points[] = $e->lowerEndpoint;
            $e->route = array_map(fn($p) => $this->canvas->cell(...$p), $points);
            if ($e->reversed)
                $e->route = array_reverse($e->route);
            $e->bends = 2 * $bent;
            $e->length = 1;
            for ($i = 1; $i < count($e->route); ++$i)
                $e->length +=
                    abs($e->route[$i][0] - $e->route[$i - 1][0])
                    + abs($e->route[$i][1] - $e->route[$i - 1][1]);
        }
    }

    private function findPathAndBoxes(): void
    {
        if ($this->graph->path !== null) {
            [$source, $target] = array_map(fn($id) => $this->nodeNumber[$id], $this->graph->path);
            $following = array_fill(0, $this->nodeCount, []);
            foreach ($this->drawn as $e)
                $following[$e->source][] = $e->target;
            $parent = [$source => null];
            $pending = [$source];
            for ($i = 0; $i < count($pending); ++$i) {
                $v = $pending[$i];
                sort($following[$v], SORT_NUMERIC);
                foreach ($following[$v] as $w)
                    if (!array_key_exists($w, $parent)) {
                        $parent[$w] = $v;
                        $pending[] = $w;
                    }
            }
            if (array_key_exists($target, $parent)) {
                $reverse = [];
                $v = $target;
                while ($v !== null) {
                    $reverse[] = $v;
                    $v = $parent[$v];
                }
                $this->path = array_reverse($reverse);
                $byEnds = [];
                foreach ($this->drawn as $e)
                    $byEnds[$e->source . ':' . $e->target] = $e;
                for ($i = 1; $i < count($this->path); ++$i)
                    $this->canvas->highlightRoute($byEnds[$this->path[$i - 1]
                        . ':'
                        . $this->path[$i]]->route);
            }
        }
        $onPath = array_fill_keys($this->path ?? [], true);
        for ($v = 0; $v < $this->nodeCount; ++$v)
            $this->canvas->box(
                $this->labels[$v],
                $this->bands[$this->vertexLayer[$v]],
                $this->coordinates->x[$v],
                $this->coordinates->left[$v],
                isset($onPath[$v]),
            );
    }

    public function process(): void
    {
        $this->analyzeGraph();
        $this->prepareDAG();
        $this->assignLayers();
        $this->insertDummies();
        $this->makeInitialOrder();
        $this->reduceCrossings();
        $this->finishCrossingCounts();
        $this->coordinates = assignCoordinates(
            $this->orders,
            $this->upper,
            $this->lower,
            $this->widths,
            $this->nodeCount,
            $this->settings,
        );
        $this->routeGeometry();
        $this->drawLinesAndRoutes();
        $this->findPathAndBoxes();
    }

    private function displaySequence(array $vertices): string
    {
        return implode(' ', array_map(fn($v) => $this->names[$v], $vertices));
    }

    private function edgeName(object $e): string
    {
        return $this->ids[$e->source] . '->' . $this->ids[$e->target];
    }

    private function edgeSetLine(string $name, array $edges): string
    {
        $names = array_map($this->edgeName(...), $edges);
        return $name . ' ' . count($edges) . ($names ? ' ' . implode(' ', $names) : '');
    }

    public function layoutLines(): array
    {
        $lines = ['graph ' . $this->graph->name];
        $parts = [];
        foreach (DEFAULTS as $name => $unused)
            $parts[] = $name . '=' . $this->settings[$name];
        $lines[] = 'settings ' . implode(' ', $parts);
        $lines[] = 'acyclic ' . $this->displaySequence($this->acyclic);
        if ($this->coffmanLabels !== null) {
            $parts = [];
            foreach ($this->coffmanLabels as $v => $label)
                $parts[] = $this->names[$v] . ':' . $label;
            $lines[] = 'labels ' . implode(' ', $parts);
        }
        foreach ($this->promotions as [$round, $v, $difference])
            $lines[] = "promote $round {$this->names[$v]} $difference";
        foreach ($this->sweepRecords as [$run, $sweep, $direction, $moved, $swaps, $count])
            $lines[] =
                "sweep $run $sweep $direction"
                . ($sweep ? " moved $moved swaps $swaps" : '')
                . " crossings $count";
        $lines[] = "best run {$this->bestRun} sweep {$this->bestSweep} crossings {$this->bestCrossings}";
        foreach ($this->siftRecords as [$round, $moves, $count])
            $lines[] = "sift $round moves $moves crossings $count";
        $c = $this->coordinates;
        foreach ($this->orders as $layer => $vertices) {
            $first = $this->bands[$layer];
            $last = $first + $this->thickness[$layer] - 1;
            if (in_array($this->settings['direction'], ['BT', 'RL'], true))
                [$first, $last] = [$this->mainLength - 1 - $last, $this->mainLength - 1 - $first];
            $lo = PHP_INT_MAX;
            $hi = PHP_INT_MIN;
            $parts = [];
            foreach ($vertices as $v) {
                $lo = min($lo, $c->x[$v] - $c->left[$v]);
                $hi = max($hi, $c->x[$v] + $c->right[$v]);
                $parts[] = $this->names[$v] . '@' . $c->x[$v];
            }
            $lines[] = "layer $layer band $first $last extent $lo $hi : " . implode(' ', $parts);
        }
        foreach ($this->gaps as $i => $segments)
            $lines[] =
                "between $i "
                . ($i + 1)
                . ' segments '
                . count($segments)
                . " crossings {$this->crossingsByGap[$i]} tracks {$this->trackCounts[$i]} gap {$this->gapWidths[$i]}";
        $parts = [];
        foreach (VARIANTS as $variant)
            $parts[] = $variant . '=' . $c->blocks[$variant] . '/' . $c->widths[$variant];
        $lines[] =
            'bk conflicts ' . count($c->conflicts) . ' ' . implode(' ', $parts) . ' smallest ' . $c->smallest;
        foreach ($this->orders as $vertices)
            foreach ($vertices as $v) {
                $parts = [];
                foreach (VARIANTS as $variant)
                    $parts[] = $variant . ' ' . $c->aligned[$variant][$v];
                $lines[] =
                    "vertex {$this->names[$v]} layer {$this->vertexLayer[$v]} pos {$this->position[$v]} "
                    . implode(' ', $parts)
                    . ' x '
                    . $c->x[$v];
            }
        foreach ($this->edges as $e) {
            $line = "edge {$this->ids[$e->source]} {$this->ids[$e->target]}";
            if ($e->transitive) {
                $lines[] = $line . ' transitive';
                continue;
            }
            if ($e->reversed)
                $line .= ' reversed';
            $chain = $e->reversed ? array_reverse($e->chain) : $e->chain;
            $path = implode(' ', array_map(fn($v) => $c->x[$v], $chain));
            $route = implode(' ', array_map(fn($p) => $p[0] . ',' . $p[1], $e->route));
            $lines[] =
                $line
                . " span {$e->span} crossings {$e->crossings} bends {$e->bends} path $path route $route";
        }
        $lines[] = 'end';
        return $lines;
    }

    public function statsLines(): array
    {
        $n = $this->nodeCount;
        $m = count($this->edges);
        $g = $this->graph;
        $lines = [
            "graph {$g->name}",
            "nodes $n edges $m self_loops {$g->selfLoops} duplicates {$g->duplicates}",
            "sources {$this->sources} sinks {$this->sinks} isolated {$this->isolated} components {$this->components}",
        ];
        foreach ($this->strongComponents as $component)
            $lines[] = 'scc ' . $this->displaySequence($component);
        $lines[] = $this->edgeSetLine(
            'reversed',
            array_values(array_filter($this->edges, fn($e) => $e->reversed)),
        );
        $lines[] = $this->edgeSetLine(
            'transitive',
            array_values(array_filter($this->edges, fn($e) => $e->transitive)),
        );
        $maxNodes = max(array_map(fn($layer) => count(array_filter(
            $layer,
            fn($v) => $v < $n,
        )), $this->orders));
        $maxVertices = max(array_map(count(...), $this->orders));
        $lines[] = "layers {$this->layerCount} max_nodes $maxNodes max_vertices $maxVertices";
        $lines[] = $this->settings['promotion'] === 'on'
            ? "promotion rounds {$this->promotionRounds} accepted "
            . count($this->promotions)
            . " dummies_before {$this->dummiesBefore}"
            : 'promotion off';
        $spans = [];
        $spanTotal = 0;
        $longEdges = [];
        foreach ($this->drawn as $e) {
            $spans[$e->span] = ($spans[$e->span] ?? 0) + 1;
            $spanTotal += $e->span;
            if ($e->span >= 2)
                $longEdges[] = $e;
        }
        $spanMax = $spans ? max(array_keys($spans)) : 0;
        $lines[] = 'dummies ' . ($this->vertexCount - $n) . " span_total $spanTotal span_max $spanMax";
        ksort($spans, SORT_NUMERIC);
        $parts = [];
        foreach ($spans as $span => $count)
            $parts[] = "$span:$count";
        $lines[] = 'spans ' . ($parts ? implode(' ', $parts) : 'none');
        $x = $this->coordinates->x;
        $vertical = count(array_filter(
            $longEdges,
            fn($e) => count(array_unique(array_map(fn($v) => $x[$v], array_slice($e->chain, 1, -1)))) === 1,
        ));
        $lines[] = 'long_edges ' . count($longEdges) . " vertical $vertical";
        $lines[] = "crossings initial {$this->initialCrossings} swept {$this->bestCrossings} best_run {$this->bestRun} best_sweep {$this->bestSweep} final {$this->finalCrossings} brute {$this->bruteCrossings}";
        $segments = $straight = $offset = 0;
        foreach ($this->gaps as $gap)
            foreach ($gap as [$a, $b]) {
                ++$segments;
                $straight += (int) ($x[$a] === $x[$b]);
                $offset += abs($x[$a] - $x[$b]);
            }
        $lines[] =
            "segments $segments straight $straight bent " . ($segments - $straight) . " offset $offset";
        $length = $bends = 0;
        $longest = null;
        foreach ($this->drawn as $e) {
            $length += $e->length;
            $bends += $e->bends;
            if ($longest === null || $e->length > $longest->length)
                $longest = $e;
        }
        $lines[] =
            "routes length $length bends $bends"
            . ($longest !== null ? ' longest ' . $this->edgeName($longest) . ' ' . $longest->length : '');
        $lines[] =
            "canvas width {$this->canvas->columns} height {$this->canvas->rows} crossing_cells "
            . $this->canvas->crossingCells();
        if ($g->path !== null) {
            [$from, $to] = $g->path;
            $lines[] =
                "path $from $to"
                . (
                    $this->path === null
                        ? ' none'
                        : ' hops ' . (count($this->path) - 1) . ' : ' . $this->displaySequence($this->path)
                );
        }
        $lines[] = 'end';
        return $lines;
    }
}

function main(): void
{
    $graphs = readGraphs();
    $layouts = $statistics = $drawings = [];
    $crossings = ['graph,run,sweep,crossings'];
    $totals = array_fill_keys([
        'graphs',
        'laid_out',
        'errors',
        'nodes',
        'edges',
        'dummies',
        'crossings_initial',
        'crossings_final',
    ], 0);
    foreach ($graphs as $g) {
        ++$totals['graphs'];
        if ($g->error !== null) {
            [$kind, $number] = $g->error;
            $error = ["graph {$g->name}", "error $kind line $number", 'end'];
            array_push($layouts, ...$error);
            array_push($statistics, ...$error);
            $drawings[] = ["graph {$g->name} error $kind"];
            ++$totals['errors'];
            continue;
        }
        $layout = new GraphLayout($g);
        $layout->process();
        array_push($layouts, ...$layout->layoutLines());
        array_push($statistics, ...$layout->statsLines());
        foreach ($layout->sweepRecords as [$run, $sweep, $direction, $moved, $swaps, $count])
            $crossings[] = "{$g->name},$run,$sweep,$count";
        $drawings[] = [
            "graph {$g->name} {$layout->canvas->columns}x{$layout->canvas->rows}",
            ...$layout->canvas->drawingLines(),
        ];
        ++$totals['laid_out'];
        $totals['nodes'] += $layout->nodeCount;
        $totals['edges'] += count($layout->edges);
        $totals['dummies'] += $layout->vertexCount - $layout->nodeCount;
        $totals['crossings_initial'] += $layout->initialCrossings;
        $totals['crossings_final'] += $layout->finalCrossings;
    }
    $parts = [];
    foreach ($totals as $name => $count)
        $parts[] = "$name $count";
    $statistics[] = 'summary ' . implode(' ', $parts);
    if (!is_dir('output'))
        mkdir('output');
    foreach ([
        'layout.txt' => $layouts,
        'stats.txt' => $statistics,
        'crossings.csv' => $crossings,
    ] as $name => $lines)
        file_put_contents('output/' . $name, $lines ? implode("\n", $lines) . "\n" : '');
    $text = implode("\n\n", array_map(fn($lines) => implode("\n", $lines), $drawings));
    file_put_contents('output/drawings.txt', $drawings ? $text . "\n" : '');
}

main();
