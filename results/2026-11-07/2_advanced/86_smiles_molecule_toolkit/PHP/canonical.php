<?php

function sequenceCompare(mixed $a, mixed $b): int
{
    if (!is_array($a))
        return $a <=> $b;
    $n = min(count($a), count($b));
    for ($i = 0; $i < $n; ++$i) {
        $cmp = sequenceCompare($a[$i], $b[$i]);
        if ($cmp)
            return $cmp;
    }
    return count($a) <=> count($b);
}

function denseRanks(array $values): array
{
    $order = array_keys($values);
    usort($order, fn($a, $b) => sequenceCompare($values[$a], $values[$b]));
    $ranks = [];
    $previous = null;
    $rank = 0;
    foreach ($order as $i) {
        if ($previous === null || sequenceCompare($values[$i], $previous) !== 0)
            ++$rank;
        $ranks[$i] = $rank;
        $previous = $values[$i];
    }
    ksort($ranks, SORT_NUMERIC);
    return array_values($ranks);
}

function refine(Molecule $m, array $ranks): array
{
    while (true) {
        $values = [];
        foreach ($m->neighbors as $i => $neighbors) {
            $pairs = [];
            foreach ($neighbors as $j => $b)
                $pairs[] = [$ranks[$j], $b->kind];
            usort($pairs, sequenceCompare(...));
            $values[] = [$ranks[$i], $pairs];
        }
        $new = denseRanks($values);
        if (count(array_unique($new)) === count(array_unique($ranks)))
            return $new;
        $ranks = $new;
    }
}

function canonicalRanks(Molecule $m): array
{
    $values = [];
    foreach ($m->atoms as $i => $a)
        $values[] = [
            $m->degree($i),
            $a->element->number,
            $a->mass,
            $a->charge,
            $a->hydrogens,
            (int) $a->aromatic,
        ];
    $ranks = refine($m, denseRanks($values));
    $classes = count(array_unique($ranks));
    while (count(array_unique($ranks)) !== count($ranks)) {
        $counts = array_count_values($ranks);
        $ties = array_keys(array_filter($counts, fn($n) => $n > 1));
        $first = array_search(min($ties), $ranks, true);
        $values = [];
        foreach ($ranks as $i => $rank)
            $values[] = (2 * $rank) - (int) ($i === $first);
        $ranks = refine($m, denseRanks($values));
    }
    return [$ranks, $classes];
}

function atomNotation(Molecule $m, int $i): string
{
    $a = $m->atoms[$i];
    $symbol = $a->element->symbol;
    $ordinary =
        in_array($symbol, ORGANIC, true)
        && (!$a->aromatic || in_array($symbol, AROMATIC, true))
        && $a->mass === 0
        && $a->charge === 0;
    if ($a->aromatic) {
        $ordinary = $ordinary && needsPi($m, $i) === needsPi($m, $i, 0);
        $symbol = strtolower($symbol);
    }
    $h = organicHydrogens($a, $m->bondTotal($i));
    if ($ordinary && $h !== null && $h === $a->hydrogens)
        return $symbol;
    $text = '[' . ($a->mass ? (string) $a->mass : '') . $symbol;
    if ($a->hydrogens)
        $text .= 'H' . ($a->hydrogens === 1 ? '' : (string) $a->hydrogens);
    if ($a->charge)
        $text .= ($a->charge > 0 ? '+' : '-') . (abs($a->charge) === 1 ? '' : (string) abs($a->charge));
    return $text . ']';
}

function bondSymbol(Molecule $m, Bond $b): string
{
    [$a, $c] = $b->ends;
    $inside = $b->ring && $m->atoms[$a]->aromatic && $m->atoms[$c]->aromatic;
    return match ($b->kind) {
        1 => $inside ? '-' : '',
        2 => '=',
        3 => '#',
        4 => $inside ? '' : ':',
    };
}

function canonicalSmiles(Molecule $m, array $ranks): string
{
    $visits = $closures = [];
    $children = array_fill(0, count($m->atoms), []);
    $visit = function (int $a, ?Bond $incoming) use (
        &$visit,
        &$visits,
        &$children,
        &$closures,
        $m,
        $ranks,
    ): void {
        $visits[$a] = count($visits) + 1;
        $neighbors = array_keys($m->neighbors[$a]);
        usort($neighbors, fn($x, $y) => $ranks[$x] <=> $ranks[$y]);
        foreach ($neighbors as $b) {
            $bond = $m->neighbors[$a][$b];
            if ($bond === $incoming || isset($closures[$bond->key()]))
                continue;
            if (!isset($visits[$b])) {
                $children[$a][] = [$b, $bond];
                $visit($b, $bond);
            } else
                $closures[$bond->key()] = true;
        }
    };
    $root = array_search(1, $ranks, true);
    $visit($root, null);
    $assignments = $occupied = [];
    $write = function (int $a) use (
        &$write,
        &$assignments,
        &$occupied,
        $children,
        $closures,
        $visits,
        $m,
    ): string {
        $text = atomNotation($m, $a);
        $neighbors = array_keys($m->neighbors[$a]);
        usort($neighbors, fn($x, $y) => $visits[$x] <=> $visits[$y]);
        foreach ($neighbors as $b) {
            $bond = $m->neighbors[$a][$b];
            $key = $bond->key();
            if (!isset($closures[$key]))
                continue;
            if (isset($assignments[$key])) {
                $n = $assignments[$key];
                unset($assignments[$key], $occupied[$n]);
                $symbol = '';
            } else {
                $n = 1;
                while (isset($occupied[$n]))
                    ++$n;
                $assignments[$key] = $n;
                $occupied[$n] = true;
                $symbol = bondSymbol($m, $bond);
            }
            $text .= $symbol . ($n < 10 ? (string) $n : sprintf('%%%02d', $n));
        }
        foreach ($children[$a] as $i => [$child, $bond]) {
            $part = bondSymbol($m, $bond) . $write($child);
            $text .= ($i + 1) < count($children[$a]) ? '(' . $part . ')' : $part;
        }
        return $text;
    };
    return $write($root);
}

function canonicalize(Molecule $m): array
{
    [$ranks, $classes] = canonicalRanks($m);
    return [canonicalSmiles($m, $ranks), $classes];
}
