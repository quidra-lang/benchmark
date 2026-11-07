<?php

require_once __DIR__ . '/dfg.php';

function dependency($counts, $first, $second)
{
    $forward = follows_count($counts, $first, $second); $reverse = follows_count($counts, $second, $first);
    return [$forward - $reverse, $forward + $reverse + 1];
}
function loop_measure($count) { return [$count, $count + 1]; }
function routing_measure($counts, $activity, $first, $second, $split)
{
    $numerator = follows_count($counts, $first, $second) + follows_count($counts, $second, $first);
    $denominator = $split ? follows_count($counts, $activity, $first) + follows_count($counts, $activity, $second) + 1 :
        follows_count($counts, $first, $activity) + follows_count($counts, $second, $activity) + 1;
    return [$numerator, $denominator];
}
function compare_fractions($a, $b) { return ($a[0] * $b[1]) <=> ($b[0] * $a[1]); }
function subtract_fractions($a, $b) { return [$a[0] * $b[1] - $b[0] * $a[1], $a[1] * $b[1]]; }
