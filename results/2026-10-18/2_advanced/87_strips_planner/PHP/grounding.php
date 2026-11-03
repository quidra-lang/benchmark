<?php

function subtype(array $parents, string $actual, string $expected): bool
{
    while ($actual !== null) {
        if ($actual === $expected)
            return true;
        $actual = $parents[$actual];
    }
    return false;
}

function notation(array $atom): string
{
    return '(' . implode(' ', [$atom[0], ...$atom[1]]) . ')';
}

function substitute(array $atom, array $binding): array
{
    return [$atom[0], array_map(fn($term) => $binding[$term], $atom[1])];
}

function subset(array $a, array $b): bool
{
    return !array_diff_key($a, $b);
}

function sortedKeys(array $set): array
{
    $keys = array_keys($set);
    sort($keys, SORT_NUMERIC);
    return $keys;
}

function sequenceCompare(array $a, array $b): int
{
    for ($i = 0; $i < min(count($a), count($b)); ++$i)
        if ($a[$i] !== $b[$i])
            return $a[$i] <=> $b[$i];
    return count($a) <=> count($b);
}

function ground(object $d, object $problem): object
{
    $objectsByType = [];
    foreach ($d->typeOrder as $kind)
        $objectsByType[$kind] = array_keys(array_filter($problem->objects, fn($actual) => subtype(
            $d->parents,
            $actual,
            $kind,
        )));
    $initialAtoms = [];
    $atomByKey = [];
    foreach ($problem->initial as $a) {
        $key = notation($a);
        $initialAtoms[$key] = true;
        $atomByKey[$key] = $a;
    }
    $candidates = $statistics = [];
    foreach ($d->actions as $schema) {
        $choices = array_map(fn($p) => $objectsByType[$p[1]], $schema->parameters);
        $assignments = 1;
        foreach ($choices as $choice)
            $assignments *= count($choice);
        $statistics[$schema->name] = [$assignments, 0, 0];
        $enumerate = function (int $i, array $args) use (
            &$enumerate,
            $choices,
            $schema,
            $d,
            $initialAtoms,
            &$candidates,
            &$statistics,
            &$atomByKey,
        ): void {
            if ($i < count($choices)) {
                foreach ($choices[$i] as $object)
                    $enumerate($i + 1, [...$args, $object]);
                return;
            }
            $binding = array_combine(array_column($schema->parameters, 0), $args);
            $pre = $neg = $add = $delete = [];
            foreach ($schema->condition as [$sign, $a]) {
                $bound = substitute($a, $binding);
                $key = notation($bound);
                $atomByKey[$key] = $bound;
                if ($bound[0] === '=')
                    $truth = $bound[1][0] === $bound[1][1];
                elseif (isset($d->static[$bound[0]]))
                    $truth = isset($initialAtoms[$key]);
                else {
                    if ($sign)
                        $pre[$key] = true;
                    else
                        $neg[$key] = true;
                    continue;
                }
                if ($truth !== $sign)
                    return;
            }
            foreach ($schema->effects as [$sign, $a]) {
                $bound = substitute($a, $binding);
                $key = notation($bound);
                $atomByKey[$key] = $bound;
                if ($sign)
                    $add[$key] = true;
                else
                    $delete[$key] = true;
            }
            $delete = array_diff_key($delete, $add);
            $candidates[] = (object) [
                'source' => $schema,
                'arguments' => $args,
                'cost' => $schema->cost,
                'pre' => $pre,
                'neg' => $neg,
                'add' => $add,
                'delete' => $delete,
            ];
            ++$statistics[$schema->name][1];
        };
        $enumerate(0, []);
    }
    $reachable = [];
    foreach ($problem->initial as $a)
        if (isset($d->fluent[$a[0]]))
            $reachable[notation($a)] = true;
    $accepted = [];
    do {
        $changed = false;
        foreach ($candidates as $i => $a)
            if (!isset($accepted[$i]) && subset($a->pre, $reachable)) {
                $accepted[$i] = true;
                $reachable += $a->add;
                ++$statistics[$a->source->name][2];
                $changed = true;
            }
    } while ($changed);
    $predicateOrder = array_flip(array_keys($d->predicates));
    $objectOrder = array_flip(array_keys($problem->objects));
    $factKeys = array_keys($reachable);
    usort($factKeys, function ($a, $b) use ($atomByKey, $predicateOrder, $objectOrder) {
        $x = $atomByKey[$a];
        $y = $atomByKey[$b];
        return (
            $predicateOrder[$x[0]] <=> $predicateOrder[$y[0]] ?: sequenceCompare(
                array_map(fn($n) => $objectOrder[$n], $x[1]),
                array_map(fn($n) => $objectOrder[$n], $y[1]),
            )
        );
    });
    $facts = array_map(fn($key) => $atomByKey[$key], $factKeys);
    $factNumbers = array_flip($factKeys);
    $actions = $actionNumbers = [];
    foreach ($candidates as $i => $candidate)
        if (isset($accepted[$i])) {
            $a = (object) [
                'number' => count($actions),
                'source' => $candidate->source,
                'arguments' => $candidate->arguments,
                'cost' => $candidate->cost,
            ];
            foreach (['pre', 'neg', 'add', 'delete'] as $field) {
                $mapped = [];
                foreach ($candidate->$field as $key => $unused)
                    if (isset($factNumbers[$key]))
                        $mapped[$factNumbers[$key]] = true;
                $a->$field = $mapped;
            }
            $actions[] = $a;
            $actionNumbers[notation([$a->source->name, $a->arguments])] = $a->number;
        }
    $initial = $goal = $unreachable = [];
    $staticCount = 0;
    foreach ($problem->initial as $a) {
        if (isset($d->fluent[$a[0]]))
            $initial[$factNumbers[notation($a)]] = true;
        else
            ++$staticCount;
    }
    foreach ($problem->goals as $a) {
        $key = notation($a);
        if (isset($factNumbers[$key]))
            $goal[$factNumbers[$key]] = true;
        elseif (!isset($d->static[$a[0]]) || !isset($initialAtoms[$key]))
            $unreachable[] = $a;
    }
    return (object) [
        'name' => $problem->name,
        'source' => $problem,
        'objectsByType' => $objectsByType,
        'statistics' => $statistics,
        'candidateCount' => count($candidates),
        'facts' => $facts,
        'actions' => $actions,
        'initial' => $initial,
        'goal' => $goal,
        'unreachable' => $unreachable,
        'staticCount' => $staticCount,
        'actionNumbers' => $actionNumbers,
    ];
}
