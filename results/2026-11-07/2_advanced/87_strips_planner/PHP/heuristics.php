<?php

const HEURISTICS = ['goalcount', 'hmax', 'hadd', 'ff', 'lmcount'];

final class Heuristics
{
    private array $achievers, $cache = [];

    public function __construct(
        private object $problem,
    ) {
        $this->achievers = array_fill(0, count($problem->facts), []);
        foreach ($problem->actions as $a)
            foreach ($a->add as $p => $unused)
                $this->achievers[$p][] = $a->number;
    }

    private function key(array $state): string
    {
        return implode(',', sortedKeys($state));
    }

    public function relaxedCosts(array $state, bool $maximum): array
    {
        $key = ($maximum ? 'max:' : 'add:') . $this->key($state);
        if (isset($this->cache[$key]))
            return $this->cache[$key];
        $costs = array_fill(0, count($this->problem->facts), null);
        foreach ($state as $p => $unused)
            $costs[$p] = 0;
        do {
            $changed = false;
            foreach ($this->problem->actions as $a) {
                $values = [];
                foreach ($a->pre as $p => $unused)
                    $values[] = $costs[$p];
                if (in_array(null, $values, true))
                    continue;
                $value = $a->cost + ($maximum ? ($values ? max($values) : 0) : array_sum($values));
                foreach ($a->add as $p => $unused)
                    if ($costs[$p] === null || $value < $costs[$p]) {
                        $costs[$p] = $value;
                        $changed = true;
                    }
            }
        } while ($changed);
        return $this->cache[$key] = $costs;
    }

    public function relaxedPlan(array $state): ?array
    {
        $key = 'plan:' . $this->key($state);
        if (array_key_exists($key, $this->cache))
            return $this->cache[$key];
        $costs = $this->relaxedCosts($state, false);
        foreach ($this->problem->goal as $p => $unused)
            if ($costs[$p] === null)
                return $this->cache[$key] = null;
        $chosen = [];
        $pending = array_keys(array_diff_key($this->problem->goal, $state));
        while ($pending) {
            $p = array_pop($pending);
            $winner = $lowest = null;
            foreach ($this->achievers[$p] as $n) {
                $a = $this->problem->actions[$n];
                $values = [];
                foreach ($a->pre as $q => $unused)
                    $values[] = $costs[$q];
                if (in_array(null, $values, true))
                    continue;
                $cost = $a->cost + array_sum($values);
                if ($lowest === null || $cost < $lowest) {
                    $lowest = $cost;
                    $winner = $n;
                }
            }
            if (!isset($chosen[$winner])) {
                $chosen[$winner] = true;
                array_push(
                    $pending,
                    ...array_keys(array_diff_key($this->problem->actions[$winner]->pre, $state)),
                );
            }
        }
        return $this->cache[$key] = sortedKeys($chosen);
    }

    public function helpful(array $state): array
    {
        $plan = $this->relaxedPlan($state);
        return (
            $plan === null
                ? []
                : array_values(array_filter($plan, fn($n) => applicable($this->problem->actions[$n], $state)))
        );
    }

    private function levels(array $state): array
    {
        $facts = array_fill(0, count($this->problem->facts), null);
        foreach ($state as $p => $unused)
            $facts[$p] = 0;
        $actions = array_fill(0, count($this->problem->actions), null);
        $level = 0;
        do {
            $changed = false;
            foreach ($this->problem->actions as $a) {
                if ($actions[$a->number] !== null)
                    continue;
                $ready = true;
                foreach ($a->pre as $p => $unused)
                    if ($facts[$p] === null || $facts[$p] > $level) {
                        $ready = false;
                        break;
                    }
                if (!$ready)
                    continue;
                $actions[$a->number] = $level;
                foreach ($a->add as $p => $unused)
                    if ($facts[$p] === null) {
                        $facts[$p] = $level + 1;
                        $changed = true;
                    }
            }
            ++$level;
        } while ($changed);
        return [$facts, $actions];
    }

    private function verified(array $state, int $excluded): bool
    {
        $reachable = $state;
        $omit = array_fill_keys($this->achievers[$excluded], true);
        do {
            $changed = false;
            foreach ($this->problem->actions as $a)
                if (!isset($omit[$a->number]) && subset($a->pre, $reachable)) {
                    $new = array_diff_key($a->add, $reachable);
                    if ($new) {
                        $reachable += $new;
                        $changed = true;
                    }
                }
        } while ($changed);
        return !subset($this->problem->goal, $reachable);
    }

    public function landmarks(array $state): ?array
    {
        $key = 'lm:' . $this->key($state);
        if (array_key_exists($key, $this->cache))
            return $this->cache[$key];
        [$fl, $al] = $this->levels($state);
        foreach ($this->problem->goal as $p => $unused)
            if ($fl[$p] === null)
                return $this->cache[$key] = null;
        $landmarks = array_diff_key($this->problem->goal, $state);
        $pending = sortedKeys($landmarks);
        $verified = [];
        for ($i = 0; $i < count($pending); ++$i) {
            $p = $pending[$i];
            $candidates = null;
            foreach ($this->achievers[$p] as $n)
                if ($al[$n] === ($fl[$p] - 1))
                    $candidates = $candidates === null
                        ? $this->problem->actions[$n]->pre
                        : array_intersect_key($candidates, $this->problem->actions[$n]->pre);
            foreach (sortedKeys(array_diff_key($candidates ?? [], $state, $landmarks)) as $q) {
                if (!array_key_exists($q, $verified))
                    $verified[$q] = $this->verified($state, $q);
                if ($verified[$q]) {
                    $landmarks[$q] = true;
                    $pending[] = $q;
                }
            }
        }
        return $this->cache[$key] = $landmarks;
    }

    public function value(string $name, array $state): ?int
    {
        if ($name === 'none')
            return 0;
        if ($name === 'goalcount')
            return count(array_diff_key($this->problem->goal, $state));
        if ($name === 'hmax' || $name === 'hadd') {
            $costs = $this->relaxedCosts($state, $name === 'hmax');
            $values = [];
            foreach ($this->problem->goal as $p => $unused)
                $values[] = $costs[$p];
            if (in_array(null, $values, true))
                return null;
            return $name === 'hmax' ? ($values ? max($values) : 0) : array_sum($values);
        }
        if ($name === 'ff') {
            $plan = $this->relaxedPlan($state);
            return $plan === null
                ? null
                : array_sum(array_map(fn($n) => $this->problem->actions[$n]->cost, $plan));
        }
        $lm = $this->landmarks($state);
        return $lm === null ? null : count($lm);
    }

    public function values(array $state): array
    {
        $values = [];
        foreach (HEURISTICS as $name)
            $values[$name] = $this->value($name, $state);
        return $values;
    }
}
