<?php
declare(strict_types=1);

namespace TextClassifier;

const NB_MODELS = ['multinomial', 'bernoulli', 'complement'];

function smoothedLog(int|float $count, int|float $total, int $alpha, int $outcomes): float
{
    return log((100 * $count + $alpha) / (100 * $total + $alpha * $outcomes));
}

final class TrainingCounts
{
    public int $documentTotal;
    public array $documents;
    public array $occurrences;
    public array $containing;
    public array $totals;
    public int $total;
    public array $termTotals = [];

    public function __construct(array $sequences, array $labels, public int $classCount, public int $vocabularySize)
    {
        $this->documentTotal = count($sequences);
        $this->documents = array_fill(0, $classCount, 0);
        $this->occurrences = $this->containing = array_fill(0, $classCount, array_fill(0, $vocabularySize, 0));
        foreach ($sequences as $index => $sequence) {
            $label = $labels[$index];
            $this->documents[$label]++;
            foreach ($sequence as $term) {
                $this->occurrences[$label][$term]++;
            }
            foreach (firstOccurrences($sequence) as $term) {
                $this->containing[$label][$term]++;
            }
        }
        $this->totals = array_map(static fn(array $row): int => array_sum($row), $this->occurrences);
        $this->total = array_sum($this->totals);
        for ($term = 0; $term < $vocabularySize; $term++) {
            $total = 0;
            foreach ($this->occurrences as $row) {
                $total += $row[$term];
            }
            $this->termTotals[] = $total;
        }
    }

    public function logPriors(): array
    {
        return array_map(fn(int $count): float => log($count / $this->documentTotal), $this->documents);
    }
}

final class Posterior
{
    public array $ranking;
    public int $label;
    public int $runnerUp;
    public float $normalizer = 0.0;
    public array $probabilities = [];
    public float $score;
    public float $margin;

    public function __construct(public array $scores)
    {
        $this->ranking = range(0, count($scores) - 1);
        usort($this->ranking, static fn(int $a, int $b): int => ($scores[$b] <=> $scores[$a]) ?: ($a <=> $b));
        $this->label = $this->ranking[0];
        $this->runnerUp = $this->ranking[1];
        $best = $scores[$this->label];
        $exponentials = [];
        foreach ($scores as $score) {
            $value = exp($score - $best);
            $exponentials[] = $value;
            $this->normalizer += $value;
        }
        foreach ($exponentials as $value) {
            $this->probabilities[] = $value / $this->normalizer;
        }
        $this->score = $this->probabilities[$this->label];
        $this->margin = $best - $scores[$this->runnerUp];
    }
}

final class NaiveBayes
{
    public function __construct(public string $kind, public array $priors, public array $base, public array $weights) {}

    public function scores(array $sequence): array
    {
        $terms = $this->kind === 'bernoulli' ? firstOccurrences($sequence) : $sequence;
        $scores = [];
        foreach ($this->weights as $label => $row) {
            $score = $this->base[$label];
            foreach ($terms as $term) {
                $score += $row[$term];
            }
            $scores[] = $score + $this->priors[$label];
        }
        return $scores;
    }

    public function predict(array $sequence): Posterior { return new Posterior($this->scores($sequence)); }
}

function trainModel(string $kind, TrainingCounts $counts, int $alpha): NaiveBayes
{
    $base = $weights = [];
    for ($label = 0; $label < $counts->classCount; $label++) {
        $row = [];
        $absentSum = 0.0;
        for ($term = 0; $term < $counts->vocabularySize; $term++) {
            if ($kind === 'multinomial') {
                $row[] = smoothedLog($counts->occurrences[$label][$term], $counts->totals[$label], $alpha, $counts->vocabularySize);
            } elseif ($kind === 'bernoulli') {
                $present = smoothedLog($counts->containing[$label][$term], $counts->documents[$label], $alpha, 2);
                $absent = smoothedLog($counts->documents[$label] - $counts->containing[$label][$term], $counts->documents[$label], $alpha, 2);
                $absentSum += $absent;
                $row[] = $present - $absent;
            } else {
                $row[] = -smoothedLog($counts->termTotals[$term] - $counts->occurrences[$label][$term], $counts->total - $counts->totals[$label], $alpha, $counts->vocabularySize);
            }
        }
        $base[] = $absentSum;
        $weights[] = $row;
    }
    return new NaiveBayes($kind, $counts->logPriors(), $base, $weights);
}
