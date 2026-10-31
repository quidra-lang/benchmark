<?php

final class BudgetExceeded extends RuntimeException {}

final class Budget
{
    public int $searches = 0, $expansions = 0;

    public function __construct(
        public ?int $limit = null,
    ) {}

    public function countExpansion(): void
    {
        if (++$this->expansions > ($this->limit ?? PHP_INT_MAX))
            throw new BudgetExceeded();
    }
}

final class Prohibitions
{
    public array $states = [], $moves = [], $permanent = [];

    public function stateAllowed(int $cell, int $time): bool
    {
        return (
            !isset($this->states[$time][$cell])
            && (!isset($this->permanent[$cell]) || $time < $this->permanent[$cell])
        );
    }

    public function actionAllowed(int $source, int $destination, int $time): bool
    {
        return (
            $this->stateAllowed($destination, $time)
            && ($source === $destination || !isset($this->moves[$time][$source . ':' . $destination]))
        );
    }

    public function arrivalAllowed(int $goal): int
    {
        $r = 0;
        foreach ($this->states as $time => $cells)
            if (isset($cells[$goal]))
                $r = max($r, $time + 1);
        return $r;
    }

    public function reserve(array $path, int $start = 0, bool $permanent = false): void
    {
        foreach ($path as $step => $cell) {
            $time = $start + $step;
            $this->states[$time][$cell] = true;
            if ($step && $cell !== $path[$step - 1])
                $this->moves[$time][$cell . ':' . $path[$step - 1]] = [$cell, $path[$step - 1]];
        }
        if ($permanent) {
            $goal = $path[count($path) - 1];
            $time = $start + count($path) - 1;
            $this->permanent[$goal] = min($this->permanent[$goal] ?? $time, $time);
        }
    }
}

function lowSearch(
    Grid $grid,
    array $agent,
    array $distance,
    int $start,
    int $t0,
    Prohibitions $p,
    int $tmax,
    Budget $budget,
    bool $window = false,
): array {
    ++$budget->searches;
    $before = $budget->expansions;
    $arrival = $p->arrivalAllowed($agent['goal']);
    $heap = new SplPriorityQueue();
    $heap->setExtractFlags(SplPriorityQueue::EXTR_DATA);
    $insertion = 0;
    $parents = [$start . ':' . $t0 => null];
    $heap->insert([$start, $t0], [-$distance[$start], 0, 0]);
    while (!$heap->isEmpty()) {
        [$cell, $time] = $heap->extract();
        $budget->countExpansion();
        if ($cell === $agent['goal'] && $time >= $arrival || $window && $time === $tmax) {
            $path = [];
            $state = [$cell, $time];
            while ($state !== null) {
                $path[] = $state[0];
                $state = $parents[$state[0] . ':' . $state[1]];
            }
            return [array_reverse($path), $budget->expansions - $before];
        }
        if ($time === $tmax)
            continue;
        foreach ($grid->adjacent[$cell] as $destination) {
            $next = $time + 1;
            $key = $destination . ':' . $next;
            if (
                !isset($distance[$destination])
                || array_key_exists($key, $parents)
                || !$p->actionAllowed($cell, $destination, $next)
            )
                continue;
            $parents[$key] = [$cell, $time];
            $g = $next - $t0;
            $heap->insert([$destination, $next], [-($g + $distance[$destination]), $g, -++$insertion]);
        }
    }
    return [null, $budget->expansions - $before];
}
