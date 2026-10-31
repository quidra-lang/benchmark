<?php

function inputLines($name) {
    return file('input/' . $name, FILE_IGNORE_NEW_LINES);
}

function absoluteMinute($datetime) {
    $date = DateTimeImmutable::createFromFormat('!Y-m-d H:i', $datetime, new DateTimeZone('UTC'));
    return intdiv($date->getTimestamp(), 60);
}

function datetime($epoch, $minute) {
    return gmdate('Y-m-d H:i', ($epoch + $minute) * 60);
}

function hourDatetime($epoch, $hour) {
    return datetime($epoch, $hour * 60);
}

function dayDate($epoch, $day) {
    return gmdate('Y-m-d', ($epoch + $day * 1440) * 60);
}

function readParams() {
    $source = inputLines('params.txt');
    $params = (object)['epoch' => absoluteMinute(substr($source[0], 6)), 'stations' => []];
    $index = 1;
    while (str_starts_with($source[$index], 'station ')) {
        $params->stations[] = (object)['code' => substr($source[$index], 8, 3), 'name' => substr($source[$index], 12)];
        $index++;
    }
    $next = function() use ($source, &$index) { return explode(' ', $source[$index++]); };
    $params->reference = $next()[1];
    $params->flatRun = (int)$next()[1];
    $spike = $next();
    $params->spike = (object)['window' => (int)$spike[1], 'count' => (int)$spike[2], 'factor' => (float)$spike[3], 'minimum' => (float)$spike[4]];
    $params->rayleigh = (float)$next()[1];
    $params->snrMin = (float)$next()[1];
    $params->topResiduals = (int)$next()[1];
    $surge = $next();
    $params->surge = (object)['threshold' => (float)$surge[1], 'hours' => (int)$surge[2]];
    $prediction = $next();
    $params->start = intdiv(absoluteMinute($prediction[1] . ' ' . $prediction[2]) - $params->epoch, 60);
    $params->hours = (int)$prediction[3];
    $params->grid = (int)$next()[1];
    $params->minRange = (float)$next()[1];
    $params->correlationLag = (int)$next()[1];
    $plot = $next();
    $params->plot = (object)['code' => $plot[1], 'hours' => (int)$plot[2], 'top' => (int)$plot[3], 'bottom' => (int)$plot[4], 'step' => (int)$plot[5]];
    return $params;
}

function readAll() {
    $params = readParams();
    $source = inputLines('constituents.txt');
    $constituents = [];
    for ($i = 1; $i <= (int)$source[0]; $i++) {
        [$name, $speed] = explode(' ', $source[$i]);
        $constituents[] = (object)['name' => $name, 'speed' => (float)$speed];
    }
    $observations = [];
    foreach ($params->stations as $station) $observations[$station->code] = [];
    foreach (array_slice(inputLines('observations.csv'), 1) as $line) {
        [$code, $time, $level] = explode(',', $line);
        $observations[$code][] = (object)['time' => intdiv(absoluteMinute($time) - $params->epoch, 60),
            'value' => $level === 'NA' ? null : (float)$level, 'milli' => $level === 'NA' ? null : (int)str_replace('.', '', $level)];
    }
    return compact('params', 'constituents', 'observations');
}
