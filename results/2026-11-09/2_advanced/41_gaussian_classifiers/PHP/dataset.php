<?php

function read_lines($path)
{
    return file($path, FILE_IGNORE_NEW_LINES);
}

function read_dataset()
{
    $training = read_lines('input/train.csv');
    $testing = read_lines('input/test.csv');
    $features = array_slice(explode(',', $training[0]), 1, -1);
    $readRows = function ($lines) {
        $rows = [];
        foreach (array_slice($lines, 1) as $line) {
            $parts = explode(',', $line);
            $rows[] = [
                'id' => (int) $parts[0],
                'values' => array_map('floatval', array_slice($parts, 1, -1)),
                'label' => $parts[count($parts) - 1]
            ];
        }
        return $rows;
    };
    $train = $readRows($training);
    $test = $readRows($testing);
    $classes = array_values(array_unique(array_column($train, 'label')));
    sort($classes, SORT_STRING);
    $classNumbers = array_flip($classes);
    foreach ($train as &$row) $row['class'] = $classNumbers[$row['label']];
    unset($row);
    foreach ($test as &$row) $row['class'] = $classNumbers[$row['label']];
    unset($row);
    $costLines = read_lines('input/costs.csv');
    $costClasses = array_flip(array_slice(explode(',', $costLines[0]), 1));
    $costs = array_fill(0, count($classes), []);
    foreach (array_slice($costLines, 1) as $line) {
        $parts = explode(',', $line);
        $row = [];
        foreach ($classes as $name) $row[] = (float) $parts[$costClasses[$name] + 1];
        $costs[$classNumbers[$parts[0]]] = $row;
    }
    $settings = ['subsets' => [], 'pairs' => []];
    $featureNumbers = array_flip($features);
    foreach (read_lines('input/params.txt') as $line) {
        $parts = explode(' ', $line);
        $keyword = array_shift($parts);
        switch ($keyword) {
            case 'PRIOR': $settings['prior'] = $parts[0]; break;
            case 'VAR_SMOOTHING': $settings['epsilon'] = (float) $parts[0]; break;
            case 'SMOOTHING_GRID': $settings['smoothingGrid'] = array_map('floatval', $parts); break;
            case 'QDA_GAMMA': $settings['gamma'] = (float) $parts[0]; break;
            case 'GAMMA_GRID': $settings['gammaGrid'] = array_map('floatval', $parts); break;
            case 'CV_FOLDS': $settings['folds'] = (int) $parts[0]; break;
            case 'CALIBRATION_EDGES': $settings['calibration'] = array_map('floatval', $parts); break;
            case 'REJECT_THRESHOLDS': $settings['reject'] = array_map('floatval', $parts); break;
            case 'CURVE': $settings['curve'] = array_map('intval', $parts); break;
            case 'OUTLIER_THRESHOLD': $settings['outlier'] = (float) $parts[0]; break;
            case 'BOOTSTRAP':
                $settings['resamples'] = (int) $parts[0];
                $settings['seed'] = (int) $parts[1];
                break;
            case 'MAP_SIZE':
                $settings['width'] = (int) $parts[0];
                $settings['height'] = (int) $parts[1];
                break;
            case 'PLOT_SIZE':
                $settings['plotWidth'] = (int) $parts[0];
                $settings['plotHeight'] = (int) $parts[1];
                break;
            case 'SUBSET':
                $name = array_shift($parts);
                $settings['subsets'][] = ['name' => $name, 'features' => array_map(fn($feature) => $featureNumbers[$feature], $parts)];
                break;
            case 'PAIR':
                $settings['pairs'][] = array_map(fn($feature) => $featureNumbers[$feature], $parts);
                break;
        }
    }
    return compact('features', 'classes', 'train', 'test', 'costs', 'settings');
}
