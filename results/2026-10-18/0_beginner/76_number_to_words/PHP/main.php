<?php

function smallWords(int $number): string
{
    $units = explode(' ', 'zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen');
    $tens = explode(' ', 'zero ten twenty thirty forty fifty sixty seventy eighty ninety');
    $parts = [];
    $hundreds = intdiv($number, 100);
    $remainder = $number % 100;
    if ($hundreds > 0) {
        $parts[] = $units[$hundreds] . ' hundred';
    }
    if ($remainder >= 20) {
        $phrase = $tens[intdiv($remainder, 10)];
        if ($remainder % 10 > 0) {
            $phrase .= '-' . $units[$remainder % 10];
        }
        $parts[] = $phrase;
    } elseif ($remainder > 0) {
        $parts[] = $units[$remainder];
    }
    return implode(' ', $parts);
}

function numberWords(int $number): string
{
    if ($number === 0) {
        return 'zero';
    }
    $parts = [];
    $thousands = intdiv($number, 1000);
    $remainder = $number % 1000;
    if ($thousands > 0) {
        $parts[] = smallWords($thousands) . ' thousand';
    }
    if ($remainder > 0) {
        $parts[] = smallWords($remainder);
    }
    return implode(' ', $parts);
}

foreach ([0, 13, 40, 100, 568, 71000, 300019, 999999] as $number) {
    printf("%d: %s\n", $number, numberWords($number));
}
