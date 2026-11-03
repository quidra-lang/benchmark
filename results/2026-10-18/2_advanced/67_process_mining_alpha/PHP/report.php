<?php

function fraction($value, $denominator = 1)
{
    if (is_array($value)) [$numerator, $denominator] = $value; else $numerator = $value;
    $negative = $numerator < 0; $n = abs($numerator); $d = $denominator; $a = $n; $b = $d;
    while ($b !== 0) { $next = $a % $b; $a = $b; $b = $next; }
    $n = intdiv($n, $a); $d = intdiv($d, $a);
    $truncated = intdiv(10000 * $n, $d);
    $decimal = intdiv($truncated, 10000) . '.' . str_pad((string) ($truncated % 10000), 4, '0', STR_PAD_LEFT);
    return ($negative ? '-' : '') . $n . '/' . $d . '=' . ($negative && $truncated !== 0 ? '-' : '') . $decimal;
}
function percentage($numerator, $denominator)
{
    $truncated = intdiv(10000 * $numerator, $denominator);
    return intdiv($truncated, 100) . '.' . str_pad((string) ($truncated % 100), 2, '0', STR_PAD_LEFT) . '%';
}
function list_names($values) { return count($values) === 0 ? '-' : implode(',', $values); }
function write_outputs($files)
{
    if (!is_dir('output')) mkdir('output', 0777, true);
    foreach ($files as $filename => $lines) file_put_contents('output/' . $filename, implode("\n", $lines) . "\n");
}
