<?php

function advance($process, $sendingEvent = null) {
    if ($sendingEvent !== null) {
        $process->L = max($process->L, $sendingEvent->L);
        foreach ($process->V as $i => $value) $process->V[$i] = max($value, $sendingEvent->V[$i]);
    }
    $process->L++;
    $process->V[$process->index]++;
}

function lessEqual($left, $right) {
    foreach ($left as $i => $value) if ($value > $right[$i]) return false;
    return true;
}

function relation($left, $right) {
    if ($left !== $right && lessEqual($left, $right)) return '->';
    if ($left !== $right && lessEqual($right, $left)) return '<-';
    return '||';
}

function deliverable($copy, $counters) {
    foreach ($copy->message->stamp as $i => $value) {
        if ($i === $copy->source ? $value !== $counters[$i] + 1 : $value > $counters[$i]) return false;
    }
    return true;
}

function missingProcesses($copy, $counters) {
    $missing = [];
    foreach ($counters as $i => $value) if ($copy->message->stamp[$i] > $value + ($i === $copy->source ? 1 : 0)) $missing[] = $i;
    return $missing;
}

function vector($values) {
    return implode(',', $values);
}
