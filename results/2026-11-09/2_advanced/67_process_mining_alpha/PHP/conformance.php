<?php

class PetriNet
{
    public $places, $transitions, $arcs, $placeIndex, $initial, $final, $inputs, $outputs;

    public function __construct($places, $transitions, $arcs, $initial, $final)
    {
        $this->places = $places;
        $this->transitions = $transitions;
        sort($this->transitions, SORT_STRING);
        $this->arcs = $arcs;
        $this->placeIndex = array_flip($places);
        $this->initial = $this->placeIndex[$initial];
        $this->final = $this->placeIndex[$final];
        $this->inputs = []; $this->outputs = [];
        foreach ($this->transitions as $name) { $this->inputs[$name] = []; $this->outputs[$name] = []; }
        foreach ($arcs as [$from, $to]) {
            if (isset($this->placeIndex[$from])) $this->inputs[$to][] = $this->placeIndex[$from];
            else $this->outputs[$from][] = $this->placeIndex[$to];
        }
        foreach ($this->transitions as $name) { sort($this->inputs[$name], SORT_NUMERIC); sort($this->outputs[$name], SORT_NUMERIC); }
    }

    public function marking($final = false)
    {
        $tokens = array_fill(0, count($this->places), 0);
        $tokens[$final ? $this->final : $this->initial] = 1;
        return $tokens;
    }

    public function enabled($marking, $transition)
    {
        if (!isset($this->inputs[$transition])) return false;
        foreach ($this->inputs[$transition] as $place) if ($marking[$place] < 1) return false;
        return true;
    }

    public function enabledTransitions($marking)
    {
        $result = [];
        foreach ($this->transitions as $transition) if ($this->enabled($marking, $transition)) $result[] = $transition;
        return $result;
    }

    public function fire($marking, $transition)
    {
        foreach ($this->inputs[$transition] as $place) $marking[$place]--;
        foreach ($this->outputs[$transition] as $place) $marking[$place]++;
        return $marking;
    }
}

function read_model()
{
    $places = []; $transitions = []; $arcs = []; $initial = ''; $final = '';
    foreach (file('input/model.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $parts = explode(' ', $line);
        if ($parts[0] === 'PLACE') $places[] = $parts[1];
        elseif ($parts[0] === 'TRANSITION') $transitions[] = $parts[1];
        elseif ($parts[0] === 'ARC') $arcs[] = [$parts[1], $parts[2]];
        elseif ($parts[0] === 'INITIAL') $initial = $parts[1];
        else $final = $parts[1];
    }
    return new PetriNet($places, $transitions, $arcs, $initial, $final);
}

function replay_record($net)
{
    $places = [];
    foreach ($net->places as $place) $places[] = ['missing' => 0, 'remaining' => 0, 'deviating' => 0,
        'waitingCount' => 0, 'waitingTotal' => 0, 'waitingMaximum' => 0, 'consumptions' => []];
    return ['missing' => 0, 'remaining' => 0, 'consumed' => 0, 'produced' => 0, 'skipped' => 0, 'fitting' => 0, 'places' => $places];
}

function fitness($record)
{
    $denominator = 2 * $record['consumed'] * $record['produced'];
    return [$denominator - $record['missing'] * $record['produced'] - $record['remaining'] * $record['consumed'], $denominator];
}
