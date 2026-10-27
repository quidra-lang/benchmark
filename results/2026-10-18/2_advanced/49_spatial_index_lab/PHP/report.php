<?php

function fraction($numerator, $denominator) {
    $first = $numerator;
    $second = $denominator;
    while ($second !== 0) [$first, $second] = [$second, $first % $second];
    return intdiv($numerator, $first) . '/' . intdiv($denominator, $first);
}

function ids($values) {
    return $values ? implode(' ', $values) : '-';
}

function writeLines($name, $lines) {
    file_put_contents('output/' . $name, $lines ? implode("\n", $lines) . "\n" : '');
}
