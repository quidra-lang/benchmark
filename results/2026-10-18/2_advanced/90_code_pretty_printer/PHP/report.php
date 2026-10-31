<?php

function docTree(Doc $d, int $depth = 0): array
{
    if ($d->kind === 'concat') {
        $out = [];
        foreach ($d->items as $child)
            array_push($out, ...docTree($child, $depth));
        return $out;
    }
    $prefix = str_repeat('  ', $depth);
    $line = match ($d->kind) {
        'text' => 'text "' . $d->value . '"',
        'suffix' => 'suffix "' . $d->value . '"',
        'if_break' => 'if_break "' . $d->value . '" "' . $d->flat . '"',
        'group' => 'group ' . $d->mode,
        'nest' => 'nest ' . $d->amount,
        default => $d->kind,
    };
    return [$prefix . $line, ...($d->child === null ? [] : docTree($d->child, $depth + 1))];
}

function diffLines(array $a, array $b): array
{
    $n = count($a);
    $m = count($b);
    $lcs = array_fill(0, $n + 1, array_fill(0, $m + 1, 0));
    for ($i = $n - 1; $i >= 0; --$i)
        for ($j = $m - 1; $j >= 0; --$j)
            $lcs[$i][$j] = $a[$i] === $b[$j]
                ? $lcs[$i + 1][$j + 1] + 1
                : max($lcs[$i + 1][$j], $lcs[$i][$j + 1]);
    $i = $j = $deleted = $inserted = 0;
    $hunks = [];
    $h = null;
    while ($i < $n || $j < $m) {
        if ($i < $n && $j < $m && $a[$i] === $b[$j]) {
            if ($h !== null) {
                $hunks[] = $h;
                $h = null;
            }
            ++$i;
            ++$j;
            continue;
        }
        if ($h === null)
            $h = (object) ['a' => $i, 'b' => $j, 'deletes' => 0, 'inserts' => 0, 'lines' => []];
        if ($j === $m || $i < $n && $lcs[$i + 1][$j] >= $lcs[$i][$j + 1]) {
            ++$h->deletes;
            ++$deleted;
            $h->lines[] = '-' . $a[$i++];
        } else {
            ++$h->inserts;
            ++$inserted;
            $h->lines[] = '+' . $b[$j++];
        }
    }
    if ($h !== null)
        $hunks[] = $h;
    $out = ['hunks=' . count($hunks) . " deleted=$deleted inserted=$inserted"];
    foreach ($hunks as $h) {
        $x = $h->a + ($h->deletes ? 1 : 0);
        $y = $h->b + ($h->inserts ? 1 : 0);
        $out[] = "@@ -$x,{$h->deletes} +$y,{$h->inserts} @@";
        array_push($out, ...$h->lines);
    }
    return $out;
}
