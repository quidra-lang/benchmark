<?php
declare(strict_types=1);

function character(int $code): string
{
    return $code >= 33 && $code <= 126 && !in_array($code, [92, 93, 94, 45], true)
        ? chr($code) : sprintf('\\x%02X', $code);
}

function set_notation(array $set, bool $negated = false): string
{
    $parts = [];
    for ($start = 0; $start < 128; ++$start) {
        if (!isset($set[$start])) {
            continue;
        }
        $end = $start;
        while ($end + 1 < 128 && isset($set[$end + 1])) {
            ++$end;
        }
        $parts[] = character($start) . ($end === $start ? '' : ($end === $start + 1 ? '' : '-') . character($end));
        $start = $end;
    }
    return '[' . ($negated ? '^' : '') . implode('', $parts) . ']';
}

function instruction_notation(array $value): string
{
    return match ($value['op']) {
        'CHAR' => 'CHAR ' . character($value['character']),
        'CLASS' => 'CLASS ' . set_notation($value['set'], $value['negated']),
        'SPLIT' => "SPLIT {$value['x']}, {$value['y']}",
        'JMP' => 'JMP ' . $value['x'],
        'SAVE', 'BACKREF' => $value['op'] . ' ' . $value['group'],
        'ASSERT' => 'ASSERT ' . $value['assertion'],
        'LOOK' => "LOOK {$value['kind']} {$value['x']}",
        default => $value['op']
    };
}

function quote(string $value): string
{
    return '"' . strtr($value, ['\\' => '\\\\', '"' => '\\"', "\n" => '\\n', "\t" => '\\t']) . '"';
}
