<?php

function breadthFirst(Molecule $m, int $root): array
{
    $parents = [$root => null];
    $queue = [$root];
    for ($j = 0; $j < count($queue); ++$j) {
        $a = $queue[$j];
        $neighbors = array_keys($m->neighbors[$a]);
        sort($neighbors, SORT_NUMERIC);
        foreach ($neighbors as $b)
            if (!array_key_exists($b, $parents)) {
                $parents[$b] = $a;
                $queue[] = $b;
            }
    }
    $paths = [];
    foreach ($parents as $a => $unused) {
        $path = [];
        $current = $a;
        while ($current !== null) {
            $path[] = $current;
            $current = $parents[$current];
        }
        $paths[$a] = $path;
    }
    return [$parents, $paths];
}

function ringEdges(array $ring): array
{
    $edges = [];
    $n = count($ring);
    foreach ($ring as $i => $a)
        $edges[bondKey($ring[($i - 1 + $n) % $n], $a)] = true;
    return $edges;
}

function ringSequence(array $ring): array
{
    $first = array_search(min($ring), $ring, true);
    $forward = [...array_slice($ring, $first), ...array_slice($ring, 0, $first)];
    $backward = [$forward[0], ...array_reverse(array_slice($forward, 1))];
    return sequenceCompare($forward, $backward) < 0 ? $forward : $backward;
}

function findRings(Molecule $m): void
{
    $candidates = $seen = [];
    $bonds = $m->orderedBonds();
    $edgeIds = [];
    foreach ($bonds as $i => $b)
        $edgeIds[$b->key()] = $i;
    foreach ($m->atoms as $root => $unused) {
        [$parents, $paths] = breadthFirst($m, $root);
        foreach ($bonds as $b) {
            [$a, $c] = $b->ends;
            if ($parents[$a] === $c || $parents[$c] === $a)
                continue;
            $shared = array_intersect($paths[$a], $paths[$c]);
            if (count($shared) !== 1 || !in_array($root, $shared, true))
                continue;
            $sequence = [...array_reverse($paths[$a]), ...array_slice($paths[$c], 0, -1)];
            $ids = [];
            foreach (ringEdges($sequence) as $key => $unused)
                $ids[] = $edgeIds[$key];
            sort($ids, SORT_NUMERIC);
            $key = implode(',', $ids);
            if (!isset($seen[$key])) {
                $seen[$key] = true;
                $candidates[] = [
                    'sequence' => $sequence,
                    'edges' => array_fill_keys($ids, true),
                    'order' => count($candidates),
                ];
            }
        }
    }
    usort(
        $candidates,
        fn($a, $b) => count($a['sequence']) <=> count($b['sequence']) ?: $a['order'] <=> $b['order'],
    );
    $basis = $rings = [];
    foreach ($candidates as $c) {
        $reduced = $c['edges'];
        while ($reduced) {
            $pivot = max(array_keys($reduced));
            if (!isset($basis[$pivot])) {
                $basis[$pivot] = $reduced;
                $rings[] = ringSequence($c['sequence']);
                break;
            }
            foreach ($basis[$pivot] as $id => $unused) {
                if (isset($reduced[$id]))
                    unset($reduced[$id]);
                else
                    $reduced[$id] = true;
            }
        }
    }
    usort($rings, fn($a, $b) => count($a) <=> count($b) ?: sequenceCompare($a, $b));
    $m->rings = $rings;
    foreach ($rings as $ring) {
        foreach ($ring as $a)
            $m->ringAtoms[$a] = true;
        foreach (ringEdges($ring) as $key => $unused)
            $m->bonds[$key]->ring = true;
    }
}

function aromaticSystems(Molecule $m, array $needing): array
{
    $remaining = array_fill_keys($needing, true);
    $systems = [];
    while ($remaining) {
        $start = min(array_keys($remaining));
        unset($remaining[$start]);
        $queue = [$start];
        for ($i = 0; $i < count($queue); ++$i) {
            $neighbors = $m->neighbors[$queue[$i]];
            ksort($neighbors, SORT_NUMERIC);
            foreach ($neighbors as $b => $bond)
                if ($bond->kind === 4 && isset($remaining[$b])) {
                    unset($remaining[$b]);
                    $queue[] = $b;
                }
        }
        $systems[] = $queue;
    }
    return $systems;
}

function matchSystem(Molecule $m, array $system): ?array
{
    $unpaired = array_fill_keys($system, true);
    $pairs = [];
    $search = function () use (&$search, &$unpaired, &$pairs, $m): bool {
        if (!$unpaired)
            return true;
        $a = min(array_keys($unpaired));
        unset($unpaired[$a]);
        $neighbors = $m->neighbors[$a];
        ksort($neighbors, SORT_NUMERIC);
        foreach ($neighbors as $b => $bond)
            if (isset($unpaired[$b]) && $bond->kind === 4) {
                unset($unpaired[$b]);
                $pairs[] = $bond->key();
                if ($search())
                    return true;
                array_pop($pairs);
                $unpaired[$b] = true;
            }
        $unpaired[$a] = true;
        return false;
    };
    return $search() ? $pairs : null;
}

function kekulize(Molecule $m, array $needing): void
{
    $selected = [];
    foreach (aromaticSystems($m, $needing) as $system) {
        $pairs = matchSystem($m, $system);
        if ($pairs === null)
            throw new AnalysisError('kekulization failed', $m->atoms[min($system)]->column);
        foreach ($pairs as $key)
            $selected[$key] = true;
    }
    foreach ($m->bonds as $key => $b)
        $b->multiplicity = $b->kind === 4 ? (isset($selected[$key]) ? 2 : 1) : $b->kind;
}
