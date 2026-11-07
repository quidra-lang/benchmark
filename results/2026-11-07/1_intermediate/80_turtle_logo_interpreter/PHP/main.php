<?php
class Token
{
    public function __construct(public string $kind, public string $text, public int $line, public bool $sign = false)
    {
    }
}

class Procedure
{
    public array $tokens = [];
    public array $body = [];

    public function __construct(public string $name, public array $parameters, public int $line)
    {
    }
}

class LogoError extends Exception
{
    public function __construct(public int $lineNumber, string $reason, public array $calls = [])
    {
        parent::__construct($reason);
    }
}

class LogoReturn extends Exception
{
    public function __construct(public ?int $value)
    {
        parent::__construct();
    }
}

class Language
{
    public const COMMANDS = [
        'FD' => ['FD', 'E'], 'FORWARD' => ['FD', 'E'], 'BK' => ['BK', 'E'], 'BACK' => ['BK', 'E'],
        'RT' => ['RT', 'E'], 'RIGHT' => ['RT', 'E'], 'LT' => ['LT', 'E'], 'LEFT' => ['LT', 'E'],
        'SETH' => ['SETH', 'E'], 'SETHEADING' => ['SETH', 'E'],
        'PU' => ['PU', ''], 'PENUP' => ['PU', ''], 'PD' => ['PD', ''], 'PENDOWN' => ['PD', ''],
        'PE' => ['PE', ''], 'PENERASE' => ['PE', ''], 'SETPEN' => ['SETPEN', 'E'],
        'SETXY' => ['SETXY', 'EE'], 'SETX' => ['SETX', 'E'], 'SETY' => ['SETY', 'E'],
        'HOME' => ['HOME', ''], 'CS' => ['CS', ''], 'CLEARSCREEN' => ['CS', ''],
        'CLEAN' => ['CLEAN', ''], 'FILL' => ['FILL', ''], 'LABEL' => ['LABEL', 'P'],
        'SNAPSHOT' => ['SNAPSHOT', ''], 'REPEAT' => ['REPEAT', 'EL'], 'FOR' => ['FOR', 'QEEL'],
        'WHILE' => ['WHILE', 'EL'], 'IF' => ['IF', 'EL'], 'IFELSE' => ['IFELSE', 'ELL'],
        'TEST' => ['TEST', 'E'], 'IFTRUE' => ['IFTRUE', 'L'], 'IFT' => ['IFTRUE', 'L'],
        'IFFALSE' => ['IFFALSE', 'L'], 'IFF' => ['IFFALSE', 'L'], 'STOP' => ['STOP', ''],
        'OUTPUT' => ['OUTPUT', 'E'], 'OP' => ['OUTPUT', 'E'], 'MAKE' => ['MAKE', 'QE'],
        'LOCAL' => ['LOCAL', 'Q'], 'LOCALMAKE' => ['LOCALMAKE', 'QE'],
        'TRACE' => ['TRACE', 'Q'], 'UNTRACE' => ['UNTRACE', 'Q'], 'SEED' => ['SEED', 'E'],
        'PRINT' => ['PRINT', 'P'], 'PR' => ['PRINT', 'P']
    ];
    public const FUNCTIONS = ['XCOR' => 0, 'YCOR' => 0, 'HEADING' => 0, 'REPCOUNT' => 0, 'RANDOM' => 1, 'ABS' => 1, 'NOT' => 1, 'AND' => 2, 'OR' => 2, 'MAX' => 2, 'MIN' => 2];

    public static function primitive(string $name): bool
    {
        return isset(self::COMMANDS[$name]) || isset(self::FUNCTIONS[$name]) || in_array($name, ['TO', 'END', 'MOD'], true);
    }

    public static function lex(string $line, int $number): array
    {
        $text = strtoupper(explode(';', $line, 2)[0]);
        $tokens = [];
        for ($i = 0; $i < strlen($text);) {
            $char = $text[$i];
            if ($char === ' ') {
                $i++;
            } elseif (str_contains('[]()+*/=-<>', $char)) {
                $spelling = $char;
                $next = $text[$i + 1] ?? '';
                if (($char === '<' && in_array($next, ['=', '>'], true)) || ($char === '>' && $next === '=')) {
                    $spelling .= $next;
                }
                $sign = $char === '-' && ($i === 0 || in_array($text[$i - 1], [' ', '[', '('], true)) && $next !== '' && $next !== ' ';
                $tokens[] = new Token('symbol', $spelling, $number, $sign);
                $i += strlen($spelling);
            } else {
                $start = $i;
                while ($i < strlen($text) && !str_contains(' []()+-*/=<>', $text[$i])) {
                    $i++;
                }
                $spelling = substr($text, $start, $i - $start);
                if (preg_match('/\A[0-9]+\z/D', $spelling)) {
                    $kind = 'number';
                } elseif (preg_match('/\A:[A-Z][A-Z0-9_]*\z/D', $spelling)) {
                    $kind = 'variable';
                } elseif (preg_match('/\A"[A-Z][A-Z0-9_]*\z/D', $spelling)) {
                    $kind = 'quote';
                } elseif (preg_match('/\A[A-Z][A-Z0-9_]*\z/D', $spelling)) {
                    $kind = 'word';
                } else {
                    throw new LogoError($number, "bad token '$spelling'");
                }
                $tokens[] = new Token($kind, $spelling, $number);
            }
        }
        return $tokens;
    }
}

class Parser
{
    private int $index = 0;

    public function __construct(private array $tokens, private array $procedures, private bool $top)
    {
    }

    private function peek(): ?Token
    {
        return $this->tokens[$this->index] ?? null;
    }

    private function read(): Token
    {
        return $this->tokens[$this->index++];
    }

    private function error(Token $token, string $reason): never
    {
        throw new LogoError($token->line, $reason);
    }

    private function unknown(Token $token): bool
    {
        return $token->kind === 'word' && !Language::primitive($token->text) && !isset($this->procedures[$token->text]);
    }

    private function need(Token $owner): Token
    {
        $token = $this->peek();
        if ($token === null || in_array($token->text, [']', ')'], true)) {
            $this->error($owner, "not enough inputs to {$owner->text}");
        }
        if ($this->unknown($token)) {
            $this->error($token, "I don't know how to {$token->text}");
        }
        return $token;
    }

    private function input(string $kind, Token $owner): mixed
    {
        $token = $this->need($owner);
        if ($kind === 'L') {
            if ($token->text !== '[') {
                $this->error($token, "{$owner->text} doesn't like {$token->text} as input");
            }
            $opening = $this->read();
            $result = [];
            while (true) {
                if ($this->peek() === null) {
                    $this->error($opening, 'missing ]');
                }
                if ($this->peek()->text === ']') {
                    break;
                }
                $result[] = $this->command();
            }
            $this->read();
            return $result;
        }
        if ($kind === 'Q') {
            if ($token->kind !== 'quote') {
                $this->error($token, "{$owner->text} doesn't like {$token->text} as input");
            }
            return $this->read();
        }
        if ($kind === 'P' && $token->kind === 'quote') {
            return ['kind' => 'quote', 'value' => substr($this->read()->text, 1)];
        }
        return $this->expression($owner);
    }

    public function sequence(): array
    {
        $result = [];
        while ($this->peek() !== null) {
            $result[] = $this->command();
        }
        return $result;
    }

    private function expressions(int $count, Token $owner): array
    {
        $result = [];
        for ($i = 0; $i < $count; $i++) {
            $result[] = $this->expression($owner);
        }
        return $result;
    }

    private function command(): array
    {
        $token = $this->read();
        if ($token->text === ']') {
            $this->error($token, 'unexpected ]');
        }
        if ($token->text === '(' && $this->peek() !== null && in_array($this->peek()->text, ['PRINT', 'PR'], true)) {
            $owner = $this->read();
            $args = [];
            while (true) {
                $next = $this->peek();
                if ($next === null || $next->text === ']') {
                    $this->error($token, 'missing )');
                }
                if ($next->text === ')') {
                    break;
                }
                $args[] = $this->input('P', $owner);
            }
            $this->read();
            return ['name' => 'MULTIPRINT', 'token' => $owner, 'args' => $args];
        }
        if ($token->kind === 'word' && in_array($token->text, ['TO', 'END'], true)) {
            $this->error($token, "misplaced {$token->text}");
        }
        if ($token->kind === 'word' && isset(Language::COMMANDS[$token->text])) {
            [$name, $kinds] = Language::COMMANDS[$token->text];
            if ($this->top && in_array($token->text, ['STOP', 'OUTPUT', 'OP', 'LOCAL', 'LOCALMAKE'], true)) {
                $this->error($token, "can only use {$token->text} inside a procedure");
            }
            $args = [];
            foreach (str_split($kinds) as $kind) {
                $args[] = $this->input($kind, $token);
            }
            if (in_array($name, ['TRACE', 'UNTRACE'], true) && !isset($this->procedures[substr($args[0]->text, 1)])) {
                $this->error($args[0], "I don't know how to " . substr($args[0]->text, 1));
            }
            return ['name' => $name, 'token' => $token, 'args' => $args];
        }
        if ($token->kind === 'word' && isset($this->procedures[$token->text])) {
            return ['name' => 'call', 'token' => $token, 'args' => $this->expressions(count($this->procedures[$token->text]->parameters), $token)];
        }
        if ($this->unknown($token)) {
            $this->error($token, "I don't know how to {$token->text}");
        }
        $this->error($token, "you don't say what to do with {$token->text}");
    }

    private function expression(Token $owner): array
    {
        return $this->binary($owner, 'sum', ['=', '<>', '<', '>', '<=', '>=']);
    }

    private function sum(Token $owner): array
    {
        return $this->binary($owner, 'product', ['+', '-']);
    }

    private function product(Token $owner): array
    {
        return $this->binary($owner, 'term', ['*', '/', 'MOD']);
    }

    private function binary(Token $owner, string $lower, array $operators): array
    {
        $left = $this->$lower($owner);
        while (($next = $this->peek()) !== null && in_array($next->text, $operators, true) && !($next->text === '-' && $next->sign)) {
            $operator = $this->read();
            $right = $this->$lower($operator);
            $left = ['kind' => 'binary', 'token' => $operator, 'left' => $left, 'right' => $right];
        }
        return $left;
    }

    private function term(Token $owner): array
    {
        $token = $this->need($owner);
        $this->read();
        if ($token->kind === 'number') {
            return ['kind' => 'number', 'value' => (int)$token->text];
        }
        if ($token->kind === 'variable') {
            return ['kind' => 'variable', 'token' => $token];
        }
        if ($token->text === '-') {
            return ['kind' => 'unary', 'value' => $this->term($token)];
        }
        if ($token->text === '(') {
            $value = $this->expression($token);
            if ($this->peek() === null || $this->peek()->text !== ')') {
                $this->error($token, 'missing )');
            }
            $this->read();
            return $value;
        }
        if ($token->kind === 'word' && isset(Language::FUNCTIONS[$token->text])) {
            return ['kind' => 'function', 'token' => $token, 'args' => $this->expressions(Language::FUNCTIONS[$token->text], $token)];
        }
        if ($token->kind === 'word' && isset($this->procedures[$token->text])) {
            return ['kind' => 'call', 'token' => $token, 'args' => $this->expressions(count($this->procedures[$token->text]->parameters), $token)];
        }
        $this->error($token, "{$owner->text} doesn't like {$token->text} as input");
    }
}

class Environment
{
    public ?bool $test = null;

    public function __construct(public array $variables = [])
    {
    }
}

class Turtle
{
    private const DIRECTIONS = [[0, 1], [1, 1], [1, 0], [1, -1], [0, -1], [-1, -1], [-1, 0], [-1, 1]];
    private int $x = 0;
    private int $y = 0;
    private int $heading = 0;
    private string $pen = 'DOWN';
    private string $character = '*';
    private array $canvas = [];
    private array $environments;
    private array $calls = [];
    private array $repetitions = [];
    private array $traced = [];
    private int $random = 1;

    public function __construct(private array $procedures)
    {
        $this->environments = [new Environment()];
    }

    private function error(Token $token, string $reason): never
    {
        throw new LogoError($token->line, $reason, $this->calls);
    }

    private function value(array $node): int|string
    {
        $kind = $node['kind'];
        if ($kind === 'number' || $kind === 'quote') {
            return $node['value'];
        }
        if ($kind === 'variable') {
            $name = substr($node['token']->text, 1);
            for ($i = count($this->environments) - 1; $i >= 0; $i--) {
                if (array_key_exists($name, $this->environments[$i]->variables)) {
                    return $this->environments[$i]->variables[$name];
                }
            }
            $this->error($node['token'], "$name has no value");
        }
        if ($kind === 'unary') {
            return -$this->value($node['value']);
        }
        if ($kind === 'binary') {
            $a = $this->value($node['left']);
            $b = $this->value($node['right']);
            $operator = $node['token']->text;
            if (in_array($operator, ['/', 'MOD'], true) && $b === 0) {
                $this->error($node['token'], "$operator doesn't like 0 as input");
            }
            return match ($operator) {
                '+' => $a + $b, '-' => $a - $b, '*' => $a * $b,
                '/' => intdiv($a, $b), 'MOD' => $a - $b * intdiv($a, $b),
                '=' => (int)($a === $b), '<>' => (int)($a !== $b), '<' => (int)($a < $b),
                '>' => (int)($a > $b), '<=' => (int)($a <= $b), '>=' => (int)($a >= $b)
            };
        }
        if ($kind === 'call') {
            $result = $this->call($node['token'], $node['args']);
            if ($result === null) {
                $this->error($node['token'], "{$node['token']->text} did not output");
            }
            return $result;
        }
        $args = [];
        foreach ($node['args'] as $arg) {
            $args[] = $this->value($arg);
        }
        $token = $node['token'];
        $a = $args[0] ?? null;
        $b = $args[1] ?? null;
        switch ($token->text) {
            case 'XCOR':
                return $this->x;
            case 'YCOR':
                return $this->y;
            case 'HEADING':
                return $this->heading;
            case 'REPCOUNT':
                if ($this->repetitions === []) {
                    $this->error($token, 'REPCOUNT outside REPEAT');
                }
                return $this->repetitions[count($this->repetitions) - 1];
            case 'RANDOM':
                if ($a <= 0) {
                    $this->error($token, "RANDOM doesn't like $a as input");
                }
                $this->random = 48271 * $this->random % 2147483647;
                return $this->random % $a;
            case 'ABS':
                return abs($a);
            case 'NOT':
                return (int)($a === 0);
            case 'AND':
                return (int)($a !== 0 && $b !== 0);
            case 'OR':
                return (int)($a !== 0 || $b !== 0);
            case 'MAX':
                return max($a, $b);
            case 'MIN':
                return min($a, $b);
        }
        return 0;
    }

    private function call(Token $token, array $arguments): ?int
    {
        $inputs = [];
        foreach ($arguments as $arg) {
            $inputs[] = $this->value($arg);
        }
        if (count($this->calls) === 100) {
            $this->error($token, 'recursion too deep');
        }
        $procedure = $this->procedures[$token->text];
        $traced = isset($this->traced[$token->text]);
        $indent = str_repeat('  ', count($this->calls));
        if ($traced) {
            echo $indent, '( ', implode(' ', array_merge([$token->text], $inputs)), " )\n";
        }
        $this->calls[] = $token->text;
        $variables = [];
        foreach ($procedure->parameters as $i => $name) {
            $variables[$name] = $inputs[$i];
        }
        $this->environments[] = new Environment($variables);
        $result = null;
        try {
            $this->execute($procedure->body);
        } catch (LogoReturn $signal) {
            $result = $signal->value;
        } finally {
            array_pop($this->environments);
            array_pop($this->calls);
        }
        if ($traced) {
            echo $indent, $token->text, $result === null ? ' stops' : " outputs $result", "\n";
        }
        return $result;
    }

    private function make(string $name, int $number): void
    {
        for ($i = count($this->environments) - 1; $i > 0; $i--) {
            if (array_key_exists($name, $this->environments[$i]->variables)) {
                $this->environments[$i]->variables[$name] = $number;
                return;
            }
        }
        $this->environments[0]->variables[$name] = $number;
    }

    private function apply(int $x, int $y): void
    {
        if ($this->pen === 'DOWN') {
            $this->canvas["$x,$y"] = $this->character;
        } elseif ($this->pen === 'ERASE') {
            unset($this->canvas["$x,$y"]);
        }
    }

    private function move(int $number): void
    {
        [$dx, $dy] = self::DIRECTIONS[intdiv($this->heading, 45)];
        if ($number < 0) {
            $dx = -$dx;
            $dy = -$dy;
        }
        $this->apply($this->x, $this->y);
        for ($i = 0; $i < abs($number); $i++) {
            $this->x += $dx;
            $this->y += $dy;
            $this->apply($this->x, $this->y);
        }
    }

    private function floorDivide(int $a, int $b): int
    {
        $value = intdiv($a, $b);
        return $a < 0 && $a % $b !== 0 ? $value - 1 : $value;
    }

    private function moveTo(int $x, int $y): void
    {
        $dx = $x - $this->x;
        $dy = $y - $this->y;
        $steps = max(abs($dx), abs($dy));
        if ($steps === 0) {
            $this->apply($this->x, $this->y);
        } else {
            for ($i = 0; $i <= $steps; $i++) {
                $this->apply($this->x + $this->floorDivide(2 * $i * $dx + $steps, 2 * $steps), $this->y + $this->floorDivide(2 * $i * $dy + $steps, 2 * $steps));
            }
        }
        $this->x = $x;
        $this->y = $y;
    }

    private function bounds(): array
    {
        $xs = $ys = [];
        foreach (array_keys($this->canvas) as $key) {
            [$x, $y] = array_map('intval', explode(',', $key));
            $xs[] = $x;
            $ys[] = $y;
        }
        return [min($xs), min($ys), max($xs), max($ys)];
    }

    private function fill(): void
    {
        if ($this->canvas === [] || isset($this->canvas["{$this->x},{$this->y}"])) {
            return;
        }
        [$x1, $y1, $x2, $y2] = $this->bounds();
        if ($this->x < $x1 || $this->x > $x2 || $this->y < $y1 || $this->y > $y2) {
            return;
        }
        $queue = [[$this->x, $this->y]];
        $this->canvas["{$this->x},{$this->y}"] = $this->character;
        $head = 0;
        while ($head < count($queue)) {
            [$x, $y] = $queue[$head++];
            foreach ([[$x - 1, $y], [$x + 1, $y], [$x, $y - 1], [$x, $y + 1]] as [$a, $b]) {
                if ($a < $x1 || $a > $x2 || $b < $y1 || $b > $y2 || isset($this->canvas["$a,$b"])) {
                    continue;
                }
                $this->canvas["$a,$b"] = $this->character;
                $queue[] = [$a, $b];
            }
        }
    }

    private function snapshot(): void
    {
        if ($this->canvas === []) {
            echo "CANVAS 0 0 0\n";
            return;
        }
        [$x1, $y1, $x2, $y2] = $this->bounds();
        echo 'CANVAS ', $x2 - $x1 + 1, ' ', $y2 - $y1 + 1, ' ', count($this->canvas), "\n";
        for ($y = $y2; $y >= $y1; $y--) {
            $row = '';
            for ($x = $x1; $x <= $x2; $x++) {
                $row .= $this->canvas["$x,$y"] ?? ' ';
            }
            echo rtrim($row, ' '), "\n";
        }
    }

    public function execute(array $commands): void
    {
        foreach ($commands as $command) {
            $token = $command['token'];
            $args = $command['args'];
            $name = $command['name'];
            if ($name === 'call') {
                $result = $this->call($token, $args);
                if ($result !== null) {
                    $this->error($token, "you don't say what to do with $result");
                }
                continue;
            }
            if ($name === 'WHILE') {
                while ($this->value($args[0]) !== 0) {
                    $this->execute($args[1]);
                }
                continue;
            }
            $values = [];
            foreach ($args as $arg) {
                $values[] = $arg instanceof Token ? substr($arg->text, 1) : (isset($arg['kind']) ? $this->value($arg) : $arg);
            }
            $a = $values[0] ?? null;
            $b = $values[1] ?? null;
            $c = $values[2] ?? null;
            $d = $values[3] ?? null;
            switch ($name) {
                case 'FD':
                    $this->move($a);
                    break;
                case 'BK':
                    $this->move(-$a);
                    break;
                case 'RT':
                case 'LT':
                case 'SETH':
                    if ($a % 45 !== 0) {
                        $this->error($token, "{$token->text} doesn't like $a as input");
                    }
                    $heading = $name === 'SETH' ? $a : $this->heading + ($name === 'LT' ? -$a : $a);
                    $this->heading = ($heading % 360 + 360) % 360;
                    break;
                case 'PU':
                    $this->pen = 'UP';
                    break;
                case 'PD':
                    $this->pen = 'DOWN';
                    break;
                case 'PE':
                    $this->pen = 'ERASE';
                    break;
                case 'SETPEN':
                    if ($a < 33 || $a > 126) {
                        $this->error($token, "SETPEN doesn't like $a as input");
                    }
                    $this->character = chr($a);
                    break;
                case 'SETXY':
                    $this->moveTo($a, $b);
                    break;
                case 'SETX':
                    $this->moveTo($a, $this->y);
                    break;
                case 'SETY':
                    $this->moveTo($this->x, $a);
                    break;
                case 'HOME':
                    $this->moveTo(0, 0);
                    $this->heading = 0;
                    break;
                case 'CS':
                    $this->canvas = [];
                    $this->x = $this->y = $this->heading = 0;
                    break;
                case 'CLEAN':
                    $this->canvas = [];
                    break;
                case 'FILL':
                    $this->fill();
                    break;
                case 'LABEL':
                    [$dx, $dy] = self::DIRECTIONS[intdiv($this->heading, 45)];
                    foreach (str_split((string)$a) as $i => $char) {
                        $x = $this->x + $i * $dx;
                        $y = $this->y + $i * $dy;
                        $this->canvas["$x,$y"] = $char;
                    }
                    break;
                case 'SNAPSHOT':
                    $this->snapshot();
                    break;
                case 'REPEAT':
                    if ($b === []) {
                        break;
                    }
                    for ($i = 1; $i <= $a; $i++) {
                        $this->repetitions[] = $i;
                        try {
                            $this->execute($b);
                        } finally {
                            array_pop($this->repetitions);
                        }
                    }
                    break;
                case 'FOR':
                    if ($d === []) {
                        $this->make($a, $c);
                        break;
                    }
                    $step = $b <= $c ? 1 : -1;
                    for ($number = $b; $step > 0 ? $number <= $c : $number >= $c; $number += $step) {
                        $this->make($a, $number);
                        $this->execute($d);
                    }
                    break;
                case 'IF':
                    if ($a !== 0) {
                        $this->execute($b);
                    }
                    break;
                case 'IFELSE':
                    $this->execute($a === 0 ? $c : $b);
                    break;
                case 'TEST':
                    $this->environments[count($this->environments) - 1]->test = $a !== 0;
                    break;
                case 'IFTRUE':
                case 'IFFALSE':
                    $test = $this->environments[count($this->environments) - 1]->test;
                    if ($test === null) {
                        $this->error($token, "{$token->text} without TEST");
                    }
                    if ($test === ($name === 'IFTRUE')) {
                        $this->execute($a);
                    }
                    break;
                case 'STOP':
                    throw new LogoReturn(null);
                case 'OUTPUT':
                    throw new LogoReturn($a);
                case 'MAKE':
                    $this->make($a, $b);
                    break;
                case 'LOCAL':
                    $this->environments[count($this->environments) - 1]->variables[$a] = 0;
                    break;
                case 'LOCALMAKE':
                    $this->environments[count($this->environments) - 1]->variables[$a] = $b;
                    break;
                case 'TRACE':
                    $this->traced[$a] = true;
                    break;
                case 'UNTRACE':
                    unset($this->traced[$a]);
                    break;
                case 'SEED':
                    if ($a <= 0) {
                        $this->error($token, "SEED doesn't like $a as input");
                    }
                    $this->random = $a;
                    break;
                case 'PRINT':
                    echo $a, "\n";
                    break;
                case 'MULTIPRINT':
                    echo implode(' ', $values), "\n";
                    break;
            }
        }
    }

    public function finish(): void
    {
        echo "TURTLE {$this->x} {$this->y} {$this->heading} {$this->pen} {$this->character}\n";
        $this->snapshot();
    }
}

function runProgram(string $name, array $source): void
{
    echo "PROGRAM $name\n";
    try {
        $procedures = $top = [];
        $current = null;
        foreach ($source as [$line, $number]) {
            $tokens = Language::lex($line, $number);
            if ($tokens === []) {
                continue;
            }
            if ($tokens[0]->kind === 'word' && $tokens[0]->text === 'TO') {
                if ($current !== null) {
                    throw new LogoError($number, "TO inside definition of {$current->name}");
                }
                if (!isset($tokens[1]) || $tokens[1]->kind !== 'word') {
                    throw new LogoError($number, 'bad procedure header');
                }
                $procedureName = $tokens[1]->text;
                if (Language::primitive($procedureName)) {
                    throw new LogoError($number, "$procedureName is a primitive");
                }
                if (isset($procedures[$procedureName])) {
                    throw new LogoError($number, "$procedureName is already defined");
                }
                $parameters = [];
                foreach (array_slice($tokens, 2) as $token) {
                    if ($token->kind !== 'variable') {
                        throw new LogoError($number, 'bad procedure header');
                    }
                    $parameter = substr($token->text, 1);
                    if (in_array($parameter, $parameters, true)) {
                        throw new LogoError($number, "duplicate input {$token->text}");
                    }
                    $parameters[] = $parameter;
                }
                $current = new Procedure($procedureName, $parameters, $number);
                $procedures[$procedureName] = $current;
            } elseif (count($tokens) === 1 && $tokens[0]->kind === 'word' && $tokens[0]->text === 'END') {
                if ($current === null) {
                    throw new LogoError($number, 'END without TO');
                }
                $current = null;
            } elseif ($current === null) {
                $top = array_merge($top, $tokens);
            } else {
                $current->tokens = array_merge($current->tokens, $tokens);
            }
        }
        if ($current !== null) {
            throw new LogoError($current->line, "missing END for {$current->name}");
        }
        foreach ($procedures as $procedure) {
            $procedure->body = (new Parser($procedure->tokens, $procedures, false))->sequence();
        }
        $body = (new Parser($top, $procedures, true))->sequence();
        $turtle = new Turtle($procedures);
        $turtle->execute($body);
        $turtle->finish();
    } catch (LogoError $error) {
        echo "ERROR line {$error->lineNumber}: ", $error->getMessage(), "\n";
        $calls = array_reverse($error->calls);
        for ($i = 0; $i < count($calls);) {
            $procedure = $calls[$i];
            $count = 0;
            while ($i < count($calls) && $calls[$i] === $procedure) {
                $count++;
                $i++;
            }
            echo "  in $procedure", $count >= 2 ? " x$count" : '', "\n";
        }
    }
}

$programs = [];
$current = -1;
$number = 0;
while (($line = fgets(STDIN)) !== false) {
    $number++;
    $line = rtrim($line, "\r\n");
    if ($line === '#EOF') {
        break;
    }
    if (str_starts_with($line, '#PROGRAM ')) {
        $programs[] = [substr($line, 9), []];
        $current++;
    } else {
        $programs[$current][1][] = [$line, $number];
    }
}
foreach ($programs as [$name, $source]) {
    runProgram($name, $source);
}
