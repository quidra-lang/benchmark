<?php

function decimalInteger(string $text): bool
{
    return preg_match('/\\A(?:0|[1-9][0-9]*)\\z/', $text) === 1;
}

function hexadecimal(string $text): bool
{
    return preg_match('/\\A[0-9a-f]{8}\\z/', $text) === 1;
}

function hexAddress(int $value): string
{
    return sprintf('%08x', $value);
}

function readInput(): array
{
    $config = ['scenarios' => [], 'regions' => [], 'watches' => []];
    foreach (file('input/config.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $fields = explode(' ', $line);
        $kind = array_shift($fields);
        switch ($kind) {
            case 'CORES': $config['cores'] = (int)$fields[0]; break;
            case 'LINE': $config['line'] = (int)$fields[0]; break;
            case 'L1': $config['l1'] = ['size' => (int)$fields[0], 'ways' => (int)$fields[1]]; break;
            case 'L2': $config['l2'] = ['size' => (int)$fields[0], 'ways' => (int)$fields[1]]; break;
            case 'LATENCY': $config['latencies'] = array_map('intval', $fields); break;
            case 'SCENARIO':
                $config['scenarios'][] = ['name' => $fields[0], 'protocol' => $fields[1], 'l1Policy' => $fields[2],
                    'l2Policy' => $fields[3], 'order' => count($config['scenarios'])];
                break;
            case 'PRIMARY': $config['primary'] = $fields[0]; break;
            case 'INTERVAL': $config['interval'] = (int)$fields[0]; break;
            case 'TOP': $config['top'] = (int)$fields[0]; break;
            case 'REGION': $config['regions'][] = ['name' => $fields[0], 'first' => hexdec($fields[1]), 'last' => hexdec($fields[2])]; break;
            case 'WATCH': $config['watches'][] = intdiv((int)hexdec($fields[0]), $config['line']); break;
        }
    }
    foreach (['l1', 'l2'] as $level) {
        $config[$level]['sets'] = intdiv($config[$level]['size'], $config['line'] * $config[$level]['ways']);
    }
    $config['capacity'] = $config['l1']['sets'] * $config['l1']['ways'];
    return ['config' => $config, 'trace' => file('input/trace.txt', FILE_IGNORE_NEW_LINES)];
}

function writeLines(string $filename, array $lines): void
{
    if (!is_dir('output')) mkdir('output', 0777, true);
    file_put_contents('output/' . $filename, $lines ? implode("\n", $lines) . "\n" : '');
}
