<?php

function parseHex(string $text): ?int
{
    return preg_match('/\A[0-9a-f]{8}\z/', $text) === 1 ? (int)hexdec($text) : null;
}

function parseRegister(string $text): ?int
{
    if ($text === '-') return null;
    return preg_match('/\Ar(?:[0-9]|[12][0-9]|3[01])\z/', $text) === 1 ? (int)substr($text, 1) : -1;
}

function readInput(): array
{
    $config = ['predictors' => [], 'variants' => []];
    foreach (file('input/config.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $words = explode(' ', $line);
        $keyword = array_shift($words);
        switch ($keyword) {
            case 'BTB': $config['btb'] = (int)$words[0]; break;
            case 'RAS': $config['ras'] = (int)$words[0]; break;
            case 'PREDICTOR':
                $config['predictors'][] = ['name' => $words[0], 'scheme' => $words[1], 'parameters' => array_map('intval', array_slice($words, 2))];
                break;
            case 'VARIANT':
                $config['variants'][] = ['name' => $words[0], 'forwarding' => $words[1] === 'ON',
                    'resolution' => $words[2], 'latency' => (int)$words[3]];
                break;
            case 'PRIMARY': $config['primaryVariant'] = $words[0]; $config['primaryPredictor'] = $words[1]; break;
            case 'WINDOW': $config['start'] = (int)$words[0]; $config['end'] = (int)$words[1]; break;
            case 'TOP': $config['top'] = (int)$words[0]; break;
            case 'INTERVAL': $config['interval'] = (int)$words[0]; break;
        }
    }
    return ['lines' => file('input/trace.txt', FILE_IGNORE_NEW_LINES), 'config' => $config];
}
