<?php

function pairKey(int $a, int $b): string
{
    return min($a, $b) . ':' . max($a, $b);
}

function mutexWithin(array $set, array $mutexes): bool
{
    $items = array_keys($set);
    foreach ($items as $i => $a)
        for ($j = $i + 1; $j < count($items); ++$j)
            if (isset($mutexes[pairKey($a, $items[$j])]))
                return true;
    return false;
}

function graphConflict(object $a, object $b, array $mutexes): bool
{
    if (
        array_intersect_key($a->delete, $b->pre + $b->add)
        || array_intersect_key($b->delete, $a->pre + $a->add)
    )
        return true;
    foreach ($a->pre as $p => $unused)
        foreach ($b->pre as $q => $unused)
            if (isset($mutexes[pairKey($p, $q)]))
                return true;
    return false;
}

final class PlanningGraph
{
    private array
        $facts,
        $factMutexes = [[]],
        $elements = [],
        $elementMutexes = [],
        $achievers = [],
        $memo = [],
        $lines = []
    ;
    private int $searched = 0, $memoHits = 0, $tried = 0;

    public function __construct(
        private array $actions,
        array $initial,
        private array $goal,
        private int $limit,
    ) {
        $this->facts = [$initial];
    }

    private function expand(int $level): void
    {
        $facts = $this->facts[$level];
        $mutexes = $this->factMutexes[$level];
        $elements = [];
        foreach ($this->actions as $a)
            if (subset($a->pre, $facts) && !mutexWithin($a->pre, $mutexes))
                $elements[] = $a;
        $count = count($elements);
        foreach (sortedKeys($facts) as $p)
            $elements[] = (object) [
                'number' => null,
                'pre' => [$p => true],
                'add' => [$p => true],
                'delete' => [],
            ];
        $exclusive = [];
        foreach ($elements as $i => $a)
            for ($j = $i + 1; $j < count($elements); ++$j)
                if (graphConflict($a, $elements[$j], $mutexes))
                    $exclusive[pairKey($i, $j)] = true;
        $this->lines[] =
            "action level $level: actions=$count noops=" . count($facts) . ' mutexes=' . count($exclusive);
        $achievers = [];
        foreach ($elements as $i => $a)
            foreach ($a->add as $p => $unused)
                $achievers[$p][] = $i;
        foreach ($achievers as &$producers)
            usort($producers, fn($a, $b) => ($elements[$a]->number ?? -1) <=> ($elements[$b]->number ?? -1));
        unset($producers);
        $next = array_fill_keys(array_keys($achievers), true);
        $nextMutexes = [];
        $keys = sortedKeys($next);
        foreach ($keys as $i => $p)
            for ($j = $i + 1; $j < count($keys); ++$j) {
                $q = $keys[$j];
                $all = true;
                foreach ($achievers[$p] as $a) {
                    foreach ($achievers[$q] as $b)
                        if ($a === $b || !isset($exclusive[pairKey($a, $b)])) {
                            $all = false;
                            break 2;
                        }
                }
                if ($all)
                    $nextMutexes[pairKey($p, $q)] = true;
            }
        $this->elements[] = $elements;
        $this->elementMutexes[] = $exclusive;
        $this->achievers[] = $achievers;
        $this->facts[] = $next;
        $this->factMutexes[] = $nextMutexes;
    }

    private function extract(int $level, array $goals): ?array
    {
        if ($level === 0)
            return [];
        $key = $level . ':' . implode(',', $goals);
        if (isset($this->memo[$key])) {
            ++$this->memoHits;
            return null;
        }
        ++$this->searched;
        $layers = $this->assign($level, $goals, 0, []);
        if ($layers === null)
            $this->memo[$key] = true;
        return $layers;
    }

    private function assign(int $level, array $goals, int $position, array $chosen): ?array
    {
        $elements = $this->elements[$level - 1];
        while (
            $position < count($goals)
            && array_any($chosen, fn($i) => isset($elements[$i]->add[$goals[$position]]))
        )
            ++$position;
        if ($position === count($goals)) {
            $previous = [];
            foreach ($chosen as $i)
                $previous += $elements[$i]->pre;
            $layers = $this->extract($level - 1, sortedKeys($previous));
            if ($layers === null)
                return null;
            $layer = [];
            foreach ($chosen as $i)
                if ($elements[$i]->number !== null)
                    $layer[] = $elements[$i]->number;
            sort($layer, SORT_NUMERIC);
            $layers[] = $layer;
            return $layers;
        }
        foreach ($this->achievers[$level - 1][$goals[$position]] as $i) {
            if (array_any($chosen, fn($j) => isset($this->elementMutexes[$level - 1][pairKey($i, $j)])))
                continue;
            ++$this->tried;
            $layers = $this->assign($level, $goals, $position + 1, [...$chosen, $i]);
            if ($layers !== null)
                return $layers;
        }
        return null;
    }

    private function finish(string $status, array $layers = []): object
    {
        $plan = [];
        foreach ($layers as $layer)
            array_push($plan, ...$layer);
        return (object) [
            'status' => $status,
            'plan' => $plan,
            'layers' => $layers,
            'lines' => $this->lines,
            'expanded' => $this->searched,
            'generated' => $this->tried,
            'memoHits' => $this->memoHits,
        ];
    }

    public function run(): object
    {
        for ($level = 0; $level <= $this->limit; ++$level) {
            $facts = $this->facts[$level];
            $mutexes = $this->factMutexes[$level];
            $this->lines[] = "fact level $level: facts=" . count($facts) . ' mutexes=' . count($mutexes);
            $possible = subset($this->goal, $facts) && !mutexWithin($this->goal, $mutexes);
            if ($possible) {
                $before = $this->searched;
                $hits = $this->memoHits;
                $layers = $this->extract($level, sortedKeys($this->goal));
                $this->lines[] =
                    "extract level $level: "
                    . ($layers !== null ? 'success' : 'fail')
                    . ' searched='
                    . ($this->searched - $before)
                    . ' memo_hits='
                    . ($this->memoHits - $hits);
                if ($layers !== null)
                    return $this->finish('solved', $layers);
            } elseif (
                $level > 0
                && count($facts) === count($this->facts[$level - 1])
                && count($mutexes) === count($this->factMutexes[$level - 1])
            )
                return $this->finish('unreachable');
            if ($level === $this->limit)
                return $this->finish('level limit');
            $this->expand($level);
        }
        throw new LogicException('Missing graph level');
    }
}
