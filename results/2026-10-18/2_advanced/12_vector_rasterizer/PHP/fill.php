<?php
declare(strict_types=1);

function fillPolygons(array $sequences, string $rule, array $clip): array {
    $edges = []; foreach ($sequences as $vertices) { $n = count($vertices); foreach ($vertices as $i => $start) { $end = $vertices[($i+1)%$n]; if ($start[1] !== $end[1]) $edges[] = [$start,$end]; } } $pixels = [];
    for ($y = $clip[1]; $y <= $clip[3]; $y++) { $crossings = []; foreach ($edges as [[$xa,$ya],[$xb,$yb]]) { if ($y < min($ya,$yb) || $y >= max($ya,$yb)) continue; $d = $yb - $ya; $n = 2*$xa*$d + (2*$y+1-2*$ya)*($xb-$xa); $direction = $d > 0 ? 1 : -1; if ($d < 0) { $n = -$n; $d = -$d; } $crossings[] = [floorRatio($n-$d,2*$d)+1,$direction]; } usort($crossings,fn($a,$b) => $a <=> $b); $count = $wind = $i = 0;
        for ($x = $clip[0]; $x <= $clip[2]; $x++) { while ($i < count($crossings) && $crossings[$i][0] <= $x) { $count++; $wind += $crossings[$i++][1]; } if ($rule === 'evenodd' ? $count % 2 !== 0 : $wind !== 0) addPoint($pixels,$x,$y); }
    } return $pixels;
}
function fillShape(array $center, array $points, array $clip): array {
    $extents = []; foreach ($points as [$dx,$dy]) $extents[$dy] = max($extents[$dy] ?? 0,abs($dx)); $pixels = [];
    foreach ($extents as $dy => $extent) { $y = $center[1] + $dy; if ($y < $clip[1] || $y > $clip[3]) continue; for ($x = max($clip[0],$center[0]-$extent); $x <= min($clip[2],$center[0]+$extent); $x++) addPoint($pixels,$x,$y); } return $pixels;
}
function floodFill(Layer $layer, array $seed, array $clip): array {
    $target = $layer->colors[$seed[1]][$seed[0]]; $pixels = []; addPoint($pixels,$seed[0],$seed[1]); $pending = [$seed];
    while ($pending) { [$x,$y] = array_pop($pending); foreach ([[$x+1,$y],[$x-1,$y],[$x,$y+1],[$x,$y-1]] as [$nx,$ny]) { if (isset($pixels[pointKey($nx,$ny)]) || $nx < $clip[0] || $nx > $clip[2] || $ny < $clip[1] || $ny > $clip[3]) continue; if ($layer->colors[$ny][$nx] === $target) { addPoint($pixels,$nx,$ny); $pending[] = [$nx,$ny]; } } } return $pixels;
}
