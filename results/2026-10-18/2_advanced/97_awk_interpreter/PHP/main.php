<?php

foreach (['lexer', 'parser', 'values_fields', 'builtins', 'streams'] as $module)
    require_once __DIR__ . "/$module.php";
const SPECIAL_NAMES = ['FILENAME', 'FNR', 'FS', 'NF', 'NR', 'OFS', 'ORS', 'SUBSEP'];

final class StaticIssue extends RuntimeException
{
    public function __construct(
        public array $position,
        string $message,
    ) {
        parent::__construct($message);
    }
}

final class Transfer extends RuntimeException
{
    public function __construct(
        public string $kind,
        public ?AwkValue $value = null,
    ) {
        parent::__construct();
    }
}

final class Analysis
{
    public array
        $functions = [],
        $rules = [],
        $functionTable = [],
        $globalNames = [],
        $bindings = [],
        $arrayNames = [],
        $statementLines = []
    ;
    private array $nodes = [], $errors = [];

    public function __construct(
        public array $items,
    ) {
        foreach ($items as $item)
            if ($item->kind === 'function')
                $this->functions[] = $item;
            else
                $this->rules[] = $item;
        foreach (SPECIAL_NAMES as $name) {
            $this->globalNames[$name] = true;
            $this->bindings['g:' . $name] = true;
        }
    }

    private function error(array $p, int $priority, string $message): void
    {
        $this->errors[] = [$p, $priority, $message];
    }

    private function resolve(object $node, ?object $function): void
    {
        $local = $function !== null && isset($function->parameterNames[$node->name]);
        $node->binding = ($local ? spl_object_id($function) : 'g') . ':' . $node->name;
        $this->bindings[$node->binding] = true;
        if (!$local)
            $this->globalNames[$node->name] = true;
        if (isset($this->functionTable[$node->name]))
            $this->error($node->position, 2, 'function ' . $node->name . ' used as variable');
    }

    public function prepare(): self
    {
        foreach ($this->functions as $f) {
            if (isset($this->functionTable[$f->name]))
                $this->error($f->namePosition, 0, 'function ' . $f->name . ' redefined');
            else
                $this->functionTable[$f->name] = $f;
            $f->parameterNames = [];
            foreach ($f->parameters as $p) {
                if (isset($f->parameterNames[$p->name]))
                    $this->error($p->position, 1, 'duplicate parameter ' . $p->name);
                $f->parameterNames[$p->name] = true;
            }
        }
        foreach ($this->items as $item) {
            $function = $item->kind === 'function' ? $item : null;
            $pending = [$item];
            while ($pending) {
                $n = array_pop($pending);
                $this->nodes[] = $n;
                if (in_array($n->kind, STATEMENTS, true))
                    $this->statementLines[$n->position[0]] = true;
                if (in_array($n->kind, ['name', 'array', 'parameter'], true))
                    $this->resolve($n, $function);
                elseif ($n->kind === 'call') {
                    $target = $this->functionTable[$n->name] ?? null;
                    if ($target === null)
                        $this->error($n->position, 3, 'undefined function ' . $n->name);
                    else {
                        $n->function = $target;
                        if (count($n->arguments) > count($target->parameters))
                            $this->error($n->position, 4, 'too many arguments to ' . $n->name);
                    }
                }
                array_push($pending, ...array_reverse($n->children));
            }
        }
        if ($this->errors) {
            usort($this->errors, fn($a, $b) => [$a[0][0], $a[0][1], $a[1]] <=> [$b[0][0], $b[0][1], $b[1]]);
            throw new StaticIssue($this->errors[0][0], $this->errors[0][2]);
        }
        $links = [];
        foreach ($this->nodes as $n) {
            if ($n->kind === 'array')
                $this->arrayNames[$n->binding] = true;
            elseif (in_array($n->kind, ['membership', 'delete', 'for_in'], true))
                $this->arrayNames[$n->array->binding] = true;
            elseif ($n->kind === 'builtin' && $n->name === 'split')
                $this->arrayNames[$n->arguments[1]->binding] = true;
            elseif ($n->kind === 'call')
                foreach ($n->arguments as $i => $arg)
                    if ($arg->kind === 'name')
                        $links[] = [$arg->binding, $n->function->parameters[$i]->binding];
        }
        $parents = [];
        foreach ($this->bindings as $binding => $_)
            $parents[$binding] = $binding;
        $root = function (string $binding) use (&$parents): string {
            while ($parents[$binding] !== $binding) {
                $parents[$binding] = $parents[$parents[$binding]];
                $binding = $parents[$binding];
            }
            return $binding;
        };
        foreach ($links as [$a, $b])
            $parents[$root($a)] = $root($b);
        $arrayRoots = [];
        foreach ($this->arrayNames as $binding => $_)
            $arrayRoots[$root($binding)] = true;
        $this->arrayNames = [];
        foreach ($this->bindings as $binding => $_)
            if (isset($arrayRoots[$root($binding)]))
                $this->arrayNames[$binding] = true;
        return $this;
    }
}

function arithmetic(string $op, AwkValue $first, AwkValue $second, array $position): AwkValue
{
    $a = toNumber($first);
    $b = toNumber($second);
    if (($op === '/' || $op === '%') && $b === 0)
        throw new RuntimeIssue($position, 'division by zero');
    if ($op === '^') {
        if ($b < 0)
            throw new RuntimeIssue($position, 'negative exponent');
        $result = 1;
        $power = $a;
        while ($b > 0) {
            if ($b % 2)
                $result *= $power;
            $b = intdiv($b, 2);
            if ($b > 0)
                $power *= $power;
        }
    } else
        $result = match ($op) {
            '+' => $a + $b,
            '-' => $a - $b,
            '*' => $a * $b,
            '/' => intdiv($a, $b),
            '%' => $a % $b,
        };
    return vNumber($result);
}

final class Engine
{
    private array $globalNames, $globals = [], $locals = [], $lines = [], $inputLines = [];
    private Record $record;
    public Streams $streams;
    private string $phase = 'BEGIN';
    private int $exitStatus = 0, $operandPosition = 0, $inputPosition = 0;
    private ?Operand $currentOperand = null;
    private ?RuntimeIssue $error = null;

    public function __construct(
        private Analysis $analysis,
        private array $options,
        private array $operands,
    ) {
        $this->globalNames = $analysis->globalNames;
        foreach ($this->globalNames as $name => $_)
            $this->globals[$name] = isset($analysis->arrayNames['g:' . $name])
                ? new AwkArray()
                : uninitialized();
        $this->globals = array_replace($this->globals, [
            'FILENAME' => vString(''),
            'FNR' => vNumber(0),
            'FS' => vString(' '),
            'NF' => vNumber(0),
            'NR' => vNumber(0),
            'OFS' => vString(' '),
            'ORS' => vString("\n"),
            'SUBSEP' => vString(chr(28)),
        ]);
        $this->record = new Record(fn($name) => $this->globalValue($name));
        $this->streams = new Streams();
        foreach ($analysis->statementLines as $line => $_)
            $this->lines[$line] = 0;
        foreach ($analysis->rules as $r) {
            $r->count = 0;
            $r->inside = false;
        }
        foreach ($analysis->functions as $f)
            $f->callCount = $f->activeCalls = $f->maxDepth = 0;
    }

    private function variable(string $binding): AwkValue|AwkArray
    {
        [$scope, $name] = explode(':', $binding, 2);
        if ($scope !== 'g')
            return $this->locals[count($this->locals) - 1][$name];
        return $name === 'NF' ? vNumber(count($this->record->fields)) : $this->globals[$name];
    }

    private function globalValue(string $name): AwkValue|AwkArray
    {
        return $this->variable('g:' . $name);
    }

    private function assignGlobalInput(string $name, string $text): void
    {
        $this->globalNames[$name] = true;
        $this->globals[$name] = inputValue($text);
    }

    private function subscript(array $expressions): string
    {
        $parts = [];
        foreach ($expressions as $e)
            $parts[] = toString($this->evaluate($e));
        return implode(toString($this->globalValue('SUBSEP')), $parts);
    }

    private function location(object $n): array
    {
        if ($n->kind === 'name')
            return ['variable', $n->binding];
        if ($n->kind === 'array') {
            $key = $this->subscript($n->indexes);
            return ['array', $this->variable($n->binding), $key];
        }
        $index = toNumber($this->evaluate($n->index));
        if ($index < 0)
            throw new RuntimeIssue($n->position, 'negative field index');
        return ['field', $index];
    }

    private function read(array $location): AwkValue
    {
        return match ($location[0]) {
            'variable' => $this->variable($location[1]),
            'field' => $this->record->read($location[1]),
            'array' => $location[1]->read($location[2]),
        };
    }

    private function store(array $location, AwkValue $value, array $position): void
    {
        if ($location[0] === 'field')
            $this->record->write($location[1], $value);
        elseif ($location[0] === 'array')
            $location[1]->put($location[2], $value);
        else {
            [$scope, $name] = explode(':', $location[1], 2);
            if ($scope !== 'g')
                $this->locals[count($this->locals) - 1][$name] = $value;
            elseif ($name === 'NF') {
                $size = toNumber($value);
                if ($size < 0)
                    throw new RuntimeIssue($position, 'negative NF');
                $this->record->resize($size);
            } else
                $this->globals[$name] = $value;
        }
    }

    private function evaluate(object $n): AwkValue
    {
        switch ($n->kind) {
            case 'number':
                return vNumber($n->value);
            case 'string':
                return vString($n->value);
            case 'name':
            case 'array':
            case 'field':
                return $this->read($this->location($n));
            case 'paren':
                return $this->evaluate($n->expression);
            case 'assignment':
                $location = $this->location($n->location);
                $value = $this->evaluate($n->value);
                if ($n->operator !== '=')
                    $value = arithmetic(
                        substr($n->operator, 0, -1),
                        $this->read($location),
                        $value,
                        $n->position,
                    );
                $this->store($location, $value, $n->position);
                return $this->read($location);
            case 'increment':
                $location = $this->location($n->location);
                $old = toNumber($this->read($location));
                $value = $old + $n->delta;
                $this->store($location, vNumber($value), $n->position);
                return vNumber($n->prefix ? $value : $old);
            case 'conditional':
                return $this->evaluate(truth($this->evaluate($n->condition)) ? $n->first : $n->second);
            case 'unary':
                $v = $this->evaluate($n->operand);
                if ($n->operator === '!')
                    return vNumber((int) !truth($v));
                $integer = toNumber($v);
                return vNumber($n->operator === '-' ? -$integer : $integer);
            case 'membership':
                $key = $this->subscript($n->indexes);
                return vNumber((int) $this->variable($n->array->binding)->has($key));
            case 'binary':
                $first = $this->evaluate($n->left);
                $op = $n->operator;
                if ($op === '||' && truth($first))
                    return vNumber(1);
                if ($op === '&&' && !truth($first))
                    return vNumber(0);
                $second = $this->evaluate($n->right);
                if ($op === '&&' || $op === '||')
                    return vNumber((int) truth($second));
                if ($op === 'concat')
                    return vString(toString($first) . toString($second));
                if (in_array($op, COMPARISONS, true)) {
                    $order = compareAwk($first, $second);
                    return vNumber((int) match ($op) {
                        '<' => $order < 0,
                        '<=' => $order <= 0,
                        '==' => $order === 0,
                        '!=' => $order !== 0,
                        '>=' => $order >= 0,
                        '>' => $order > 0,
                    });
                }
                return arithmetic($op, $first, $second, $n->position);
            case 'call':
                return $this->call($n);
            case 'builtin':
                return $this->builtin($n);
            default:
                return $this->getline($n);
        }
    }

    private function call(object $n): AwkValue
    {
        $f = $n->function;
        $local = [];
        foreach ($f->parameters as $i => $p) {
            $array = isset($this->analysis->arrayNames[$p->binding]);
            if (isset($n->arguments[$i])) {
                $arg = $n->arguments[$i];
                $value = $array ? $this->variable($arg->binding) : $this->evaluate($arg);
            } else
                $value = $array ? new AwkArray() : uninitialized();
            $local[$p->name] = $value;
        }
        ++$f->callCount;
        ++$f->activeCalls;
        $f->maxDepth = max($f->maxDepth, $f->activeCalls);
        $this->locals[] = $local;
        try {
            $this->statement($f->body);
        } catch (Transfer $t) {
            if ($t->kind === 'return')
                return $t->value;
            throw $t;
        } finally {
            array_pop($this->locals);
            --$f->activeCalls;
        }
        return uninitialized();
    }

    private function builtin(object $n): AwkValue
    {
        $name = $n->name;
        $args = $n->arguments;
        if ($name === 'length') {
            if (!$args)
                return vNumber(strlen(toString($this->record->zero)));
            $arg = $args[0];
            if ($arg->kind === 'name' && isset($this->analysis->arrayNames[$arg->binding]))
                return vNumber(count($this->variable($arg->binding)->elements));
            return vNumber(strlen(toString($this->evaluate($arg))));
        }
        if ($name === 'split') {
            $text = toString($this->evaluate($args[0]));
            $separator = count($args) === 3
                ? toString($this->evaluate($args[2]))
                : toString($this->globalValue('FS'));
            $array = $this->variable($args[1]->binding);
            $array->elements = [];
            $pieces = splitPieces($text, $separator);
            foreach ($pieces as $i => $piece)
                $array->put((string) ($i + 1), inputValue($piece));
            return vNumber(count($pieces));
        }
        if ($name === 'close')
            return vNumber($this->streams->close(toString($this->evaluate($args[0]))));
        $values = [];
        foreach ($args as $arg)
            $values[] = $this->evaluate($arg);
        return invokeBuiltin($name, $values, $n->position);
    }

    private function getline(object $n): AwkValue
    {
        if ($n->filename !== null) {
            $filename = toString($this->evaluate($n->filename));
            [$status, $line] = $this->streams->getline($filename);
        } elseif ($this->phase === 'END')
            return vNumber(0);
        else {
            $line = $this->nextRecord();
            $status = $line === null ? 0 : 1;
        }
        if ($status === 1) {
            if ($n->target === null)
                $this->record->set($line);
            else {
                $location = $this->location($n->target);
                $this->store($location, inputValue($line), $n->position);
            }
        }
        return vNumber($status);
    }

    private function output(object $n): void
    {
        $arguments = [];
        foreach ($n->arguments as $arg)
            $arguments[] = $this->evaluate($arg);
        if ($n->kind === 'print') {
            if (!$arguments)
                $arguments = [$this->record->zero];
            $text =
                implode(toString($this->globalValue('OFS')), array_map(toString(...), $arguments))
                . toString($this->globalValue('ORS'));
        } else
            $text = formatOutput($arguments, $n->position);
        $filename = $n->filename === null ? null : toString($this->evaluate($n->filename));
        $this->streams->write($text, $filename, $n->redirect, $n->redirectPosition);
    }

    private function loopBody(object $body): bool
    {
        try {
            $this->statement($body);
        } catch (Transfer $t) {
            if ($t->kind === 'break')
                return false;
            if ($t->kind !== 'continue')
                throw $t;
        }
        return true;
    }

    private function statement(object $n): void
    {
        if ($n->kind === 'block') {
            foreach ($n->statements as $s)
                $this->statement($s);
            return;
        }
        if ($n->kind === 'empty')
            return;
        ++$this->lines[$n->position[0]];
        switch ($n->kind) {
            case 'expression_statement':
                $this->evaluate($n->expression);
                break;
            case 'print':
            case 'printf':
                $this->output($n);
                break;
            case 'if':
                $branch = truth($this->evaluate($n->condition)) ? $n->first : $n->second;
                if ($branch !== null)
                    $this->statement($branch);
                break;
            case 'while':
                while (truth($this->evaluate($n->condition)))
                    if (!$this->loopBody($n->body))
                        break;
                break;
            case 'do':
                do {
                    if (!$this->loopBody($n->body))
                        break;
                } while (truth($this->evaluate($n->condition)));
                break;
            case 'for':
                if ($n->initial !== null)
                    $this->evaluate($n->initial);
                while ($n->condition === null || truth($this->evaluate($n->condition))) {
                    if (!$this->loopBody($n->body))
                        break;
                    if ($n->update !== null)
                        $this->evaluate($n->update);
                }
                break;
            case 'for_in':
                $keys = $this->variable($n->array->binding)->keys();
                usort($keys, subscriptCompare(...));
                foreach ($keys as $key) {
                    $this->store(
                        ['variable', $n->variable->binding],
                        inputValue($key),
                        $n->variable->position,
                    );
                    if (!$this->loopBody($n->body))
                        break;
                }
                break;
            case 'delete':
                $array = $this->variable($n->array->binding);
                if ($n->indexes === null)
                    $array->elements = [];
                else {
                    $key = $this->subscript($n->indexes);
                    $array->remove($key);
                }
                break;
            case 'next':
                if ($this->phase === 'BEGIN' || $this->phase === 'END')
                    throw new RuntimeIssue($n->position, 'next used in BEGIN or END');
                throw new Transfer('next');
            case 'exit':
                if ($n->value !== null)
                    $this->exitStatus = toNumber($this->evaluate($n->value));
                throw new Transfer('exit');
            case 'return':
                throw new Transfer(
                    'return',
                    $n->value === null ? uninitialized() : $this->evaluate($n->value),
                );
            default:
                throw new Transfer($n->kind);
        }
    }

    private function nextRecord(): ?string
    {
        while (true) {
            if ($this->inputPosition < count($this->inputLines)) {
                $line = $this->inputLines[$this->inputPosition++];
                ++$this->currentOperand->records;
                $this->globals['NR'] = vNumber(toNumber($this->globalValue('NR')) + 1);
                $this->globals['FNR'] = vNumber(toNumber($this->globalValue('FNR')) + 1);
                return $line;
            }
            if ($this->operandPosition === count($this->operands))
                return null;
            $operand = $this->operands[$this->operandPosition++];
            if ($operand->kind === 'assignment')
                $this->assignGlobalInput($operand->name, $operand->value);
            else {
                $this->currentOperand = $operand;
                $this->inputLines = readRecords($operand->name);
                $this->inputPosition = 0;
                $this->globals['FILENAME'] = vString($operand->name);
                $this->globals['FNR'] = vNumber(0);
            }
        }
    }

    private function runActions(string $phase): void
    {
        $this->phase = $phase;
        foreach ($this->analysis->rules as $r)
            if ($r->flavor === $phase) {
                ++$r->count;
                $this->statement($r->action);
            }
    }

    private function matches(object $r): bool
    {
        if ($r->flavor === 'all')
            return true;
        if ($r->flavor === 'pattern')
            return truth($this->evaluate($r->patterns[0]));
        if (!$r->inside && truth($this->evaluate($r->patterns[0])))
            $r->inside = true;
        if (!$r->inside)
            return false;
        if (truth($this->evaluate($r->patterns[1])))
            $r->inside = false;
        return true;
    }

    private function runRecords(): void
    {
        if (!array_any($this->analysis->rules, fn($r) => $r->flavor !== 'BEGIN'))
            return;
        $this->phase = 'records';
        $rules = array_values(array_filter(
            $this->analysis->rules,
            fn($r) => !in_array($r->flavor, ['BEGIN', 'END'], true),
        ));
        while (($line = $this->nextRecord()) !== null) {
            $this->record->set($line);
            try {
                foreach ($rules as $r)
                    if ($this->matches($r)) {
                        ++$r->count;
                        if ($r->action === null)
                            $this->streams->write(
                                toString($this->record->zero) . toString($this->globalValue('ORS')),
                            );
                        else
                            $this->statement($r->action);
                    }
            } catch (Transfer $t) {
                if ($t->kind !== 'next')
                    throw $t;
            }
        }
    }

    public function execute(): void
    {
        try {
            foreach ($this->options as [$name, $text])
                $this->assignGlobalInput($name, $text);
            try {
                $this->runActions('BEGIN');
                $this->runRecords();
            } catch (Transfer $t) {
                if ($t->kind !== 'exit')
                    throw $t;
            }
            try {
                $this->runActions('END');
            } catch (Transfer $t) {
                if ($t->kind !== 'exit')
                    throw $t;
            }
        } catch (RuntimeIssue $e) {
            $this->error = $e;
        }
    }

    public function statistics(): array
    {
        $out = [
            $this->error === null
                ? 'status: exit ' . $this->exitStatus
                : 'status: runtime error at '
                . implode(':', $this->error->position)
                . ': '
                . $this->error->getMessage(),
            '[inputs]',
        ];
        foreach ($this->operands as $o)
            if ($o->kind === 'file')
                $out[] = "{$o->name} records={$o->records}";
        $out[] = '[getline]';
        foreach ($this->streams->inputs as $name => $s)
            $out[] = $name . ' ' . ($s->everOpened ? 'reads=' . $s->reads : 'missing');
        $out[] = '[rules]';
        foreach ($this->analysis->rules as $r)
            $out[] = implode(':', $r->position) . " {$r->flavor} count={$r->count}";
        $out[] = '[functions]';
        foreach ($this->analysis->functions as $f)
            $out[] = "{$f->name} calls={$f->callCount} depth={$f->maxDepth}";
        $out[] = '[outputs]';
        $s = $this->streams->stdout;
        $out[] = "stdout.txt writes={$s->writes} bytes=" . strlen($s->content);
        foreach ($this->streams->outputs as $name => $s)
            $out[] = "$name writes={$s->writes} bytes=" . strlen($s->content);
        $out[] = '[lines]';
        ksort($this->lines, SORT_NUMERIC);
        foreach ($this->lines as $line => $count)
            $out[] = "$line count=$count";
        $out[] = '[globals]';
        $names = array_keys($this->globalNames);
        sort($names, SORT_STRING);
        foreach ($names as $name) {
            $v = $this->globalValue($name);
            $text = isset($this->analysis->arrayNames['g:' . $name])
                ? 'array (' . count($v->elements) . ')'
                : describe($v);
            $out[] = "$name = $text";
        }
        return $out;
    }
}

[$options, $operands] = parseArguments(file('input/args.txt', FILE_IGNORE_NEW_LINES));
try {
    $items = new AwkParser(tokenize(file_get_contents('input/program.awk')))->parse();
    $analysis = new Analysis($items)->prepare();
    $engine = new Engine($analysis, $options, $operands);
    $engine->execute();
    $stats = $engine->statistics();
    $streams = $engine->streams;
} catch (SyntaxIssue $e) {
    $stats = ['status: syntax error at ' . implode(':', $e->position)];
    $streams = new Streams();
} catch (StaticIssue $e) {
    $stats = ['status: error at ' . implode(':', $e->position) . ': ' . $e->getMessage()];
    $streams = new Streams();
}
$streams->save();
file_put_contents('output/stats.txt', implode("\n", $stats) . "\n");
