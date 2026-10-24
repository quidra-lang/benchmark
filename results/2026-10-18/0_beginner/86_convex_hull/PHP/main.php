<?php
function crossProduct(array $o, array $a, array $b): int {
    return ($a[0]-$o[0])*($b[1]-$o[1])-($a[1]-$o[1])*($b[0]-$o[0]);
}
function chain(array $points): array {
    $result = [];
    foreach ($points as $point) {
        while (count($result) >= 2 && crossProduct($result[count($result)-2],$result[count($result)-1],$point) <= 0) array_pop($result);
        $result[] = $point;
    }
    return $result;
}
$points = [[3,2],[-6,1],[8,4],[0,0],[-3,7],[4,-3],[1,-5],[-2,1],[5,6],[-6,-2],[2,-2],[7,-1],[-3,4],[2,8],[-6,3]];
usort($points,fn($a,$b) => ($a[0]<=>$b[0]) ?: ($a[1]<=>$b[1]));
$lower = chain($points);
$upper = chain(array_reverse($points));
array_pop($lower);
array_pop($upper);
$hull = array_merge($lower,$upper);
printf("hull: %d points\n",count($hull));
$twiceArea = 0;
foreach ($hull as $i => [$x,$y]) {
    [$nextX,$nextY] = $hull[($i+1)%count($hull)];
    printf("(%d, %d)\n",$x,$y);
    $twiceArea += $x*$nextY-$nextX*$y;
}
printf("area: %.1F\n",$twiceArea/2);
