<?php
declare(strict_types=1);

function pointKey(int $x, int $y): string { return "$x,$y"; }
function addPoint(array &$set, int $x, int $y): void { $set[pointKey($x, $y)] = [$x, $y]; }
function bresenham(array $start, array $end): array {
    [$x, $y] = $start; [$ex, $ey] = $end; $dx = abs($ex - $x); $dy = -abs($ey - $y); $sx = $x < $ex ? 1 : -1; $sy = $y < $ey ? 1 : -1; $error = $dx + $dy; $points = [];
    while (true) { $points[] = [$x, $y]; if ($x === $ex && $y === $ey) return $points; $doubled = 2 * $error; if ($doubled >= $dy) { $error += $dy; $x += $sx; } if ($doubled <= $dx) { $error += $dx; $y += $sy; } }
}
function expandSquare(int $x, int $y, int $width): array {
    $low = -intdiv($width - 1, 2); $points = []; for ($j = $low; $j < $low + $width; $j++) for ($i = $low; $i < $low + $width; $i++) $points[] = [$x + $i, $y + $j]; return $points;
}
function circlePoints(int $radius): array {
    $points = []; $a = $radius; $b = 0; $error = 1 - $radius;
    while ($a >= $b) { foreach ([[$a,$b],[$b,$a],[-$b,$a],[-$a,$b],[-$a,-$b],[-$b,-$a],[$b,-$a],[$a,-$b]] as [$x,$y]) addPoint($points,$x,$y); $b++; if ($error < 0) $error += 2 * $b + 1; else { $a--; $error += 2 * ($b - $a) + 1; } } return $points;
}
function addQuadrants(array &$points, int $x, int $y): void { foreach ([[$x,$y],[-$x,$y],[$x,-$y],[-$x,-$y]] as [$xx,$yy]) addPoint($points,$xx,$yy); }
function ellipsePoints(int $rx, int $ry): array {
    $rx2 = $rx * $rx; $ry2 = $ry * $ry; $x = 0; $y = $ry; $points = []; addPoint($points,0,$ry); addPoint($points,0,-$ry);
    while ($ry2 * $x < $rx2 * $y) { $d = 4 * $ry2 * ($x + 1) * ($x + 1) + $rx2 * (2 * $y - 1) * (2 * $y - 1) - 4 * $rx2 * $ry2; $x++; if ($d >= 0) $y--; addQuadrants($points,$x,$y); }
    while ($y > 0) { $d = $ry2 * (2 * $x + 1) * (2 * $x + 1) + 4 * $rx2 * ($y - 1) * ($y - 1) - 4 * $rx2 * $ry2; $y--; if ($d <= 0) $x++; addQuadrants($points,$x,$y); } return $points;
}
function bezierPoints(array $controls, int $segments): array {
    $degree = count($controls) - 1; $scale = $degree === 2 ? $segments * $segments : $segments * $segments * $segments; $points = [];
    for ($i = 0; $i <= $segments; $i++) { $r = $segments - $i; $weights = $degree === 2 ? [$r*$r,2*$i*$r,$i*$i] : [$r*$r*$r,3*$i*$r*$r,3*$i*$i*$r,$i*$i*$i]; $x = $y = 0; foreach ($controls as $j => [$cx,$cy]) { $x += $weights[$j] * $cx; $y += $weights[$j] * $cy; } $points[] = [roundRatio($x,$scale),roundRatio($y,$scale)]; } return $points;
}
