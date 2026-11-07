<?php

function mergeSort(array &$numbers, int $lo, int $hi, int &$inversions): void
{
    if ($lo === $hi) {
        return;
    }
    $mid = intdiv($lo + $hi, 2);
    mergeSort($numbers, $lo, $mid, $inversions);
    mergeSort($numbers, $mid + 1, $hi, $inversions);
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
}

$numbers = [47, 12, 85, 33, 6, 71, 29, 58, 90, 14];
$inversions = 0;
mergeSort($numbers, 0, count($numbers) - 1, $inversions);
printf("sorted: %s\ninversions: %d\n", implode(' ', $numbers), $inversions);
