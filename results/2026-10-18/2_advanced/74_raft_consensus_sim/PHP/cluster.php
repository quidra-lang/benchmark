<?php

function readCluster(): object
{
    $settings = (object) [];
    foreach (file('input/cluster.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $values = explode(' ', $line);
        $key = array_shift($values);
        $settings->$key = $key === 'ELECTION' ? array_map('intval', $values) : (int) $values[0];
    }
    $controls = $requests = [];
    foreach (file('input/script.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $values = explode(' ', $line);
        $time = (int) array_shift($values);
        $kind = array_shift($values);
        if ($kind === 'REQUEST') {
            $node = (int) array_shift($values);
            $requests[] = (object) ['number' => count($requests) + 1, 'time' => $time, 'startNode' => $node, 'destination' => $node,
                'scheduled' => $time, 'command' => implode(' ', $values), 'attempts' => 0, 'redirects' => 0, 'accepted' => null, 'abandoned' => false];
        } else {
            $args = $kind === 'PARTITION' ? array_map(fn($token) => array_map('intval', explode(',', $token)), $values) : array_map('intval', $values);
            $controls[$time][] = (object) compact('kind', 'args');
        }
    }
    return (object) compact('settings', 'controls', 'requests');
}
