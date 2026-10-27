<?php

function read_lines($path)
{
    return file($path, FILE_IGNORE_NEW_LINES);
}

function read_examples($path, $multiclass = false)
{
    $rows = [];
    foreach (array_slice(read_lines($path), 1) as $line) {
        $fields = explode(',', $line);
        $row = ['id' => $fields[0], 'point' => [(float) $fields[1], (float) $fields[2]]];
        if ($multiclass) { $row['class'] = (int) $fields[3]; $row['role'] = $fields[4]; }
        else $row['label'] = (int) $fields[3];
        $rows[] = $row;
    }
    return $rows;
}

function read_dataset()
{
    $params = ['kernels' => []];
    foreach (read_lines('input/params.txt') as $line) {
        $values = explode(' ', $line);
        $key = array_shift($values);
        switch ($key) {
            case 'C_GRID': $params['cs'] = array_map('floatval', $values); break;
            case 'KERNEL':
                $kernel = ['name' => $values[0], 'kind' => $values[1], 'index' => count($params['kernels'])];
                if ($kernel['kind'] === 'poly') { $kernel['degree'] = (int) $values[2]; $kernel['gamma'] = (float) $values[3]; $kernel['coef0'] = (float) $values[4]; }
                elseif ($kernel['kind'] === 'rbf') $kernel['gamma'] = (float) $values[2];
                $params['kernels'][] = $kernel;
                break;
            case 'TOLERANCE': $params['tau'] = (float) $values[0]; break;
            case 'EPS': $params['eps'] = (float) $values[0]; break;
            case 'MAX_PASSES': $params['maxPasses'] = (int) $values[0]; break;
            case 'FOLDS': $params['folds'] = (int) $values[0]; break;
            case 'LEARNING_CURVE': $params['learningCurve'] = array_map('intval', $values); break;
            case 'NEWTON_ITERATIONS': $params['newtonIterations'] = (int) $values[0]; break;
            case 'MULTICLASS': $params['multiName'] = $values[0]; $params['multiC'] = (float) $values[1]; break;
            case 'PEGASOS': $params['pegasos'] = ['lambda' => (float) $values[0], 'iterations' => (int) $values[1], 'seed' => (int) $values[2]]; break;
            case 'PLOT_X': $params['xMin'] = (float) $values[0]; $params['xMax'] = (float) $values[1]; break;
            case 'PLOT_Y': $params['yMin'] = (float) $values[0]; $params['yMax'] = (float) $values[1]; break;
            case 'PLOT_SIZE': $params['width'] = (int) $values[0]; $params['height'] = (int) $values[1]; break;
        }
    }
    $multiTrain = [];
    $multiTest = [];
    foreach (read_examples('input/multiclass.csv', true) as $row) {
        if ($row['role'] === 'train') $multiTrain[] = $row;
        else $multiTest[] = $row;
    }
    return ['train' => read_examples('input/train.csv'), 'test' => read_examples('input/test.csv'),
        'multiTrain' => $multiTrain, 'multiTest' => $multiTest, 'params' => $params];
}
