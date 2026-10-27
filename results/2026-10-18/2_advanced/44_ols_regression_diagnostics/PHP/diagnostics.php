<?php

function diagnose($model, $statistics, $parameters) {
    $n = $model['n'];
    $rank = $model['rank'];
    $residuals = $model['weightedResiduals'];
    $df = $statistics['df'];
    $sigma = $statistics['sigma'];
    $rows = [];
    for ($i = 0; $i < $n; $i++) {
        $h = $model['leverage'][$i];
        $z = $residuals[$i] / ($sigma * sqrt(1 - $h));
        $studentized = $z * sqrt(($df - 1) / ($df - $z * $z));
        $cooks = $z * $z * $h / ($rank * (1 - $h));
        $dffits = $studentized * sqrt($h / (1 - $h));
        $flags = '';
        if ($h > $parameters['LEVERAGE'] * $rank / $n) $flags .= 'H';
        if (abs($studentized) > $parameters['STUDENTIZED']) $flags .= 'O';
        if ($cooks > $parameters['COOK'] / $n) $flags .= 'C';
        if (abs($dffits) > $parameters['DFFITS'] * sqrt($rank / $n)) $flags .= 'F';
        $deletedSigma = $sigma * sqrt(($df - $z * $z) / ($df - 1));
        $dfbetas = [];
        for ($k = 0; $k < $rank; $k++) {
            $dfbetas[] = $model['g'][$i][$k] * $residuals[$i] / (1 - $h) / ($deletedSigma * sqrt($model['variance'][$k]));
        }
        $rows[] = ['standardized' => $z, 'studentized' => $studentized, 'cooks' => $cooks, 'dffits' => $dffits, 'flags' => $flags === '' ? '-' : $flags, 'dfbetas' => $dfbetas];
    }
    $differences = 0.0;
    for ($i = 1; $i < $n; $i++) $differences += ($residuals[$i] - $residuals[$i - 1]) * ($residuals[$i] - $residuals[$i - 1]);
    $dw = $differences / $model['rss'];
    $squares = $matrix = [];
    foreach ($model['matrix'] as $i => $row) {
        $squares[] = $residuals[$i] * $residuals[$i];
        $selected = [];
        foreach ($model['accepted'] as $j) $selected[] = $row[$j];
        $matrix[] = $selected;
    }
    $auxiliary = fit($matrix, $squares, array_fill(0, $n, 1.0), $parameters['RANK_TOL']);
    $meanSquare = array_sum($squares) / $n;
    $squareTss = 0.0;
    foreach ($squares as $value) $squareTss += ($value - $meanSquare) * ($value - $meanSquare);
    $bp = $n * (1 - $auxiliary['rss'] / $squareTss);
    $mean = array_sum($residuals) / $n;
    $second = $third = $fourth = 0.0;
    foreach ($residuals as $value) {
        $delta = $value - $mean;
        $second += $delta * $delta;
        $third += $delta * $delta * $delta;
        $fourth += $delta * $delta * $delta * $delta;
    }
    $second /= $n;
    $third /= $n;
    $fourth /= $n;
    $skewness = $third / ($second * sqrt($second));
    $kurtosis = $fourth / ($second * $second);
    $jb = $n / 6 * ($skewness * $skewness + ($kurtosis - 3) * ($kurtosis - 3) / 4);
    return ['rows' => $rows, 'dw' => $dw, 'bp' => ['value' => $bp, 'df' => $auxiliary['rank'] - 1, 'p' => chiP($bp, $auxiliary['rank'] - 1)], 'jb' => ['value' => $jb, 'p' => chiP($jb, 2), 'skewness' => $skewness, 'kurtosis' => $kurtosis]];
}
