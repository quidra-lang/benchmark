<?php
declare(strict_types=1);

namespace IniValidator;

const LITERAL_DOLLAR = "\x01";

final class LogicalLine
{
    public function __construct(
        public int $number,
        public array $segments,
        public ?array $error,
    ) {}
}

function logicalLines(array $physical): array
{
    $result = [];
    $escapes = ['\\' => '\\', '"' => '"', 'n' => "\n", 't' => "\t", '$' => LITERAL_DOLLAR];
    for ($index = 0; $index < count($physical);) {
        $number = $index + 1;
        $source = $physical[$index++];
        $segments = [];
        $current = '';
        $quoted = false;
        $error = null;
        $position = 0;
        while ($position < strlen($source)) {
            $char = $source[$position];
            if ($char === '\\' && $position === strlen($source) - 1) {
                $source = ltrim($physical[$index++], ' ');
                $position = 0;
            } elseif ($quoted && $char === '\\') {
                $follower = $source[$position + 1];
                if (isset($escapes[$follower])) {
                    $current .= $escapes[$follower];
                } else {
                    $error ??= ['E_ESCAPE', 'invalid escape sequence \\' . $follower];
                }
                $position += 2;
            } elseif ($char === '"') {
                $segments[] = $current;
                $current = '';
                $quoted = !$quoted;
                ++$position;
            } elseif (!$quoted && ($char === ';' || $char === '#')) {
                break;
            } else {
                $current .= $char;
                ++$position;
            }
        }
        if ($quoted) {
            $error ??= ['E_UNTERMINATED', 'unterminated string'];
        }
        $segments[] = $current;
        $result[] = new LogicalLine($number, $segments, $error);
    }
    return $result;
}
