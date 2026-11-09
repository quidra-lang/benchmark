<?php

function distance(object $point, object $station): float
{
    $dx = (float) $point->x - $station->x;
    $dy = (float) $point->y - $station->y;
    $dz = (float) $point->z + $station->elevation;
    return sqrt($dx * $dx + $dy * $dy + $dz * $dz);
}

function evaluate(object $point, array $observations, float $velocity): object
{
    $distances = [];
    $residuals = [];
    $squares = 0.0;
    foreach ($observations as $observation) {
        $length = distance($point, $observation->station);
        $residual = $observation->time - $point->t0 - $length / $velocity;
        $distances[] = $length;
        $residuals[] = $residual;
        $squares += $residual * $residual;
    }
    return (object) ['distances' => $distances, 'residuals' => $residuals,
        'squares' => $squares, 'rms' => sqrt($squares / count($observations))];
}

function normalEquations(object $point, array $observations, float $velocity): object
{
    $evaluation = evaluate($point, $observations, $velocity);
    $gradients = [];
    foreach ($observations as $j => $observation) {
        $station = $observation->station;
        $denominator = $velocity * $evaluation->distances[$j];
        $gradients[] = [($point->x - $station->x) / $denominator, ($point->y - $station->y) / $denominator,
            ($point->z + $station->elevation) / $denominator, 1.0];
    }
    $matrix = array_fill(0, 4, array_fill(0, 4, 0.0));
    $rhs = array_fill(0, 4, 0.0);
    for ($a = 0; $a < 4; $a++) {
        for ($c = 0; $c < 4; $c++) {
            for ($j = 0; $j < count($observations); $j++) {
                $matrix[$a][$c] += $gradients[$j][$a] * $gradients[$j][$c];
            }
        }
        for ($j = 0; $j < count($observations); $j++) {
            $rhs[$a] += $gradients[$j][$a] * $evaluation->residuals[$j];
        }
    }
    return (object) ['matrix' => $matrix, 'rhs' => $rhs, 'evaluation' => $evaluation];
}

function cholesky(array $matrix): array
{
    $lower = array_fill(0, 4, array_fill(0, 4, 0.0));
    for ($a = 0; $a < 4; $a++) {
        for ($c = 0; $c <= $a; $c++) {
            $total = 0.0;
            for ($k = 0; $k < $c; $k++) {
                $total += $lower[$a][$k] * $lower[$c][$k];
            }
            $lower[$a][$c] = $a === $c ? sqrt($matrix[$a][$a] - $total) : ($matrix[$a][$c] - $total) / $lower[$c][$c];
        }
    }
    return $lower;
}

function solveCholesky(array $lower, array $rhs): array
{
    $forward = array_fill(0, 4, 0.0);
    for ($a = 0; $a < 4; $a++) {
        $total = 0.0;
        for ($k = 0; $k < $a; $k++) {
            $total += $lower[$a][$k] * $forward[$k];
        }
        $forward[$a] = ($rhs[$a] - $total) / $lower[$a][$a];
    }
    $solution = array_fill(0, 4, 0.0);
    for ($a = 3; $a >= 0; $a--) {
        $total = 0.0;
        for ($k = $a + 1; $k < 4; $k++) {
            $total += $lower[$k][$a] * $solution[$k];
        }
        $solution[$a] = ($forward[$a] - $total) / $lower[$a][$a];
    }
    return $solution;
}

function gridSearch(array $observations, object $params): object
{
    [$xmin, $xmax, $xstep] = $params->gridX;
    [$ymin, $ymax, $ystep] = $params->gridY;
    [$zmin, $zmax, $zstep] = $params->gridZ;
    $depths = [];
    for ($c = 0; $zmin + $c * $zstep <= $zmax; $c++) {
        $depths[] = $zmin + $c * $zstep;
    }
    $profile = array_fill(0, count($depths), null);
    $best = null;
    for ($a = 0; $xmin + $a * $xstep <= $xmax; $a++) {
        $x = $xmin + $a * $xstep;
        for ($b = 0; $ymin + $b * $ystep <= $ymax; $b++) {
            $y = $ymin + $b * $ystep;
            foreach ($depths as $index => $z) {
                $point = (object) ['x' => $x, 'y' => $y, 'z' => $z];
                $deltas = [];
                $total = 0.0;
                foreach ($observations as $observation) {
                    $delta = $observation->time - distance($point, $observation->station) / $params->velocity;
                    $deltas[] = $delta;
                    $total += $delta;
                }
                $point->t0 = $total / count($observations);
                $squares = 0.0;
                foreach ($deltas as $delta) {
                    $residual = $delta - $point->t0;
                    $squares += $residual * $residual;
                }
                if ($best === null || $squares < $best->squares) {
                    $best = (object) ['point' => $point, 'squares' => $squares];
                }
                if ($profile[$index] === null || $squares < $profile[$index]) {
                    $profile[$index] = $squares;
                }
            }
        }
    }
    foreach ($profile as &$value) {
        $value = sqrt($value / count($observations));
    }
    unset($value);
    return (object) ['point' => $best->point, 'rms' => sqrt($best->squares / count($observations)), 'profile' => $profile];
}

function geiger(object $initial, array $observations, float $velocity): object
{
    $point = clone $initial;
    $iterations = [];
    for ($iteration = 0; $iteration < 8; $iteration++) {
        $equations = normalEquations($point, $observations, $velocity);
        $delta = solveCholesky(cholesky($equations->matrix), $equations->rhs);
        $point = (object) ['x' => $point->x + $delta[0], 'y' => $point->y + $delta[1],
            'z' => max(0.0, $point->z + $delta[2]), 't0' => $point->t0 + $delta[3]];
        $evaluation = evaluate($point, $observations, $velocity);
        $iterations[] = (object) ['point' => $point, 'rms' => $evaluation->rms];
    }
    return (object) ['point' => $point, 'iterations' => $iterations, 'distances' => $evaluation->distances,
        'residuals' => $evaluation->residuals, 'squares' => $evaluation->squares, 'rms' => $evaluation->rms];
}

function locationRun(array $observations, object $params): object
{
    $grid = gridSearch($observations, $params);
    $result = geiger($grid->point, $observations, $params->velocity);
    $result->grid = $grid;
    $result->observations = $observations;
    return $result;
}

function uncertainty(object $point, array $observations, float $velocity): object
{
    $equations = normalEquations($point, $observations, $velocity);
    $lower = cholesky($equations->matrix);
    $variance = $equations->evaluation->squares / (count($observations) - 4);
    $covariance = array_fill(0, 4, array_fill(0, 4, 0.0));
    for ($c = 0; $c < 4; $c++) {
        $unit = array_fill(0, 4, 0.0);
        $unit[$c] = 1.0;
        $column = solveCholesky($lower, $unit);
        for ($a = 0; $a < 4; $a++) {
            $covariance[$a][$c] = $variance * $column[$a];
        }
    }
    $xx = $covariance[0][0];
    $yy = $covariance[1][1];
    $xy = $covariance[0][1];
    $mu = ($xx + $yy) / 2;
    $difference = ($xx - $yy) / 2;
    $rho = sqrt($difference * $difference + $xy * $xy);
    $theta = atan2(2 * $xy, $xx - $yy) / 2 * 180 / 3.141592653589793;
    $azimuth = 90 - $theta;
    if ($azimuth >= 180) {
        $azimuth -= 180;
    }
    return (object) ['smaj' => sqrt($mu + $rho), 'smin' => sqrt($mu - $rho), 'az' => $azimuth,
        'erz' => sqrt($covariance[2][2]), 'ert' => sqrt($covariance[3][3])];
}
