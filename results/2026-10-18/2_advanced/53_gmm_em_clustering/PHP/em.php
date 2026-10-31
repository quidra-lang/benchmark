<?php

function adjust($initial, $type) {
    $components = $initial;
    if ($type === 'TIED') {
        $a = $b = $c = 0.0;
        foreach ($components as $component) {
            $a += $component['w'] * $component['a'];
            $b += $component['w'] * $component['b'];
            $c += $component['w'] * $component['c'];
        }
        foreach ($components as &$component) {
            $component['a'] = $a;
            $component['b'] = $b;
            $component['c'] = $c;
        }
        unset($component);
    } elseif ($type === 'DIAG') {
        foreach ($components as &$component) $component['b'] = 0.0;
        unset($component);
    } elseif ($type === 'SPHERICAL') {
        foreach ($components as &$component) {
            $v = ($component['a'] + $component['c']) / 2;
            $component['a'] = $v;
            $component['b'] = 0.0;
            $component['c'] = $v;
        }
        unset($component);
    }
    return $components;
}

function expectation($points, $components) {
    $responsibilities = $logDensities = [];
    $loglik = 0.0;
    foreach ($points as $point) {
        $logs = [];
        foreach ($components as $component) $logs[] = logWeighted($point, $component);
        $maximum = max($logs);
        $exponents = [];
        $total = 0.0;
        foreach ($logs as $value) {
            $exponents[] = exp($value - $maximum);
            $total += $exponents[count($exponents) - 1];
        }
        $row = [];
        foreach ($exponents as $value) $row[] = $value / $total;
        $responsibilities[] = $row;
        $lp = $maximum + log($total);
        $logDensities[] = $lp;
        $loglik += $lp;
    }
    return compact('responsibilities', 'logDensities', 'loglik');
}

function maximization($points, $responsibilities, $type, $eps) {
    $components = $moments = [];
    $K = count($responsibilities[0]);
    $n = count($points);
    for ($k = 0; $k < $K; $k++) {
        $count = $sx = $sy = 0.0;
        foreach ($points as $i => $point) {
            $r = $responsibilities[$i][$k];
            $count += $r;
            $sx += $r * $point['x'];
            $sy += $r * $point['y'];
        }
        $mx = $sx / $count;
        $my = $sy / $count;
        $A = $B = $C = 0.0;
        foreach ($points as $i => $point) {
            $r = $responsibilities[$i][$k];
            $dx = $point['x'] - $mx;
            $dy = $point['y'] - $my;
            $A += $r * $dx * $dx;
            $B += $r * $dx * $dy;
            $C += $r * $dy * $dy;
        }
        $moments[] = [$A, $B, $C];
        $component = ['w' => $count / $n, 'mx' => $mx, 'my' => $my];
        if ($type === 'FULL') {
            $component += ['a' => $A / $count + $eps, 'b' => $B / $count, 'c' => $C / $count + $eps];
        } elseif ($type === 'DIAG') {
            $component += ['a' => $A / $count + $eps, 'b' => 0.0, 'c' => $C / $count + $eps];
        } elseif ($type === 'SPHERICAL') {
            $v = ($A / $count + $C / $count) / 2 + $eps;
            $component += ['a' => $v, 'b' => 0.0, 'c' => $v];
        }
        $components[] = $component;
    }
    if ($type === 'TIED') {
        $A = $B = $C = 0.0;
        foreach ($moments as $moment) {
            $A += $moment[0];
            $B += $moment[1];
            $C += $moment[2];
        }
        foreach ($components as &$component) $component += ['a' => $A / $n + $eps, 'b' => $B / $n, 'c' => $C / $n + $eps];
        unset($component);
    }
    return $components;
}

function emFit($points, $initial, $type, $iterations, $eps) {
    $components = adjust($initial, $type);
    $step = expectation($points, $components);
    $trace = [$step['loglik']];
    for ($iteration = 1; $iteration <= $iterations; $iteration++) {
        $components = maximization($points, $step['responsibilities'], $type, $eps);
        $step = expectation($points, $components);
        $trace[] = $step['loglik'];
    }
    return array_merge(['components' => $components, 'trace' => $trace], $step);
}
