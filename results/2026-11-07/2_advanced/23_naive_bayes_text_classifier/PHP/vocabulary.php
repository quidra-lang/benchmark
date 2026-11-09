<?php
declare(strict_types=1);

namespace TextClassifier;

function firstOccurrences(array $sequence): array
{
    $seen = $result = [];
    foreach ($sequence as $term) {
        $key = '#' . $term;
        if (!isset($seen[$key])) {
            $seen[$key] = true;
            $result[] = $term;
        }
    }
    return $result;
}

function chiSquare(int $withTerm, int $frequency, int $classSize, int $total): float
{
    $b = $frequency - $withTerm;
    $c = $classSize - $withTerm;
    $e = $total - $classSize - $b;
    $difference = $withTerm * $e - $b * $c;
    $numerator = $total * $difference * $difference;
    $denominator = $frequency * ($total - $frequency) * $classSize * ($total - $classSize);
    return $denominator === 0 ? 0.0 : $numerator / $denominator;
}

final class RankedTerm
{
    public function __construct(public string $term, public int $frequency, public float $score, public int $bestClass) {}
}

final class Vocabulary
{
    public int $termCount;
    public int $candidateCount;
    public array $ranking = [];
    public array $terms;
    public array $index = [];
    public array $frequencies = [];

    public function __construct(array $sequences, array $labels, int $classCount, int $minFrequency, int $size)
    {
        $counts = $terms = [];
        $classSizes = array_fill(0, $classCount, 0);
        foreach ($sequences as $index => $sequence) {
            $label = $labels[$index];
            $classSizes[$label]++;
            foreach (firstOccurrences($sequence) as $term) {
                $key = '#' . $term;
                if (!isset($counts[$key])) {
                    $counts[$key] = array_fill(0, $classCount, 0);
                    $terms[] = $term;
                }
                $counts[$key][$label]++;
            }
        }
        usort($terms, 'strcmp');
        $this->termCount = count($terms);
        foreach ($terms as $term) {
            $row = $counts['#' . $term];
            $frequency = array_sum($row);
            if ($frequency < $minFrequency) {
                continue;
            }
            $bestClass = 0;
            $bestScore = chiSquare($row[0], $frequency, $classSizes[0], count($sequences));
            for ($label = 1; $label < $classCount; $label++) {
                $score = chiSquare($row[$label], $frequency, $classSizes[$label], count($sequences));
                if ($score > $bestScore) {
                    $bestClass = $label;
                    $bestScore = $score;
                }
            }
            $this->ranking[] = new RankedTerm($term, $frequency, $bestScore, $bestClass);
        }
        $this->candidateCount = count($this->ranking);
        usort($this->ranking, static fn(RankedTerm $a, RankedTerm $b): int => ($b->score <=> $a->score) ?: strcmp($a->term, $b->term));
        if ($size > 0 && count($this->ranking) > $size) {
            $this->ranking = array_slice($this->ranking, 0, $size);
        }
        $this->terms = array_map(static fn(RankedTerm $entry): string => $entry->term, $this->ranking);
        usort($this->terms, 'strcmp');
        $frequencies = [];
        foreach ($this->ranking as $entry) {
            $frequencies['#' . $entry->term] = $entry->frequency;
        }
        foreach ($this->terms as $index => $term) {
            $this->index['#' . $term] = $index;
            $this->frequencies[] = $frequencies['#' . $term];
        }
    }

    public function size(): int { return count($this->terms); }

    public function encode(array $sequence): array
    {
        $result = [];
        foreach ($sequence as $term) {
            if (isset($this->index['#' . $term])) {
                $result[] = $this->index['#' . $term];
            }
        }
        return $result;
    }
}
