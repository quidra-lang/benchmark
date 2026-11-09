<?php

function hundredths(string $text): int
{
    return (int) str_replace('.', '', $text);
}

function readInput(): object
{
    $fields = [];
    foreach (file('input/params.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $parts = explode(' ', $line);
        $name = array_shift($parts);
        $fields[$name] = $parts;
    }
    $decimalCandidates = fn($name) => array_map(function ($text) {
        $integer = hundredths($text);
        return (object) ['text' => $text, 'hundredths' => $integer, 'value' => $integer / 100];
    }, $fields[$name]);
    $settings = (object) [
        'windows' => array_map(fn($text) => (object) ['text' => $text, 'value' => (int) $text], $fields['WINDOWS']),
        'kernels' => $fields['KERNELS'], 'bandwidths' => $decimalCandidates('BANDWIDTHS'),
        'degrees' => array_map('intval', $fields['LOESS_DEGREES']), 'spans' => $decimalCandidates('SPANS'),
        'robustIterations' => (int) $fields['ROBUST_ITERATIONS'][0],
        'lambdas' => array_map(fn($text) => (object) ['text' => $text, 'value' => (float) $text], $fields['LAMBDAS']),
        'folds' => (int) $fields['CV_FOLDS'][0], 'directions' => $fields['ISOTONIC'],
        'gridPoints' => (int) $fields['GRID_POINTS'][0], 'bandZ' => (float) $fields['BAND_Z'][0],
        'bandMethods' => $fields['BAND_METHODS'], 'threshold' => hundredths($fields['OUTLIER_THRESHOLD'][0]),
        'bootstrap' => (int) $fields['BOOTSTRAP'][0], 'trim' => (int) $fields['BOOTSTRAP'][1],
        'seed' => (int) $fields['BOOTSTRAP'][2], 'plotSeries' => $fields['PLOT_SERIES'],
        'plotMethods' => $fields['PLOT_METHODS'], 'width' => (int) $fields['PLOT_SIZE'][0], 'height' => (int) $fields['PLOT_SIZE'][1]
    ];
    $byName = [];
    foreach (array_slice(file('input/series.csv', FILE_IGNORE_NEW_LINES), 1) as $line) {
        [$name, $rawX, $rawY] = explode(',', $line);
        if (!isset($byName[$name])) {
            $byName[$name] = (object) ['name' => $name, 'points' => []];
        }
        $X = hundredths($rawX);
        $Y = hundredths($rawY);
        $byName[$name]->points[] = (object) ['X' => $X, 'Y' => $Y, 'x' => $X / 100, 'y' => $Y / 100];
    }
    $series = array_values($byName);
    foreach ($series as $index => $item) {
        usort($item->points, fn($a, $b) => $a->X <=> $b->X);
        $item->mode = $settings->directions[$index];
    }
    $tests = [];
    foreach (array_slice(file('input/test_points.csv', FILE_IGNORE_NEW_LINES), 1) as $line) {
        [$name, $rawX] = explode(',', $line);
        $tests[] = (object) ['name' => $name, 'X' => hundredths($rawX)];
    }
    return (object) compact('settings', 'series', 'tests');
}
