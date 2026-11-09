<?php

const KEYWORDS = [
    'int',
    'float',
    'bool',
    'string',
    'void',
    'if',
    'else',
    'while',
    'for',
    'return',
    'break',
    'continue',
    'true',
    'false',
    'switch',
    'case',
    'default',
];

const TYPES = ['int', 'float', 'bool', 'string', 'void'];

const DOUBLE_SYMBOLS = ['<=', '>=', '==', '!=', '&&', '||', '+=', '-=', '*=', '/=', '%='];

const ASSIGNMENTS = ['=', '+=', '-=', '*=', '/=', '%='];

final class SourceError extends RuntimeException
{
    public function __construct(
        public int $sourceLine,
        public int $column,
        string $message,
    ) {
        parent::__construct($message);
    }
}

final class SourceToken
{
    public array $leading = [], $trailing = [];
    public bool $allowed = false, $trailingComma = false, $ownLine = false;

    public function __construct(
        public string $kind,
        public string $text,
        public int $line,
        public int $column,
        public int $blank,
        public int $index = -1,
    ) {}

    public function isComment(): bool
    {
        return $this->kind === 'line_comment' || $this->kind === 'block_comment';
    }
}

function lexicalAnalysis(array $lines): array
{
    $tokens = $comments = $items = [];
    $previous = 0;
    foreach ($lines as $li => $line) {
        $n = strlen($line);
        $i = 0;
        while ($i < $n) {
            $ch = $line[$i];
            if ($ch === ' ') {
                ++$i;
                continue;
            }
            $start = $i;
            $pair = substr($line, $i, 2);
            if ($pair === '//') {
                $kind = 'line_comment';
                $text = rtrim(substr($line, $i), ' ');
                $i = $n;
            } elseif ($pair === '/*') {
                $end = strpos($line, '*/', $i + 2);
                if ($end === false)
                    throw new SourceError($li + 1, $i + 1, 'unterminated comment');
                $i = $end + 2;
                $kind = 'block_comment';
                $text = substr($line, $start, $i - $start);
            } elseif (ctype_alpha($ch) || $ch === '_') {
                ++$i;
                while ($i < $n && (ctype_alnum($line[$i]) || $line[$i] === '_'))
                    ++$i;
                $text = substr($line, $start, $i - $start);
                $kind = in_array($text, KEYWORDS, true) ? 'keyword' : 'identifier';
            } elseif (ctype_digit($ch)) {
                ++$i;
                while ($i < $n && ctype_digit($line[$i]))
                    ++$i;
                if (($i + 1) < $n && $line[$i] === '.' && ctype_digit($line[$i + 1])) {
                    $i += 2;
                    while ($i < $n && ctype_digit($line[$i]))
                        ++$i;
                }
                $text = substr($line, $start, $i - $start);
                $kind = 'number';
            } elseif ($ch === '"') {
                ++$i;
                $closed = false;
                while ($i < $n) {
                    if ($line[$i] === '\\')
                        $i += 2;
                    elseif ($line[$i] === '"') {
                        ++$i;
                        $closed = true;
                        break;
                    } else
                        ++$i;
                }
                if (!$closed)
                    throw new SourceError($li + 1, $start + 1, 'unterminated string');
                $text = substr($line, $start, $i - $start);
                $kind = 'string';
            } elseif (in_array($pair, DOUBLE_SYMBOLS, true)) {
                $i += 2;
                $text = $pair;
                $kind = 'symbol';
            } elseif (str_contains('+-*/%<>=!()[]{},;.?:', $ch)) {
                ++$i;
                $text = $ch;
                $kind = 'symbol';
            } else
                throw new SourceError($li + 1, $start + 1, "unexpected character '$ch'");
            $t = new SourceToken($kind, $text, $li + 1, $start + 1, max(0, $li - $previous));
            $previous = $li + 1;
            $items[] = $t;
            if ($t->isComment())
                $comments[] = $t;
            else {
                $t->index = count($tokens);
                $tokens[] = $t;
            }
        }
    }
    $end = new SourceToken('end', '', count($lines) + 1, 1, 0, count($tokens));
    $end->allowed = true;
    $tokens[] = $end;
    return [$tokens, $comments, $items];
}
