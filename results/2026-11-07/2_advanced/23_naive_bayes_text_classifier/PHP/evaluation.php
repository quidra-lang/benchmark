<?php
declare(strict_types=1);

namespace TextClassifier;

function realText(float $value): string
{
    $rounded = round($value, 4, PHP_ROUND_HALF_UP);
    return number_format($rounded == 0 ? 0 : $rounded, 4, '.', '');
}

function proportionText(int $numerator, int $denominator): string
{
    return $numerator . '/' . $denominator . ' ' . realText($numerator / $denominator);
}

function fractionText(int $numerator, int $denominator): string
{
    if ($denominator === 0) {
        return '- -';
    }
    $a = $numerator;
    $b = $denominator;
    while ($b !== 0) {
        [$a, $b] = [$b, $a % $b];
    }
    return proportionText(intdiv($numerator, $a), intdiv($denominator, $a));
}

final class Evaluation
{
    public array $matrix;
    public int $total;
    public int $correct = 0;
    public float $microF1;
    public float $macroF1;

    public function __construct(int $classCount, array $truths, array $predictions)
    {
        $this->matrix = array_fill(0, $classCount, array_fill(0, $classCount, 0));
        foreach ($truths as $index => $truth) {
            $this->matrix[$truth][$predictions[$index]]++;
        }
        $this->total = count($truths);
        $f1Sum = 0.0;
        $scored = 0;
        for ($label = 0; $label < $classCount; $label++) {
            $this->correct += $this->matrix[$label][$label];
            $denominator = $this->predictedCount($label) + $this->support($label);
            if ($denominator > 0) {
                $f1Sum += 2 * $this->matrix[$label][$label] / $denominator;
                $scored++;
            }
        }
        $this->microF1 = $this->correct / $this->total;
        $this->macroF1 = $f1Sum / $scored;
    }

    public function support(int $label): int { return array_sum($this->matrix[$label]); }

    public function predictedCount(int $label): int
    {
        $count = 0;
        foreach ($this->matrix as $row) {
            $count += $row[$label];
        }
        return $count;
    }

    public function lines(array $names): array
    {
        $lines = ['true\\predicted ' . implode(' ', $names)];
        foreach ($names as $label => $name) {
            $lines[] = $name . ' ' . implode(' ', $this->matrix[$label]);
        }
        foreach ($names as $label => $name) {
            $hits = $this->matrix[$label][$label];
            $predicted = $this->predictedCount($label);
            $support = $this->support($label);
            $lines[] = "class $name precision " . fractionText($hits, $predicted) . ' recall ' . fractionText($hits, $support)
                . ' f1 ' . fractionText(2 * $hits, $predicted + $support) . " support $support";
        }
        $lines[] = 'micro_f1 ' . realText($this->microF1) . ' macro_f1 ' . realText($this->macroF1);
        return $lines;
    }
}
