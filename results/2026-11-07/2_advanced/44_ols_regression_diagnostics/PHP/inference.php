<?php

function logGammaValue($x) {
    $coefficients = [76.18009172947146, -86.50532032941677, 24.01409824083091, -1.231739572450155, 0.001208650973866179, -0.000005395239384953];
    $t = $x + 5.5;
    $adjusted = $t - ($x + 0.5) * log($t);
    $sum = 1.000000000190015;
    foreach ($coefficients as $j => $coefficient) $sum += $coefficient / ($x + $j + 1);
    return -$adjusted + log(2.5066282746310005 * $sum / $x);
}

function replaceSmall($value) {
    return abs($value) < 1e-300 ? 1e-300 : $value;
}

function betaFraction($a, $b, $x) {
    $c = 1.0;
    $d = 1 / replaceSmall(1 - ($a + $b) * $x / ($a + 1));
    $h = $d;
    for ($m = 1; $m <= 1000; $m++) {
        $q = $m * ($b - $m) * $x / (($a - 1 + 2 * $m) * ($a + 2 * $m));
        $d = 1 / replaceSmall(1 + $q * $d);
        $c = replaceSmall(1 + $q / $c);
        $h *= $d * $c;
        $q = -($a + $m) * ($a + $b + $m) * $x / (($a + 2 * $m) * ($a + 1 + 2 * $m));
        $d = 1 / replaceSmall(1 + $q * $d);
        $c = replaceSmall(1 + $q / $c);
        $delta = $d * $c;
        $h *= $delta;
        if (abs($delta - 1) < 1e-15) break;
    }
    return $h;
}

function incompleteBeta($x, $a, $b) {
    if ($x <= 0) return 0.0;
    if ($x >= 1) return 1.0;
    $factor = exp(logGammaValue($a + $b) - logGammaValue($a) - logGammaValue($b) + $a * log($x) + $b * log(1 - $x));
    return $x < ($a + 1) / ($a + $b + 2) ? $factor * betaFraction($a, $b, $x) / $a : 1 - $factor * betaFraction($b, $a, 1 - $x) / $b;
}

function incompleteGammaQ($a, $x) {
    if ($x == 0) return 1.0;
    $factor = exp(-$x + $a * log($x) - logGammaValue($a));
    if ($x < $a + 1) {
        $term = 1 / $a;
        $sum = $term;
        $exponent = $a;
        for ($i = 0; $i < 1000; $i++) {
            $exponent++;
            $term *= $x / $exponent;
            $sum += $term;
            if (abs($term) < abs($sum) * 1e-15) break;
        }
        return 1 - $sum * $factor;
    }
    $offset = $x + 1 - $a;
    $c = 1 / 1e-300;
    $d = 1 / $offset;
    $h = $d;
    for ($i = 1; $i <= 1000; $i++) {
        $q = -$i * ($i - $a);
        $offset += 2;
        $d = 1 / replaceSmall($q * $d + $offset);
        $c = replaceSmall($offset + $q / $c);
        $delta = $d * $c;
        $h *= $delta;
        if (abs($delta - 1) < 1e-15) break;
    }
    return $factor * $h;
}

function tP($value, $degrees) {
    return incompleteBeta($degrees / ($degrees + $value * $value), $degrees / 2, 0.5);
}

function fP($value, $numerator, $denominator) {
    return incompleteBeta($denominator / ($denominator + $numerator * $value), $denominator / 2, $numerator / 2);
}

function chiP($value, $degrees) {
    return incompleteGammaQ($degrees / 2, $value / 2);
}

function tQuantile($confidence, $degrees) {
    $low = 0.0;
    $high = 1000.0;
    for ($i = 0; $i < 100; $i++) {
        $middle = ($low + $high) / 2;
        if (tP($middle, $degrees) > 1 - $confidence) $low = $middle;
        else $high = $middle;
    }
    return ($low + $high) / 2;
}

function significanceMark($value) {
    if ($value === null) return '';
    if ($value < 0.001) return '***';
    if ($value < 0.01) return '**';
    if ($value < 0.05) return '*';
    return $value < 0.1 ? '.' : '';
}

function fixed($value) {
    if ($value === null) return 'NA';
    $text = sprintf('%.4F', abs($value));
    return $value < 0 && $text !== '0.0000' ? '-' . $text : $text;
}

function pValue($value) {
    return $value === null ? 'NA' : ($value < 0.0001 ? '<0.0001' : fixed($value));
}
