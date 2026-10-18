<?php
$names = str_split('ABCDEFG');
$weights = array_fill(0,7,array_fill(0,7,0));
foreach ([['A','B',7],['A','C',3],['A','D',9],['B','C',2],['C','E',6],['B','D',3],['D','E',4],['D','F',5],['E','F',3],['E','G',8],['F','G',4]] as [$a,$b,$weight]) {
    $i = ord($a)-65; $j = ord($b)-65;
    $weights[$i][$j] = $weights[$j][$i] = $weight;
}
$distance = array_fill(0,7,PHP_INT_MAX); $distance[0] = 0;
$previous = array_fill(0,7,-1); $finalized = array_fill(0,7,false);
for ($step = 0; $step < 7; $step++) {
    $vertex = -1;
    for ($i = 0; $i < 7; $i++) {
        if (!$finalized[$i] && ($vertex < 0 || $distance[$i] < $distance[$vertex])) $vertex = $i;
    }
    $finalized[$vertex] = true;
    for ($neighbor = 0; $neighbor < 7; $neighbor++) {
        $weight = $weights[$vertex][$neighbor];
        if ($weight > 0 && $distance[$vertex]+$weight < $distance[$neighbor]) {
            $distance[$neighbor] = $distance[$vertex]+$weight;
            $previous[$neighbor] = $vertex;
        }
    }
}
foreach ($names as $i => $name) {
    $path = []; $vertex = $i;
    while ($vertex >= 0) {
        array_unshift($path,$names[$vertex]);
        $vertex = $previous[$vertex];
    }
    printf("%s: distance=%d path=%s\n",$name,$distance[$i],implode('-',$path));
}
