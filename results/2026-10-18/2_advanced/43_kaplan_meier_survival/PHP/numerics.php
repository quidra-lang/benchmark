<?php

const Z = 1.959963984540054;

function solve($matrix, $vector)
{
    $a = $matrix;
    $b = $vector;
    $m = count($b);
    for ($k = 0; $k < $m; $k++) {
        for ($i = $k + 1; $i < $m; $i++) {
            $factor = $a[$i][$k] / $a[$k][$k];
            for ($j = $k; $j < $m; $j++) {
                $a[$i][$j] -= $factor * $a[$k][$j];
            }
            $b[$i] -= $factor * $b[$k];
        }
    }
    $x = array_fill(0, $m, 0.0);
    for ($i = $m - 1; $i >= 0; $i--) {
        $value = $b[$i];
        for ($j = $i + 1; $j < $m; $j++) {
            $value -= $a[$i][$j] * $x[$j];
        }
        $x[$i] = $value / $a[$i][$i];
    }
    return $x;
}

function inverse($matrix)
{
    $m = count($matrix);
    $result = array_fill(0, $m, array_fill(0, $m, 0.0));
    for ($c = 0; $c < $m; $c++) {
        $unit = array_fill(0, $m, 0.0);
        $unit[$c] = 1.0;
        $column = solve($matrix, $unit);
        for ($r = 0; $r < $m; $r++) {
            $result[$r][$c] = $column[$r];
        }
    }
    return $result;
}

function logGammaValue($a)
{
    $coefficients = [76.18009172947146, -86.50532032941677, 24.01409824083091,
        -1.231739572450155, 0.001208650973866179, -0.000005395239384953];
    $xi0 = $a + 5.5;
    $xi1 = $xi0 - ($a + 0.5) * log($xi0);
    $sigma = 1.000000000190015;
    $y = $a;
    foreach ($coefficients as $coefficient) {
        $y += 1;
        $sigma += $coefficient / $y;
    }
    return -$xi1 + log(2.5066282746310005 * $sigma / $a);
}

function upperGamma($a, $x)
{
    if ($x == 0) {
        return 1.0;
    }
    $prefactor = exp(-$x + $a * log($x) - logGammaValue($a));
    if ($x < $a + 1) {
        $alpha = $a;
        $xi = 1 / $a;
        $sigma = $xi;
        for ($i = 0; $i < 1000; $i++) {
            $alpha += 1;
            $xi *= $x / $alpha;
            $sigma += $xi;
            if (abs($xi) < abs($sigma) * 1e-15) {
                break;
            }
        }
        return 1 - $sigma * $prefactor;
    }
    $epsilon = 1e-300;
    $b = $x + 1 - $a;
    $c = 1 / $epsilon;
    $d = 1 / $b;
    $h = $d;
    for ($i = 1; $i <= 1000; $i++) {
        $an = -$i * ($i - $a);
        $b += 2;
        $d = $an * $d + $b;
        if (abs($d) < $epsilon) {
            $d = $epsilon;
        }
        $c = $b + $an / $c;
        if (abs($c) < $epsilon) {
            $c = $epsilon;
        }
        $d = 1 / $d;
        $delta = $d * $c;
        $h *= $delta;
        if (abs($delta - 1) < 1e-15) {
            break;
        }
    }
    return $prefactor * $h;
}

function chiSquareP($chisq, $degrees)
{
    return upperGamma($degrees / 2, $chisq / 2);
}
