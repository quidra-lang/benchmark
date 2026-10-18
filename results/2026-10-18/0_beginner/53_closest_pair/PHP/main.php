<?php
$points = [[12,-7],[-33,25],[41,18],[-8,-44],[27,39],[-46,-12],[5,14],[36,-29],[-19,47],[-2,3]];
$nearest = [0,0,PHP_INT_MAX];
$farthest = [0,0,-1];
for ($i = 0; $i < count($points)-1; $i++) {
    for ($j = $i+1; $j < count($points); $j++) {
        $dx = $points[$i][0]-$points[$j][0];
        $dy = $points[$i][1]-$points[$j][1];
        $squared = $dx*$dx+$dy*$dy;
        if ($squared < $nearest[2]) $nearest = [$i,$j,$squared];
        if ($squared > $farthest[2]) $farthest = [$i,$j,$squared];
    }
}
foreach (['closest'=>$nearest,'farthest'=>$farthest] as $label => [$i,$j,$squared]) printf("%s: P%d P%d %.4F\n",$label,$i,$j,sqrt($squared));
