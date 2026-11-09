<?php
class ForthError extends Exception
{
    public function __construct(public string $word, public string $reason, public ?int $forthCode = null)
    {
        parent::__construct($reason);
    }
}

class ForthWord
{
    public array $code = [];
    public int $localCount = 0;
    public ?ForthWord $doesWord = null;
    public int $doesStart = 0;
    public ?int $xt = null;

    public function __construct(
        public string $name,
        public string $kind,
        public ?int $value = null,
        public int $here = 0
    ) {}
}

class Forth
{
    private const COMPILE_ONLY = ['IF', 'ELSE', 'THEN', 'DO', '?DO', 'LOOP', '+LOOP', 'LEAVE',
        'UNLOOP', 'I', 'J', 'BEGIN', 'UNTIL', 'WHILE', 'REPEAT', 'AGAIN', 'CASE', 'OF',
        'ENDOF', 'ENDCASE', 'EXIT', 'RECURSE', 'DOES>', ';', '>R', 'R>', 'R@', 'ABORT"', "[']", '{:'];
    private const INTERPRET_ONLY = [':', ':NONAME', 'FORGET'];
    private const BUILTINS = ['+', '-', '*', '/', 'MOD', '/MOD', '*/', '*/MOD', 'NEGATE', 'ABS',
        'MIN', 'MAX', '1+', '1-', '2*', '2/', '=', '<>', '<', '>', '0=', '0<>', '0<', '0>',
        'WITHIN', 'TRUE', 'FALSE', 'AND', 'OR', 'XOR', 'INVERT', 'DUP', '?DUP', 'DROP',
        'SWAP', 'OVER', 'ROT', '-ROT', 'NIP', 'TUCK', '2DUP', '2DROP', '2SWAP', '2OVER',
        'DEPTH', 'PICK', 'ROLL', '.', '.R', '.S', '?', 'CR', 'EMIT', 'SPACE', 'SPACES',
        'BL', '!', '@', '+!', ',', 'ALLOT', 'HERE', 'CELLS', 'CELL+', 'BASE', 'HEX', 'DECIMAL',
        'CREATE', 'VARIABLE', 'CONSTANT', 'VALUE', 'DEFER', "'", 'EXECUTE', 'CATCH', 'THROW', 'ABORT', 'WORDS'];
    private const CODES = ['aborted' => -1, 'stack overflow' => -3, 'stack underflow' => -4,
        'return stack overflow' => -5, 'return stack underflow' => -6, 'nesting too deep' => -7,
        'invalid address' => -9, 'division by zero' => -10, 'undefined word' => -13,
        'missing name' => -16, 'invalid name' => -19, 'deferred word not set' => -21,
        'invalid argument' => -24, 'no CREATE word' => -31, 'invalid base' => -40];
    private array $stack = [];
    private array $returns = [];
    private array $memory = [10];
    private array $dictionary = [];
    private array $builtins = [];
    private array $tokens = [];
    private string $pending = '';
    private ?ForthWord $compiling = null;
    private array $control = [];
    private array $locals = [];
    private int $depth = 0;
    private string $line = '';
    private int $position = 0;
    private string $definitionName = '';
    private bool $anonymous = false;

    public function __construct()
    {
        foreach (self::BUILTINS as $name) {
            $this->builtins[$name] = new ForthWord($name, 'builtin');
        }
    }

    private function fail(string $word, string $reason, ?int $code = null): never
    {
        throw new ForthError($word, $reason, $code ?? (self::CODES[$reason] ?? null));
    }

    private function readWord(): ?string
    {
        $length = strlen($this->line);
        while ($this->position < $length && $this->line[$this->position] === ' ') {
            $this->position++;
        }
        if ($this->position === $length) {
            return null;
        }
        $start = $this->position;
        while ($this->position < $length && $this->line[$this->position] !== ' ') {
            $this->position++;
        }
        return substr($this->line, $start, $this->position - $start);
    }

    private function readName(string $source): string
    {
        return $this->readWord() ?? $this->fail($source, 'missing name');
    }

    private function number(string $text, ?int $base = null): ?int
    {
        $base ??= $this->memory[0];
        if (strlen($text) === 3 && $text[0] === "'" && $text[2] === "'") {
            return ord($text[1]);
        }
        if ($text !== '' && str_contains('$#%', $text[0])) {
            $base = ['$' => 16, '#' => 10, '%' => 2][$text[0]];
            $text = substr($text, 1);
        } elseif ($base < 2 || $base > 36) {
            $this->fail($text, 'invalid base');
        }
        $negative = str_starts_with($text, '-');
        $digits = strtoupper($negative ? substr($text, 1) : $text);
        if ($digits === '') {
            return null;
        }
        $values = [];
        foreach (str_split($digits) as $c) {
            $ord = ord($c);
            $d = $ord >= 48 && $ord <= 57 ? $ord - 48 : ($ord >= 65 && $ord <= 90 ? $ord - 55 : -1);
            if ($d < 0 || $d >= $base) {
                return null;
            }
            $values[] = $d;
        }
        $result = 0;
        foreach ($values as $d) {
            $result = $result * $base + $d;
        }
        return $negative ? -$result : $result;
    }

    private function checkName(string $name): string
    {
        $key = strtoupper($name);
        $special = array_merge(self::COMPILE_ONLY, self::INTERPRET_ONLY, ['."', '(', '\\', 'TO', 'IS']);
        if (in_array($key, $special, true) || $this->number($name, 10) !== null) {
            $this->fail($name, 'invalid name');
        }
        return $key;
    }

    private function lookup(string $name): ?ForthWord
    {
        $key = strtoupper($name);
        for ($i = count($this->dictionary) - 1; $i >= 0; $i--) {
            if ($this->dictionary[$i]->name === $key) {
                return $this->dictionary[$i];
            }
        }
        return $this->builtins[$key] ?? null;
    }

    private function token(ForthWord $word): int
    {
        if ($word->xt === null) {
            $this->tokens[] = $word;
            $word->xt = count($this->tokens);
        }
        return $word->xt;
    }

    private function validToken(int $value): bool
    {
        return $value >= 1 && $value <= count($this->tokens);
    }

    private function take(int $count, string $source): array
    {
        if (count($this->stack) < $count) {
            $this->fail($source, 'stack underflow');
        }
        return $count === 0 ? [] : array_splice($this->stack, -$count);
    }

    private function push(int $value, string $source): void
    {
        $this->stack[] = $value;
        if (count($this->stack) > 1000) {
            $this->fail($source, 'stack overflow');
        }
    }

    private function pushAll(array $values, string $source): void
    {
        foreach ($values as $value) {
            $this->push($value, $source);
        }
    }

    private function returnNeed(int $count, string $source): void
    {
        if (count($this->returns) < $count) {
            $this->fail($source, 'return stack underflow');
        }
    }

    private function returnPush(int $value, string $source): void
    {
        $this->returns[] = $value;
        if (count($this->returns) > 1000) {
            $this->fail($source, 'return stack overflow');
        }
    }

    private function address(int $value, string $source): int
    {
        if ($value < 0 || $value % 8 !== 0 || $value >= count($this->memory) * 8) {
            $this->fail($source, 'invalid address');
        }
        return intdiv($value, 8);
    }

    private function outputNumber(int $value, string $source): string
    {
        $base = $this->memory[0];
        if ($base < 2 || $base > 36) {
            $this->fail($source, 'invalid base');
        }
        $n = abs($value);
        $digits = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
        $text = '';
        do {
            $text = $digits[$n % $base] . $text;
            $n = intdiv($n, $base);
        } while ($n > 0);
        return ($value < 0 ? '-' : '') . $text;
    }

    private function flush(): void
    {
        echo rtrim($this->pending, ' '), "\n";
        $this->pending = '';
    }

    private function emit(string $op, string $source, mixed ...$args): int
    {
        $this->compiling->code[] = array_merge([$op, $source], $args);
        return count($this->compiling->code) - 1;
    }

    private function mismatch(string $source, array $kinds): void
    {
        if ($this->control === [] || !in_array($this->control[array_key_last($this->control)]['kind'], $kinds, true)) {
            $this->fail($source, 'control structure mismatch');
        }
    }

    private function compile(string $source): void
    {
        $key = strtoupper($source);
        switch ($key) {
            case 'IF':
                $this->control[] = ['kind' => 'IF', 'at' => $this->emit('zero_jump', $source, null)];
                break;
            case 'ELSE':
                $this->mismatch($source, ['IF']);
                $old = array_pop($this->control);
                $index = $this->emit('jump', $source, null);
                $this->compiling->code[$old['at']][2] = count($this->compiling->code);
                $this->control[] = ['kind' => 'ELSE', 'at' => $index];
                break;
            case 'THEN':
                $this->mismatch($source, ['IF', 'ELSE']);
                $record = array_pop($this->control);
                $this->compiling->code[$record['at']][2] = count($this->compiling->code);
                break;
            case 'BEGIN':
                $this->control[] = ['kind' => 'BEGIN', 'begin' => count($this->compiling->code)];
                break;
            case 'UNTIL':
            case 'AGAIN':
                $this->mismatch($source, ['BEGIN']);
                $record = array_pop($this->control);
                $this->emit($key === 'UNTIL' ? 'zero_jump' : 'jump', $source, $record['begin']);
                break;
            case 'WHILE':
                $this->mismatch($source, ['BEGIN']);
                $record = array_pop($this->control);
                $this->control[] = ['kind' => 'WHILE', 'begin' => $record['begin'], 'at' => $this->emit('zero_jump', $source, null)];
                break;
            case 'REPEAT':
                $this->mismatch($source, ['WHILE']);
                $record = array_pop($this->control);
                $this->emit('jump', $source, $record['begin']);
                $this->compiling->code[$record['at']][2] = count($this->compiling->code);
                break;
            case 'DO':
            case '?DO':
                $this->control[] = ['kind' => $key, 'at' => $this->emit('do', $source, null, $key === '?DO'), 'leaves' => []];
                break;
            case 'LOOP':
            case '+LOOP':
                $this->mismatch($source, ['DO', '?DO']);
                $record = array_pop($this->control);
                $this->emit('loop', $source, $record['at'] + 1, $key === '+LOOP');
                $finish = count($this->compiling->code);
                $this->compiling->code[$record['at']][2] = $finish;
                foreach ($record['leaves'] as $at) {
                    $this->compiling->code[$at][2] = $finish;
                }
                break;
            case 'LEAVE':
                $found = null;
                for ($i = count($this->control) - 1; $i >= 0; $i--) {
                    if (in_array($this->control[$i]['kind'], ['DO', '?DO'], true)) {
                        $found = $i;
                        break;
                    }
                }
                if ($found === null) {
                    $this->fail($source, 'control structure mismatch');
                }
                $this->control[$found]['leaves'][] = $this->emit('leave', $source, null);
                break;
            case 'CASE':
                $this->control[] = ['kind' => 'CASE', 'ends' => []];
                break;
            case 'OF':
                $this->mismatch($source, ['CASE']);
                $this->control[] = ['kind' => 'OF', 'at' => $this->emit('of', $source, null)];
                break;
            case 'ENDOF':
                $this->mismatch($source, ['OF']);
                $record = array_pop($this->control);
                $this->control[array_key_last($this->control)]['ends'][] = $this->emit('jump', $source, null);
                $this->compiling->code[$record['at']][2] = count($this->compiling->code);
                break;
            case 'ENDCASE':
                $this->mismatch($source, ['CASE']);
                $record = array_pop($this->control);
                $this->emit('drop', $source);
                foreach ($record['ends'] as $at) {
                    $this->compiling->code[$at][2] = count($this->compiling->code);
                }
                break;
            case 'EXIT':
                $this->emit('exit', $source);
                break;
            case 'RECURSE':
                $this->emit('call', $source, $this->compiling);
                break;
            case 'DOES>':
                if ($this->control !== []) {
                    $this->fail($source, 'control structure mismatch');
                }
                $this->emit('does', $source, $this->compiling, count($this->compiling->code) + 1);
                break;
            case ';':
                if ($this->control !== []) {
                    $kind = $this->control[array_key_last($this->control)]['kind'];
                    $kind = ['ELSE' => 'IF', 'WHILE' => 'BEGIN'][$kind] ?? $kind;
                    $this->fail($source, 'unclosed ' . $kind);
                }
                $word = $this->compiling;
                $this->compiling = null;
                if ($this->anonymous) {
                    $this->push($this->token($word), $source);
                } else {
                    $this->dictionary[] = $word;
                }
                break;
            case "[']":
                $name = $this->readName($source);
                $word = $this->lookup($name) ?? $this->fail($name, 'undefined word');
                $this->emit('literal', $source, $this->token($word));
                break;
            case '{:':
                $names = [];
                while (true) {
                    $name = $this->readWord() ?? $this->fail($source, 'unterminated locals');
                    if (strtoupper($name) === ':}') {
                        break;
                    }
                    $names[] = $name;
                }
                $slots = [];
                foreach ($names as $name) {
                    if ($name === '--') {
                        break;
                    }
                    $keyName = $this->checkName($name);
                    $index = $this->compiling->localCount++;
                    $this->locals[$keyName] = $index;
                    $slots[] = $index;
                }
                $this->emit('locals', $source, $slots);
                break;
            case '>R':
            case 'R>':
            case 'R@':
            case 'I':
            case 'J':
            case 'UNLOOP':
                $this->emit('return_stack', $source, $key);
                break;
            default:
                if (array_key_exists($key, $this->locals)) {
                    $this->emit('local', $source, $this->locals[$key]);
                } elseif (($word = $this->lookup($source)) !== null) {
                    $this->emit('call', $source, $word);
                } elseif (($value = $this->number($source)) !== null) {
                    $this->emit('literal', $source, $value);
                } else {
                    $this->fail($source, 'undefined word');
                }
        }
    }

    private function process(string $source): void
    {
        $key = strtoupper($source);
        if ($key === '\\') {
            $this->position = strlen($this->line);
            return;
        }
        if ($key === '(') {
            $finish = strpos($this->line, ')', $this->position);
            if ($finish === false) {
                $this->fail($source, 'unterminated comment');
            }
            $this->position = $finish + 1;
            return;
        }
        if ($this->compiling === null && in_array($key, self::COMPILE_ONLY, true)) {
            $this->fail($source, 'compile only');
        }
        if ($this->compiling !== null && in_array($key, self::INTERPRET_ONLY, true)) {
            $this->fail($source, 'interpret only');
        }
        switch ($key) {
            case '."':
            case 'ABORT"':
                $start = $this->position + 1;
                $finish = $start <= strlen($this->line) ? strpos($this->line, '"', $start) : false;
                if ($this->position >= strlen($this->line) || $finish === false) {
                    $this->fail($source, 'unterminated string');
                }
                $text = substr($this->line, $start, $finish - $start);
                $this->position = $finish + 1;
                if ($this->compiling !== null) {
                    $this->emit($key === '."' ? 'write' : 'abort_string', $source, $text);
                } else {
                    $this->pending .= $text;
                }
                break;
            case 'TO':
            case 'IS':
                $name = $this->readName($source);
                if ($key === 'TO' && $this->compiling !== null && array_key_exists(strtoupper($name), $this->locals)) {
                    $this->emit('set_local', $source, $this->locals[strtoupper($name)]);
                    return;
                }
                $word = $this->lookup($name) ?? $this->fail($name, 'undefined word');
                if ($word->kind !== ($key === 'TO' ? 'value' : 'defer')) {
                    $this->fail($name, $key === 'TO' ? 'not a value' : 'not deferred');
                }
                if ($this->compiling !== null) {
                    $this->emit($key === 'TO' ? 'to' : 'is', $source, $word);
                } else {
                    $this->assignWord($word, $source, $key === 'IS');
                }
                break;
            case ':':
            case ':NONAME':
                $name = $key === ':' ? $this->readName($source) : $source;
                if ($key === ':') {
                    $this->checkName($name);
                }
                $this->compiling = new ForthWord(strtoupper($name), 'colon', null, count($this->memory) * 8);
                $this->definitionName = $name;
                $this->anonymous = $key === ':NONAME';
                $this->control = [];
                $this->locals = [];
                break;
            case 'FORGET':
                $name = $this->readName($source);
                $index = null;
                for ($i = count($this->dictionary) - 1; $i >= 0; $i--) {
                    if ($this->dictionary[$i]->name === strtoupper($name)) {
                        $index = $i;
                        break;
                    }
                }
                if ($index === null) {
                    $this->fail($name, 'undefined word');
                }
                $this->memory = array_slice($this->memory, 0, intdiv($this->dictionary[$index]->here, 8));
                $this->dictionary = array_slice($this->dictionary, 0, $index);
                break;
            default:
                if ($this->compiling !== null) {
                    $this->compile($source);
                } elseif (($word = $this->lookup($source)) !== null) {
                    $this->execute($word, $source);
                } elseif (($value = $this->number($source)) !== null) {
                    $this->push($value, $source);
                } else {
                    $this->fail($source, 'undefined word');
                }
        }
    }

    private function assignWord(ForthWord $word, string $source, bool $deferred): void
    {
        $value = $this->take(1, $source)[0];
        if ($deferred) {
            if (!$this->validToken($value)) {
                $this->fail($source, 'invalid argument');
            }
            $word->value = $value;
        } else {
            $this->memory[intdiv($word->value, 8)] = $value;
        }
    }

    private function returnOperation(string $key, string $source): void
    {
        switch ($key) {
            case '>R':
                $this->returnPush($this->take(1, $source)[0], $source);
                break;
            case 'R>':
                $this->returnNeed(1, $source);
                $this->push(array_pop($this->returns), $source);
                break;
            case 'R@':
            case 'I':
                $this->returnNeed(1, $source);
                $this->push($this->returns[count($this->returns) - 1], $source);
                break;
            case 'J':
                $this->returnNeed(3, $source);
                $this->push($this->returns[count($this->returns) - 3], $source);
                break;
            case 'UNLOOP':
                $this->returnNeed(2, $source);
                array_splice($this->returns, -2);
                break;
        }
    }

    private function executeDefinition(ForthWord $word, int $start, string $source): void
    {
        if ($this->depth === 100) {
            $this->fail($source, 'nesting too deep');
        }
        $this->depth++;
        $returnSize = count($this->returns);
        $locals = array_fill(0, $word->localCount, 0);
        $pc = $start;
        while ($pc < count($word->code)) {
            [$op, $spelling] = $instruction = $word->code[$pc++];
            $a = $instruction[2] ?? null;
            $b = $instruction[3] ?? null;
            switch ($op) {
                case 'literal':
                    $this->push($a, $spelling);
                    break;
                case 'call':
                    $this->execute($a, $spelling);
                    break;
                case 'write':
                    $this->pending .= $a;
                    break;
                case 'local':
                    $this->push($locals[$a], $spelling);
                    break;
                case 'set_local':
                    $locals[$a] = $this->take(1, $spelling)[0];
                    break;
                case 'locals':
                    $values = $this->take(count($a), $spelling);
                    foreach ($a as $i => $slot) {
                        $locals[$slot] = $values[$i];
                    }
                    break;
                case 'to':
                case 'is':
                    $this->assignWord($a, $spelling, $op === 'is');
                    break;
                case 'exit':
                    break 2;
                case 'does':
                    $created = $this->dictionary === [] ? null : $this->dictionary[array_key_last($this->dictionary)];
                    if ($created === null || $created->kind !== 'create') {
                        $this->fail($spelling, 'no CREATE word');
                    }
                    $created->doesWord = $a;
                    $created->doesStart = $b;
                    break 2;
                case 'jump':
                    $pc = $a;
                    break;
                case 'zero_jump':
                    if ($this->take(1, $spelling)[0] === 0) {
                        $pc = $a;
                    }
                    break;
                case 'do':
                    [$limit, $index] = $this->take(2, $spelling);
                    if ($b && $limit === $index) {
                        $pc = $a;
                    } else {
                        $this->returnPush($limit, $spelling);
                        $this->returnPush($index, $spelling);
                    }
                    break;
                case 'loop':
                    $step = $b ? $this->take(1, $spelling)[0] : 1;
                    $this->returnNeed(2, $spelling);
                    $last = count($this->returns) - 1;
                    $index = $this->returns[$last];
                    $limit = $this->returns[$last - 1];
                    $next = $index + $step;
                    if (($index - $limit < 0) !== ($next - $limit < 0)) {
                        array_splice($this->returns, -2);
                    } else {
                        $this->returns[$last] = $next;
                        $pc = $a;
                    }
                    break;
                case 'leave':
                    $this->returnNeed(2, $spelling);
                    array_splice($this->returns, -2);
                    $pc = $a;
                    break;
                case 'of':
                    [$x, $y] = $this->take(2, $spelling);
                    if ($x !== $y) {
                        $this->push($x, $spelling);
                        $pc = $a;
                    }
                    break;
                case 'drop':
                    $this->take(1, $spelling);
                    break;
                case 'return_stack':
                    $this->returnOperation($a, $spelling);
                    break;
                case 'abort_string':
                    if ($this->take(1, $spelling)[0] !== 0) {
                        $this->fail($spelling, $a, -2);
                    }
                    break;
            }
        }
        if (count($this->returns) > $returnSize) {
            $this->returns = array_slice($this->returns, 0, $returnSize);
        }
        $this->depth--;
    }

    private function executeToken(int $value, string $source): void
    {
        if (!$this->validToken($value)) {
            $this->fail($source, 'invalid argument');
        }
        $word = $this->tokens[$value - 1];
        $this->execute($word, $word->name);
    }

    private function execute(ForthWord $word, string $source): void
    {
        while ($word->kind === 'defer') {
            if ($word->value === null) {
                $this->fail($source, 'deferred word not set');
            }
            if (!$this->validToken($word->value)) {
                $this->fail($source, 'invalid argument');
            }
            $word = $this->tokens[$word->value - 1];
            $source = $word->name;
        }
        switch ($word->kind) {
            case 'colon':
                $this->executeDefinition($word, 0, $source);
                break;
            case 'create':
            case 'variable':
                $this->push($word->value, $source);
                if ($word->doesWord !== null) {
                    $this->executeDefinition($word->doesWord, $word->doesStart, $source);
                }
                break;
            case 'constant':
                $this->push($word->value, $source);
                break;
            case 'value':
                $this->push($this->memory[intdiv($word->value, 8)], $source);
                break;
            case 'builtin':
                $this->builtin($word->name, $source);
                break;
        }
    }

    private function divmod(int $a, int $b): array
    {
        $q = intdiv($a, $b);
        $r = $a % $b;
        if ($r !== 0 && (($a < 0) !== ($b < 0))) {
            $q--;
            $r += $b;
        }
        return [$q, $r];
    }

    private function builtin(string $key, string $source): void
    {
        if (in_array($key, ['+', '-', '*', '/', 'MOD', '/MOD', 'MIN', 'MAX', '=', '<>', '<', '>', 'AND', 'OR', 'XOR'], true)) {
            [$a, $b] = $this->take(2, $source);
            if (in_array($key, ['/', 'MOD', '/MOD'], true)) {
                if ($b === 0) {
                    $this->fail($source, 'division by zero');
                }
                [$q, $r] = $this->divmod($a, $b);
                $this->pushAll($key === '/' ? [$q] : ($key === 'MOD' ? [$r] : [$r, $q]), $source);
            } else {
                $result = match ($key) {
                    '+' => $a + $b, '-' => $a - $b, '*' => $a * $b,
                    'MIN' => min($a, $b), 'MAX' => max($a, $b),
                    '=' => $a === $b ? -1 : 0, '<>' => $a !== $b ? -1 : 0,
                    '<' => $a < $b ? -1 : 0, '>' => $a > $b ? -1 : 0,
                    'AND' => $a & $b, 'OR' => $a | $b, 'XOR' => $a ^ $b
                };
                $this->push($result, $source);
            }
            return;
        }
        if (in_array($key, ['NEGATE', 'ABS', '1+', '1-', '2*', '2/', '0=', '0<>', '0<', '0>', 'INVERT', 'CELLS', 'CELL+'], true)) {
            $a = $this->take(1, $source)[0];
            $result = match ($key) {
                'NEGATE' => -$a, 'ABS' => abs($a), '1+' => $a + 1, '1-' => $a - 1,
                '2*' => 2 * $a, '2/' => $this->divmod($a, 2)[0],
                '0=' => $a === 0 ? -1 : 0, '0<>' => $a !== 0 ? -1 : 0,
                '0<' => $a < 0 ? -1 : 0, '0>' => $a > 0 ? -1 : 0,
                'INVERT' => -$a - 1, 'CELLS' => 8 * $a, 'CELL+' => $a + 8
            };
            $this->push($result, $source);
            return;
        }
        $stackCounts = ['DUP' => 1, '?DUP' => 1, 'DROP' => 1, 'SWAP' => 2, 'OVER' => 2,
            'ROT' => 3, '-ROT' => 3, 'NIP' => 2, 'TUCK' => 2, '2DUP' => 2, '2DROP' => 2, '2SWAP' => 4, '2OVER' => 4];
        if (isset($stackCounts[$key])) {
            $values = $this->take($stackCounts[$key], $source);
            $a = $values[0];
            $b = $values[1] ?? null;
            $c = $values[2] ?? null;
            $d = $values[3] ?? null;
            $result = match ($key) {
                'DUP' => [$a, $a], '?DUP' => $a === 0 ? [$a] : [$a, $a],
                'DROP', '2DROP' => [], 'SWAP' => [$b, $a], 'OVER' => [$a, $b, $a],
                'ROT' => [$b, $c, $a], '-ROT' => [$c, $a, $b], 'NIP' => [$b],
                'TUCK' => [$b, $a, $b], '2DUP' => [$a, $b, $a, $b],
                '2SWAP' => [$c, $d, $a, $b], '2OVER' => [$a, $b, $c, $d, $a, $b]
            };
            $this->pushAll($result, $source);
            return;
        }
        switch ($key) {
            case '*/':
            case '*/MOD':
                [$a, $b, $c] = $this->take(3, $source);
                if ($c === 0) {
                    $this->fail($source, 'division by zero');
                }
                [$q, $r] = $this->divmod($a * $b, $c);
                $this->pushAll($key === '*/' ? [$q] : [$r, $q], $source);
                break;
            case 'WITHIN':
                [$n, $lo, $hi] = $this->take(3, $source);
                $this->push($lo <= $n && $n < $hi ? -1 : 0, $source);
                break;
            case 'TRUE':
            case 'FALSE':
            case 'BL':
            case 'BASE':
            case 'HERE':
                $this->push(['TRUE' => -1, 'FALSE' => 0, 'BL' => 32, 'BASE' => 0, 'HERE' => count($this->memory) * 8][$key], $source);
                break;
            case 'DEPTH':
                $this->push(count($this->stack), $source);
                break;
            case 'PICK':
            case 'ROLL':
                $u = $this->take(1, $source)[0];
                if ($u < 0) {
                    $this->fail($source, 'invalid argument');
                }
                if (count($this->stack) <= $u) {
                    $this->fail($source, 'stack underflow');
                }
                $index = count($this->stack) - 1 - $u;
                $value = $key === 'PICK' ? $this->stack[$index] : array_splice($this->stack, $index, 1)[0];
                $this->push($value, $source);
                break;
            case '.':
            case '.R':
            case '?':
                $values = $this->take($key === '.R' ? 2 : 1, $source);
                $n = $key === '?' ? $this->memory[$this->address($values[0], $source)] : $values[0];
                $text = $this->outputNumber($n, $source);
                $this->pending .= $key === '.R' ? str_repeat(' ', max(0, $values[1] - strlen($text))) . $text : $text . ' ';
                break;
            case '.S':
                $this->outputNumber(0, $source);
                $this->pending .= '<' . $this->outputNumber(count($this->stack), $source) . '> ';
                foreach ($this->stack as $value) {
                    $this->pending .= $this->outputNumber($value, $source) . ' ';
                }
                break;
            case 'CR':
                $this->flush();
                break;
            case 'EMIT':
                $c = $this->take(1, $source)[0];
                if ($c < 32 || $c > 126) {
                    $this->fail($source, 'invalid argument');
                }
                $this->pending .= chr($c);
                break;
            case 'SPACE':
                $this->pending .= ' ';
                break;
            case 'SPACES':
                $this->pending .= str_repeat(' ', max(0, $this->take(1, $source)[0]));
                break;
            case '!':
            case '+!':
                [$n, $a] = $this->take(2, $source);
                $index = $this->address($a, $source);
                $this->memory[$index] = $key === '!' ? $n : $this->memory[$index] + $n;
                break;
            case '@':
                $this->push($this->memory[$this->address($this->take(1, $source)[0], $source)], $source);
                break;
            case ',':
                $this->memory[] = $this->take(1, $source)[0];
                break;
            case 'ALLOT':
                $n = $this->take(1, $source)[0];
                if ($n < 0 || $n % 8 !== 0) {
                    $this->fail($source, 'invalid argument');
                }
                $this->memory = array_merge($this->memory, array_fill(0, intdiv($n, 8), 0));
                break;
            case 'HEX':
            case 'DECIMAL':
                $this->memory[0] = $key === 'HEX' ? 16 : 10;
                break;
            case 'CREATE':
            case 'VARIABLE':
            case 'CONSTANT':
            case 'VALUE':
            case 'DEFER':
                $name = $this->checkName($this->readName($source));
                $value = in_array($key, ['CONSTANT', 'VALUE'], true) ? $this->take(1, $source)[0] : null;
                $here = count($this->memory) * 8;
                $stored = in_array($key, ['CREATE', 'VARIABLE', 'VALUE'], true) ? $here : $value;
                $this->dictionary[] = new ForthWord($name, strtolower($key), $stored, $here);
                if ($key === 'VARIABLE' || $key === 'VALUE') {
                    $this->memory[] = $key === 'VARIABLE' ? 0 : $value;
                }
                break;
            case "'":
                $name = $this->readName($source);
                $word = $this->lookup($name) ?? $this->fail($name, 'undefined word');
                $this->push($this->token($word), $source);
                break;
            case 'EXECUTE':
                $this->executeToken($this->take(1, $source)[0], $source);
                break;
            case 'CATCH':
                $xt = $this->take(1, $source)[0];
                if (!$this->validToken($xt)) {
                    $this->fail($source, 'invalid argument');
                }
                $saved = $this->stack;
                $savedReturns = count($this->returns);
                $savedDepth = $this->depth;
                $code = 0;
                try {
                    $this->executeToken($xt, $source);
                } catch (ForthError $exception) {
                    if ($exception->forthCode === null) {
                        throw $exception;
                    }
                    $this->stack = $saved;
                    if (count($this->returns) > $savedReturns) {
                        $this->returns = array_slice($this->returns, 0, $savedReturns);
                    }
                    $this->depth = $savedDepth;
                    $code = $exception->forthCode;
                }
                $this->push($code, $source);
                break;
            case 'THROW':
                $n = $this->take(1, $source)[0];
                if ($n !== 0) {
                    $this->fail($source, 'exception ' . $n, $n);
                }
                break;
            case 'ABORT':
                $this->fail($source, 'aborted');
            case 'WORDS':
                for ($i = count($this->dictionary) - 1; $i >= 0; $i--) {
                    $this->pending .= $this->dictionary[$i]->name . ' ';
                }
                break;
        }
    }

    public function run(): void
    {
        while (($input = fgets(STDIN)) !== false) {
            $this->line = str_ends_with($input, "\n") ? substr($input, 0, -1) : $input;
            if ($this->line === 'BYE') {
                if ($this->compiling !== null) {
                    echo 'ERROR ', $this->definitionName, ": unterminated definition\n";
                }
                break;
            }
            $this->position = 0;
            try {
                while (($source = $this->readWord()) !== null) {
                    $this->process($source);
                }
            } catch (ForthError $exception) {
                if ($this->pending !== '') {
                    $this->flush();
                }
                echo 'ERROR ', $exception->word, ': ', $exception->reason, "\n";
                $this->stack = [];
                $this->returns = [];
                $this->depth = 0;
                $this->compiling = null;
            }
            if ($this->pending !== '') {
                $this->flush();
            }
        }
    }
}

(new Forth())->run();
