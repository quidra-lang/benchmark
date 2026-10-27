<?php

const FORMS = ['ALLOC' => ['p', 'd'], 'PUSH' => ['r'], 'LOAD' => ['i', 'f'], 'POP' => ['n'],
    'SET' => ['i', 'f', 'r'], 'OVERWRITE' => ['i', 'r'], 'CHECKPOINT' => ['label']];
const COMMANDS = ['ALLOC', 'PUSH', 'LOAD', 'POP', 'SET', 'OVERWRITE', 'CHECKPOINT'];

function readInputs(): object
{
    $settings = (object) ['collectors' => []];
    foreach (file('input/config.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $fields = explode(' ', $line);
        switch ($fields[0]) {
            case 'HEAP':
                $settings->heap = (int) $fields[1];
                break;
            case 'COLLECTOR':
                $collector = (object) ['name' => $fields[1], 'type' => $fields[2]];
                if ($collector->type === 'GENERATIONAL') {
                    $collector->young = (int) $fields[3];
                    $collector->age = (int) $fields[4];
                }
                $settings->collectors[] = $collector;
                break;
            case 'MAPS':
                $settings->maps = array_fill_keys(array_slice($fields, 1), true);
                break;
            case 'MMU':
                $settings->windows = array_map('intval', array_slice($fields, 1));
                break;
            case 'WIDTH':
                $settings->width = (int) $fields[1];
                break;
        }
    }
    return (object) ['settings' => $settings, 'lines' => file('input/mutator.txt', FILE_IGNORE_NEW_LINES)];
}

function parseCommand(string $text, int $line): object
{
    $tokens = explode(' ', $text);
    $op = $tokens[0];
    if (!isset(FORMS[$op]) || count($tokens) !== count(FORMS[$op]) + 1) {
        return (object) ['reason' => 'syntax'];
    }
    $command = (object) ['op' => $op, 'line' => $line];
    foreach (FORMS[$op] as $index => $name) {
        $token = $tokens[$index + 1];
        if ($name === 'label') {
            if (!preg_match('/\A[a-z0-9_]{1,16}\z/', $token)) {
                return (object) ['reason' => 'syntax'];
            }
            $command->label = $token;
        } elseif ($name === 'r' && $token === '-') {
            $command->r = null;
        } else {
            if (!preg_match('/\A(?:0|[1-9][0-9]{0,3})\z/', $token)) {
                return (object) ['reason' => 'syntax'];
            }
            $command->$name = (int) $token;
        }
    }
    if (($op === 'ALLOC' && ($command->p > 6 || $command->d > 24)) || ($op === 'POP' && $command->n === 0)) {
        return (object) ['reason' => 'range'];
    }
    return $command;
}
