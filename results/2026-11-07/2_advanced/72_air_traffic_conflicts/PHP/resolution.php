<?php

require_once __DIR__ . '/flight_plans.php';

function priority_order($a, $b)
{
    $da = $a['departure'] + $a['delay']; $db = $b['departure'] + $b['delay'];
    return $da > $db || ($da === $db && strcmp($a['callsign'], $b['callsign']) > 0) ? [$a['callsign'], $b['callsign']] : [$b['callsign'], $a['callsign']];
}

function manoeuvres($maxDelay)
{
    $choices = [['level_up', 10], ['level_down', -10], ['speed_down', null]];
    for ($delay = 60; $delay <= $maxDelay; $delay += 60) $choices[] = ['delay_' . $delay, $delay];
    return $choices;
}

function propose($plan, $name, $amount, $types, $params)
{
    if ($name === 'level_up' || $name === 'level_down') {
        $plan['offset'] += $amount;
        foreach (level_list($plan) as $level) if ($level < $params['levelMin'] || $level > $params['levelMax']) return null;
    } elseif ($name === 'speed_down') {
        $plan['speed'] = intdiv($plan['speed'] * 9, 10);
        if ($plan['speed'] < $types[$plan['type']]['minimum']) return null;
    } else $plan['delay'] += $amount;
    return $plan;
}
