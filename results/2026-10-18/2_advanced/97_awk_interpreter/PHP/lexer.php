<?php

const KEYWORDS = [
    'BEGIN',
    'END',
    'function',
    'if',
    'else',
    'while',
    'for',
    'do',
    'break',
    'continue',
    'next',
    'exit',
    'return',
    'delete',
    'in',
    'getline',
    'print',
    'printf',
];

const BUILTINS = ['length', 'substr', 'index', 'split', 'sprintf', 'toupper', 'tolower', 'close', 'int'];

const PAIRS = ['+=', '-=', '*=', '/=', '%=', '^=', '==', '<=', '>=', '!=', '++', '--', '&&', '||', '>>'];

const ESCAPES = ['n' => "\n", 't' => "\t", '\\' => '\\', '"' => '"', '/' => '/'];

final readonly class Token
{
    public function __construct(
        public string $kind,
        public string $spelling,
        public mixed $value,
        public array $position,
    ) {}
}

final class SyntaxIssue extends RuntimeException
{
    public function __construct(
        public array $position,
    ) {
        parent::__construct();
    }
}

function tokenize(string $source): array
{
    $tokens = [];
    $i = 0;
    $line = $column = 1;
    $n = strlen($source);
    while ($i < $n) {
        $ch = $source[$i];
        $start = [$line, $column];
        if ($ch === ' ') {
            ++$i;
            ++$column;
            continue;
        }
        if (substr($source, $i, 2) === "\\\n") {
            $i += 2;
            ++$line;
            $column = 1;
            continue;
        }
        if ($ch === '#') {
            $end = strpos($source, "\n", $i);
            if ($end === false)
                $end = $n;
            $column += $end - $i;
            $i = $end;
            continue;
        }
        if ($ch === "\n") {
            $tokens[] = new Token('newline', "\n", null, $start);
            ++$i;
            ++$line;
            $column = 1;
            continue;
        }
        $end = $i + 1;
        $value = null;
        if (ctype_digit($ch)) {
            while ($end < $n && ctype_digit($source[$end]))
                ++$end;
            $kind = 'number';
            $value = (int) substr($source, $i, $end - $i);
        } elseif (ctype_alpha($ch) || $ch === '_') {
            while ($end < $n && (ctype_alnum($source[$end]) || $source[$end] === '_'))
                ++$end;
            $word = substr($source, $i, $end - $i);
            $kind = in_array($word, KEYWORDS, true)
                ? 'keyword'
                : (
                    in_array($word, BUILTINS, true)
                        ? 'builtin'
                        : ($end < $n && $source[$end] === '(' ? 'function_name' : 'name')
                );
        } elseif ($ch === '"') {
            $value = '';
            while ($end < $n && $source[$end] !== '"') {
                if ($source[$end] === "\n")
                    throw new SyntaxIssue($start);
                if ($source[$end] === '\\') {
                    if (($end + 1) === $n || !isset(ESCAPES[$source[$end + 1]]))
                        throw new SyntaxIssue([$line, $column + $end - $i]);
                    $value .= ESCAPES[$source[$end + 1]];
                    $end += 2;
                } else
                    $value .= $source[$end++];
            }
            if ($end === $n)
                throw new SyntaxIssue($start);
            ++$end;
            $kind = 'string';
        } elseif (in_array(substr($source, $i, 2), PAIRS, true)) {
            ++$end;
            $kind = 'symbol';
        } elseif (str_contains('+-*/%^!><?:=()[]{},;$', $ch))
            $kind = 'symbol';
        else
            throw new SyntaxIssue($start);
        $tokens[] = new Token($kind, substr($source, $i, $end - $i), $value, $start);
        $column += $end - $i;
        $i = $end;
    }
    $tokens[] = new Token('end', '', null, [substr_count($source, "\n") + 1, 1]);
    return $tokens;
}
