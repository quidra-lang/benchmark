<?php

function simulate(array $instructions, array $variant, array $mispredictions): array
{
    $times = [];
    $records = [];
    foreach ($instructions as $i => $instruction) {
        $F = 1;
        $D = 2;
        $X = 3;
        if ($i > 0) {
            $previous = $times[$i - 1];
            $F = $mispredictions[$i - 1] ? $previous['X'] + (idResolved($instructions[$i - 1], $variant) ? 0 : 1) : $previous['D'];
            $D = max($F + 1, $previous['X']);
            $X = max($D + 1, $previous['M']);
            $base = $previous['X'] + 1;
            $bounds = [
                ['cause' => 'control', 'value' => $D + 1, 'producer' => null],
                ['cause' => 'structural', 'value' => $previous['M'], 'producer' => null],
                ['cause' => 'load_use', 'value' => $base, 'producer' => null],
                ['cause' => 'raw', 'value' => $base, 'producer' => null]
            ];
            foreach ($instruction['sources'] as $source) {
                if ($source['producer'] === null) continue;
                $ready = readyCycle($source, $instruction, $variant, $instructions, $times);
                $X = max($X, $ready);
                $kind = $instructions[$source['producer']]['className'] === 'LOAD' ? 2 : 3;
                if ($ready > $bounds[$kind]['value']) {
                    $bounds[$kind]['value'] = $ready;
                    $bounds[$kind]['producer'] = $source['producer'];
                }
            }
            $current = $base;
            foreach ($bounds as $cause => $bound) {
                if ($bound['value'] > $current) {
                    $records[] = ['cause' => $bound['cause'], 'cycles' => $bound['value'] - $current,
                        'responsible' => $cause < 2 ? $i - 1 : $i, 'waiting' => $i, 'producer' => $bound['producer']];
                    $current = $bound['value'];
                }
            }
        }
        $M = $X + ($instruction['className'] === 'MUL' ? $variant['latency'] : 1);
        $times[] = compact('F', 'D', 'X', 'M') + ['W' => $M + 1];
    }
    $last = count($instructions) - 1;
    if ($instructions[$last]['className'] === 'MUL' && $variant['latency'] >= 2) {
        $records[] = ['cause' => 'structural', 'cycles' => $variant['latency'] - 1,
            'responsible' => $last, 'waiting' => null, 'producer' => null];
    }
    return ['times' => $times, 'records' => $records, 'cycles' => $times[$last]['W']];
}
