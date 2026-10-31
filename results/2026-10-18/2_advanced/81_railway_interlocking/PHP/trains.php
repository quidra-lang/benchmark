<?php

function readTrains(): array
{
    $trains = [];
    $requests = [];
    foreach (file('input/trains.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $f = explode(' ', $line);
        $kind = array_shift($f);
        $name = $f[0];
        if ($kind === 'TRAIN') {
            $trains[$name] = (object) [
                'name' => $name,
                'symbol' => chr(97 + count($trains)),
                'length' => (int) $f[1],
                'acceleration' => (int) $f[2],
                'deceleration' => (int) $f[3],
                'maxSpeed' => (int) $f[4],
                'entry' => $f[5],
                'entryTime' => (int) $f[6],
                'entrySpeed' => (int) $f[7],
                'exit' => null,
                'scheduledExit' => null,
                'stops' => [],
                'stopIndex' => 0,
                'state' => 'WAITING',
                'direction' => null,
                'path' => [],
                'head' => 0,
                'speed' => 0,
                'dwelling' => false,
                'awaitingDeparture' => null,
                'emergency' => false,
                'boundary' => null,
                'boundaryCoordinate' => null,
                'entered' => null,
                'exited' => null,
                'distance' => 0,
                'maximumSpeed' => 0,
                'standing' => 0,
                'passes' => 0,
            ];
        } elseif ($kind === 'REQUEST')
            $requests[] = [(int) $f[2], $name, $f[1]];
        elseif ($kind === 'STOP' || $kind === 'TURN')
            $trains[$name]->stops[] = (object) [
                'kind' => $kind,
                'section' => $f[1],
                'dwell' => (int) $f[2],
                'scheduledArrival' => (int) $f[3],
                'scheduledDeparture' => (int) $f[4],
                'arrival' => null,
                'departure' => null,
            ];
        else {
            $trains[$name]->exit = $f[1];
            $trains[$name]->scheduledExit = (int) $f[2];
        }
    }
    return [$trains, $requests];
}

function brakingDistance(int $speed, int $deceleration): int
{
    $n = intdiv($speed, $deceleration);
    return ($n * $speed) - intdiv($deceleration * $n * ($n + 1), 2);
}

function selectSpeed(object $train, ?int $distance): int
{
    $lo = max($train->speed - $train->deceleration, 0);
    if (!$train->emergency)
        for ($speed = min($train->speed + $train->acceleration, $train->maxSpeed); $speed >= $lo; --$speed) {
            if ($distance === null || ($speed + brakingDistance($speed, $train->deceleration)) <= $distance)
                return $speed;
        }
    return $lo;
}
