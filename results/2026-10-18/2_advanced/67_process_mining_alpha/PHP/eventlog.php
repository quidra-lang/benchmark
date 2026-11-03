<?php

const MONTH_LENGTHS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

function read_inputs()
{
    $lines = file('input/eventlog.csv', FILE_IGNORE_NEW_LINES);
    $rows = [];
    foreach (array_slice($lines, 1) as $i => $line) {
        [$caseId, $activity, $timestamp, $resource] = explode(',', $line);
        $rows[] = compact('caseId', 'activity', 'timestamp', 'resource') + ['line' => $i + 2];
    }
    $parameters = [];
    foreach (file('input/params.txt', FILE_IGNORE_NEW_LINES) as $line) {
        [$key, $value] = explode(' ', $line);
        $parameters[$key] = $value;
    }
    return compact('rows', 'parameters');
}

function timestamp_minutes($timestamp)
{
    $month = (int) substr($timestamp, 5, 2); $day = (int) substr($timestamp, 8, 2);
    $hour = (int) substr($timestamp, 11, 2); $minute = (int) substr($timestamp, 14, 2);
    if ($month < 1 || $month > 12 || $day < 1 || $day > MONTH_LENGTHS[$month - 1] || $hour > 23 || $minute > 59) return null;
    $days = 0;
    for ($i = 0; $i < $month - 1; $i++) $days += MONTH_LENGTHS[$i];
    return (($days + $day - 1) * 24 + $hour) * 60 + $minute;
}

function build_cases($events)
{
    $grouped = [];
    foreach ($events as $event) $grouped[$event['caseId']][] = $event;
    $ids = array_keys($grouped);
    sort($ids, SORT_STRING);
    $cases = [];
    foreach ($ids as $id) {
        $ordered = $grouped[$id];
        usort($ordered, fn($a, $b) => ($a['time'] <=> $b['time']) ?: ($a['line'] <=> $b['line']));
        $cases[] = ['id' => (string) $id, 'events' => $ordered, 'trace' => array_column($ordered, 'activity'),
            'duration' => $ordered[count($ordered) - 1]['time'] - $ordered[0]['time']];
    }
    return $cases;
}

function median($values)
{
    sort($values, SORT_NUMERIC);
    $middle = intdiv(count($values), 2);
    return count($values) % 2 === 1 ? [$values[$middle], 1] : [$values[$middle - 1] + $values[$middle], 2];
}
