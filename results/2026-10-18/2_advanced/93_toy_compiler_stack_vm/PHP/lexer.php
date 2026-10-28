<?php

const KEYWORDS = [
    'int',
    'bool',
    'void',
    'true',
    'false',
    'if',
    'else',
    'while',
    'for',
    'break',
    'continue',
    'return',
    'print',
    'read',
];

const PAIRS = ['<=', '>=', '==', '!=', '&&', '||'];

final readonly class Token
{
    public function __construct(
        public string $kind,
        public string $spelling,
        public array $position,
    ) {}
}

final class ToyCompileError extends RuntimeException
{
    public function __construct(
        public string $kind,
        public array $position,
        string $message,
    ) {
        parent::__construct($message);
    }
}

function tokenize(array $lines): array
{
    $source = implode("\n", array_column($lines, 1)) . "\n";
    $line = $lines[0][0];
    $column = 1;
    $i = 0;
    $n = strlen($source);
    $tokens = [];
    while ($i < $n) {
        $ch = $source[$i];
        $start = [$line, $column];
        if ($ch === ' ') {
            ++$i;
            ++$column;
            continue;
        }
        if ($ch === "\n") {
            ++$i;
            ++$line;
            $column = 1;
            continue;
        }
        $pair = substr($source, $i, 2);
        if ($pair === '//') {
            $end = strpos($source, "\n", $i);
            $column += $end - $i;
            $i = $end;
            continue;
        }
        if ($pair === '/*') {
            $end = strpos($source, '*/', $i + 2);
            if ($end === false)
                throw new ToyCompileError('lexical', $start, 'unterminated comment');
            $end += 2;
            $comment = substr($source, $i, $end - $i);
            $newlines = substr_count($comment, "\n");
            if ($newlines) {
                $line += $newlines;
                $column = strlen($comment) - strrpos($comment, "\n");
            } else
                $column += strlen($comment);
            $i = $end;
            continue;
        }
        $end = $i + 1;
        if (ctype_alpha($ch) || $ch === '_') {
            while ($end < $n && (ctype_alnum($source[$end]) || $source[$end] === '_'))
                ++$end;
            $s = substr($source, $i, $end - $i);
            $kind = in_array($s, KEYWORDS, true) ? 'keyword' : 'identifier';
        } elseif (ctype_digit($ch)) {
            while ($end < $n && ctype_digit($source[$end]))
                ++$end;
            $s = substr($source, $i, $end - $i);
            $digits = ltrim($s, '0');
            if (strlen($digits) > 10 || strlen($digits) === 10 && strcmp($digits, '2147483647') > 0)
                throw new ToyCompileError('lexical', $start, 'integer literal too large');
            $kind = 'integer';
        } elseif (in_array($pair, PAIRS, true)) {
            ++$end;
            $s = $pair;
            $kind = 'symbol';
        } elseif (str_contains('+-*/%<>=!(){}[],;', $ch)) {
            $s = $ch;
            $kind = 'symbol';
        } else
            throw new ToyCompileError('lexical', $start, "unexpected character '$ch'");
        $tokens[] = new Token($kind, $s, $start);
        $column += $end - $i;
        $i = $end;
    }
    [$last, $text] = $lines[count($lines) - 1];
    $tokens[] = new Token('end', '', [$last, strlen($text) + 1]);
    return $tokens;
}
