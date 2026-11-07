<?php

const SYMBOLS = '+-*/\\^<>=~:.?@#&$';

const INFIX = [
    ':-' => [1200, 1199, 1199],
    ';' => [1100, 1099, 1100],
    '->' => [1050, 1049, 1050],
    ',' => [1000, 999, 1000],
    '=' => [700, 699, 699],
    '\\=' => [700, 699, 699],
    '==' => [700, 699, 699],
    '\\==' => [700, 699, 699],
    'is' => [700, 699, 699],
    '=:=' => [700, 699, 699],
    '=\\=' => [700, 699, 699],
    '<' => [700, 699, 699],
    '>' => [700, 699, 699],
    '=<' => [700, 699, 699],
    '>=' => [700, 699, 699],
    '=..' => [700, 699, 699],
    '+' => [500, 500, 499],
    '-' => [500, 500, 499],
    '*' => [400, 400, 399],
    '/' => [400, 400, 399],
    '//' => [400, 400, 399],
    'mod' => [400, 400, 399],
    'rem' => [400, 400, 399],
];

const PREFIX = ['\\+' => 900, '-' => 200];

final readonly class Token
{
    public function __construct(
        public string $kind,
        public mixed $value,
        public string $spelling,
        public int $line,
        public int $column,
        public bool $space,
        public int $index,
    ) {}
}

final class ReaderSyntaxError extends RuntimeException
{
    public function __construct(
        public Token $token,
        ?string $message = null,
    ) {
        $message ??= match (true) {
            $token->kind === 'invalid' => $token->value,
            $token->kind === 'eof' => 'unexpected end of file',
            $token->kind === 'end' => 'unexpected end of clause',
            $token->kind === 'name' && isset(INFIX[$token->value]) => 'operator priority clash',
            default => 'unexpected "' . $token->spelling . '"',
        };
        parent::__construct($message);
    }
}

function tokenize(string $text, int $column = 1): array
{
    $tokens = [];
    $i = 0;
    $line = 1;
    $space = true;
    $n = strlen($text);
    while ($i < $n) {
        $ch = $text[$i];
        if ($ch === ' ' || $ch === "\n") {
            if ($ch === "\n") {
                ++$line;
                $column = 1;
            } else
                ++$column;
            ++$i;
            $space = true;
            continue;
        }
        if ($ch === '%') {
            $end = strpos($text, "\n", $i);
            if ($end === false)
                $end = $n;
            $column += $end - $i;
            $i = $end;
            $space = true;
            continue;
        }
        $start = $i;
        $startColumn = $column;
        if (ctype_digit($ch)) {
            ++$i;
            while ($i < $n && ctype_digit($text[$i]))
                ++$i;
            $digits = ltrim(substr($text, $start, $i - $start), '0');
            if ($digits === '')
                $digits = '0';
            if (strlen($digits) > 10 || strlen($digits) === 10 && strcmp($digits, '2147483647') > 0) {
                $kind = 'invalid';
                $value = 'integer too large';
            } else {
                $kind = 'integer';
                $value = (int) $digits;
            }
        } elseif (ctype_alpha($ch) || $ch === '_') {
            ++$i;
            while ($i < $n && (ctype_alnum($text[$i]) || $text[$i] === '_'))
                ++$i;
            $value = substr($text, $start, $i - $start);
            $kind = ctype_lower($ch) ? 'name' : 'variable';
        } elseif (str_contains(SYMBOLS, $ch)) {
            ++$i;
            while ($i < $n && str_contains(SYMBOLS, $text[$i]))
                ++$i;
            $value = substr($text, $start, $i - $start);
            $kind = $value === '.' && ($i === $n || str_contains(" \n%", $text[$i])) ? 'end' : 'name';
        } elseif ($ch === '!' || $ch === ';') {
            $kind = 'name';
            $value = $ch;
            ++$i;
        } elseif (str_contains(',|()[]', $ch)) {
            $kind = 'punct';
            $value = $ch;
            ++$i;
        } elseif ($ch === "'") {
            ++$i;
            $represented = '';
            $incorrect = false;
            while (true) {
                if ($i === $n || $text[$i] === "\n") {
                    $kind = 'invalid';
                    $value = 'unterminated quoted atom';
                    break;
                }
                $current = $text[$i];
                if ($current === "'") {
                    if (($i + 1) < $n && $text[$i + 1] === "'") {
                        $represented .= "'";
                        $i += 2;
                    } else {
                        ++$i;
                        $kind = $incorrect ? 'invalid' : 'quoted';
                        $value = $incorrect ? 'undefined escape sequence' : $represented;
                        break;
                    }
                } elseif ($current === '\\') {
                    ++$i;
                    if ($i < $n && $text[$i] !== "\n") {
                        $escape = $text[$i++];
                        $escapes = ['n' => "\n", 't' => "\t", '\\' => '\\', "'" => "'"];
                        if (!isset($escapes[$escape]))
                            $incorrect = true;
                        $represented .= $escapes[$escape] ?? $escape;
                    }
                } else
                    $represented .= $text[$i++];
            }
        } else {
            $kind = 'invalid';
            $value = "illegal character '$ch'";
            ++$i;
        }
        $tokens[] = new Token(
            $kind,
            $value,
            substr($text, $start, $i - $start),
            $line,
            $startColumn,
            $space,
            count($tokens),
        );
        $column += $i - $start;
        $space = false;
    }
    $tokens[] = new Token('eof', null, '', $line, $column, $space, count($tokens));
    return $tokens;
}

final class Reader
{
    private array $tokens;
    public int $position = 0;
    public array $names = [], $counts = [];

    public function __construct(string $text, int $column = 1)
    {
        $this->tokens = tokenize($text, $column);
    }

    public function peek(): Token
    {
        return $this->tokens[$this->position];
    }

    public function take(): Token
    {
        $t = $this->peek();
        if ($t->kind !== 'eof')
            ++$this->position;
        return $t;
    }

    private function punctuation(string $s): bool
    {
        return $this->peek()->kind === 'punct' && $this->peek()->value === $s;
    }

    private function expect(string $s): void
    {
        $t = $this->take();
        if ($t->kind !== 'punct' || $t->value !== $s)
            throw new ReaderSyntaxError($t);
    }

    public function clause(bool $query = false): mixed
    {
        $this->names = $this->counts = [];
        [$term] = $this->term(1200);
        $t = $this->take();
        if ($t->kind !== 'end')
            throw new ReaderSyntaxError($t);
        if ($query && $this->peek()->kind !== 'eof')
            throw new ReaderSyntaxError($this->peek());
        return $term;
    }

    private function term(int $limit): array
    {
        [$term, $priority] = $this->primary($limit);
        while (true) {
            $t = $this->peek();
            $operator =
                $t->kind === 'name' && isset(INFIX[$t->value]) || $t->kind === 'punct' && $t->value === ',';
            if (!$operator)
                return [$term, $priority];
            [$p, $left, $right] = INFIX[$t->value];
            if ($p > $limit || $priority > $left)
                return [$term, $priority];
            $this->take();
            [$arg] = $this->term($right);
            $term = new Compound($t->value, $term, $arg);
            $priority = $p;
        }
    }

    private function canStart(): bool
    {
        $t = $this->peek();
        return (
            in_array($t->kind, ['integer', 'variable', 'quoted'], true)
            || $t->kind === 'punct'
            && in_array($t->value, ['(', '['], true)
            || $t->kind === 'name'
            && (!isset(INFIX[$t->value]) || isset(PREFIX[$t->value]))
        );
    }

    private function primary(int $limit): array
    {
        $t = $this->take();
        if ($t->kind === 'integer')
            return [$t->value, 0];
        if ($t->kind === 'variable') {
            $name = $t->value;
            $this->counts[$name] = ($this->counts[$name] ?? 0) + 1;
            if ($name === '_')
                return [new PrologVariable(), 0];
            return [$this->names[$name] ??= new PrologVariable(), 0];
        }
        if ($t->kind === 'punct' && $t->value === '(') {
            [$term] = $this->term(1200);
            $this->expect(')');
            return [$term, 0];
        }
        if ($t->kind === 'punct' && $t->value === '[') {
            if ($this->punctuation(']')) {
                $this->take();
                return ['[]', 0];
            }
            $elements = [$this->term(999)[0]];
            while ($this->punctuation(',')) {
                $this->take();
                $elements[] = $this->term(999)[0];
            }
            $tail = '[]';
            if ($this->punctuation('|')) {
                $this->take();
                $tail = $this->term(999)[0];
            }
            $this->expect(']');
            return [makeList($elements, $tail), 0];
        }
        if ($t->kind === 'name' || $t->kind === 'quoted') {
            if ($this->punctuation('(') && !$this->peek()->space) {
                $this->take();
                $args = [$this->term(999)[0]];
                while ($this->punctuation(',')) {
                    $this->take();
                    $args[] = $this->term(999)[0];
                }
                $this->expect(')');
                return [new Compound($t->value, ...$args), 0];
            }
            if (
                $t->kind === 'name'
                && $t->value === '-'
                && $this->peek()->kind === 'integer'
                && !$this->peek()->space
            )
                return [-$this->take()->value, 0];
            if ($t->kind === 'name' && isset(PREFIX[$t->value]) && $this->canStart()) {
                $p = PREFIX[$t->value];
                if ($p > $limit)
                    throw new ReaderSyntaxError($t, 'operator priority clash');
                [$arg] = $this->term($p);
                return [new Compound($t->value, $arg), $p];
            }
            return [$t->value, 0];
        }
        throw new ReaderSyntaxError($t);
    }
}
