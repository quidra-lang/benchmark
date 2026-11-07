<?php

function category(int $value): int
{
    $n = 0;
    while (abs($value) >= (1 << $n)) $n++;
    return $n;
}

function extra(int $value, ?int $n = null): int
{
    $n = $n ?? category($value);
    return $value >= 0 ? $value : $value + (1 << $n) - 1;
}

function restore(int $value, int $n): int
{
    return $n === 0 ? 0 : ($value >= (1 << ($n - 1)) ? $value : $value - (1 << $n) + 1);
}

function assignCodes(object $table): object
{
    $result = clone $table;
    $codes = [];
    $decode = array_fill(0, 17, []);
    $code = $at = 0;
    for ($length = 1; $length <= 16; $length++) {
        for ($i = 0; $i < $table->bits[$length - 1]; $i++) {
            $symbol = $table->values[$at++];
            $codes[$symbol] = (object) compact('code', 'length');
            $decode[$length][$code] = $symbol;
            $code++;
        }
        $code *= 2;
    }
    $result->codes = $codes;
    $result->decode = $decode;
    return $result;
}

function optimized(array $frequencies, int $tableClass, int $id): object
{
    $freq = array_merge($frequencies, [1]);
    $sizes = array_fill(0, 257, 0);
    $others = array_fill(0, 257, -1);
    while (true) {
        $first = $second = -1;
        for ($v = 0; $v <= 256; $v++) if ($freq[$v] > 0 && ($first < 0 || $freq[$v] <= $freq[$first])) $first = $v;
        for ($v = 0; $v <= 256; $v++) if ($v !== $first && $freq[$v] > 0 && ($second < 0 || $freq[$v] <= $freq[$second])) $second = $v;
        if ($second < 0) break;
        $freq[$first] += $freq[$second];
        $freq[$second] = 0;
        $sizes[$first]++;
        while ($others[$first] !== -1) { $first = $others[$first]; $sizes[$first]++; }
        $others[$first] = $second;
        $sizes[$second]++;
        while ($others[$second] !== -1) { $second = $others[$second]; $sizes[$second]++; }
    }
    $counts = array_fill(0, 257, 0);
    foreach ($sizes as $size) if ($size > 0) $counts[$size]++;
    for ($length = 256; $length >= 17; $length--) while ($counts[$length] > 0) {
        $shorter = $length - 2;
        while ($counts[$shorter] === 0) $shorter--;
        $counts[$length] -= 2;
        $counts[$length - 1]++;
        $counts[$shorter + 1] += 2;
        $counts[$shorter]--;
    }
    $longest = 16;
    while ($counts[$longest] === 0) $longest--;
    $counts[$longest]--;
    $values = [];
    for ($v = 0; $v <= 255; $v++) if ($sizes[$v] > 0) $values[] = $v;
    usort($values, fn($a, $b) => ($sizes[$a] <=> $sizes[$b]) ?: ($a <=> $b));
    return assignCodes((object) ['tableClass' => $tableClass, 'id' => $id, 'bits' => array_slice($counts, 1, 16), 'values' => $values]);
}
