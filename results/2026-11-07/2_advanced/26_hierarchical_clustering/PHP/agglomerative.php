<?php

final class Merge
{
    public function __construct(public int $a, public int $b, public float $height, public int $size) {}
}

final class Edge
{
    public function __construct(public int $parent, public int $child, public float $weight) {}
}

function lanceWilliams(string $method, int $a, int $b, int $k): array
{
    return match ($method) {
        'single' => [0.5, 0.5, 0.0, -0.5],
        'complete' => [0.5, 0.5, 0.0, 0.5],
        'average' => [$a / ($a + $b), $b / ($a + $b), 0.0, 0.0],
        'weighted' => [0.5, 0.5, 0.0, 0.0],
        'centroid' => [$a / ($a + $b), $b / ($a + $b), -($a * $b) / (($a + $b) * ($a + $b)), 0.0],
        'median' => [0.5, 0.5, -0.25, 0.0],
        default => [($a + $k) / ($a + $b + $k), ($b + $k) / ($a + $b + $k), -$k / ($a + $b + $k), 0.0],
    };
}

function agglomerate(array $delta, string $method): array
{
    $count = count($delta);
    $capacity = 2 * $count - 1;
    $squared = in_array($method, ['centroid', 'median', 'ward'], true);
    $values = array_fill(0, $capacity, array_fill(0, $capacity, 0.0));
    for ($i = 0; $i < $count; ++$i) {
        for ($j = 0; $j < $count; ++$j) {
            $values[$i][$j] = $squared ? $delta[$i][$j] * $delta[$i][$j] : $delta[$i][$j];
        }
    }
    $sizes = array_fill(0, $capacity, 1);
    $active = range(0, $count - 1);
    $merges = [];
    for ($step = 0; $step < $count - 1; ++$step) {
        [$a, $b] = [$active[0], $active[1]];
        foreach ($active as $position => $first) {
            for ($other = $position + 1; $other < count($active); ++$other) {
                $second = $active[$other];
                if ($values[$first][$second] < $values[$a][$b]) {
                    [$a, $b] = [$first, $second];
                }
            }
        }
        $node = $count + $step;
        $sizes[$node] = $sizes[$a] + $sizes[$b];
        $merges[] = new Merge($a, $b, $squared ? sqrt($values[$a][$b]) : $values[$a][$b], $sizes[$node]);
        foreach ($active as $k) {
            if ($k === $a || $k === $b) {
                continue;
            }
            [$aa, $ab, $beta, $gamma] = lanceWilliams($method, $sizes[$a], $sizes[$b], $sizes[$k]);
            $value = $aa * $values[$a][$k] + $ab * $values[$b][$k] + $beta * $values[$a][$b] + $gamma * abs($values[$a][$k] - $values[$b][$k]);
            $values[$node][$k] = $values[$k][$node] = $value;
        }
        $active = array_values(array_filter($active, fn($k) => $k !== $a && $k !== $b));
        $active[] = $node;
    }
    return $merges;
}

function minimumSpanningTree(array $delta): array
{
    $count = count($delta);
    $inside = array_fill(0, $count, false);
    $inside[0] = true;
    $key = $delta[0];
    $parent = array_fill(0, $count, 0);
    $edges = [];
    for ($step = 0; $step < $count - 1; ++$step) {
        $chosen = -1;
        for ($u = 0; $u < $count; ++$u) {
            if (!$inside[$u] && ($chosen < 0 || $key[$u] < $key[$chosen])) {
                $chosen = $u;
            }
        }
        $inside[$chosen] = true;
        $edges[] = new Edge($parent[$chosen], $chosen, $key[$chosen]);
        for ($u = 0; $u < $count; ++$u) {
            if (!$inside[$u] && $delta[$chosen][$u] < $key[$u]) {
                $key[$u] = $delta[$chosen][$u];
                $parent[$u] = $chosen;
            }
        }
    }
    return $edges;
}
