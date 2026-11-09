<?php
declare(strict_types=1);

namespace TextClassifier;

function vectorLength(array $values): float
{
    $total = 0.0;
    foreach ($values as $value) {
        $total += $value * $value;
    }
    return sqrt($total);
}

final class RocchioPrediction
{
    public array $ranking;
    public int $label;
    public float $score;

    public function __construct(array $similarities)
    {
        $this->ranking = range(0, count($similarities) - 1);
        usort($this->ranking, static fn(int $a, int $b): int => ($similarities[$b] <=> $similarities[$a]) ?: ($a <=> $b));
        $this->label = $this->ranking[0];
        $this->score = $similarities[$this->label];
    }
}

final class Rocchio
{
    public array $idf = [];
    public array $centroids;
    public array $lengths = [];

    public function __construct(array $sequences, array $labels, int $classCount, array $frequencies)
    {
        foreach ($frequencies as $frequency) {
            $this->idf[] = log(count($sequences) / $frequency);
        }
        $this->centroids = array_fill(0, $classCount, array_fill(0, count($frequencies), 0.0));
        $documents = array_fill(0, $classCount, 0);
        foreach ($sequences as $index => $sequence) {
            $label = $labels[$index];
            $documents[$label]++;
            $vector = $this->vector($sequence);
            $length = vectorLength($vector);
            if ($length > 0) {
                foreach ($vector as $term => $value) {
                    $this->centroids[$label][$term] += $value / $length;
                }
            }
        }
        foreach ($this->centroids as $label => $row) {
            foreach ($row as $term => $value) {
                $this->centroids[$label][$term] = $value / $documents[$label];
            }
            $this->lengths[] = vectorLength($this->centroids[$label]);
        }
    }

    public function vector(array $sequence): array
    {
        $frequencies = array_count_values($sequence);
        $vector = [];
        foreach ($this->idf as $term => $idf) {
            $vector[] = ($frequencies[$term] ?? 0) * $idf;
        }
        return $vector;
    }

    public function predict(array $sequence): RocchioPrediction
    {
        $vector = $this->vector($sequence);
        $length = vectorLength($vector);
        $similarities = [];
        foreach ($this->centroids as $label => $centroid) {
            $similarity = 0.0;
            if ($length > 0 && $this->lengths[$label] > 0) {
                $product = 0.0;
                foreach ($vector as $term => $value) {
                    $product += $value * $centroid[$term];
                }
                $similarity = $product / ($length * $this->lengths[$label]);
            }
            $similarities[] = $similarity;
        }
        return new RocchioPrediction($similarities);
    }
}
