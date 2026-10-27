<?php

const SERVICES = ['l1', 'upgrade', 'through', 'cache', 'l2', 'memory'];
const COUNTERS = ['accesses', 'reads', 'writes', 'hits', 'misses', 'fences', 'compulsory', 'capacity', 'conflict',
    'coherence', 'trueSharing', 'falseSharing', 'invalidationsSent', 'invalidationsReceived', 'supplied',
    'backInvalidations', 'latency', 'readLatency', 'writeLatency', 'fenceStall'];

function fraction(int $p, int $q): string
{
    $a = $p;
    $b = $q;
    while ($b !== 0) {
        $remainder = $a % $b;
        $a = $b;
        $b = $remainder;
    }
    return intdiv($p, $a) . '/' . intdiv($q, $a);
}

function decimalNotation(int $p, int $q): string
{
    $value = intdiv(2 * $p * 100 + $q, 2 * $q);
    return intdiv($value, 100) . '.' . str_pad((string)($value % 100), 2, '0', STR_PAD_LEFT);
}

function coreString(array $cores): string
{
    $numbers = array_keys($cores);
    sort($numbers, SORT_NUMERIC);
    return $numbers ? implode('', $numbers) : '-';
}

function rangeCounts(array $labels, array $counts): string
{
    $parts = [];
    foreach ($labels as $index => $label) $parts[] = $label . ':' . $counts[$index];
    return implode(' ', $parts);
}

function newCounters(): array
{
    $result = array_fill_keys(COUNTERS, 0);
    $result['finish'] = 0;
    $result['bus'] = array_fill_keys(BUS_TYPES, 0);
    $result['service'] = array_fill_keys(SERVICES, 0);
    return $result;
}

function totalCounters(array $cores): array
{
    $total = newCounters();
    foreach ($cores as $core) {
        foreach (COUNTERS as $key) $total[$key] += $core[$key];
        foreach (BUS_TYPES as $key) $total['bus'][$key] += $core['bus'][$key];
        foreach (SERVICES as $key) $total['service'][$key] += $core['service'][$key];
        $total['finish'] = max($total['finish'], $core['finish']);
    }
    return $total;
}

function sixLines(string $label, array $c): array
{
    $services = $bus = [];
    foreach (SERVICES as $key) $services[] = $key . ' ' . $c['service'][$key];
    foreach (BUS_TYPES as $key) $bus[] = $key . ' ' . $c['bus'][$key];
    return [
        $label . ' accesses ' . $c['accesses'] . ' reads ' . $c['reads'] . ' writes ' . $c['writes'] .
            ' hits ' . $c['hits'] . ' misses ' . $c['misses'] . ' fences ' . $c['fences'],
        $label . ' misses compulsory ' . $c['compulsory'] . ' capacity ' . $c['capacity'] .
            ' conflict ' . $c['conflict'] . ' coherence ' . $c['coherence'] .
            ' true_sharing ' . $c['trueSharing'] . ' false_sharing ' . $c['falseSharing'],
        $label . ' service ' . implode(' ', $services),
        $label . ' bus ' . implode(' ', $bus),
        $label . ' snoop invalidations_sent ' . $c['invalidationsSent'] . ' invalidations_received ' .
            $c['invalidationsReceived'] . ' supplied ' . $c['supplied'] . ' back_invalidations ' . $c['backInvalidations'],
        $label . ' time latency ' . $c['latency'] . ' amat ' . fraction($c['latency'], $c['accesses']) . ' ' .
            decimalNotation($c['latency'], $c['accesses']) . ' fence_stall ' . $c['fenceStall'] . ' finish ' . $c['finish']
    ];
}
