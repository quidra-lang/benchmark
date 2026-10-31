<?php

function discountedReturn(array $rewards, int $gamma): int
{
    $value = 0;
    for ($step = count($rewards) - 1; $step >= 0; $step--) {
        $value = 10000 * $rewards[$step] + floorDivide($gamma * $value, 100);
    }
    return $value;
}

class FirstVisit
{
    private array $totals;
    private array $counts;

    public function __construct(int $states)
    {
        $this->totals = array_fill(0, $states, array_fill(0, 4, 0));
        $this->counts = array_fill(0, $states, array_fill(0, 4, 0));
    }

    public function update(array &$table, array $steps, int $gamma): void
    {
        $first = [];
        foreach ($steps as $index => $step) {
            $key = $step->state * 4 + $step->action;
            if (!isset($first[$key])) {
                $first[$key] = $index;
            }
        }
        $value = 0;
        for ($index = count($steps) - 1; $index >= 0; $index--) {
            $step = $steps[$index];
            $value = 10000 * $step->reward + floorDivide($gamma * $value, 100);
            if ($first[$step->state * 4 + $step->action] !== $index) {
                continue;
            }
            $this->totals[$step->state][$step->action] += $value;
            $this->counts[$step->state][$step->action]++;
            $table[$step->state][$step->action] = floorDivide($this->totals[$step->state][$step->action], $this->counts[$step->state][$step->action]);
        }
    }
}
