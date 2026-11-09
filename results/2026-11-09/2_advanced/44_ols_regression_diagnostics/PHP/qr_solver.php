<?php

function fit($matrix, $response, $weights, $tolerance) {
    $n = count($matrix);
    $p = count($matrix[0]);
    $roots = array_map('sqrt', $weights);
    $weighted = $working = $b = [];
    for ($i = 0; $i < $n; $i++) {
        $weighted[$i] = [];
        for ($j = 0; $j < $p; $j++) $weighted[$i][$j] = $roots[$i] * $matrix[$i][$j];
        $working[$i] = $weighted[$i];
        $b[$i] = $roots[$i] * $response[$i];
    }
    $lengths = [];
    for ($j = 0; $j < $p; $j++) {
        $sum = 0.0;
        for ($i = 0; $i < $n; $i++) $sum += $weighted[$i][$j] * $weighted[$i][$j];
        $lengths[$j] = sqrt($sum);
    }
    $accepted = [];
    $triangular = array_fill(0, $p, array_fill(0, $p, 0.0));
    for ($j = 0; $j < $p; $j++) {
        $start = count($accepted);
        $sum = 0.0;
        for ($i = $start; $i < $n; $i++) $sum += $working[$i][$j] * $working[$i][$j];
        $length = sqrt($sum);
        if ($length <= $tolerance * $lengths[$j]) continue;
        $accepted[] = $j;
        $alpha = $working[$start][$j] >= 0 ? -$length : $length;
        $vector = array_fill(0, $n, 0.0);
        $vector[$start] = $working[$start][$j] - $alpha;
        for ($i = $start + 1; $i < $n; $i++) $vector[$i] = $working[$i][$j];
        $norm = 0.0;
        for ($i = $start; $i < $n; $i++) $norm += $vector[$i] * $vector[$i];
        for ($i = 0; $i < $start; $i++) $triangular[$i][$start] = $working[$i][$j];
        $triangular[$start][$start] = $alpha;
        for ($column = $j + 1; $column < $p; $column++) {
            $projection = 0.0;
            for ($i = $start; $i < $n; $i++) $projection += $vector[$i] * $working[$i][$column];
            $delta = 2 * $projection / $norm;
            for ($i = $start; $i < $n; $i++) $working[$i][$column] -= $delta * $vector[$i];
        }
        $projection = 0.0;
        for ($i = $start; $i < $n; $i++) $projection += $vector[$i] * $b[$i];
        $delta = 2 * $projection / $norm;
        for ($i = $start; $i < $n; $i++) $b[$i] -= $delta * $vector[$i];
    }
    $rank = count($accepted);
    $effects = array_slice($b, 0, $rank);
    $coefficients = array_fill(0, $p, null);
    for ($k = $rank - 1; $k >= 0; $k--) {
        $sum = 0.0;
        for ($l = $k + 1; $l < $rank; $l++) $sum += $triangular[$k][$l] * $coefficients[$accepted[$l]];
        $coefficients[$accepted[$k]] = ($effects[$k] - $sum) / $triangular[$k][$k];
    }
    $inverse = array_fill(0, $rank, array_fill(0, $rank, 0.0));
    for ($m = 0; $m < $rank; $m++) for ($l = $rank - 1; $l >= 0; $l--) {
        $sum = 0.0;
        for ($q = $l + 1; $q < $rank; $q++) $sum += $triangular[$l][$q] * $inverse[$q][$m];
        $inverse[$l][$m] = (($l === $m ? 1.0 : 0.0) - $sum) / $triangular[$l][$l];
    }
    $variance = [];
    for ($k = 0; $k < $rank; $k++) {
        $sum = 0.0;
        for ($m = 0; $m < $rank; $m++) $sum += $inverse[$k][$m] * $inverse[$k][$m];
        $variance[] = $sum;
    }
    $u = $g = $leverage = $fitted = $residuals = $weightedResiduals = [];
    $rss = 0.0;
    for ($i = 0; $i < $n; $i++) {
        $transformed = [];
        $h = 0.0;
        for ($k = 0; $k < $rank; $k++) {
            $sum = 0.0;
            for ($m = 0; $m < $rank; $m++) $sum += $weighted[$i][$accepted[$m]] * $inverse[$m][$k];
            $transformed[] = $sum;
            $h += $sum * $sum;
        }
        $gradient = [];
        for ($k = 0; $k < $rank; $k++) {
            $sum = 0.0;
            for ($m = 0; $m < $rank; $m++) $sum += $inverse[$k][$m] * $transformed[$m];
            $gradient[] = $sum;
        }
        $prediction = 0.0;
        for ($k = 0; $k < $rank; $k++) $prediction += $matrix[$i][$accepted[$k]] * $coefficients[$accepted[$k]];
        $residual = $response[$i] - $prediction;
        $epsilon = $roots[$i] * $residual;
        $u[] = $transformed;
        $g[] = $gradient;
        $leverage[] = $h;
        $fitted[] = $prediction;
        $residuals[] = $residual;
        $weightedResiduals[] = $epsilon;
        $rss += $epsilon * $epsilon;
    }
    return compact('matrix', 'response', 'weights', 'n', 'p', 'rank', 'accepted', 'effects', 'coefficients', 'inverse', 'variance', 'u', 'g', 'leverage', 'fitted', 'residuals', 'weightedResiduals', 'rss');
}
