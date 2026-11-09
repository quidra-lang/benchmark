<?php

class InputError extends RuntimeException {}

function wellFormedNumber(string $text): bool
{
    return (bool) preg_match('/\A(?:0|[1-9][0-9]{0,5})\z/', $text);
}

function readDimacs(string $filename): object
{
    $lines = file($filename, FILE_IGNORE_NEW_LINES);
    $clauses = [];
    $header = null;
    $pending = [];
    foreach ($lines as $index => $line) {
        if (str_starts_with($line, 'c') || trim($line, ' ') === '') continue;
        $tokens = preg_split('/ +/', trim($line, ' '));
        $number = $index + 1;
        if ($tokens[0] === 'p') {
            if ($header !== null) throw new InputError('duplicate header at line ' . $number);
            if (count($tokens) !== 4 || $tokens[1] !== 'cnf' || !wellFormedNumber($tokens[2]) || !wellFormedNumber($tokens[3])) {
                throw new InputError('bad header at line ' . $number);
            }
            $header = (object) ['variables' => (int) $tokens[2], 'count' => (int) $tokens[3]];
            continue;
        }
        if ($header === null) throw new InputError('missing header');
        foreach ($tokens as $token) {
            if (!preg_match('/\A(?:0|-?[1-9][0-9]{0,5})\z/', $token)) throw new InputError('bad token ' . $token . ' at line ' . $number);
            $literal = (int) $token;
            if (abs($literal) > $header->variables) throw new InputError('literal out of range ' . $token . ' at line ' . $number);
            if ($literal === 0) {
                $clauses[] = $pending;
                $pending = [];
            } else $pending[] = $literal;
        }
    }
    if ($header === null) throw new InputError('missing header');
    if ($pending) throw new InputError('unterminated clause');
    if (count($clauses) !== $header->count) throw new InputError('clause count mismatch header=' . $header->count . ' found=' . count($clauses));
    return (object) ['variables' => $header->variables, 'clauses' => $clauses];
}

function modelLines(array $model): array
{
    $tokens = [];
    for ($variable = 1; $variable < count($model); $variable++) $tokens[] = $model[$variable] ? $variable : -$variable;
    $tokens[] = 0;
    $lines = [];
    foreach (array_chunk($tokens, 10) as $chunk) $lines[] = 'v ' . implode(' ', $chunk);
    return $lines;
}
