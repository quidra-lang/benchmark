<?php
function distance(array $a, array $b, string $metric): float {
    $total = 0.0; $dot = 0.0; $squaresA = 0.0; $squaresB = 0.0;
    foreach ($a as $j => $x) {
        $y = $b[$j]; $difference = $x - $y;
        if ($metric === 'squared_euclidean') $total += $difference * $difference;
        elseif ($metric === 'manhattan') $total += abs($difference);
        elseif ($metric === 'chebyshev') $total = max($total, abs($difference));
        else { $dot += $x * $y; $squaresA += $x * $x; $squaresB += $y * $y; }
    }
    if ($metric !== 'cosine') return $total;
    $normA = sqrt($squaresA); $normB = sqrt($squaresB);
    return $normA == 0 || $normB == 0 ? 1.0 : 1 - $dot / ($normA * $normB);
}
function sortNeighbors(array $neighbors): array {
    usort($neighbors, fn($a, $b) => ($a[0] <=> $b[0]) ?: strcmp($a[1]->id, $b[1]->id)); return $neighbors;
}
final class Prediction {
    public string $label;
    public float $share, $runnerShare, $estimate;
    public ?string $runner;
    public array $neighbors;
    public function __construct(array $nearest, string $weighting, bool $retain = true) {
        $tallies = []; $weightTotal = 0.0; $weighted = 0.0; $targetTotal = 0.0;
        foreach ($nearest as [$gap, $row]) {
            $weight = 1 / ($gap + 0.000000001); $key = $row->label;
            if (!isset($tallies[$key])) $tallies[$key] = ['label' => $key, 'count' => 0, 'distance' => 0.0, 'weight' => 0.0];
            $tallies[$key]['count']++; $tallies[$key]['distance'] += $gap; $tallies[$key]['weight'] += $weight; $weightTotal += $weight;
            $targetTotal += $row->target; $weighted += $weight * $row->target;
        }
        $ranked = array_values($tallies); $field = $weighting === 'uniform' ? 'count' : 'weight';
        usort($ranked, fn($a, $b) => ($b[$field] <=> $a[$field]) ?: (($a['distance'] <=> $b['distance']) ?: strcmp($a['label'], $b['label'])));
        $denominator = $weighting === 'uniform' ? count($nearest) : $weightTotal;
        $this->label = $ranked[0]['label']; $this->share = $ranked[0][$field] / $denominator;
        $this->runner = $ranked[1]['label'] ?? null; $this->runnerShare = isset($ranked[1]) ? $ranked[1][$field] / $denominator : 0.0;
        $this->estimate = $weighting === 'uniform' ? $targetTotal / count($nearest) : $weighted / $weightTotal;
        $this->neighbors = $retain ? $nearest : [];
    }
}
