<?php
$polygon = [[1,1],[11,2],[13,9],[9,7],[7,12],[5,6],[2,10],[3,5]];
foreach ([[4,8],[6,4],[10,8],[7,11],[14,3],[12,8]] as [$px,$py]) {
    $crossings = 0;
    foreach ($polygon as $i => [$x1,$y1]) {
        [$x2,$y2] = $polygon[($i+1)%count($polygon)];
        if (($y1 > $py) !== ($y2 > $py)) {
            $intersection = $x1+($x2-$x1)*($py-$y1)/($y2-$y1);
            if ($intersection > $px) $crossings++;
        }
    }
    printf("(%d, %d): %s\n",$px,$py,$crossings%2 === 1 ? 'inside' : 'outside');
}
