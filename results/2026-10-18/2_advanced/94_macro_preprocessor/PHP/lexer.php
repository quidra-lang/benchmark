<?php

const PUNCTUATORS = [
    '...',
    '<<=',
    '>>=',
    '->',
    '++',
    '--',
    '<<',
    '>>',
    '<=',
    '>=',
    '==',
    '!=',
    '&&',
    '||',
    '*=',
    '/=',
    '%=',
    '+=',
    '-=',
    '&=',
    '^=',
    '|=',
    '##',
    '[',
    ']',
    '(',
    ')',
    '{',
    '}',
    '.',
    '&',
    '*',
    '+',
    '-',
    '~',
    '!',
    '/',
    '%',
    '<',
    '>',
    '^',
    '|',
    '?',
    ':',
    ';',
    '=',
    ',',
    '#',
];

final readonly class PPToken
{
    public function __construct(
        public string $kind,
        public string $spelling,
        public int $line,
        public bool $space,
        public array $hide = [],
    ) {}

    public function changed(?int $line = null, ?bool $space = null, ?array $hide = null): self
    {
        return new self(
            $this->kind,
            $this->spelling,
            $line ?? $this->line,
            $space ?? $this->space,
            $hide ?? $this->hide,
        );
    }
}

final readonly class LogicalLine
{
    public function __construct(
        public array $tokens,
        public int $start,
        public int $end,
    ) {}
}

function identifierStart(string $c): bool
{
    return $c === '_' || ctype_alpha($c);
}

function readToken(string $text, int $i = 0, bool $header = false): array
{
    $c = $text[$i];
    $n = strlen($text);
    if ($header && $c === '<') {
        $close = strpos($text, '>', $i + 1);
        $newline = strpos($text, "\n", $i + 1);
        if ($close !== false && ($newline === false || $close < $newline))
            return ['header', substr($text, $i, $close - $i + 1), $close + 1];
    }
    if (identifierStart($c)) {
        $end = $i + 1;
        while ($end < $n && (identifierStart($text[$end]) || ctype_digit($text[$end])))
            ++$end;
        return ['identifier', substr($text, $i, $end - $i), $end];
    }
    if (ctype_digit($c) || $c === '.' && ($i + 1) < $n && ctype_digit($text[$i + 1])) {
        $end = $i + 1;
        while ($end < $n) {
            if (str_contains('eEpP', $text[$end]) && ($end + 1) < $n && str_contains('+-', $text[$end + 1]))
                $end += 2;
            elseif (identifierStart($text[$end]) || ctype_digit($text[$end]) || $text[$end] === '.')
                ++$end;
            else
                break;
        }
        return ['number', substr($text, $i, $end - $i), $end];
    }
    if ($c === '"' || $c === "'") {
        $end = $i + 1;
        while ($end < $n && $text[$end] !== "\n") {
            if ($text[$end] === $c)
                return [$c === '"' ? 'string' : 'character', substr($text, $i, $end - $i + 1), $end + 1];
            if ($text[$end] === '\\' && ($end + 1) < $n && $text[$end + 1] !== "\n")
                $end += 2;
            else
                ++$end;
        }
    }
    foreach (PUNCTUATORS as $p)
        if (substr($text, $i, strlen($p)) === $p)
            return ['punctuator', $p, $i + strlen($p)];
    return ['other', $c, $i + 1];
}

function scan(string $text, array $positions, int $start = 1): array
{
    $lines = $tokens = [];
    $i = 0;
    $spaced = true;
    $n = strlen($text);
    while ($i < $n) {
        if ($text[$i] === ' ') {
            $spaced = true;
            ++$i;
        } elseif ($text[$i] === "\n") {
            $end = $positions[$i];
            $lines[] = new LogicalLine($tokens, $start, $end);
            $tokens = [];
            $start = $end + 1;
            $spaced = true;
            ++$i;
        } elseif (substr($text, $i, 2) === '/*') {
            $close = strpos($text, '*/', $i + 2);
            $i = $close === false ? $n : $close + 2;
            $spaced = true;
        } elseif (substr($text, $i, 2) === '//') {
            $close = strpos($text, "\n", $i + 2);
            $i = $close === false ? $n : $close;
            $spaced = true;
        } else {
            $header =
                count($tokens) === 2 && $tokens[0]->spelling === '#' && $tokens[1]->spelling === 'include';
            [$kind, $spelling, $end] = readToken($text, $i, $header);
            $tokens[] = new PPToken($kind, $spelling, $positions[$i], $spaced);
            $i = $end;
            $spaced = false;
        }
    }
    if ($tokens)
        $lines[] = new LogicalLine($tokens, $start, $positions[count($positions) - 1]);
    return $lines;
}

function lexSource(string $text): array
{
    $spliced = '';
    $positions = [];
    $i = 0;
    $line = 1;
    while ($i < strlen($text)) {
        if (substr($text, $i, 2) === "\\\n") {
            $i += 2;
            ++$line;
            continue;
        }
        $c = $text[$i++];
        $spliced .= $c;
        $positions[] = $line;
        if ($c === "\n")
            ++$line;
    }
    return scan($spliced, $positions);
}

function lexDefinition(string $text, int $line): array
{
    $text .= "\n";
    $out = [];
    foreach (scan($text, array_fill(0, strlen($text), $line), $line) as $logical)
        array_push($out, ...$logical->tokens);
    return $out;
}

function render(array $tokens): string
{
    $out = '';
    foreach ($tokens as $i => $t)
        $out .= ($i && $t->space ? ' ' : '') . $t->spelling;
    return $out;
}

function singleToken(string $text): ?string
{
    if ($text === '' || str_starts_with($text, '//') || str_starts_with($text, '/*'))
        return null;
    [$kind, , $end] = readToken($text);
    return $end === strlen($text) ? $kind : null;
}
