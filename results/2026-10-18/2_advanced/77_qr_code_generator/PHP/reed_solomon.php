<?php

function gfTables(): array
{
    static $powers = null;
    static $logarithms = null;
    if ($powers === null) {
        $powers = array_fill(0, 255, 0);
        $logarithms = array_fill(0, 256, 0);
        $element = 1;
        for ($i = 0; $i < 255; $i++) {
            $powers[$i] = $element;
            $logarithms[$element] = $i;
            $element *= 2;
            if ($element >= 256) {
                $element ^= 0x11d;
            }
        }
    }
    return [$powers, $logarithms];
}

function alpha(int $exponent): int
{
    [$powers] = gfTables();
    return $powers[($exponent % 255 + 255) % 255];
}

function gfMultiply(int $a, int $b): int
{
    if ($a === 0 || $b === 0) {
        return 0;
    }
    [$powers, $logarithms] = gfTables();
    return $powers[($logarithms[$a] + $logarithms[$b]) % 255];
}

function gfDivide(int $a, int $b): int
{
    if ($a === 0) {
        return 0;
    }
    [$powers, $logarithms] = gfTables();
    return $powers[($logarithms[$a] - $logarithms[$b] + 255) % 255];
}

function generator(int $degree): array
{
    $polynomial = [1];
    for ($i = 0; $i < $degree; $i++) {
        $next = array_fill(0, count($polynomial) + 1, 0);
        foreach ($polynomial as $j => $value) {
            $next[$j] ^= $value;
            $next[$j + 1] ^= gfMultiply($value, alpha($i));
        }
        $polynomial = $next;
    }
    return $polynomial;
}

function rsEncode(array $data, int $degree): array
{
    $polynomial = generator($degree);
    $work = array_merge($data, array_fill(0, $degree, 0));
    for ($i = 0; $i < count($data); $i++) {
        $coefficient = $work[$i];
        for ($j = 0; $j <= $degree; $j++) {
            $work[$i + $j] ^= gfMultiply($coefficient, $polynomial[$j]);
        }
    }
    return array_slice($work, count($data));
}

function syndromes(array $codewords, int $degree): array
{
    $result = [];
    for ($j = 0; $j < $degree; $j++) {
        $value = 0;
        foreach ($codewords as $codeword) {
            $value = gfMultiply($value, alpha($j)) ^ $codeword;
        }
        $result[] = $value;
    }
    return $result;
}

function gfEvaluate(array $coefficients, int $value): int
{
    $result = 0;
    for ($i = count($coefficients) - 1; $i >= 0; $i--) {
        $result = gfMultiply($result, $value) ^ $coefficients[$i];
    }
    return $result;
}

function rsCorrect(array $received, int $degree): object
{
    $original = syndromes($received, $degree);
    $failure = fn() => (object) ['status' => 'failed', 'syndromes' => $original, 'positions' => [], 'codewords' => $received];
    if (count(array_filter($original, fn($value) => $value !== 0)) === 0) {
        return (object) ['status' => 'ok', 'syndromes' => $original, 'positions' => [], 'codewords' => $received];
    }
    $locator = [1];
    $previous = [1];
    $length = 0;
    $shift = 1;
    $beta = 1;
    for ($q = 0; $q < $degree; $q++) {
        $delta = $original[$q];
        for ($i = 1; $i <= $length; $i++) {
            $delta ^= gfMultiply($locator[$i] ?? 0, $original[$q - $i]);
        }
        if ($delta === 0) {
            $shift++;
            continue;
        }
        $saved = $locator;
        $factor = gfDivide($delta, $beta);
        while (count($locator) < count($previous) + $shift) {
            $locator[] = 0;
        }
        foreach ($previous as $i => $value) {
            $locator[$i + $shift] ^= gfMultiply($factor, $value);
        }
        if (2 * $length <= $q) {
            $length = $q + 1 - $length;
            $previous = $saved;
            $beta = $delta;
            $shift = 1;
        } else {
            $shift++;
        }
    }
    if ($length > intdiv($degree, 2)) {
        return $failure();
    }
    $positions = [];
    for ($i = 0; $i < count($received); $i++) {
        if (gfEvaluate($locator, alpha(255 - (count($received) - 1 - $i))) === 0) {
            $positions[] = $i;
        }
    }
    if (count($positions) !== $length) {
        return $failure();
    }
    $omega = array_fill(0, $degree, 0);
    $derivative = array_fill(0, max(0, count($locator) - 1), 0);
    foreach ($original as $i => $value) {
        for ($j = 0; $j < count($locator) && $i + $j < $degree; $j++) {
            $omega[$i + $j] ^= gfMultiply($value, $locator[$j]);
        }
    }
    for ($i = 1; $i < count($locator); $i += 2) {
        $derivative[$i - 1] = $locator[$i];
    }
    $corrected = $received;
    foreach ($positions as $position) {
        $x = alpha(count($received) - 1 - $position);
        $z = alpha(255 - (count($received) - 1 - $position));
        $denominator = gfEvaluate($derivative, $z);
        if ($denominator === 0) {
            return $failure();
        }
        $corrected[$position] ^= gfMultiply($x, gfDivide(gfEvaluate($omega, $z), $denominator));
    }
    foreach (syndromes($corrected, $degree) as $value) {
        if ($value !== 0) {
            return $failure();
        }
    }
    $changed = [];
    foreach ($positions as $position) {
        if ($corrected[$position] !== $received[$position]) {
            $changed[] = $position;
        }
    }
    return (object) ['status' => 'corrected', 'syndromes' => $original, 'positions' => $changed, 'codewords' => $corrected];
}
