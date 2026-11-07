<?php

function readInput(): array
{
    $stationLines = file('input/stations.csv', FILE_IGNORE_NEW_LINES);
    $stations = [];
    foreach (array_slice($stationLines, 1) as $index => $line) {
        [$code, $x, $y, $elevation] = explode(',', $line);
        $stations[] = (object) ['index' => $index, 'code' => $code, 'x' => (int) $x, 'y' => (int) $y,
            'elevation' => (int) $elevation];
    }
    $waveformLines = file('input/waveforms.txt', FILE_IGNORE_NEW_LINES);
    $position = 0;
    foreach ($stations as $station) {
        $header = explode(' ', $waveformLines[$position++]);
        $station->start = (int) $header[2];
        $count = (int) $header[3];
        $station->samples = [];
        while (count($station->samples) < $count) {
            foreach (explode(' ', $waveformLines[$position++]) as $sample) {
                $station->samples[] = (int) $sample;
            }
        }
    }
    $fields = [];
    foreach (file('input/params.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $values = array_slice(explode(' ', $line), 1);
        $fields[] = array_map(fn($value) => str_contains($value, '.') ? (float) $value : (int) $value, $values);
    }
    $params = (object) [
        'staWindow' => $fields[0][0], 'ltaWindow' => $fields[1][0], 'triggerOn' => $fields[2], 'triggerOff' => $fields[3],
        'minDuration' => $fields[4][0], 'noiseLevel' => $fields[5][0], 'amplitudeWindow' => $fields[6][0], 'clipLevel' => $fields[7][0],
        'associationWindow' => $fields[8][0], 'minStations' => $fields[9][0], 'velocity' => $fields[10][0],
        'gridX' => $fields[11], 'gridY' => $fields[12], 'gridZ' => $fields[13], 'residualLimit' => $fields[14][0],
        'qualityA' => $fields[15], 'qualityB' => $fields[16], 'cluster' => $fields[17],
        'localMagnitude' => $fields[18], 'durationMagnitude' => $fields[19], 'mapArea' => $fields[20],
        'mapSize' => $fields[21], 'section' => $fields[22], 'timeline' => $fields[23]
    ];
    return [$stations, $params];
}
