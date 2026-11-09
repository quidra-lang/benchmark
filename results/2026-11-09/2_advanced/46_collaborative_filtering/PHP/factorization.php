<?php

class FactorRandom
{
    private int $state;

    public function __construct(int $seed)
    {
        $this->state = $seed;
    }

    public function next(): int
    {
        $this->state = (48271 * $this->state) % 2147483647;
        return $this->state;
    }

    public function factor(): float
    {
        return ($this->next() % 2001 - 1000) / 10000;
    }
}

function dot(array $first, array $second): float
{
    $total = 0.0;
    for ($index = 0; $index < count($first); $index++) {
        $total += $first[$index] * $second[$index];
    }
    return $total;
}

function trainSvd(object $data): object
{
    $settings = $data->settings;
    $random = new FactorRandom($settings->seed);
    $userFactors = [];
    $itemFactors = [];
    foreach ($data->users as $user) {
        $vector = [];
        for ($f = 0; $f < $settings->factors; $f++) {
            $vector[] = $random->factor();
        }
        $userFactors[] = $vector;
    }
    foreach ($data->items as $item) {
        $vector = [];
        for ($f = 0; $f < $settings->factors; $f++) {
            $vector[] = $random->factor();
        }
        $itemFactors[] = $vector;
    }
    $userBias = array_fill(0, count($data->users), 0.0);
    $itemBias = array_fill(0, count($data->items), 0.0);
    $order = array_keys($data->train);
    $predict = function ($user, $item) use ($data, &$userBias, &$itemBias, &$userFactors, &$itemFactors) {
        return (($data->mean + $userBias[$user]) + $itemBias[$item]) + dot($userFactors[$user], $itemFactors[$item]);
    };
    $history = [];
    for ($epoch = 1; $epoch <= $settings->epochs; $epoch++) {
        for ($index = count($order) - 1; $index >= 1; $index--) {
            $other = $random->next() % ($index + 1);
            [$order[$index], $order[$other]] = [$order[$other], $order[$index]];
        }
        foreach ($order as $index) {
            $row = $data->train[$index];
            $u = $row->u;
            $i = $row->i;
            $error = $row->rating - $predict($u, $i);
            $userBias[$u] += $settings->learningRate * ($error - $settings->regularization * $userBias[$u]);
            $itemBias[$i] += $settings->learningRate * ($error - $settings->regularization * $itemBias[$i]);
            for ($factor = 0; $factor < $settings->factors; $factor++) {
                $a = $userFactors[$u][$factor];
                $b = $itemFactors[$i][$factor];
                $userFactors[$u][$factor] = $a + $settings->learningRate * ($error * $b - $settings->regularization * $a);
                $itemFactors[$i][$factor] = $b + $settings->learningRate * ($error * $a - $settings->regularization * $b);
            }
        }
        $history[] = (object) ['method' => 'SVD', 'epoch' => $epoch, 'rmse' => trainingRmse($data->train, $predict)];
    }
    return (object) compact('userFactors', 'itemFactors', 'userBias', 'itemBias', 'predict', 'history');
}

function solve(array $matrix, array $right): array
{
    $size = count($right);
    $lower = array_fill(0, $size, array_fill(0, $size, 0.0));
    for ($row = 0; $row < $size; $row++) {
        for ($column = 0; $column <= $row; $column++) {
            $total = 0.0;
            for ($index = 0; $index < $column; $index++) {
                $total += $lower[$row][$index] * $lower[$column][$index];
            }
            $value = $matrix[$row][$column] - $total;
            $lower[$row][$column] = $row === $column ? sqrt($value) : $value / $lower[$column][$column];
        }
    }
    $forward = array_fill(0, $size, 0.0);
    for ($row = 0; $row < $size; $row++) {
        $total = 0.0;
        for ($column = 0; $column < $row; $column++) {
            $total += $lower[$row][$column] * $forward[$column];
        }
        $forward[$row] = ($right[$row] - $total) / $lower[$row][$row];
    }
    $result = array_fill(0, $size, 0.0);
    for ($row = $size - 1; $row >= 0; $row--) {
        $total = 0.0;
        for ($column = $row + 1; $column < $size; $column++) {
            $total += $lower[$column][$row] * $result[$column];
        }
        $result[$row] = ($forward[$row] - $total) / $lower[$row][$row];
    }
    return $result;
}

function trainAls(object $data, callable $baseline): object
{
    $settings = $data->settings;
    $random = new FactorRandom($settings->seed);
    $itemFactors = [];
    foreach ($data->items as $item) {
        $vector = [];
        for ($f = 0; $f < $settings->factors; $f++) {
            $vector[] = $random->factor();
        }
        $itemFactors[] = $vector;
    }
    $userFactors = array_fill(0, count($data->users), []);
    $residual = [];
    foreach ($data->train as $row) {
        $residual[] = $row->rating - $baseline($row->u, $row->i);
    }
    $fit = function ($entries, $factors, $key) use ($settings, $residual) {
        $size = $settings->factors;
        $matrix = array_fill(0, $size, array_fill(0, $size, 0.0));
        $right = array_fill(0, $size, 0.0);
        for ($first = 0; $first < $size; $first++) {
            for ($second = 0; $second < $size; $second++) {
                $total = 0.0;
                foreach ($entries as $row) {
                    $total += $factors[$row->$key][$first] * $factors[$row->$key][$second];
                }
                $matrix[$first][$second] = $total;
            }
            $matrix[$first][$first] += $settings->alsReg * count($entries);
            $total = 0.0;
            foreach ($entries as $row) {
                $total += $residual[$row->index] * $factors[$row->$key][$first];
            }
            $right[$first] = $total;
        }
        return solve($matrix, $right);
    };
    $predict = function ($user, $item) use ($baseline, &$userFactors, &$itemFactors) {
        return $baseline($user, $item) + dot($userFactors[$user], $itemFactors[$item]);
    };
    $history = [];
    for ($iteration = 1; $iteration <= $settings->alsIterations; $iteration++) {
        foreach ($data->users as $user => $group) {
            $userFactors[$user] = $fit($group->entries, $itemFactors, 'i');
        }
        foreach ($data->items as $item => $group) {
            $itemFactors[$item] = $fit($group->entries, $userFactors, 'u');
        }
        $history[] = (object) ['method' => 'ALS', 'epoch' => $iteration, 'rmse' => trainingRmse($data->train, $predict)];
    }
    return (object) compact('userFactors', 'itemFactors', 'predict', 'history');
}
