<?php

function readRows(array $lines): array
{
    $rows = [];
    foreach (array_slice($lines, 1) as $line) {
        $values = explode(',', $line);
        $id = array_shift($values);
        $rows[] = ['id' => $id, 'values' => array_map(fn($v) => $v === 'NA' ? null : (float)$v, $values)];
    }
    return $rows;
}

function readDataset(): array
{
    $lines = file('input/data.csv', FILE_IGNORE_NEW_LINES);
    $names = array_slice(explode(',', $lines[0]), 1);
    $settings = [];
    foreach (file('input/params.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $values = explode(' ', $line);
        $keyword = array_shift($values);
        switch ($keyword) {
            case 'MISSING': $settings['missing'] = $values[0]; break;
            case 'SCALING': $settings['scaling'] = $values[0]; break;
            case 'COMPONENTS': $settings['components'] = $values[0]; break;
            case 'CUMULATIVE_TARGET': $settings['target'] = (float)$values[0]; break;
            case 'PARALLEL': $settings['parallel'] = (int)$values[0]; $settings['seed'] = (int)$values[1]; break;
            case 'T2_LIMIT': $settings['t2Limit'] = (float)$values[0]; break;
            case 'SPE_LIMIT': $settings['speLimit'] = (float)$values[0]; break;
            case 'VARIMAX_CYCLES': $settings['cycles'] = (int)$values[0]; break;
            case 'TOP_ROWS': $settings['top'] = (int)$values[0]; break;
            case 'SCREE_WIDTH': $settings['screeWidth'] = (int)$values[0]; break;
            case 'BIPLOT_SIZE': $settings['biplotWidth'] = (int)$values[0]; $settings['biplotHeight'] = (int)$values[1]; break;
            case 'CIRCLE_RADIUS': $settings['radius'] = (int)$values[0]; break;
            case 'DIAGNOSTIC_SIZE': $settings['diagnosticWidth'] = (int)$values[0]; $settings['diagnosticHeight'] = (int)$values[1]; break;
        }
    }
    return ['names' => $names, 'rows' => readRows($lines),
        'supplementary' => readRows(file('input/supplementary.csv', FILE_IGNORE_NEW_LINES)), 'settings' => $settings];
}
