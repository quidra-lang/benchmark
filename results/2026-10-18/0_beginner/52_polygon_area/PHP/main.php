<?php
$polygons = [[[0,0],[5,0],[6,4],[1,3]],[[2,1],[0,4],[3,7],[7,6],[8,2]],[[0,0],[8,0],[8,6],[5,6],[4,3],[3,6],[0,6]]];
foreach ($polygons as $number => $vertices) {
    $twiceArea = 0; $perimeter = 0.0;
    foreach ($vertices as $i => [$x,$y]) {
        [$nextX,$nextY] = $vertices[($i+1)%count($vertices)];
        $twiceArea += $x*$nextY-$nextX*$y;
        $dx = $x-$nextX; $dy = $y-$nextY;
        $perimeter += sqrt($dx*$dx+$dy*$dy);
    }
    printf("polygon %d: area=%.1F perimeter=%.3F\n",$number+1,abs($twiceArea)/2,round($perimeter,3,PHP_ROUND_HALF_UP));
}
