<?php

function mergeSets(int $a, int $b): object
{
    $intersection = $a & $b;
    return (object) ['set' => $intersection !== 0 ? $intersection : ($a | $b), 'change' => $intersection !== 0 ? 0 : 1];
}

function provisional(object $tree, object $rooted, array $encoded, int $column): object
{
    $sets = [];
    $changes = 0;
    for ($i = count($rooted->order) - 1; $i >= 0; $i--) {
        $node = $rooted->order[$i];
        if ($node < $tree->count) {
            $sets[$node] = $encoded[$node][$column];
        } else {
            $children = array_values(array_filter($rooted->children[$node], fn($child) => $child !== $rooted->outgroup));
            $result = mergeSets($sets[$children[0]], $sets[$children[1]]);
            $sets[$node] = $result->set;
            $changes += $result->change;
        }
    }
    $changes += mergeSets($sets[$rooted->root], $sets[$rooted->outgroup])->change;
    return (object) compact('sets', 'changes');
}

function parsimonyScore(object $tree, array $encoded, int $outgroup): object
{
    $rooted = rootTree($tree, $outgroup);
    $columns = [];
    $total = 0;
    for ($c = 0; $c < count($encoded[0]); $c++) {
        $changes = provisional($tree, $rooted, $encoded, $c)->changes;
        $columns[] = $changes;
        $total += $changes;
    }
    return (object) compact('total', 'columns');
}

function branches(object $tree, int $outgroup): array
{
    $rooted = rootTree($tree, $outgroup);
    $edges = [];
    foreach ($rooted->order as $node) {
        if ($node === $rooted->root) {
            continue;
        }
        $edges[] = (object) ['u' => $rooted->parent[$node], 'v' => $node,
            'mask' => $node === $outgroup ? $rooted->ingroup : $rooted->masks[$node], 'length' => $rooted->lengths[$node]];
    }
    usort($edges, fn($a, $b) => $a->mask <=> $b->mask);
    return $edges;
}

function insertTaxon(object $tree, object $branch, int $taxon): object
{
    $result = cloneTree($tree);
    $node = $result->next++;
    disconnect($result, $branch->u, $branch->v);
    connect($result, $branch->u, $node);
    connect($result, $node, $branch->v);
    connect($result, $node, $taxon);
    return $result;
}

function nniCandidates(object $tree, int $outgroup): iterable
{
    $rooted = rootTree($tree, $outgroup);
    foreach (branches($tree, $outgroup) as $edge) {
        $u = $edge->u;
        $v = $edge->v;
        if ($u < $tree->count || $v < $tree->count) {
            continue;
        }
        $descendants = $rooted->children[$v];
        usort($descendants, fn($a, $b) => $rooted->masks[$a] <=> $rooted->masks[$b]);
        $side = null;
        foreach ($rooted->children[$u] as $node) {
            if ($node !== $v && $node !== $outgroup) {
                $side = $node;
                break;
            }
        }
        for ($index = 0; $index < 2; $index++) {
            $child = $descendants[$index];
            $result = cloneTree($tree);
            disconnect($result, $u, $side);
            disconnect($result, $v, $child);
            connect($result, $u, $child);
            connect($result, $v, $side);
            yield (object) ['tree' => $result, 'mask' => $edge->mask, 'swap' => $index + 1];
        }
    }
}

function firstBase(int $set): int
{
    foreach ([1, 2, 4, 8] as $bit) {
        if (($set & $bit) !== 0) {
            return $bit;
        }
    }
    return 0;
}

function reconstruct(object $tree, array $encoded, int $outgroup): object
{
    $rooted = rootTree($tree, $outgroup);
    $edges = branches($tree, $outgroup);
    $ancestors = [];
    foreach ($rooted->order as $node) {
        if ($node >= $tree->count) {
            $ancestors[$node] = '';
        }
    }
    $branchChanges = [];
    foreach ($edges as $edge) {
        $branchChanges[$edge->mask] = 0;
    }
    $columns = [];
    $total = 0;
    $bits = [1, 2, 4, 8];
    for ($c = 0; $c < count($encoded[0]); $c++) {
        $result = provisional($tree, $rooted, $encoded, $c);
        $sets = $result->sets;
        $columns[] = $result->changes;
        $total += $result->changes;
        $x0 = firstBase(mergeSets($sets[$rooted->root], $sets[$outgroup])->set);
        $states = [];
        foreach ([$rooted->root, $outgroup] as $node) {
            $states[$node] = ($sets[$node] & $x0) !== 0 ? $x0 : firstBase($sets[$node]);
        }
        foreach ($rooted->order as $node) {
            if ($node === $rooted->root || $node === $outgroup) {
                continue;
            }
            $inherited = $states[$rooted->parent[$node]];
            $states[$node] = ($sets[$node] & $inherited) !== 0 ? $inherited : firstBase($sets[$node]);
        }
        foreach ($ancestors as $node => $sequence) {
            $ancestors[$node] .= LETTERS[array_search($states[$node], $bits, true)];
        }
        foreach ($edges as $edge) {
            if ($states[$edge->u] !== $states[$edge->v]) {
                $branchChanges[$edge->mask]++;
            }
        }
    }
    foreach ($edges as $edge) {
        connect($tree, $edge->u, $edge->v, $branchChanges[$edge->mask] / count($encoded[0]));
    }
    return (object) compact('ancestors', 'branchChanges', 'columns', 'total', 'rooted');
}
