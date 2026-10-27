<?php

function readInput(): object
{
    $fields = [];
    foreach (file('input/params.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $parts = explode(' ', $line);
        $name = array_shift($parts);
        $fields[$name] = $parts;
    }
    $settings = (object) ['season' => (int) $fields['season'][0], 'holdout' => (int) $fields['holdout'][0],
        'horizon' => (int) $fields['horizon'][0], 'cvStart' => (int) $fields['cv_start'][0], 'combo' => (int) $fields['combo'][0],
        'alpha' => array_map('floatval', $fields['alpha']), 'beta' => array_map('floatval', $fields['beta']),
        'gamma' => array_map('floatval', $fields['gamma']), 'phi' => array_map('floatval', $fields['phi']),
        'maxAr' => (int) $fields['max_ar'][0], 'maxLag' => (int) $fields['max_lag'][0],
        'ljungBox' => array_map('intval', $fields['ljung_box']), 'outlier' => (float) $fields['outlier'][0],
        'interval' => array_map('floatval', $fields['interval'])];
    $series = [];
    $byName = [];
    foreach (array_slice(file('input/series.csv', FILE_IGNORE_NEW_LINES), 1) as $line) {
        [$name, $period, $value] = explode(',', $line);
        if (!isset($byName[$name])) {
            $item = (object) ['name' => $name, 'periods' => [], 'raw' => [], 'events' => []];
            $series[] = $item;
            $byName[$name] = $item;
        }
        $byName[$name]->periods[] = $period;
        $byName[$name]->raw[] = $value === 'NA' ? null : (int) $value;
    }
    foreach (array_slice(file('input/events.csv', FILE_IGNORE_NEW_LINES), 1) as $line) {
        [$name, $period, $kind] = explode(',', $line);
        $byName[$name]->events[$period] = $kind;
    }
    foreach (array_slice(file('input/inventory.csv', FILE_IGNORE_NEW_LINES), 1) as $line) {
        [$name, $onHand, $leadTime, $review, $service] = explode(',', $line);
        $byName[$name]->inventory = (object) ['onHand' => (int) $onHand, 'leadTime' => (int) $leadTime,
            'review' => (int) $review, 'service' => (float) $service];
    }
    return (object) compact('settings', 'series');
}

function nextMonth(string $period): string
{
    [$year, $month] = array_map('intval', explode('-', $period));
    if ($month === 12) {
        $year++;
        $month = 1;
    } else {
        $month++;
    }
    return sprintf('%04d-%02d', $year, $month);
}

function formatReal(float $value): string
{
    $text = number_format($value, 4, '.', '');
    return $text === '-0.0000' ? '0.0000' : $text;
}

function writeLines(string $name, array $values): void
{
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    file_put_contents('output/' . $name, $values ? implode("\n", $values) . "\n" : '');
}
