<?php

function argmax_index($values)
{
    $best = 0;
    for ($i = 1; $i < count($values); $i++) if ($values[$i] > $values[$best]) $best = $i;
    return $best;
}

function emission_factor($model, $observation, $state)
{
    return $observation < 0 ? 1.0 : $model['emission'][$state][$observation];
}

function forward($model, $observations)
{
    $count = count($model['states']);
    $factors = [];
    $scales = [];
    $loglik = 0.0;
    foreach ($observations as $t => $observation) {
        $row = [];
        for ($j = 0; $j < $count; $j++) {
            $probability = $model['initial'][$j];
            if ($t > 0) {
                $probability = 0.0;
                for ($i = 0; $i < $count; $i++) $probability += $factors[$t - 1][$i] * $model['transition'][$i][$j];
            }
            $row[] = $probability * emission_factor($model, $observation, $j);
        }
        $scale = 0.0;
        foreach ($row as $value) $scale += $value;
        $scales[] = $scale;
        $normalized = [];
        foreach ($row as $value) $normalized[] = $value / $scale;
        $factors[] = $normalized;
        $loglik += log($scale);
    }
    return compact('factors', 'scales', 'loglik');
}

function forward_backward($model, $observations)
{
    $result = forward($model, $observations);
    $count = count($model['states']);
    $length = count($observations);
    $backward = array_fill(0, $length, []);
    $backward[$length - 1] = array_fill(0, $count, 1.0);
    for ($t = $length - 2; $t >= 0; $t--) {
        $backward[$t] = [];
        for ($i = 0; $i < $count; $i++) {
            $value = 0.0;
            for ($j = 0; $j < $count; $j++) $value += $model['transition'][$i][$j] * emission_factor($model, $observations[$t + 1], $j) * $backward[$t + 1][$j];
            $backward[$t][] = $value / $result['scales'][$t + 1];
        }
    }
    $gamma = [];
    foreach ($result['factors'] as $t => $row) {
        $current = [];
        foreach ($row as $i => $value) $current[] = $value * $backward[$t][$i];
        $gamma[] = $current;
    }
    $result['backward'] = $backward;
    $result['gamma'] = $gamma;
    return $result;
}

function viterbi($model, $observations)
{
    $count = count($model['states']);
    $transitions = [];
    foreach ($model['transition'] as $row) $transitions[] = array_map('log', $row);
    $delta = [];
    foreach ($model['initial'] as $j => $value) $delta[] = log($value) + ($observations[0] < 0 ? 0 : log($model['emission'][$j][$observations[0]]));
    $predecessors = [array_fill(0, $count, 0)];
    for ($t = 1; $t < count($observations); $t++) {
        $next = [];
        $row = [];
        for ($j = 0; $j < $count; $j++) {
            $candidates = [];
            foreach ($delta as $i => $value) $candidates[] = $value + $transitions[$i][$j];
            $best = argmax_index($candidates);
            $row[] = $best;
            $next[] = ($delta[$best] + $transitions[$best][$j]) + ($observations[$t] < 0 ? 0 : log($model['emission'][$j][$observations[$t]]));
        }
        $predecessors[] = $row;
        $delta = $next;
    }
    $path = array_fill(0, count($observations), 0);
    $last = count($path) - 1;
    $path[$last] = argmax_index($delta);
    $logprob = $delta[$path[$last]];
    for ($t = $last; $t > 0; $t--) $path[$t - 1] = $predecessors[$t][$path[$t]];
    return compact('path', 'logprob');
}

function decode($model, $observations)
{
    $result = forward_backward($model, $observations);
    $best = viterbi($model, $observations);
    $posterior = [];
    $confidence = [];
    foreach ($result['gamma'] as $row) {
        $state = argmax_index($row);
        $posterior[] = $state;
        $confidence[] = $row[$state];
    }
    $result['viterbi'] = $best['path'];
    $result['logprob'] = $best['logprob'];
    $result['posterior'] = $posterior;
    $result['confidence'] = $confidence;
    return $result;
}
