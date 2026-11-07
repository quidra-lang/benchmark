<?php

function rho(array $point, int $theta, array $trig, int $step): int
{
    return floorDiv($point['x'] * $trig['cos'][$theta] + $point['y'] * $trig['sin'][$theta], 16384 * $step);
}

function circlePoints(int $radius): array
{
    $points = [];
    $a = $radius;
    $b = 0;
    $error = 1 - $radius;
    while ($a >= $b) {
        foreach ([[$a, $b], [$b, $a], [-$b, $a], [-$a, $b], [-$a, -$b], [-$b, -$a], [$b, -$a], [$a, -$b]] as [$x, $y]) {
            $points[$x . ',' . $y] = ['x' => $x, 'y' => $y];
        }
        $b++;
        if ($error < 0) $error += 2 * $b + 1;
        else {
            $a--;
            $error += 2 * ($b - $a) + 1;
        }
    }
    return array_values($points);
}

function circleVotes(array $edges, int $width, int $height, int $minimum, int $maximum): array
{
    $pixels = [];
    foreach ($edges as $index => $value) if ($value) $pixels[] = ['x' => $index % $width, 'y' => intdiv($index, $width)];
    $layers = [];
    for ($radius = $minimum; $radius <= $maximum; $radius++) {
        $offsets = circlePoints($radius);
        $counts = array_fill(0, $width * $height, 0);
        foreach ($pixels as $point) {
            foreach ($offsets as $offset) {
                $x = $point['x'] + $offset['x'];
                $y = $point['y'] + $offset['y'];
                if ($x >= 0 && $x < $width && $y >= 0 && $y < $height) $counts[$y * $width + $x]++;
            }
        }
        $layers[] = compact('radius', 'offsets', 'counts');
    }
    return $layers;
}

function circlePeaks(array $layers, int $width, int $height, int $percent): array
{
    $peaks = [];
    $candidates = 0;
    foreach ($layers as $k => $layer) {
        $points = count($layer['offsets']);
        foreach ($layer['counts'] as $index => $votes) {
            if (100 * $votes < $percent * $points) continue;
            $candidates++;
            $x = $index % $width;
            $y = intdiv($index, $width);
            $peak = true;
            for ($other = max(0, $k - 2); $other <= min(count($layers) - 1, $k + 2) && $peak; $other++) {
                $neighbor = $layers[$other];
                $lhs = $votes * count($neighbor['offsets']);
                for ($ny = max(0, $y - 2); $ny <= min($height - 1, $y + 2) && $peak; $ny++) {
                    for ($nx = max(0, $x - 2); $nx <= min($width - 1, $x + 2); $nx++) {
                        $next = $ny * $width + $nx;
                        if ($other === $k && $next === $index) continue;
                        $rhs = $neighbor['counts'][$next] * $points;
                        $earlier = $other < $k || ($other === $k && $next < $index);
                        if ($lhs < $rhs || ($lhs === $rhs && $earlier)) {
                            $peak = false;
                            break;
                        }
                    }
                }
            }
            if ($peak) $peaks[] = ['radius' => $layer['radius'], 'x' => $x, 'y' => $y,
                'votes' => $votes, 'points' => $points, 'offsets' => $layer['offsets']];
        }
    }
    return compact('candidates', 'peaks');
}

function lineVotes(array $pixels, array $trig, int $step): array
{
    $votes = [];
    for ($theta = 0; $theta < 180; $theta++) {
        $counts = [];
        foreach ($pixels as $point) {
            $r = rho($point, $theta, $trig, $step);
            $counts[$r] = ($counts[$r] ?? 0) + 1;
        }
        $votes[] = $counts;
    }
    return $votes;
}

function linePeaks(array $votes, int $threshold): array
{
    $peaks = [];
    for ($theta = 0; $theta < 180; $theta++) {
        foreach ($votes[$theta] as $r => $count) {
            if ($count < $threshold) continue;
            $peak = true;
            for ($t = max(0, $theta - 2); $t <= min(179, $theta + 2) && $peak; $t++) {
                for ($s = $r - 2; $s <= $r + 2; $s++) {
                    if ($t === $theta && $s === $r) continue;
                    $other = $votes[$t][$s] ?? 0;
                    $earlier = $t < $theta || ($t === $theta && $s < $r);
                    if ($count < $other || ($count === $other && $earlier)) {
                        $peak = false;
                        break;
                    }
                }
            }
            if ($peak) $peaks[] = ['theta' => $theta, 'rho' => $r, 'votes' => $count];
        }
    }
    return $peaks;
}
