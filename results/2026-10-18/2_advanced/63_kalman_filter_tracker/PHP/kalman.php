<?php

function motion($kind, $t, $q)
{
    $n = $kind === 'CV' ? 4 : 6;
    $f = matIdentity($n);
    $noise = matZeros($n);
    $f[0][2] = $f[1][3] = $t;
    if ($kind === 'CV') {
        $entries = [[0, 0, $q * $t * $t * $t / 3], [0, 2, $q * $t * $t / 2], [2, 2, $q * $t]];
    } else {
        $f[0][4] = $f[1][5] = $t * $t / 2;
        $f[2][4] = $f[3][5] = $t;
        $entries = [[0, 0, $q * $t * $t * $t * $t * $t / 20], [0, 2, $q * $t * $t * $t * $t / 8],
            [0, 4, $q * $t * $t * $t / 6], [2, 2, $q * $t * $t * $t / 3],
            [2, 4, $q * $t * $t / 2], [4, 4, $q * $t]];
    }
    for ($axis = 0; $axis < 2; $axis++) {
        foreach ($entries as [$i, $j, $value]) {
            $noise[$i + $axis][$j + $axis] = $value;
            $noise[$j + $axis][$i + $axis] = $value;
        }
    }
    return ['F' => $f, 'Q' => $noise];
}

function measurementModel($size, $sigma)
{
    $h = matZeros(2, $size);
    $h[0][0] = $h[1][1] = 1.0;
    return ['H' => $h, 'R' => matDiagonal([$sigma * $sigma, $sigma * $sigma])];
}

function kalmanInitialize($kind, $measurement, $params)
{
    $x = array_merge($measurement, [0.0, 0.0]);
    $variances = [$params['SIGMA'] * $params['SIGMA'], $params['SIGMA'] * $params['SIGMA'],
        $params['INIT_VELOCITY_VARIANCE'], $params['INIT_VELOCITY_VARIANCE']];
    if ($kind === 'CA') {
        array_push($x, 0.0, 0.0);
        array_push($variances, $params['INIT_ACCELERATION_VARIANCE'], $params['INIT_ACCELERATION_VARIANCE']);
    }
    return ['x' => $x, 'P' => matDiagonal($variances)];
}

function kalmanPredict($estimate, $kind, $t, $q)
{
    $motion = motion($kind, $t, $q);
    $f = $motion['F'];
    return ['x' => matVectorProduct($f, $estimate['x']),
        'P' => matAdd(matProduct(matProduct($f, $estimate['P']), matTranspose($f)), $motion['Q']), 'F' => $f];
}

function kalmanInnovation($prediction, $measurement, $sigma)
{
    $measurementModel = measurementModel(count($prediction['x']), $sigma);
    $h = $measurementModel['H'];
    $r = $measurementModel['R'];
    $nu = vecSubtract($measurement, matVectorProduct($h, $prediction['x']));
    $s = matAdd(matProduct(matProduct($h, $prediction['P']), matTranspose($h)), $r);
    $si = matInverse($s);
    return ['nu' => $nu, 'S' => $s, 'Si' => $si, 'H' => $h, 'R' => $r, 'd2' => quadratic2($nu, $si)];
}

function kalmanUpdate($prediction, $residual)
{
    $k = matProduct(matProduct($prediction['P'], matTranspose($residual['H'])), $residual['Si']);
    $j = matSubtract(matIdentity(count($prediction['x'])), matProduct($k, $residual['H']));
    $x = vecAdd($prediction['x'], matVectorProduct($k, $residual['nu']));
    $p = matAdd(matProduct(matProduct($j, $prediction['P']), matTranspose($j)),
        matProduct(matProduct($k, $residual['R']), matTranspose($k)));
    $logLikelihood = -log(2 * M_PI) - log(determinant2($residual['S'])) / 2 - $residual['d2'] / 2;
    return ['x' => $x, 'P' => $p, 'logLikelihood' => $logLikelihood];
}

function kalmanSmooth($history)
{
    $states = array_fill(0, count($history), null);
    $last = count($history) - 1;
    $states[$last] = $history[$last]['estimate']['x'];
    for ($i = $last - 1; $i >= 0; $i--) {
        $current = $history[$i]['estimate'];
        $next = $history[$i + 1]['prediction'];
        $gain = matProduct(matProduct($current['P'], matTranspose($next['F'])), matInverse($next['P']));
        $states[$i] = vecAdd($current['x'], matVectorProduct($gain, vecSubtract($states[$i + 1], $next['x'])));
    }
    return $states;
}
