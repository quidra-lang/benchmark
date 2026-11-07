<?php

const FFT_PI = 3.141592653589793;

function rot($angle)
{
    return [cos($angle), -sin($angle)];
}

function conjugate($value)
{
    return [$value[0], -$value[1]];
}

function multiply($a, $b)
{
    return [$a[0] * $b[0] - $a[1] * $b[1], $a[0] * $b[1] + $a[1] * $b[0]];
}

function squared($value)
{
    return $value[0] * $value[0] + $value[1] * $value[1];
}

function magnitude($value)
{
    return sqrt(squared($value));
}

function phase($value)
{
    return atan2($value[1], $value[0]);
}

function isPowerOfTwo($value)
{
    return ($value & ($value - 1)) === 0;
}

function asComplex($values, $length = null)
{
    $length = $length ?? count($values);
    $result = [];
    for ($i = 0; $i < $length; $i++) {
        $result[] = [$values[$i] ?? 0.0, 0.0];
    }
    return $result;
}

function pow2($minimum)
{
    $length = 1;
    while ($length < $minimum) {
        $length *= 2;
    }
    return $length;
}

function radix2($input, $inverse = false)
{
    $values = $input;
    $length = count($values);
    $bits = 0;
    for ($size = $length; $size > 1; $size = intdiv($size, 2)) {
        $bits++;
    }
    for ($n = 1; $n < $length; $n++) {
        $original = $n;
        $reversed = 0;
        for ($bit = 0; $bit < $bits; $bit++) {
            $reversed = 2 * $reversed + $original % 2;
            $original = intdiv($original, 2);
        }
        if ($n < $reversed) {
            [$values[$n], $values[$reversed]] = [$values[$reversed], $values[$n]];
        }
    }
    $twiddles = [];
    for ($k = 0; $k < intdiv($length, 2); $k++) {
        $value = rot(2 * FFT_PI * $k / $length);
        $twiddles[] = $inverse ? conjugate($value) : $value;
    }
    for ($size = 2; $size <= $length; $size *= 2) {
        $half = intdiv($size, 2);
        $stride = intdiv($length, $size);
        for ($block = 0; $block < $length; $block += $size) {
            for ($j = 0; $j < $half; $j++) {
                $t = multiply($twiddles[$j * $stride], $values[$block + $j + $half]);
                $u = $values[$block + $j];
                $values[$block + $j] = [$u[0] + $t[0], $u[1] + $t[1]];
                $values[$block + $j + $half] = [$u[0] - $t[0], $u[1] - $t[1]];
            }
        }
    }
    if ($inverse) {
        foreach ($values as &$value) {
            $value = [$value[0] / $length, $value[1] / $length];
        }
        unset($value);
    }
    return $values;
}

function bluestein($input)
{
    $length = count($input);
    $size = pow2(2 * $length - 1);
    $chirp = [];
    $a = asComplex([], $size);
    $b = asComplex([], $size);
    for ($n = 0; $n < $length; $n++) {
        $chirp[] = rot(FFT_PI * (($n * $n) % (2 * $length)) / $length);
        $a[$n] = multiply($input[$n], $chirp[$n]);
        $b[$n] = conjugate($chirp[$n]);
        if ($n > 0) {
            $b[$size - $n] = conjugate($chirp[$n]);
        }
    }
    $first = radix2($a);
    $second = radix2($b);
    $product = [];
    foreach ($first as $k => $value) {
        $product[] = multiply($value, $second[$k]);
    }
    $convolution = radix2($product, true);
    $result = [];
    foreach ($chirp as $k => $value) {
        $result[] = multiply($value, $convolution[$k]);
    }
    return $result;
}

function dft($input)
{
    return isPowerOfTwo(count($input)) ? radix2($input) : bluestein($input);
}

function idft($input)
{
    if (isPowerOfTwo(count($input))) {
        return radix2($input, true);
    }
    $transformed = bluestein(array_map('conjugate', $input));
    $length = count($input);
    return array_map(fn($value) => [$value[0] / $length, -$value[1] / $length], $transformed);
}

function packedFFT($values)
{
    $length = count($values);
    $half = intdiv($length, 2);
    $packed = [];
    for ($j = 0; $j < $half; $j++) {
        $packed[] = [$values[2 * $j], $values[2 * $j + 1]];
    }
    $transformed = radix2($packed);
    $result = [];
    for ($k = 0; $k <= $half; $k++) {
        $a = $transformed[$k % $half];
        $b = conjugate($transformed[($half - $k) % $half]);
        $even = [($a[0] + $b[0]) / 2, ($a[1] + $b[1]) / 2];
        $odd = [($a[1] - $b[1]) / 2, -($a[0] - $b[0]) / 2];
        $term = multiply(rot(2 * FFT_PI * $k / $length), $odd);
        $result[] = [$even[0] + $term[0], $even[1] + $term[1]];
    }
    return $result;
}

function convolution($first, $second)
{
    $count = count($first) + count($second) - 1;
    $length = pow2($count);
    $a = radix2(asComplex($first, $length));
    $b = radix2(asComplex($second, $length));
    $product = [];
    foreach ($a as $k => $value) {
        $product[] = multiply($value, $b[$k]);
    }
    $inverse = radix2($product, true);
    $result = [];
    for ($i = 0; $i < $count; $i++) {
        $result[] = $inverse[$i][0];
    }
    return $result;
}

function chirpZ($values, $start, $step, $count, $sampleRate)
{
    $length = pow2(count($values) + $count - 1);
    $a = asComplex([], $length);
    $b = asComplex([], $length);
    for ($n = 0; $n < count($values); $n++) {
        $shifted = multiply([$values[$n], 0.0], rot(2 * FFT_PI * $start * $n / $sampleRate));
        $a[$n] = multiply($shifted, rot(FFT_PI * $step * ($n * $n) / $sampleRate));
    }
    for ($m = -(count($values) - 1); $m < $count; $m++) {
        $b[$m < 0 ? $m + $length : $m] = conjugate(rot(FFT_PI * $step * ($m * $m) / $sampleRate));
    }
    $first = radix2($a);
    $second = radix2($b);
    $product = [];
    foreach ($first as $k => $value) {
        $product[] = multiply($value, $second[$k]);
    }
    $transformed = radix2($product, true);
    $result = [];
    for ($j = 0; $j < $count; $j++) {
        $result[] = multiply(rot(FFT_PI * $step * ($j * $j) / $sampleRate), $transformed[$j]);
    }
    return $result;
}
