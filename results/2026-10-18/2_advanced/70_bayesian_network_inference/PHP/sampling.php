<?php

class Minstd
{
    public $state;

    public function __construct($seed)
    {
        $this->state = $seed;
    }

    public function next()
    {
        $this->state = (48271 * $this->state) % 2147483647;
        return $this->state / 2147483647;
    }
}

function chooseState($probabilities, $random)
{
    $draw = $random->next();
    $cumulative = 0.0;
    foreach ($probabilities as $state => $probability) {
        $cumulative += $probability;
        if ($draw < $cumulative) {
            return $state;
        }
    }
    return count($probabilities) - 1;
}

function weightedSample($network, $evidence, $random)
{
    $assignment = array_fill(0, count($network->variables), 0);
    $weight = 1.0;
    foreach ($network->topological as $index) {
        $variable = $network->variables[$index];
        $row = $variable->cpt[combinationIndex($variable->parents, $assignment, $network->sizes)];
        if (isset($evidence[$index])) {
            $assignment[$index] = $evidence[$index];
            $weight *= $row[$assignment[$index]];
        } else {
            $assignment[$index] = chooseState($row, $random);
        }
    }
    return ['assignment' => $assignment, 'weight' => $weight];
}
