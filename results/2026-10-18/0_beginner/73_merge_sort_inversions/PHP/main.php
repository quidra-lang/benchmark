<?php

function mergeSort(array &$numbers, int $lo, int $hi): int
{
    if ($lo === $hi) {
        return 0;
    }
    $mid = intdiv($lo + $hi, 2);
    $inversions = mergeSort($numbers, $lo, $mid);
    $inversions += mergeSort($numbers, $mid + 1, $hi);
    $left = array_slice($numbers, $lo, $mid - $lo + 1);
    $right = array_slice($numbers, $mid + 1, $hi - $mid);
    $merged = [];
    $i = $j = 0;
    while ($i < count($left) && $j < count($right)) {
        if ($left[$i] <= $right[$j]) {
            $merged[] = $left[$i++];
        } else {
            $merged[] = $right[$j++];
            $inversions += count($left) - $i;
        }
    }
    $merged = array_merge($merged, array_slice($left, $i), array_slice($right, $j));
    array_splice($numbers, $lo, $hi - $lo + 1, $merged);
    printf("merge [%d..%d]: %s\n", $lo, $hi, implode(' ', $merged));
    return $inversions;
}

$numbers = [47, 12, 85, 33, 6, 71, 29, 58, 90, 14];
$inversions = mergeSort($numbers, 0, count($numbers) - 1);
printf("sorted: %s\ninversions: %d\n", implode(' ', $numbers), $inversions);
