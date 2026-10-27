<?php

function riskSets($subjects)
{
    $counts = [];
    foreach ($subjects as $subject) {
        $time = $subject['time'];
        if (!isset($counts[$time])) {
            $counts[$time] = ['events' => 0, 'censored' => 0];
        }
        $key = $subject['event'] === 1 ? 'events' : 'censored';
        $counts[$time][$key]++;
    }
    ksort($counts, SORT_NUMERIC);
    $rows = [];
    $atRisk = count($subjects);
    foreach ($counts as $time => $count) {
        $rows[] = ['time' => $time, 'atRisk' => $atRisk,
            'events' => $count['events'], 'censored' => $count['censored']];
        $atRisk -= $count['events'] + $count['censored'];
    }
    return $rows;
}

function kaplanMeier($subjects)
{
    $events = array_values(array_filter(riskSets($subjects), fn($row) => $row['events'] > 0));
    $rows = [];
    $survival = 1.0;
    $greenwood = 0.0;
    $cumHazard = 0.0;
    $hazardVariance = 0.0;
    foreach ($events as $i => $event) {
        $time = $event['time'];
        $n = $event['atRisk'];
        $d = $event['events'];
        $survival *= ($n - $d) / $n;
        if ($n === $d || $greenwood === null) {
            $greenwood = null;
        } else {
            $greenwood += $d / ($n * ($n - $d));
        }
        $stdErr = $lower = $upper = null;
        if ($survival != 0) {
            $root = sqrt($greenwood);
            $stdErr = $survival * $root;
            $logarithm = log($survival);
            $omega = Z * $root / (-$logarithm);
            $lower = exp($logarithm * exp($omega));
            $upper = exp($logarithm * exp(-$omega));
        }
        $cumHazard += $d / $n;
        $hazardVariance += $d / ($n * $n);
        $censored = 0;
        foreach ($subjects as $subject) {
            if ($subject['event'] === 0 && $subject['time'] >= $time &&
                ($i + 1 === count($events) || $subject['time'] < $events[$i + 1]['time'])) {
                $censored++;
            }
        }
        $rows[] = ['time' => $time, 'atRisk' => $n, 'events' => $d, 'censored' => $censored,
            'survival' => $survival, 'stdErr' => $stdErr, 'lower' => $lower, 'upper' => $upper,
            'cumHazard' => $cumHazard, 'hazardSe' => sqrt($hazardVariance)];
    }
    return $rows;
}

function rowAt($rows, $time)
{
    $result = ['survival' => 1.0, 'stdErr' => 0.0, 'lower' => null,
        'upper' => null, 'cumHazard' => 0.0, 'hazardSe' => 0.0];
    foreach ($rows as $row) {
        if ($row['time'] > $time) {
            break;
        }
        $result = $row;
    }
    return $result;
}

function lifeTable($subjects, $width, $count)
{
    $rows = [];
    $survival = 1.0;
    $greenwood = 0.0;
    for ($i = 0; $i < $count; $i++) {
        $start = $i * $width;
        $end = ($i + 1) * $width;
        $atRisk = $events = $withdrawn = 0;
        foreach ($subjects as $subject) {
            if ($subject['time'] >= $start) {
                $atRisk++;
            }
            if ($subject['time'] >= $start && $subject['time'] < $end) {
                if ($subject['event'] === 1) {
                    $events++;
                } else {
                    $withdrawn++;
                }
            }
        }
        $f = 2 * $atRisk - $withdrawn;
        $q = (2 * $events) / $f;
        $survival *= ($f - 2 * $events) / $f;
        $greenwood += (4 * $events) / ($f * ($f - 2 * $events));
        $rows[] = ['start' => $start, 'end' => $end, 'atRisk' => $atRisk,
            'events' => $events, 'withdrawn' => $withdrawn, 'exposed' => $f / 2,
            'q' => $q, 'survival' => $survival, 'stdErr' => $survival * sqrt($greenwood),
            'hazard' => (2000 * $events) / ($width * ($f - $events))];
    }
    return $rows;
}
