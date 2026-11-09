<?php

function detectCorners(array $gx, array $gy, int $width, int $height, int $window, int $threshold, int $maximum): array
{
    $half = intdiv($window - 1, 2);
    $response = array_fill(0, $width * $height, 0);
    for ($y = 0; $y < $height; $y++) {
        for ($x = 0; $x < $width; $x++) {
            $xx = $yy = $xy = 0;
            for ($j = -$half; $j <= $half; $j++) {
                for ($i = -$half; $i <= $half; $i++) {
                    $dx = clamped($gx, $x + $i, $y + $j, $width, $height);
                    $dy = clamped($gy, $x + $i, $y + $j, $width, $height);
                    $xx += $dx * $dx;
                    $yy += $dy * $dy;
                    $xy += $dx * $dy;
                }
            }
            $response[$y * $width + $x] = $xx * $yy - $xy * $xy - intdiv(($xx + $yy) * ($xx + $yy), 25);
        }
    }
    $candidates = [];
    foreach ($response as $index => $value) {
        if ($value < $threshold) continue;
        $peak = true;
        foreach (neighbors($index, $width, $height) as $next) {
            if ($response[$next] > $value || ($response[$next] === $value && $next < $index)) {
                $peak = false;
                break;
            }
        }
        if ($peak) $candidates[] = ['x' => $index % $width, 'y' => intdiv($index, $width), 'response' => $value];
    }
    usort($candidates, fn($a, $b) => ($b['response'] <=> $a['response']) ?: ($a['y'] <=> $b['y']) ?: ($a['x'] <=> $b['x']));
    $corners = array_slice($candidates, 0, $maximum);
    foreach ($corners as $i => &$corner) $corner['number'] = $i + 1;
    unset($corner);
    return compact('response', 'candidates', 'corners');
}
