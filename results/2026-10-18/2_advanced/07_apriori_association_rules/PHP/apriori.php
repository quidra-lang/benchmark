<?php
function one_smaller_subsets(array $items): array { $subsets = []; foreach ($items as $i => $_) { $copy = $items; array_splice($copy,$i,1); $subsets[] = $copy; } return $subsets; }
function generate_candidates(array $previous, int $size, ?array $taxonomy): array {
    usort($previous,'compare_sets'); $joined = [];
    foreach ($previous as $i => $first) for ($j = $i + 1; $j < count($previous); $j++) {
        $second = $previous[$j]; if (array_slice($first,0,-1) !== array_slice($second,0,-1)) break; $joined[] = [...$first,$second[count($second) - 1]];
    }
    $known = []; foreach ($previous as $items) $known[set_key($items)] = true; $excluded = $pruned = 0; $survivors = [];
    foreach ($joined as $candidate) {
        if ($taxonomy !== null && $size === 2 && (($taxonomy[$candidate[0]] ?? null) === $candidate[1] || ($taxonomy[$candidate[1]] ?? null) === $candidate[0])) { $excluded++; continue; }
        $reject = false; foreach (one_smaller_subsets($candidate) as $subset) if (!isset($known[set_key($subset)])) { $reject = true; break; }
        if ($reject) $pruned++; else $survivors[] = $candidate;
    }
    return [count($joined),$excluded,$pruned,$survivors];
}
function count_supports(array $baskets, array $candidates): array {
    $counts = $byFirst = [];
    foreach ($candidates as $items) { $key = set_key($items); $counts[$key] = 0; $byFirst[$items[0]][] = $items; }
    foreach ($baskets as $basket) foreach ($basket as $item => $_) foreach ($byFirst[$item] ?? [] as $items) if (contains($basket,$items)) $counts[set_key($items)]++;
    return $counts;
}
