<?php

const KEYWORDS = [
    'let',
    'rec',
    'and',
    'in',
    'fun',
    'if',
    'then',
    'else',
    'match',
    'with',
    'true',
    'false',
    'mod',
    'val',
];

const SYMBOLS = [
    ';;',
    '->',
    '::',
    ':',
    '||',
    '&&',
    '<=',
    '>=',
    '<>',
    ';',
    '=',
    '<',
    '>',
    '+',
    '-',
    '*',
    '/',
    '^',
    '(',
    ')',
    '[',
    ']',
    ',',
    '|',
];

const ESCAPES = ['n' => "\n", 't' => "\t", '\\' => '\\', '"' => '"'];

final readonly class Token
{
    public function __construct(
        public string $kind,
        public string $spelling,
        public mixed $value,
        public array $position,
    ) {}

    public function isName(): bool
    {
        return $this->kind === 'identifier' && $this->spelling !== '_';
    }
}

function wordCharacter(string $ch): bool
{
    return ctype_alnum($ch) || $ch === '_';
}

function tokenize(string $source, string $filename): array
{
    $tokens = [];
    $i = 0;
    $line = $column = 1;
    $n = strlen($source);
    while ($i < $n) {
        $start = $i;
        $position = [$filename, $line, $column];
        $ch = $source[$i];
        $kind = null;
        $value = null;
        if ($ch === ' ' || $ch === "\n")
            ++$i;
        elseif (substr($source, $i, 2) === '(*') {
            $end = strpos($source, '*)', $i + 2);
            if ($end === false) {
                $kind = 'invalid';
                $value = 'unterminated comment';
                $i = $n;
            } else
                $i = $end + 2;
        } elseif (ctype_digit($ch)) {
            ++$i;
            while ($i < $n && ctype_digit($source[$i]))
                ++$i;
            $digits = ltrim(substr($source, $start, $i - $start), '0');
            if ($digits === '')
                $digits = '0';
            if (strlen($digits) > 10 || strlen($digits) === 10 && strcmp($digits, '2147483647') > 0) {
                $kind = 'invalid';
                $value = 'integer literal too large';
            } else {
                $kind = 'integer';
                $value = (int) $digits;
            }
        } elseif (ctype_alpha($ch) || $ch === '_') {
            ++$i;
            while ($i < $n && (wordCharacter($source[$i]) || $source[$i] === "'"))
                ++$i;
            $value = substr($source, $start, $i - $start);
            $kind = in_array($value, KEYWORDS, true) ? $value : 'identifier';
        } elseif ($ch === "'" && ($i + 1) < $n && ctype_lower($source[$i + 1])) {
            $i += 2;
            while ($i < $n && wordCharacter($source[$i]))
                ++$i;
            $kind = 'type_variable';
            $value = substr($source, $start, $i - $start);
        } elseif ($ch === '"') {
            ++$i;
            $decoded = '';
            $invalid = false;
            while ($i < $n && $source[$i] !== '"' && $source[$i] !== "\n") {
                if ($source[$i] === '\\' && ($i + 1) < $n && $source[$i + 1] !== "\n") {
                    $escape = $source[$i + 1];
                    if (isset(ESCAPES[$escape]))
                        $decoded .= ESCAPES[$escape];
                    else
                        $invalid = true;
                    $i += 2;
                } else
                    $decoded .= $source[$i++];
            }
            if ($i === $n || $source[$i] === "\n") {
                $kind = 'invalid';
                $value = 'unterminated string';
            } else {
                ++$i;
                $kind = $invalid ? 'invalid' : 'string';
                $value = $invalid ? 'invalid escape sequence' : $decoded;
            }
        } else {
            $symbol = substr($source, $i, 2);
            if (in_array($symbol, SYMBOLS, true)) {
                $i += 2;
                $kind = $value = $symbol;
            } elseif (in_array($ch, SYMBOLS, true)) {
                ++$i;
                $kind = $value = $ch;
            } else {
                ++$i;
                $kind = 'invalid';
                $value = "illegal character '$ch'";
            }
        }
        $consumed = substr($source, $start, $i - $start);
        if ($kind !== null)
            $tokens[] = new Token($kind, $consumed, $value, $position);
        $newlines = substr_count($consumed, "\n");
        if ($newlines) {
            $line += $newlines;
            $column = strlen($consumed) - strrpos($consumed, "\n");
        } else
            $column += strlen($consumed);
    }
    $tokens[] = new Token('EOF', '', null, [$filename, substr_count($source, "\n") + 1, 1]);
    return $tokens;
}
