<?php

function points(array $domains): iterable
{
    $indices = array_fill(0, count($domains), 0);
    while (true) {
        $point = [];
        foreach ($domains as $i => $domain) {
            $point[$domain->reference] = $domain->values[$indices[$i]];
        }
        yield $point;
        $position = count($domains) - 1;
        while ($position >= 0) {
            $indices[$position]++;
            if ($indices[$position] < count($domains[$position]->values)) {
                break;
            }
            $indices[$position] = 0;
            $position--;
        }
        if ($position < 0) {
            return;
        }
    }
}

function dayNotation(array $days): string
{
    $ordered = array_keys($days);
    sort($ordered, SORT_NUMERIC);
    $runs = [];
    $first = $last = $ordered[0];
    foreach (array_slice($ordered, 1) as $day) {
        if ($day !== $last + 1) {
            $runs[] = $first . '-' . $last;
            $first = $day;
        }
        $last = $day;
    }
    $runs[] = $first . '-' . $last;
    return implode(',', $runs);
}

function conflictWinner(object $policy, object $first, object $second): object
{
    if ($policy->algorithm === 'first-applicable') {
        return $first;
    }
    $effect = in_array($policy->algorithm, ['deny-overrides', 'permit-unless-deny'], true) ? 'DENY' : 'PERMIT';
    return $first->effect === $effect ? $first : $second;
}

function blocker(object $rule, array $values): ?object
{
    foreach ($rule->parent->children as $earlier) {
        if ($earlier === $rule) {
            break;
        }
        if ($values[$earlier->id] !== 'NOT_APPLICABLE') {
            return $earlier;
        }
    }
    return null;
}
