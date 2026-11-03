<?php

function choose(array $table, int $state, int $epsilon, Minstd $generator): int
{
    if ($generator->draw() % 1000 < $epsilon) {
        return $generator->draw() % 4;
    }
    return firstMaximum($table[$state]);
}

function nextValue(array $table, int $state, ?int $epsilon = null): int
{
    if ($state < 0) {
        return 0;
    }
    $row = $table[$state];
    $maximum = $row[firstMaximum($row)];
    if ($epsilon === null) {
        return $maximum;
    }
    return floorDivide($epsilon * array_sum($row) + 4 * (1000 - $epsilon) * $maximum, 4000);
}

function target(int $reward, int $next, int $future, int $gamma): int
{
    return 10000 * $reward + ($next < 0 ? 0 : floorDivide($gamma * $future, 100));
}

function update(array &$table, int $state, int $action, int $reward, int $next, int $future, int $gamma, int $alpha): void
{
    $old = $table[$state][$action];
    $table[$state][$action] = $old + floorDivide($alpha * (target($reward, $next, $future, $gamma) - $old), 100);
}

class DynaModel
{
    private array $entries = [];
    private array $pairs = [];

    public function record(int $state, int $action, int $reward, int $next): void
    {
        $key = $state * 4 + $action;
        if (!isset($this->entries[$key])) {
            $this->pairs[] = $key;
        }
        $this->entries[$key] = (object) compact('state', 'action', 'reward', 'next');
    }

    public function plan(array &$table, int $count, int $gamma, int $alpha, Minstd $generator): void
    {
        for ($step = 0; $step < $count; $step++) {
            $key = $this->pairs[$generator->draw() % count($this->pairs)];
            $entry = $this->entries[$key];
            $future = nextValue($table, $entry->next);
            update($table, $entry->state, $entry->action, $entry->reward, $entry->next, $future, $gamma, $alpha);
        }
    }
}
