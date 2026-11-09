<?php
declare(strict_types=1);

final class SyntaxFault extends Exception {}
final class BasicFault extends Exception {}

const SIGNATURES = [
    'ABS' => ['I'], 'SGN' => ['I'], 'INT' => ['I'], 'SQR' => ['I'],
    'RND' => ['I'], 'LEN' => ['S'], 'ASC' => ['S'], 'VAL' => ['S'],
    'CHR$' => ['I'], 'STR$' => ['I'], 'LEFT$' => ['SI'],
    'RIGHT$' => ['SI'], 'MID$' => ['SI', 'SII'], 'INSTR' => ['SS']
];

const ERROR_CODES = [
    'NEXT WITHOUT FOR' => 1, 'RETURN WITHOUT GOSUB' => 3,
    'OUT OF DATA' => 4, 'ILLEGAL FUNCTION CALL' => 5,
    'OVERFLOW' => 6, 'OUT OF MEMORY' => 7,
    'UNDEFINED LINE NUMBER' => 8, 'SUBSCRIPT OUT OF RANGE' => 9,
    'DUPLICATE DEFINITION' => 10, 'DIVISION BY ZERO' => 11,
    'TYPE MISMATCH' => 13, 'STRING TOO LONG' => 15,
    'RESUME WITHOUT ERROR' => 20, 'FOR WITHOUT NEXT' => 26,
    'WHILE WITHOUT WEND' => 29, 'WEND WITHOUT WHILE' => 30,
    'INPUT PAST END' => 62
];

const OPERATORS = [
    0 => ['OR'], 1 => ['AND'], 2 => [],
    3 => ['=', '<>', '<', '>', '<=', '>='],
    4 => ['+', '-'], 5 => ['*', '/', 'MOD'],
    6 => [], 7 => ['^']
];

function badSyntax(): never
{
    throw new SyntaxFault('SYNTAX ERROR');
}

function fault(string $message): never
{
    throw new BasicFault($message);
}

function variableName(string $name): bool
{
    return preg_match('/^[A-Z][0-9]?\\$?$/D', $name) === 1;
}

function nameType(string $name): string
{
    return str_ends_with($name, '$') ? 'S' : 'I';
}

function valueType(int|string $value): string
{
    return is_string($value) ? 'S' : 'I';
}

function node(string $kind, string $type, mixed $value, array $args = []): object
{
    return (object)['kind' => $kind, 'type' => $type, 'value' => $value, 'args' => $args];
}

function stmt(string $kind): object
{
    return (object)[
        'kind' => $kind, 'line' => 0, 'next' => null,
        'expr' => null, 'target' => null, 'targets' => [],
        'expressions' => [], 'values' => [], 'numbers' => [],
        'name' => '', 'mode' => '', 'clauses' => [], 'items' => []
    ];
}

function tokenize(string $source): array
{
    $tokens = [];
    $length = strlen($source);
    $p = 0;
    while ($p < $length) {
        $ch = $source[$p];
        if ($ch === ' ') {
            $p++;
        } elseif ($ch === '"') {
            $end = strpos($source, '"', $p + 1);
            if ($end === false) badSyntax();
            $tokens[] = (object)[
                'kind' => 'S', 'text' => substr($source, $p, $end - $p + 1),
                'value' => substr($source, $p + 1, $end - $p - 1)
            ];
            $p = $end + 1;
        } elseif (ctype_digit($ch)) {
            $start = $p;
            while ($p < $length && ctype_digit($source[$p])) $p++;
            $word = substr($source, $start, $p - $start);
            $value = (int)$word;
            if ($value > 32767 || strlen($word) > 5) badSyntax();
            $tokens[] = (object)['kind' => 'I', 'text' => $word, 'value' => $value];
        } elseif ($ch >= 'A' && $ch <= 'Z') {
            if (substr($source, $p, 3) === 'REM') {
                $tokens[] = (object)['kind' => 'W', 'text' => 'REM', 'value' => 'REM'];
                break;
            }
            $start = $p;
            while ($p < $length && (($source[$p] >= 'A' && $source[$p] <= 'Z') ||
                   ctype_digit($source[$p]))) $p++;
            if ($p < $length && $source[$p] === '$') $p++;
            $word = substr($source, $start, $p - $start);
            $tokens[] = (object)['kind' => 'W', 'text' => $word, 'value' => $word];
        } else {
            if (!str_contains('+-*/^=<>() ,;:', $ch)) badSyntax();
            $two = substr($source, $p, 2);
            $word = in_array($two, ['<>', '<=', '>='], true) ? $two : $ch;
            $tokens[] = (object)['kind' => 'P', 'text' => $word, 'value' => $word];
            $p += strlen($word);
        }
    }
    $tokens[] = (object)['kind' => 'E', 'text' => '', 'value' => ''];
    return $tokens;
}

final class Parser
{
    private int $position = 0;

    public function __construct(private array $tokens) {}

    private function current(): object
    {
        return $this->tokens[$this->position];
    }

    private function at(string $word): bool
    {
        $token = $this->current();
        return ($token->kind === 'W' || $token->kind === 'P') &&
               $token->text === $word;
    }

    private function take(string $word): bool
    {
        if (!$this->at($word)) return false;
        $this->position++;
        return true;
    }

    private function expect(string $word): void
    {
        if (!$this->take($word)) badSyntax();
    }

    private function integer(): object
    {
        $result = $this->expression();
        if ($result->type !== 'I') badSyntax();
        return $result;
    }

    private function integerAt(int $level): object
    {
        $result = $this->expression($level);
        if ($result->type !== 'I') badSyntax();
        return $result;
    }

    private function number(): int
    {
        $token = $this->current();
        if ($token->kind !== 'I') badSyntax();
        $this->position++;
        return $token->value;
    }

    private function target(): object
    {
        $token = $this->current();
        if ($token->kind !== 'W' || !variableName($token->text)) badSyntax();
        $this->position++;
        $args = [];
        if ($this->take('(')) {
            $args[] = $this->integer();
            if ($this->take(',')) $args[] = $this->integer();
            $this->expect(')');
        }
        return node($args === [] ? 'variable' : 'array',
                    nameType($token->text), $token->text, $args);
    }

    private function expression(int $level = 0): object
    {
        if ($level === 2 && $this->take('NOT')) {
            return node('unary', 'I', 'NOT', [$this->integerAt(2)]);
        }
        if ($level === 6 && $this->take('-')) {
            return node('unary', 'I', '-', [$this->integerAt(6)]);
        }
        if ($level === 8) return $this->primary();
        $left = $this->expression($level + 1);
        while (in_array($this->current()->text, OPERATORS[$level], true)) {
            $operation = $this->current()->text;
            $this->position++;
            $right = $this->expression($level === 7 ? 6 : $level + 1);
            if ($left->type !== $right->type ||
                ($left->type === 'S' && $level !== 3 && $operation !== '+')) badSyntax();
            $left = node('binary', $level === 3 ? 'I' : $left->type,
                         $operation, [$left, $right]);
            if ($level === 7) break;
        }
        return $left;
    }

    private function primary(): object
    {
        $token = $this->current();
        if ($token->kind === 'I' || $token->kind === 'S') {
            $this->position++;
            return node('constant', $token->kind, $token->value);
        }
        if ($this->take('(')) {
            $result = $this->expression();
            $this->expect(')');
            return $result;
        }
        if ($token->kind === 'W' && variableName($token->text)) {
            return $this->target();
        }
        if ($this->take('ERR')) return node('builtin', 'I', 'ERR');
        if ($this->take('ERL')) return node('builtin', 'I', 'ERL');
        if ($token->kind === 'W' && isset(SIGNATURES[$token->text])) {
            $this->position++;
            $this->expect('(');
            $args = [$this->expression()];
            while ($this->take(',')) $args[] = $this->expression();
            $this->expect(')');
            $signature = implode('', array_map(fn($arg) => $arg->type, $args));
            if (!in_array($signature, SIGNATURES[$token->text], true)) badSyntax();
            return node('call', nameType($token->text), $token->text, $args);
        }
        badSyntax();
    }

    private function clause(): object
    {
        if ($this->current()->kind === 'I') {
            return (object)['line' => $this->number(), 'body' => []];
        }
        return (object)['line' => null, 'body' => $this->listing(true)];
    }

    private function listing(bool $inClause = false): array
    {
        $result = [$this->statement($inClause)];
        while ($this->take(':')) $result[] = $this->statement($inClause);
        return $result;
    }

    private function statement(bool $inClause): object
    {
        $word = $this->current()->text;
        if ($inClause && in_array($word,
            ['IF', 'FOR', 'NEXT', 'WHILE', 'WEND', 'DATA'], true)) badSyntax();
        $s = stmt($word);
        foreach (['REM', 'RETURN', 'WEND', 'END', 'STOP'] as $kind) {
            if ($this->take($kind)) return $s;
        }
        if ($this->take('PRINT')) {
            $expressionLast = false;
            while ($this->current()->kind !== 'E' && !$this->at(':') &&
                   !$this->at('ELSE')) {
                if ($this->take(';')) {
                    $s->items[] = (object)['kind' => ';', 'expr' => null];
                    $expressionLast = false;
                } elseif ($this->take(',')) {
                    $s->items[] = (object)['kind' => ',', 'expr' => null];
                    $expressionLast = false;
                } else {
                    $kind = $this->at('TAB') ? 'TAB' :
                           ($this->at('SPC') ? 'SPC' : 'value');
                    if ($kind === 'value' && $expressionLast) badSyntax();
                    if ($kind === 'value') {
                        $e = $this->expression();
                    } else {
                        $this->position++;
                        $this->expect('(');
                        $e = $this->integer();
                        $this->expect(')');
                    }
                    $s->items[] = (object)['kind' => $kind, 'expr' => $e];
                    $expressionLast = $kind === 'value';
                }
            }
            return $s;
        }
        if ($this->take('INPUT') || $this->take('READ') || $this->take('DIM')) {
            do {
                $target = $this->target();
                if ($word === 'DIM' && $target->kind !== 'array') badSyntax();
                $s->targets[] = $target;
            } while ($this->take(','));
            return $s;
        }
        if ($this->take('DATA')) {
            do {
                $negative = $this->take('-');
                $token = $this->current();
                if ($token->kind !== 'I' &&
                    ($token->kind !== 'S' || $negative)) badSyntax();
                $this->position++;
                $s->values[] = $negative ? -$token->value : $token->value;
            } while ($this->take(','));
            return $s;
        }
        if ($this->take('IF')) {
            $s->expr = $this->integer();
            $this->expect('THEN');
            $s->clauses[] = $this->clause();
            if ($this->take('ELSE')) $s->clauses[] = $this->clause();
            if ($this->current()->kind !== 'E') badSyntax();
            return $s;
        }
        if ($this->take('GOTO') || $this->take('GOSUB')) {
            $s->numbers[] = $this->number();
            return $s;
        }
        if ($this->take('ON')) {
            if ($this->take('ERROR')) {
                $s->kind = 'handler';
                $this->expect('GOTO');
                $s->numbers[] = $this->number();
            } else {
                $s->expr = $this->integer();
                if ($this->take('GOTO')) {
                    $s->mode = 'GOTO';
                } else {
                    $this->expect('GOSUB');
                    $s->mode = 'GOSUB';
                }
                $s->numbers[] = $this->number();
                while ($this->take(',')) $s->numbers[] = $this->number();
            }
            return $s;
        }
        if ($this->take('RESUME')) {
            if ($this->take('NEXT')) {
                $s->mode = 'NEXT';
            } elseif ($this->current()->kind === 'I') {
                $s->mode = 'line';
                $s->numbers[] = $this->number();
            }
            return $s;
        }
        if ($this->take('FOR')) {
            $token = $this->current();
            if ($token->kind !== 'W' || !variableName($token->text) ||
                nameType($token->text) !== 'I') badSyntax();
            $s->name = $token->text;
            $this->position++;
            $this->expect('=');
            $s->expressions[] = $this->integer();
            $this->expect('TO');
            $s->expressions[] = $this->integer();
            $s->expressions[] = $this->take('STEP')
                ? $this->integer() : node('constant', 'I', 1);
            return $s;
        }
        if ($this->take('NEXT')) {
            $token = $this->current();
            if ($token->kind === 'W' && variableName($token->text) &&
                nameType($token->text) === 'I') {
                $s->name = $token->text;
                $this->position++;
            }
            return $s;
        }
        if ($this->take('WHILE') || $this->take('RANDOMIZE')) {
            $s->expr = $this->integer();
            return $s;
        }
        if ($this->take('RESTORE')) {
            if ($this->current()->kind === 'I') $s->numbers[] = $this->number();
            return $s;
        }
        $this->take('LET');
        $s->kind = 'assign';
        $s->target = $this->target();
        $this->expect('=');
        $s->expr = $this->expression();
        if ($s->expr->type !== $s->target->type) badSyntax();
        return $s;
    }

    public function parse(): array
    {
        $result = $this->listing();
        if ($this->current()->kind !== 'E') badSyntax();
        return $result;
    }
}

final class Machine
{
    private array $variables = [];
    private array $arrays = [];
    private array $stack = [];
    private array $entries = [];
    private array $sequence = [];
    private array $data = [];
    private int $dataPosition = 0;
    private int $inputPosition = 0;
    private int $random = 1;
    private int $handler = 0;
    private bool $handling = false;
    private ?object $remembered = null;
    private int $err = 0;
    private int $erl = 0;
    private string $buffer = '';
    private array $output = [];

    public function __construct(private array $inputs) {}

    private function endLine(): void
    {
        $this->output[] = rtrim($this->buffer, ' ');
        $this->buffer = '';
    }

    private function message(string $text): void
    {
        if ($this->buffer !== '') $this->endLine();
        $this->output[] = $text;
    }

    private function checked(int|float $value): int
    {
        if ($value < -32768 || $value > 32767) fault('OVERFLOW');
        return (int)$value;
    }

    private function get(string $name): int|string
    {
        return $this->variables[$name] ?? (nameType($name) === 'S' ? '' : 0);
    }

    private function declare(string $name, array $bounds): void
    {
        $size = 1;
        foreach ($bounds as $bound) $size *= $bound + 1;
        $initial = nameType($name) === 'S' ? '' : 0;
        $this->arrays[$name] = ['bounds' => $bounds,
                                'values' => array_fill(0, $size, $initial)];
    }

    private function address(object $target): array
    {
        $name = $target->value;
        if ($target->kind === 'variable') return ['name' => $name, 'index' => null];
        $indices = [];
        foreach ($target->args as $e) $indices[] = $this->evaluate($e);
        if (!isset($this->arrays[$name])) {
            $this->declare($name, array_fill(0, count($indices), 10));
        }
        $array = $this->arrays[$name];
        if (count($indices) !== count($array['bounds'])) fault('SUBSCRIPT OUT OF RANGE');
        $index = 0;
        foreach ($indices as $i => $value) {
            if ($value < 0 || $value > $array['bounds'][$i]) fault('SUBSCRIPT OUT OF RANGE');
            $index = $index * ($array['bounds'][$i] + 1) + $value;
        }
        return ['name' => $name, 'index' => $index];
    }

    private function load(array $address): int|string
    {
        if ($address['index'] === null) return $this->get($address['name']);
        return $this->arrays[$address['name']]['values'][$address['index']];
    }

    private function store(array $address, int|string $value): void
    {
        if ($address['index'] === null) {
            $this->variables[$address['name']] = $value;
        } else {
            $this->arrays[$address['name']]['values'][$address['index']] = $value;
        }
    }

    private function evaluate(object $e): int|string
    {
        $op = $e->value;
        if ($e->kind === 'constant') return $op;
        if ($e->kind === 'variable' || $e->kind === 'array') {
            return $this->load($this->address($e));
        }
        if ($e->kind === 'builtin') return $op === 'ERR' ? $this->err : $this->erl;
        if ($e->kind === 'unary') {
            $a = $this->evaluate($e->args[0]);
            return $op === 'NOT' ? ~$a : $this->checked(-$a);
        }
        $args = [];
        foreach ($e->args as $arg) $args[] = $this->evaluate($arg);
        if ($e->kind === 'call') return $this->callFunction($op, $args);
        [$a, $b] = $args;
        if (in_array($op, OPERATORS[3], true)) {
            $comparison = is_string($a) ? strcmp($a, $b) : ($a <=> $b);
            $result = match ($op) {
                '=' => $comparison === 0,
                '<>' => $comparison !== 0,
                '<' => $comparison < 0,
                '>' => $comparison > 0,
                '<=' => $comparison <= 0,
                '>=' => $comparison >= 0
            };
            return $result ? -1 : 0;
        }
        if ($e->type === 'S') {
            $text = $a . $b;
            if (strlen($text) > 255) fault('STRING TOO LONG');
            return $text;
        }
        return match ($op) {
            '+' => $this->checked($a + $b),
            '-' => $this->checked($a - $b),
            '*' => $this->checked($a * $b),
            '/' => $this->quotient($a, $b),
            'MOD' => $this->remainder($a, $b),
            '^' => $this->exponent($a, $b),
            'AND' => $a & $b,
            'OR' => $a | $b,
            default => throw new BasicFault('ILLEGAL FUNCTION CALL')
        };
    }

    private function quotient(int $a, int $b): int
    {
        if ($b === 0) fault('DIVISION BY ZERO');
        return $this->checked(intdiv($a, $b));
    }

    private function remainder(int $a, int $b): int
    {
        if ($b === 0) fault('DIVISION BY ZERO');
        return $a - $b * intdiv($a, $b);
    }

    private function exponent(int $a, int $b): int
    {
        if ($b < 0) fault('ILLEGAL FUNCTION CALL');
        if (abs($a) > 1 && $b > 15) fault('OVERFLOW');
        return $this->checked($a ** $b);
    }

    private function callFunction(string $name, array $args): int|string
    {
        $a = $args[0];
        $b = $args[1] ?? null;
        $c = $args[2] ?? null;
        switch ($name) {
            case 'ABS':
                return $this->checked(abs($a));
            case 'SGN':
                return $a <=> 0;
            case 'INT':
                return $a;
            case 'SQR':
                if ($a < 0) fault('ILLEGAL FUNCTION CALL');
                return (int)floor(sqrt($a));
            case 'RND':
                if ($a < 1) fault('ILLEGAL FUNCTION CALL');
                $this->random = ($this->random * 48271) % 2147483647;
                return $this->random % $a + 1;
            case 'LEN':
                return strlen($a);
            case 'ASC':
                if ($a === '') fault('ILLEGAL FUNCTION CALL');
                return ord($a[0]);
            case 'VAL':
                preg_match('/^ *([+-]?[0-9]+)/', $a, $m);
                return $this->checked(isset($m[1]) ? (int)$m[1] : 0);
            case 'CHR$':
                if ($a < 32 || $a > 126) fault('ILLEGAL FUNCTION CALL');
                return chr($a);
            case 'STR$':
                return (string)$a;
            case 'LEFT$':
                if ($b < 0) fault('ILLEGAL FUNCTION CALL');
                return substr($a, 0, $b);
            case 'RIGHT$':
                if ($b < 0) fault('ILLEGAL FUNCTION CALL');
                return $b === 0 ? '' : substr($a, -min($b, strlen($a)));
            case 'MID$':
                if ($b < 1 || ($c !== null && $c < 0)) fault('ILLEGAL FUNCTION CALL');
                return $c !== null ? substr($a, $b - 1, $c) : substr($a, $b - 1);
            case 'INSTR':
                $index = strpos($a, $b);
                return $index === false ? 0 : $index + 1;
        }
        fault('ILLEGAL FUNCTION CALL');
    }

    private function line(int $number): object
    {
        if (!isset($this->entries[$number])) fault('UNDEFINED LINE NUMBER');
        return $this->entries[$number];
    }

    private function push(array $frame): void
    {
        if (count($this->stack) === 100) fault('OUT OF MEMORY');
        $this->stack[] = $frame;
    }

    private function search(string $kind, string $name = ''): ?int
    {
        for ($i = count($this->stack) - 1; $i >= 0; --$i) {
            $frame = $this->stack[$i];
            if ($frame['kind'] === 'GOSUB') break;
            if ($frame['kind'] === $kind &&
                ($name === '' || $frame['name'] === $name)) return $i;
        }
        return null;
    }

    private function matching(object $s, string $opening, string $closing): ?object
    {
        $start = array_search($s, $this->sequence, true);
        $depth = 0;
        for ($i = $start + 1; $i < count($this->sequence); ++$i) {
            $t = $this->sequence[$i];
            if ($t->kind === $opening) {
                $depth++;
            } elseif ($t->kind === $closing) {
                if ($depth === 0) return $t->next;
                $depth--;
            }
        }
        fault($opening . ' WITHOUT ' . $closing);
    }

    private function subroutine(int $number, ?object $after): object
    {
        $target = $this->line($number);
        $this->push(['kind' => 'GOSUB', 'position' => $after, 'name' => '']);
        return $target;
    }

    private function execute(object $s): ?object
    {
        $following = $s->next;
        switch ($s->kind) {
            case 'assign':
                $address = $this->address($s->target);
                $this->store($address, $this->evaluate($s->expr));
                break;
            case 'PRINT':
                foreach ($s->items as $item) {
                    if ($item->kind === ',') {
                        $this->buffer .= str_repeat(' ', 10 - strlen($this->buffer) % 10);
                    } elseif ($item->kind !== ';') {
                        $value = $this->evaluate($item->expr);
                        if ($item->kind === 'value') {
                            $this->buffer .= (string)$value;
                        } else {
                            if ($value < 0) fault('ILLEGAL FUNCTION CALL');
                            $amount = $item->kind === 'SPC' ? $value :
                                max(0, $value - strlen($this->buffer));
                            $this->buffer .= str_repeat(' ', $amount);
                        }
                    }
                }
                $last = $s->items === [] ? null : end($s->items);
                if ($last === null || ($last->kind !== ';' && $last->kind !== ',')) {
                    $this->endLine();
                }
                break;
            case 'INPUT':
            case 'READ':
                foreach ($s->targets as $target) {
                    $address = $this->address($target);
                    if ($s->kind === 'READ') {
                        if ($this->dataPosition >= count($this->data)) fault('OUT OF DATA');
                        $value = $this->data[$this->dataPosition++]['value'];
                        if (valueType($value) !== $target->type) fault('TYPE MISMATCH');
                    } else {
                        while (true) {
                            if ($this->inputPosition >= count($this->inputs)) fault('INPUT PAST END');
                            $word = $this->inputs[$this->inputPosition++];
                            if ($target->type === 'S') {
                                $value = $word;
                                break;
                            }
                            if (preg_match('/^-?[0-9]+$/D', $word)) {
                                $n = (int)$word;
                                if ($n >= -32768 && $n <= 32767) {
                                    $value = $n;
                                    break;
                                }
                            }
                            $this->message('?REDO FROM START');
                        }
                    }
                    $this->store($address, $value);
                }
                break;
            case 'RESTORE':
                if ($s->numbers === []) {
                    $this->dataPosition = 0;
                } else {
                    $number = $s->numbers[0];
                    $this->line($number);
                    $this->dataPosition = count($this->data);
                    foreach ($this->data as $i => $entry) {
                        if ($entry['line'] >= $number) {
                            $this->dataPosition = $i;
                            break;
                        }
                    }
                }
                break;
            case 'IF':
                $index = $this->evaluate($s->expr) === 0 ? 1 : 0;
                $chosen = $s->clauses[$index] ?? null;
                if ($chosen !== null) {
                    $following = $chosen->line !== null
                        ? $this->line($chosen->line) : $chosen->body[0];
                }
                break;
            case 'GOTO':
                $following = $this->line($s->numbers[0]);
                break;
            case 'GOSUB':
                $following = $this->subroutine($s->numbers[0], $following);
                break;
            case 'ON':
                $n = $this->evaluate($s->expr);
                if ($n < 0) fault('ILLEGAL FUNCTION CALL');
                if ($n >= 1 && $n <= count($s->numbers)) {
                    $following = $s->mode === 'GOTO'
                        ? $this->line($s->numbers[$n - 1])
                        : $this->subroutine($s->numbers[$n - 1], $following);
                }
                break;
            case 'RETURN':
                $index = null;
                for ($i = count($this->stack) - 1; $i >= 0; --$i) {
                    if ($this->stack[$i]['kind'] === 'GOSUB') {
                        $index = $i;
                        break;
                    }
                }
                if ($index === null) fault('RETURN WITHOUT GOSUB');
                $following = $this->stack[$index]['position'];
                array_splice($this->stack, $index);
                break;
            case 'FOR':
                $values = [];
                foreach ($s->expressions as $e) $values[] = $this->evaluate($e);
                [$start, $final, $step] = $values;
                if ($step === 0) fault('ILLEGAL FUNCTION CALL');
                $index = $this->search('FOR', $s->name);
                if ($index !== null) array_splice($this->stack, $index);
                $this->variables[$s->name] = $start;
                if (($step > 0 && $start > $final) ||
                    ($step < 0 && $start < $final)) {
                    $following = $this->matching($s, 'FOR', 'NEXT');
                } else {
                    $this->push(['kind' => 'FOR', 'position' => $following,
                                 'name' => $s->name, 'final' => $final, 'step' => $step]);
                }
                break;
            case 'NEXT':
                $index = $this->search('FOR', $s->name);
                if ($index === null) fault('NEXT WITHOUT FOR');
                array_splice($this->stack, $index + 1);
                $frame = $this->stack[$index];
                $value = $this->checked($this->get($frame['name']) + $frame['step']);
                $this->variables[$frame['name']] = $value;
                if (($frame['step'] > 0 && $value > $frame['final']) ||
                    ($frame['step'] < 0 && $value < $frame['final'])) {
                    array_pop($this->stack);
                } else {
                    $following = $frame['position'];
                }
                break;
            case 'WHILE':
                if ($this->evaluate($s->expr) === 0) {
                    $following = $this->matching($s, 'WHILE', 'WEND');
                } else {
                    $this->push(['kind' => 'WHILE', 'position' => $s, 'name' => '']);
                }
                break;
            case 'WEND':
                $index = $this->search('WHILE');
                if ($index === null) fault('WEND WITHOUT WHILE');
                $following = $this->stack[$index]['position'];
                array_splice($this->stack, $index);
                break;
            case 'DIM':
                foreach ($s->targets as $target) {
                    $name = $target->value;
                    $bounds = [];
                    foreach ($target->args as $e) $bounds[] = $this->evaluate($e);
                    if (isset($this->arrays[$name])) fault('DUPLICATE DEFINITION');
                    $size = 1;
                    foreach ($bounds as $bound) {
                        if ($bound < 0) fault('ILLEGAL FUNCTION CALL');
                        $size *= $bound + 1;
                    }
                    if ($size > 10000) fault('OUT OF MEMORY');
                    $this->declare($name, $bounds);
                }
                break;
            case 'RANDOMIZE':
                $n = $this->evaluate($s->expr);
                if ($n < 1) fault('ILLEGAL FUNCTION CALL');
                $this->random = $n;
                break;
            case 'handler':
                if ($s->numbers[0] !== 0) $this->line($s->numbers[0]);
                $this->handler = $s->numbers[0];
                break;
            case 'RESUME':
                if (!$this->handling) fault('RESUME WITHOUT ERROR');
                $following = match ($s->mode) {
                    'line' => $this->line($s->numbers[0]),
                    'NEXT' => $this->remembered->next,
                    default => $this->remembered
                };
                $this->handling = false;
                break;
            case 'STOP':
                $this->message('BREAK IN LINE ' . $s->line);
                return null;
            case 'END':
                return null;
        }
        return $following;
    }

    private function connect(array $body, ?object $after, int $number): void
    {
        $following = $after;
        for ($i = count($body) - 1; $i >= 0; --$i) {
            $s = $body[$i];
            $s->line = $number;
            $s->next = $following;
            foreach ($s->clauses as $clause) {
                $this->connect($clause->body, $following, $number);
            }
            $following = $s;
        }
    }

    private function finish(): array
    {
        if ($this->buffer !== '') $this->endLine();
        $this->output[] = 'READY';
        return $this->output;
    }

    public function run(array $source): array
    {
        ksort($source, SORT_NUMERIC);
        $parsed = [];
        foreach ($source as $number => $code) {
            try {
                $parsed[] = ['number' => $number,
                             'body' => (new Parser(tokenize($code)))->parse()];
            } catch (SyntaxFault $error) {
                $this->message('ERROR IN LINE ' . $number . ': SYNTAX ERROR');
                return $this->finish();
            }
        }
        $after = null;
        for ($i = count($parsed) - 1; $i >= 0; --$i) {
            $entry = $parsed[$i];
            $this->connect($entry['body'], $after, $entry['number']);
            $this->entries[$entry['number']] = $entry['body'][0];
            $after = $entry['body'][0];
        }
        foreach ($parsed as $entry) {
            foreach ($entry['body'] as $s) {
                $this->sequence[] = $s;
                if ($s->kind === 'DATA') {
                    foreach ($s->values as $value) {
                        $this->data[] = ['line' => $s->line, 'value' => $value];
                    }
                }
            }
        }
        $position = $after;
        while ($position !== null) {
            $current = $position;
            try {
                $position = $this->execute($current);
            } catch (BasicFault $error) {
                if ($this->handler !== 0 && !$this->handling) {
                    $this->err = ERROR_CODES[$error->getMessage()] ?? 0;
                    $this->erl = $current->line;
                    $this->remembered = $current;
                    $this->handling = true;
                    try {
                        $position = $this->line($this->handler);
                    } catch (BasicFault $secondary) {
                        $this->message('ERROR IN LINE ' . $current->line .
                                       ': ' . $secondary->getMessage());
                        $position = null;
                    }
                } else {
                    $this->message('ERROR IN LINE ' . $current->line .
                                   ': ' . $error->getMessage());
                    $position = null;
                }
            }
        }
        return $this->finish();
    }
}

$lines = file('php://stdin', FILE_IGNORE_NEW_LINES);
$lines = array_map(fn($line) => rtrim($line, "\r"), $lines);
$count = (int)$lines[0];
$cursor = 1;
$output = [];
for ($program = 0; $program < $count; ++$program) {
    $source = [];
    while ($lines[$cursor] !== 'RUN') {
        $line = $lines[$cursor++];
        preg_match('/^([0-9]+)(?: +(.*))?$/D', $line, $parts);
        $number = (int)$parts[1];
        if (isset($parts[2])) $source[$number] = $parts[2];
        else unset($source[$number]);
    }
    $cursor++;
    $inputs = [];
    while ($lines[$cursor] !== 'END') $inputs[] = $lines[$cursor++];
    $cursor++;
    array_push($output, ...(new Machine($inputs))->run($source));
}
echo implode("\n", $output), "\n";
