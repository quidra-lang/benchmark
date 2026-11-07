<?php

require_once __DIR__ . '/logistic.php';

class Minstd
{
    public function __construct(private int $state) {}

    public function draw(): int
    {
        $this->state = (48271 * $this->state) % 2147483647;
        return $this->state;
    }
}

function shuffleWithGenerator(array &$values, Minstd $generator): void
{
    for ($i = count($values) - 1; $i >= 1; $i--) {
        $other = $generator->draw() % ($i + 1);
        [$values[$i], $values[$other]] = [$values[$other], $values[$i]];
    }
}

function cholesky(array $matrix): array
{
    $size = count($matrix);
    $factor = array_fill(0, $size, array_fill(0, $size, 0.0));
    for ($column = 0; $column < $size; $column++) {
        for ($row = $column; $row < $size; $row++) {
            $total = 0.0;
            for ($inner = 0; $inner < $column; $inner++) {
                $total += $factor[$row][$inner] * $factor[$column][$inner];
            }
            $remainder = $matrix[$row][$column] - $total;
            $factor[$row][$column] = $row === $column ? sqrt($remainder) : $remainder / $factor[$column][$column];
        }
    }
    return $factor;
}

function solveFactor(array $factor, array $right): array
{
    $size = count($right);
    $forward = $solution = array_fill(0, $size, 0.0);
    for ($row = 0; $row < $size; $row++) {
        $total = 0.0;
        for ($column = 0; $column < $row; $column++) {
            $total += $factor[$row][$column] * $forward[$column];
        }
        $forward[$row] = ($right[$row] - $total) / $factor[$row][$row];
    }
    for ($row = $size - 1; $row >= 0; $row--) {
        $total = 0.0;
        for ($column = $row + 1; $column < $size; $column++) {
            $total += $factor[$column][$row] * $solution[$column];
        }
        $solution[$row] = ($forward[$row] - $total) / $factor[$row][$row];
    }
    return $solution;
}

function gradientDescent(array $vectors, array $targets, float $lambda, float $rate, int $iterations): object
{
    $weights = array_fill(0, count($vectors[0]), 0.0);
    $checkpoints = [(object) ['iteration' => 0, 'weights' => $weights]];
    for ($iteration = 1; $iteration <= $iterations; $iteration++) {
        $direction = logisticGradient($weights, $vectors, $targets, $lambda);
        foreach ($weights as $component => $weight) {
            $weights[$component] = $weight - $rate * $direction[$component];
        }
        if ($iteration % 100 === 0) {
            $checkpoints[] = (object) compact('iteration', 'weights');
        }
    }
    return (object) compact('weights', 'checkpoints');
}

function stochasticDescent(array $vectors, array $targets, float $lambda, float $rate, int $batchSize, int $epochs, int $seed): object
{
    $weights = array_fill(0, count($vectors[0]), 0.0);
    $checkpoints = [(object) ['iteration' => 0, 'weights' => $weights]];
    $generator = new Minstd($seed);
    $order = range(0, count($vectors) - 1);
    for ($epoch = 1; $epoch <= $epochs; $epoch++) {
        shuffleWithGenerator($order, $generator);
        for ($start = 0; $start < count($order); $start += $batchSize) {
            $batch = array_slice($order, $start, $batchSize);
            $batchVectors = array_map(fn($index) => $vectors[$index], $batch);
            $batchTargets = array_map(fn($index) => $targets[$index], $batch);
            $direction = logisticGradient($weights, $batchVectors, $batchTargets, $lambda);
            foreach ($weights as $component => $weight) {
                $weights[$component] = $weight - $rate * $direction[$component];
            }
        }
        $checkpoints[] = (object) ['iteration' => $epoch, 'weights' => $weights];
    }
    return (object) compact('weights', 'checkpoints');
}

function newton(array $vectors, array $targets, float $lambda): object
{
    $weights = array_fill(0, count($vectors[0]), 0.0);
    $checkpoints = [(object) ['iteration' => 0, 'weights' => $weights]];
    $steps = [];
    for ($iteration = 1; $iteration <= 10; $iteration++) {
        $direction = logisticGradient($weights, $vectors, $targets, $lambda);
        $delta = solveFactor(cholesky(logisticHessian($weights, $vectors, $lambda)), $direction);
        $steps[] = (object) ['gradient' => $direction, 'delta' => $delta];
        foreach ($weights as $component => $weight) {
            $weights[$component] = $weight - $delta[$component];
        }
        $checkpoints[] = (object) compact('iteration', 'weights');
    }
    return (object) compact('weights', 'checkpoints', 'steps');
}
