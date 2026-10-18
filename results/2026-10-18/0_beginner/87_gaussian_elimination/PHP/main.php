<?php
function solveSystem(array $matrix): array {
    $n = count($matrix);
    for ($k = 0; $k < $n; $k++) {
        $pivot = $k;
        for ($i = $k+1; $i < $n; $i++) {
            if (abs($matrix[$i][$k]) > abs($matrix[$pivot][$k])) $pivot = $i;
        }
        [$matrix[$k],$matrix[$pivot]] = [$matrix[$pivot],$matrix[$k]];
        for ($i = $k+1; $i < $n; $i++) {
            $factor = $matrix[$i][$k]/$matrix[$k][$k];
            for ($j = $k; $j <= $n; $j++) $matrix[$i][$j] = $matrix[$i][$j]-$factor*$matrix[$k][$j];
        }
    }
    $solution = array_fill(0,$n,0.0);
    for ($i = $n-1; $i >= 0; $i--) {
        $subtotal = $matrix[$i][$n];
        for ($j = $i+1; $j < $n; $j++) $subtotal -= $matrix[$i][$j]*$solution[$j];
        $solution[$i] = $subtotal/$matrix[$i][$i];
    }
    return $solution;
}
$systems = [[[2.0,-1.0,3.0,7.0],[4.0,1.0,-2.0,3.0],[-3.0,5.0,1.0,-4.0]],[[1.0,3.0,-2.0,4.0,6.0],[5.0,-2.0,1.0,3.0,-7.0],[-2.0,4.0,6.0,-1.0,9.0],[3.0,1.0,-4.0,2.0,5.0]]];
foreach ($systems as $number => $matrix) {
    printf("system %d:\n",$number+1);
    foreach (solveSystem($matrix) as $i => $value) printf("x%d = %.4F\n",$i+1,round($value,4,PHP_ROUND_HALF_UP));
}
