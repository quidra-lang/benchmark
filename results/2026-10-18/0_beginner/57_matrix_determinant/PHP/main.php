<?php
function laplace(array $matrix): int {
    $n = count($matrix);
    if ($n === 1) return $matrix[0][0];
    $total = 0;
    for ($j = 0; $j < $n; $j++) {
        $minor = [];
        for ($row = 1; $row < $n; $row++) {
            $values = [];
            for ($column = 0; $column < $n; $column++) if ($column !== $j) $values[] = $matrix[$row][$column];
            $minor[] = $values;
        }
        $term = $matrix[0][$j]*laplace($minor);
        $total += $j%2 === 0 ? $term : -$term;
    }
    return $total;
}
$matrices = [[[2,-3,1],[5,4,-2],[-1,6,3]],[[3,0,-2,5],[1,4,7,-3],[-6,2,1,8],[9,-5,3,2]],[[4,-1,7,0,-3],[2,8,-5,6,1],[-9,3,2,-4,5],[6,0,-7,3,-2],[1,-6,4,9,8]]];
foreach ($matrices as $matrix) printf("det(%dx%d) = %d\n",count($matrix),count($matrix),laplace($matrix));
