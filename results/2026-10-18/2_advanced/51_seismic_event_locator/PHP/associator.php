<?php

function associate(array $picks, int $window, int $minimumStations): array
{
    $candidates = [];
    $count = count($picks);
    for ($i = 0; $i < $count; $i++) {
        $first = $picks[$i];
        if ($first->candidate !== null) {
            continue;
        }
        $stations = [];
        $selected = [];
        for ($j = $i; $j < $count && $picks[$j]->sample <= $first->sample + $window; $j++) {
            $pick = $picks[$j];
            if ($pick->candidate !== null || isset($stations[$pick->station->index])) {
                continue;
            }
            $stations[$pick->station->index] = true;
            $selected[] = $pick;
        }
        if (count($selected) < $minimumStations) {
            continue;
        }
        $number = count($candidates) + 1;
        foreach ($selected as $pick) {
            $pick->candidate = $number;
        }
        $candidates[] = (object) ['number' => $number, 'first' => $first, 'picks' => $selected];
    }
    return $candidates;
}
