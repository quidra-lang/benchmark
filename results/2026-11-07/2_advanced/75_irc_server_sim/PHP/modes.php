<?php

function modeItems(string $mode, array $arguments): array
{
    $sign = '+';
    $next = 0;
    $result = [];
    foreach (str_split($mode) as $character) {
        if ($character === '+' || $character === '-') { $sign = $character; continue; }
        $argument = null;
        if (str_contains('ovb', $character)) $argument = $arguments[$next++] ?? null;
        elseif ($character === 'k') {
            $argument = $arguments[$next++] ?? null;
            if ($sign === '-') $argument = '*';
        } elseif ($character === 'l' && $sign === '+') {
            $candidate = $arguments[$next++] ?? null;
            if ($candidate !== null && strlen($candidate) <= 4 && digits($candidate) && (int) $candidate >= 1) $argument = $candidate;
        }
        $result[] = (object) compact('sign', 'character', 'argument');
    }
    return $result;
}

function changeString(array $changes): string
{
    $result = '';
    $previous = null;
    $arguments = [];
    foreach ($changes as $change) {
        if ($change->sign !== $previous) { $result .= $change->sign; $previous = $change->sign; }
        $result .= $change->character;
        if ($change->argument !== null) $arguments[] = $change->argument;
    }
    foreach ($arguments as $argument) $result .= ' ' . $argument;
    return $result;
}
