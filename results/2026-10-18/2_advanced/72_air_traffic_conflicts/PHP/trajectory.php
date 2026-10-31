<?php

function build_trajectory($plan, $types)
{
    $segments = []; $time = $plan['departure'] + $plan['delay']; $flightLevel = $plan['level'] + $plan['offset']; $routeLength = 0.0;
    $waypointTimes = [[$time, $flightLevel]]; $rates = $types[$plan['type']];
    $addSegment = function ($leg, $phase, $ts, $te, $start, $velocity, $end) use (&$segments) {
        $segments[] = ['number' => count($segments) + 1, 'leg' => $leg, 'phase' => $phase, 'ts' => $ts, 'te' => $te,
            'start' => $start, 'velocity' => $velocity, 'end' => $end];
    };
    for ($leg = 1; $leg < count($plan['waypoints']); $leg++) {
        $p = $plan['waypoints'][$leg - 1]; $q = $plan['waypoints'][$leg];
        $dx = $q['x'] - $p['x']; $dy = $q['y'] - $p['y'];
        $length = sqrt($dx * $dx + $dy * $dy) / 10; $duration = $length * 3600 / $plan['speed'];
        $vx = ($dx / 10) / $duration; $vy = ($dy / 10) / $duration;
        $target = $q['level'] === null ? $flightLevel : $q['level'] + $plan['offset'];
        $x = $p['x'] / 10; $y = $p['y'] / 10; $routeLength += $length;
        if ($target === $flightLevel) {
            $addSegment($leg, 'LVL', $time, $time + $duration, [$x, $y, $flightLevel * 100], [$vx, $vy, 0.0], [$q['x'] / 10, $q['y'] / 10, $target * 100]);
        } else {
            $climbing = $target > $flightLevel; $rate = $climbing ? $rates['climb'] : $rates['descent'];
            $changeTime = abs($target - $flightLevel) * 6000 / $rate;
            $intermediate = [$x + $vx * $changeTime, $y + $vy * $changeTime, $target * 100];
            $addSegment($leg, $climbing ? 'CLB' : 'DES', $time, $time + $changeTime, [$x, $y, $flightLevel * 100], [$vx, $vy, $climbing ? $rate / 60 : -$rate / 60], $intermediate);
            $addSegment($leg, 'LVL', $time + $changeTime, $time + $duration, $intermediate, [$vx, $vy, 0.0], [$q['x'] / 10, $q['y'] / 10, $target * 100]);
        }
        $time += $duration; $flightLevel = $target; $waypointTimes[] = [$time, $flightLevel];
    }
    return ['segments' => $segments, 'arrival' => $time, 'length' => $routeLength, 'waypointTimes' => $waypointTimes];
}

function position($segment, $time)
{
    $dt = $time - $segment['ts']; $result = [];
    foreach ($segment['start'] as $i => $value) $result[] = $value + $segment['velocity'][$i] * $dt;
    return $result;
}

function active_segment($trajectory, $time)
{
    $segments = $trajectory['segments'];
    if (!($segments[0]['ts'] <= $time && $time < $segments[count($segments) - 1]['te'])) return null;
    foreach ($segments as $segment) if ($segment['ts'] <= $time && $time < $segment['te']) return $segment;
    return null;
}

function current_position($trajectory, $time)
{
    $segment = active_segment($trajectory, $time);
    return $segment === null ? null : ['point' => position($segment, $time), 'segment' => $segment];
}
