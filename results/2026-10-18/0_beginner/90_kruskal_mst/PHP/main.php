<?php
$edges = [['A','B',7],['C','A',4],['B','C',9],['B','D',14],['D','C',6],['C','E',3],['E','D',5],['F','D',11],['E','G',16],['G','F',8],['H','F',12],['G','H',2],['H','E',10]];
usort($edges,fn($a,$b) => $a[2]<=>$b[2]);
$parents = array_combine(str_split('ABCDEFGH'),str_split('ABCDEFGH'));
function findRoot(array &$parents, string $vertex): string {
    while ($parents[$vertex] !== $vertex) {
        $parents[$vertex] = $parents[$parents[$vertex]];
        $vertex = $parents[$vertex];
    }
    return $vertex;
}
$accepted = $skipped = $total = 0;
foreach ($edges as [$a,$b,$weight]) {
    $first = findRoot($parents,$a);
    $second = findRoot($parents,$b);
    if ($first === $second) $skipped++;
    else {
        $parents[$second] = $first;
        $accepted++; $total += $weight;
        $endpoints = [$a,$b]; sort($endpoints,SORT_STRING);
        printf("%s-%s %d\n",$endpoints[0],$endpoints[1],$weight);
        if ($accepted === 7) break;
    }
}
printf("total weight: %d\nskipped: %d\n",$total,$skipped);
