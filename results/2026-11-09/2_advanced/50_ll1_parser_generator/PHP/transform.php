<?php

function freshName(object $grammar, string $source): string
{
    $name = $source;
    do $name = substr($name, 0, -1) . "'>";
    while (isset($grammar->rules[$name]));
    return $name;
}

function leadingReachable(object $grammar, string $source, string $target): bool
{
    $queue = [$source];
    $seen = [$source => true];
    for ($head = 0; $head < count($queue); $head++) {
        foreach ($grammar->rules[$queue[$head]] as $right) {
            $symbol = $right[0] ?? null;
            if ($symbol === $target) return true;
            if ($symbol !== null && isNonterminal($symbol) && !isset($seen[$symbol])) {
                $seen[$symbol] = true;
                $queue[] = $symbol;
            }
        }
    }
    return false;
}

function uniqueAlternatives(array $alternatives): array
{
    $seen = [];
    $result = [];
    foreach ($alternatives as $right) {
        $key = json_encode($right);
        if (!isset($seen[$key])) {
            $seen[$key] = true;
            $result[] = $right;
        }
    }
    return $result;
}

function eliminate(object $original): object
{
    $grammar = copyGrammar($original);
    $order = $original->order;
    $log = [];
    foreach ($order as $index => $left) {
        for ($earlier = 0; $earlier < $index; $earlier++) {
            $source = $order[$earlier];
            $hasLeading = false;
            foreach ($grammar->rules[$left] as $right) if (($right[0] ?? null) === $source) {
                $hasLeading = true;
                break;
            }
            if (!$hasLeading || !leadingReachable($grammar, $source, $left)) continue;
            $alternatives = [];
            foreach ($grammar->rules[$left] as $right) {
                if (($right[0] ?? null) === $source) {
                    foreach ($grammar->rules[$source] as $replacement) $alternatives[] = array_merge($replacement, array_slice($right, 1));
                } else $alternatives[] = $right;
            }
            $grammar->rules[$left] = uniqueAlternatives($alternatives);
            $log[] = 'substitute ' . $source . ' into ' . $left;
        }
        $alternatives = $grammar->rules[$left];
        $hadCycle = false;
        foreach ($alternatives as $right) if (count($right) === 1 && $right[0] === $left) {
            $hadCycle = true;
            break;
        }
        if ($hadCycle) {
            $alternatives = array_values(array_filter($alternatives, fn($right) => count($right) !== 1 || $right[0] !== $left));
            $grammar->rules[$left] = $alternatives;
            $log[] = 'remove cycle ' . $left . ' -> ' . $left;
        }
        $recursive = array_values(array_filter($alternatives, fn($right) => ($right[0] ?? null) === $left));
        if (!$recursive) continue;
        $name = freshName($grammar, $left);
        $grammar->rules[$left] = [];
        foreach ($alternatives as $right) if (($right[0] ?? null) !== $left) $grammar->rules[$left][] = array_merge($right, [$name]);
        $grammar->rules[$name] = [];
        foreach ($recursive as $right) $grammar->rules[$name][] = array_merge(array_slice($right, 1), [$name]);
        $grammar->rules[$name][] = [];
        array_splice($grammar->order, array_search($left, $grammar->order, true) + 1, 0, [$name]);
        $log[] = 'eliminate left recursion in ' . $left . ' with ' . $name;
    }
    return (object) compact('grammar', 'log');
}

function factor(object $original): object
{
    $grammar = copyGrammar($original);
    $log = [];
    for ($index = 0; $index < count($grammar->order); $index++) {
        $left = $grammar->order[$index];
        $alternatives = $grammar->rules[$left];
        $used = [];
        $replacement = [];
        $created = [];
        foreach ($alternatives as $right) {
            if (!$right) {
                $replacement[] = $right;
                continue;
            }
            if (isset($used[$right[0]])) continue;
            $used[$right[0]] = true;
            $group = array_values(array_filter($alternatives, fn($other) => ($other[0] ?? null) === $right[0]));
            if (count($group) === 1) {
                $replacement[] = $right;
                continue;
            }
            $length = 0;
            while ($length < count($right)) {
                $matches = true;
                foreach ($group as $other) if (($other[$length] ?? null) !== $right[$length]) {
                    $matches = false;
                    break;
                }
                if (!$matches) break;
                $length++;
            }
            $prefix = array_slice($right, 0, $length);
            $name = freshName($grammar, $left);
            $grammar->rules[$name] = array_map(fn($other) => array_slice($other, $length), $group);
            $replacement[] = array_merge($prefix, [$name]);
            $created[] = $name;
            $log[] = 'left factor ' . $left . ' on ' . notation($prefix) . ' with ' . $name;
        }
        $grammar->rules[$left] = $replacement;
        array_splice($grammar->order, $index + 1, 0, $created);
    }
    return (object) compact('grammar', 'log');
}
