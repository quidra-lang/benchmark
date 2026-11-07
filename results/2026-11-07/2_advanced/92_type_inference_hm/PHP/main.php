<?php

foreach (['lexer', 'parser', 'unifier', 'inference', 'evaluator'] as $module)
    require_once __DIR__ . "/$module.php";
function printValue(mixed $v): string
{
    if (is_bool($v))
        return $v ? 'true' : 'false';
    if (is_int($v))
        return (string) $v;
    if (is_string($v))
        return '"' . strtr($v, ['\\' => '\\\\', '"' => '\\"', "\n" => '\\n', "\t" => '\\t']) . '"';
    if ($v instanceof MLPair)
        return '(' . printValue($v->first) . ', ' . printValue($v->second) . ')';
    if (is_array($v))
        return '[' . implode('; ', array_map(printValue(...), $v)) . ']';
    return '<fun>';
}

final class TypePrinter
{
    private array $names = [];

    public function __construct(
        private ?array $quantified = null,
    ) {}

    public function format(TypeVariable|MLType $value): string
    {
        $v = resolve($value);
        if ($v instanceof TypeVariable) {
            $id = spl_object_id($v);
            if (!isset($this->names[$id])) {
                $i = count($this->names);
                $prefix = $this->quantified !== null && !isset($this->quantified[$id]) ? "'_" : "'";
                $this->names[$id] = $prefix . chr(97 + ($i % 26)) . ($i >= 26 ? (string) intdiv($i, 26) : '');
            }
            return $this->names[$id];
        }
        if (in_array($v->kind, ['int', 'bool', 'string'], true))
            return $v->kind;
        $a = resolve($v->children[0]);
        $left = $this->format($a);
        $ak = $a instanceof MLType ? $a->kind : null;
        if ($v->kind === 'list')
            return (in_array($ak, ['pair', 'function'], true) ? '(' . $left . ')' : $left) . ' list';
        $b = resolve($v->children[1]);
        $right = $this->format($b);
        $bk = $b instanceof MLType ? $b->kind : null;
        if ($v->kind === 'pair')
            return (
                (in_array($ak, ['pair', 'function'], true) ? '(' . $left . ')' : $left)
                . ' * '
                . (in_array($bk, ['pair', 'function'], true) ? '(' . $right . ')' : $right)
            );
        return ($ak === 'function' ? '(' . $left . ')' : $left) . ' -> ' . $right;
    }
}

function formatDeclaredType(MLNode $e): string
{
    if ($e->kind === 'type_variable')
        return $e->value;
    if (in_array($e->kind, ['int', 'bool', 'string'], true))
        return $e->kind;
    $a = $e->children[0];
    $left = formatDeclaredType($a);
    if ($e->kind === 'list')
        return (in_array($a->kind, ['pair', 'function'], true) ? '(' . $left . ')' : $left) . ' list';
    $b = $e->children[1];
    $right = formatDeclaredType($b);
    if ($e->kind === 'pair')
        return (
            (in_array($a->kind, ['pair', 'function'], true) ? '(' . $left . ')' : $left)
            . ' * '
            . (in_array($b->kind, ['pair', 'function'], true) ? '(' . $right . ')' : $right)
        );
    return ($a->kind === 'function' ? '(' . $left . ')' : $left) . ' -> ' . $right;
}

function signatureType(MLNode $e, array &$variables): TypeVariable|MLType
{
    if ($e->kind === 'type_variable')
        return $variables[$e->value] ??= new TypeVariable();
    $children = [];
    foreach ($e->children as $c)
        $children[] = signatureType($c, $variables);
    return new MLType($e->kind, ...$children);
}

function identicalTypes(TypeVariable|MLType $a, TypeVariable|MLType $b): bool
{
    $a = resolve($a);
    $b = resolve($b);
    if ($a instanceof TypeVariable || $b instanceof TypeVariable)
        return $a === $b;
    if ($a->kind !== $b->kind)
        return false;
    foreach ($a->children as $i => $c)
        if (!identicalTypes($c, $b->children[$i]))
            return false;
    return true;
}

function signatureMatches(TypeVariable|MLType $a, TypeVariable|MLType $b, array &$assignments): bool
{
    $a = resolve($a);
    $b = resolve($b);
    if ($a instanceof TypeVariable) {
        $id = spl_object_id($a);
        if (isset($assignments[$id]))
            return identicalTypes($assignments[$id], $b);
        $assignments[$id] = $b;
        return true;
    }
    if ($b instanceof TypeVariable || $a->kind !== $b->kind)
        return false;
    foreach ($a->children as $i => $c)
        if (!signatureMatches($c, $b->children[$i], $assignments))
            return false;
    return true;
}

function checkSignatures(BindingGroup $g, array $signatures): void
{
    foreach ($g->bindings as $i => $b) {
        if ($signatures[$i] === null)
            continue;
        $variables = $assignments = [];
        $declared = signatureType($signatures[$i][1], $variables);
        $inferred = $b->scheme->value;
        if (!signatureMatches($inferred, $declared, $assignments))
            throw new InferenceError('signature', $b->position, [
                'name' => $b->name,
                'inferred' => $inferred,
                'declared' => $declared,
            ]);
        $b->scheme = new TypeScheme($declared, freeVariables($declared));
    }
}

function typeErrorMessage(InferenceError $e): string
{
    $d = $e->details;
    $p = new TypePrinter();
    if ($e->kind === 'unbound') {
        $name = $d['name'];
        $best = null;
        $distance = 3;
        foreach ($d['candidates'] as $candidate) {
            $v = levenshtein($name, $candidate);
            if (
                $v <= 2
                && $v < strlen($name)
                && ($v < $distance || $v === $distance && ($best === null || strcmp($candidate, $best) < 0))
            ) {
                $distance = $v;
                $best = $candidate;
            }
        }
        return "unbound variable '$name'" . ($best === null ? '' : " (did you mean '$best'?)");
    }
    if ($e->kind === 'not_function')
        return 'expected a function but found ' . $p->format($d['found']);
    if ($e->kind === 'check') {
        $message = 'expected ' . $p->format($d['expected']) . ' but found ' . $p->format($d['found']);
        $f = $d['failure'];
        if ($f->infinite) {
            $v = $f->expected;
            $t = $f->found;
            if (!$v instanceof TypeVariable)
                [$v, $t] = [$t, $v];
            $message .= ' (infinite type ' . $p->format($v) . ' = ' . $p->format($t) . ')';
        } elseif ($f->nested)
            $message .= ' (' . $p->format($f->expected) . ' vs ' . $p->format($f->found) . ')';
        return $message;
    }
    $name = $d['name'];
    return match ($e->kind) {
        'duplicate_pattern' => "variable '$name' is bound twice in this pattern",
        'duplicate_let' => "variable '$name' is bound twice in this let",
        'recursive_function' => "'$name' in let rec must be a function",
        default => "'$name' has type "
            . $p->format($d['inferred'])
            . ' but its signature is '
            . $p->format($d['declared']),
    };
}

function builtinEnvironments(): array
{
    $a = new TypeVariable();
    $b = new TypeVariable();
    $fst = new TypeScheme(new MLType('function', new MLType('pair', $a, $b), $a), [
        spl_object_id($a) => $a,
        spl_object_id($b) => $b,
    ]);
    $a = new TypeVariable();
    $b = new TypeVariable();
    $snd = new TypeScheme(new MLType('function', new MLType('pair', $a, $b), $b), [
        spl_object_id($a) => $a,
        spl_object_id($b) => $b,
    ]);
    $r = new TypeVariable();
    $types = [
        'fst' => $fst,
        'snd' => $snd,
        'not' => new TypeScheme(new MLType('function', new MLType('bool'), new MLType('bool'))),
        'string_of_int' => new TypeScheme(new MLType('function', new MLType('int'), new MLType('string'))),
        'failwith' => new TypeScheme(new MLType('function', new MLType('string'), $r), [
            spl_object_id($r) => $r,
        ]),
    ];
    $fail = static function ($value, $position): never {
        throw new RuntimeFailure($position, 'failure ' . printValue($value));
    };
    $values = new ValueEnvironment([
        'fst' => new MLBuiltin(fn($v, $p) => $v->first),
        'snd' => new MLBuiltin(fn($v, $p) => $v->second),
        'not' => new MLBuiltin(fn($v, $p) => !$v),
        'string_of_int' => new MLBuiltin(fn($v, $p) => (string) $v),
        'failwith' => new MLBuiltin($fail),
    ]);
    return [$types, $values];
}

function leadingParameters(MLNode $e): array
{
    $parameters = [];
    while ($e->kind === 'fun') {
        $parameters[] = $e->value->spelling;
        $e = $e->children[0];
    }
    return [$parameters, $e];
}

function formatBinding(Binding $b): string
{
    [$parameters, $body] = leadingParameters($b->expression);
    return implode(' ', [$b->name, ...$parameters, '=', formatExpression($body)]);
}

function formatGroup(BindingGroup $g): string
{
    return (
        ($g->recPosition === null ? 'let ' : 'let rec ')
        . implode(' and ', array_map(formatBinding(...), $g->bindings))
    );
}

function endsWithMatch(MLNode $e): bool
{
    return match ($e->kind) {
        'match' => true,
        'let', 'fun' => endsWithMatch($e->children[0]),
        'if' => endsWithMatch($e->children[2]),
        default => false,
    };
}

function formatPattern(MLNode $p): string
{
    if ($p->kind === 'name' || $p->kind === 'wildcard')
        return $p->value;
    if (in_array($p->kind, ['integer', 'boolean', 'string'], true))
        return printValue($p->value);
    if ($p->kind === 'list')
        return '[' . implode('; ', array_map(formatPattern(...), $p->children)) . ']';
    [$a, $b] = $p->children;
    $left = formatPattern($a);
    $right = formatPattern($b);
    if ($p->kind === 'pair')
        return "($left, $right)";
    return ($a->kind === 'cons' ? "($left)" : $left) . ' :: ' . $right;
}

function formatExpression(MLNode $e, int $minimum = 0): string
{
    $c = $e->children;
    $strength = 9;
    switch ($e->kind) {
        case 'integer':
        case 'boolean':
        case 'string':
            $text = printValue($e->value);
            break;
        case 'name':
            $text = $e->value;
            break;
        case 'fun':
            $strength = 0;
            [$parameters, $body] = leadingParameters($e);
            $text = 'fun ' . implode(' ', $parameters) . ' -> ' . formatExpression($body);
            break;
        case 'apply':
            $strength = 8;
            $text = formatExpression($c[0], 8) . ' ' . formatExpression($c[1], 9);
            break;
        case 'binary':
            [$strength, $right] = OPERATORS[$e->value->spelling];
            $text =
                formatExpression($c[0], $right ? $strength + 1 : $strength)
                . ' '
                . $e->value->spelling
                . ' '
                . formatExpression($c[1], $right ? $strength : $strength + 1);
            break;
        case 'negate':
            $strength = 7;
            $text = '-' . formatExpression($c[0], 7);
            break;
        case 'if':
            $strength = 0;
            $text =
                'if '
                . formatExpression($c[0])
                . ' then '
                . formatExpression($c[1])
                . ' else '
                . formatExpression($c[2]);
            break;
        case 'pair':
            $text = '(' . formatExpression($c[0]) . ', ' . formatExpression($c[1]) . ')';
            break;
        case 'list':
            $text = '[' . implode('; ', array_map(formatExpression(...), $c)) . ']';
            break;
        case 'let':
            $strength = 0;
            $text = formatGroup($e->value) . ' in ' . formatExpression($c[0]);
            break;
        case 'match':
            $strength = 0;
            $arms = [];
            foreach ($e->value as $i => [$pattern, $arm]) {
                $body = formatExpression($arm);
                if ($i < (count($e->value) - 1) && endsWithMatch($arm))
                    $body = '(' . $body . ')';
                $arms[] = formatPattern($pattern) . ' -> ' . $body;
            }
            $text = 'match ' . formatExpression($c[0]) . ' with ' . implode(' | ', $arms);
            break;
    }
    return $strength < $minimum ? '(' . $text . ')' : $text;
}

function formatItem(Item $item): string
{
    if ($item->kind === 'signature')
        return 'val ' . $item->value[0]->spelling . ' : ' . formatDeclaredType($item->value[1]) . ';;';
    return (
        ($item->kind === 'declaration' ? formatGroup($item->value) : formatExpression($item->value)) . ';;'
    );
}

function coverageType(TypeVariable|MLType $type): array
{
    $t = resolve($type);
    if ($t instanceof TypeVariable || $t->kind === 'function')
        return ['opaque'];
    return [$t->kind, ...array_map(coverageType(...), $t->children)];
}

function coveragePattern(MLNode $p): ?array
{
    if ($p->kind === 'name' || $p->kind === 'wildcard')
        return null;
    if (in_array($p->kind, ['integer', 'boolean', 'string'], true))
        return [[$p->kind, $p->value], []];
    if ($p->kind === 'list') {
        $r = [['nil'], []];
        foreach (array_reverse($p->children) as $c)
            $r = [['cons'], [coveragePattern($c), $r]];
        return $r;
    }
    return [[$p->kind === 'pair' ? 'pair' : 'cons'], array_map(coveragePattern(...), $p->children)];
}

function constructors(array $t): array
{
    return match ($t[0]) {
        'bool' => [['boolean', false], ['boolean', true]],
        'list' => [['nil'], ['cons']],
        'pair' => [['pair']],
        default => [],
    };
}

function constructorArguments(array $constructor, array $t): array
{
    return match ($constructor[0]) {
        'pair' => array_slice($t, 1),
        'cons' => [$t[1], $t],
        default => [],
    };
}

function specialize(array $matrix, array $constructor, int $arity): array
{
    $rows = [];
    foreach ($matrix as $row) {
        if ($row[0] === null)
            $rows[] = [...array_fill(0, $arity, null), ...array_slice($row, 1)];
        elseif ($row[0][0] === $constructor)
            $rows[] = [...$row[0][1], ...array_slice($row, 1)];
    }
    return $rows;
}

function usefulPattern(array $matrix, array $query, array $types, array &$memo): bool
{
    if (!$query)
        return !$matrix;
    if (!$matrix)
        return true;
    $key = serialize([$matrix, $query, $types]);
    if (isset($memo[$key]))
        return $memo[$key];
    $head = $query[0];
    $rest = array_slice($query, 1);
    $remainingTypes = array_slice($types, 1);
    if ($head !== null) {
        [$constructor, $arguments] = $head;
        $selected = specialize($matrix, $constructor, count($arguments));
        return $memo[$key] = usefulPattern(
            $selected,
            [...$arguments, ...$rest],
            [...constructorArguments($constructor, $types[0]), ...$remainingTypes],
            $memo,
        );
    }
    $possible = constructors($types[0]);
    $present = [];
    foreach ($matrix as $row)
        if ($row[0] !== null)
            $present[serialize($row[0][0])] = true;
    if ($possible && array_all($possible, fn($c) => isset($present[serialize($c)]))) {
        foreach ($possible as $constructor) {
            $args = constructorArguments($constructor, $types[0]);
            if (usefulPattern(
                specialize($matrix, $constructor, count($args)),
                [...array_fill(0, count($args), null), ...$rest],
                [...$args, ...$remainingTypes],
                $memo,
            ))
                return $memo[$key] = true;
        }
        return $memo[$key] = false;
    }
    $default = [];
    foreach ($matrix as $row)
        if ($row[0] === null)
            $default[] = array_slice($row, 1);
    return $memo[$key] = usefulPattern($default, $rest, $remainingTypes, $memo);
}

function expressionNodes(MLNode $e): Generator
{
    yield $e;
    if ($e->kind === 'let')
        foreach ($e->value->bindings as $b)
            yield from expressionNodes($b->expression);
    foreach ($e->children as $c)
        yield from expressionNodes($c);
    if ($e->kind === 'match')
        foreach ($e->value as [$pattern, $arm])
            yield from expressionNodes($arm);
}

function recursionClassification(MLNode $expr, array $targets, array $references): string
{
    [, $body] = leadingParameters($expr);
    $calls = [];
    $visit = function (MLNode $e, bool $tail) use (&$visit, &$calls, $targets, $references): void {
        $c = $e->children;
        $isTarget = fn($n) => (
            isset($references[spl_object_id($n)])
            && isset($targets[spl_object_id($references[spl_object_id($n)])])
        );
        if ($e->kind === 'name') {
            if ($isTarget($e))
                $calls[] = false;
            return;
        }
        if ($e->kind === 'apply') {
            $args = [];
            $function = $e;
            while ($function->kind === 'apply') {
                $args[] = $function->children[1];
                $function = $function->children[0];
            }
            if ($function->kind === 'name' && $isTarget($function))
                $calls[] = $tail;
            else
                $visit($function, false);
            foreach (array_reverse($args) as $arg)
                $visit($arg, false);
            return;
        }
        if ($e->kind === 'if') {
            $visit($c[0], false);
            $visit($c[1], $tail);
            $visit($c[2], $tail);
            return;
        }
        if ($e->kind === 'match') {
            $visit($c[0], false);
            foreach ($e->value as [$p, $arm])
                $visit($arm, $tail);
            return;
        }
        if ($e->kind === 'let') {
            foreach ($e->value->bindings as $b)
                $visit($b->expression, false);
            $visit($c[0], $tail);
            return;
        }
        if ($e->kind === 'binary' && in_array($e->value->spelling, ['&&', '||'], true)) {
            $visit($c[0], false);
            $visit($c[1], $tail);
            return;
        }
        foreach ($c as $x)
            $visit($x, false);
    };
    $visit($body, true);
    return !$calls ? '' : (in_array(false, $calls, true) ? 'recursive' : 'tail recursive');
}

final class StaticSymbol
{
    public bool $used = false;

    public function __construct(
        public string $name,
        public array $position,
        public bool $topLevel = false,
    ) {}
}

final class StaticChecks
{
    private array $symbols = [], $references = [], $groups = [], $warnings = [];

    private function symbol(string $name, array $position, bool $top = false): StaticSymbol
    {
        $s = new StaticSymbol($name, $position, $top);
        $this->symbols[] = $s;
        return $s;
    }

    private function bindPattern(MLNode $p, array &$env): void
    {
        if ($p->kind === 'name')
            $env[$p->value] = $this->symbol($p->value, $p->position);
        foreach ($p->children as $c)
            $this->bindPattern($c, $env);
    }

    private function group(BindingGroup $g, array $env, bool $top = false): array
    {
        $inner = $env;
        $targets = [];
        foreach ($g->bindings as $b) {
            $s = $this->symbol($b->name, $b->position, $top);
            $inner[$b->name] = $s;
            $targets[spl_object_id($s)] = true;
        }
        $this->groups[] = [$g, $targets];
        $right = $g->recPosition === null ? $env : $inner;
        foreach ($g->bindings as $b)
            $this->expression($b->expression, $right);
        return $inner;
    }

    private function matchWarnings(MLNode $e): void
    {
        $memo = $matrix = [];
        $types = [coverageType($e->children[0]->inferred)];
        foreach ($e->value as $i => [$pattern, $arm]) {
            $query = [coveragePattern($pattern)];
            if ($i && !usefulPattern($matrix, $query, $types, $memo))
                $this->warnings[] = [$pattern->position, 2, 'this match case is unused'];
            $matrix[] = $query;
        }
        if (usefulPattern($matrix, [null], $types, $memo))
            $this->warnings[] = [$e->position, 1, 'this match is not exhaustive'];
    }

    private function expression(MLNode $e, array $env): void
    {
        if ($e->kind === 'name') {
            $s = $env[$e->value] ?? null;
            $this->references[spl_object_id($e)] = $s;
            if ($s !== null)
                $s->used = true;
            return;
        }
        if ($e->kind === 'fun') {
            $inner = $env;
            $p = $e->value;
            if ($p->spelling !== '_')
                $inner[$p->spelling] = $this->symbol($p->spelling, $p->position);
            $this->expression($e->children[0], $inner);
            return;
        }
        if ($e->kind === 'let') {
            $this->expression($e->children[0], $this->group($e->value, $env));
            return;
        }
        if ($e->kind === 'match') {
            $this->expression($e->children[0], $env);
            $this->matchWarnings($e);
            foreach ($e->value as [$p, $arm]) {
                $inner = $env;
                $this->bindPattern($p, $inner);
                $this->expression($arm, $inner);
            }
            return;
        }
        foreach ($e->children as $c)
            $this->expression($c, $env);
    }

    public function item(Item $item, array $environmentNames): array
    {
        $env = array_fill_keys($environmentNames, null);
        if ($item->kind === 'declaration')
            $this->group($item->value, $env, true);
        else
            $this->expression($item->value, $env);
        foreach ($this->groups as [$g, $targets]) {
            if ($g->recPosition === null)
                continue;
            $used = false;
            foreach ($g->bindings as $b)
                foreach (expressionNodes($b->expression) as $node) {
                    $s = $this->references[spl_object_id($node)] ?? null;
                    if ($s !== null && isset($targets[spl_object_id($s)]))
                        $used = true;
                }
            if (!$used)
                $this->warnings[] = [$g->recPosition, 3, 'unused rec flag'];
            foreach ($g->bindings as $b)
                $b->classification = recursionClassification($b->expression, $targets, $this->references);
        }
        foreach ($this->symbols as $s)
            if (!$s->topLevel && !$s->used && !str_starts_with($s->name, '_'))
                $this->warnings[] = [$s->position, 4, "unused variable '{$s->name}'"];
        usort($this->warnings, fn($a, $b) => [$a[0][1], $a[0][2], $a[1]] <=> [$b[0][1], $b[0][2], $b[1]]);
        return $this->warnings;
    }
}

function classificationSuffix(Binding $b): string
{
    return $b->classification === '' ? '' : ' (' . $b->classification . ')';
}

final class MiniML
{
    private array
        $typeEnvironment,
        $types = [],
        $values = [],
        $formatted = [],
        $reports = [],
        $statistics = [],
        $sourceLines = []
    ;
    private ValueEnvironment $valueEnvironment;
    private string $currentFile = '';

    public function __construct(
        private array $sources,
    ) {
        [$this->typeEnvironment, $this->valueEnvironment] = builtinEnvironments();
        foreach ($sources as $name => $source) {
            $lines = explode("\n", $source);
            array_pop($lines);
            $this->sourceLines[$name] = $lines;
            $this->statistics[$name] = array_fill_keys([
                'items',
                'bindings',
                'syntax',
                'type',
                'runtime',
                'warnings',
                'calls',
            ], 0);
        }
    }

    private function report(string $kind, array $position, string $message): void
    {
        [$file, $line, $column] = $position;
        $counter = $kind === 'warning' ? 'warnings' : explode(' ', $kind)[0];
        ++$this->statistics[$this->currentFile][$counter];
        $this->reports[] = "$file:$line:$column: $kind: $message";
        if (isset($this->sourceLines[$file][$line - 1])) {
            $this->reports[] = '    ' . $this->sourceLines[$file][$line - 1];
            $this->reports[] = str_repeat(' ', $column + 3) . '^';
        }
    }

    private function unusedSignature(array $s): void
    {
        $this->report('warning', $s[0]->position, "signature for '{$s[0]->spelling}' is never used");
    }

    private function writeTypes(Item $item, TypeVariable|MLType|null $inferred, array $locals): void
    {
        if ($item->kind === 'declaration')
            foreach ($item->value->bindings as $b)
                $this->types[] =
                    $b->name
                    . ' : '
                    . new TypePrinter()->format($b->scheme->value)
                    . classificationSuffix($b);
        else
            $this->types[] = '- : ' . new TypePrinter()->format($inferred);
        usort($locals, fn($a, $b) => array_slice($a->position, 1) <=> array_slice($b->position, 1));
        foreach ($locals as $b) {
            [, $line, $column] = $b->position;
            $this->types[] =
                "  {$b->name} ($line:$column) : "
                . new TypePrinter($b->scheme->quantified)->format($b->scheme->value)
                . classificationSuffix($b);
        }
    }

    private function processItem(Item $item, array &$pending, Evaluator $evaluator): void
    {
        $this->formatted[] = formatItem($item);
        if ($item->kind === 'signature') {
            $name = $item->value[0]->spelling;
            if (isset($pending[$name]))
                $this->unusedSignature($pending[$name]);
            $pending[$name] = $item->value;
            return;
        }
        $signatures = [];
        if ($item->kind === 'declaration')
            foreach ($item->value->bindings as $b) {
                $signatures[] = $pending[$b->name] ?? null;
                unset($pending[$b->name]);
            }
        $inferencer = new Inferencer();
        $inferred = null;
        try {
            if ($item->kind === 'declaration') {
                $inferencer->group($item->value, $this->typeEnvironment);
                checkSignatures($item->value, $signatures);
            } else
                $inferred = $inferencer->expression($item->value, $this->typeEnvironment);
        } catch (InferenceError $e) {
            $this->report('type error', $e->position, typeErrorMessage($e));
            return;
        }
        $warnings = new StaticChecks()->item($item, array_keys($this->typeEnvironment));
        $this->writeTypes($item, $inferred, $inferencer->localBindings);
        foreach ($warnings as [$position, $priority, $message])
            $this->report('warning', $position, $message);
        try {
            if ($item->kind === 'declaration')
                $environment = $evaluator->group($item->value, $this->valueEnvironment);
            else
                $value = $evaluator->expression($item->value, $this->valueEnvironment);
        } catch (RuntimeFailure $e) {
            $this->report('runtime error', $e->position, $e->getMessage());
            return;
        }
        if ($item->kind === 'declaration') {
            foreach ($item->value->bindings as $b) {
                $this->values[] = $b->name . ' = ' . printValue($environment->bindings[$b->name]);
                $this->typeEnvironment[$b->name] = $b->scheme;
            }
            $this->valueEnvironment = $environment;
            $this->statistics[$this->currentFile]['bindings'] += count($item->value->bindings);
        } else
            $this->values[] = '- = ' . printValue($value);
    }

    public function run(): array
    {
        foreach ($this->sources as $file => $source) {
            $this->currentFile = $file;
            $this->types[] = $this->values[] = "== $file ==";
            $this->formatted[] = "(* $file *)";
            $pending = [];
            $evaluator = new Evaluator();
            $parser = new MLParser(tokenize($source, $file));
            while ($parser->peek()->kind !== 'EOF') {
                ++$this->statistics[$file]['items'];
                try {
                    $item = $parser->item();
                } catch (SyntaxFailure $e) {
                    $t = $e->token;
                    $message = match ($t->kind) {
                        'invalid' => $t->value,
                        'EOF' => 'unexpected end of file',
                        default => "unexpected '{$t->spelling}'",
                    };
                    $this->report('syntax error', $t->position, $message);
                    $parser->recover();
                    continue;
                }
                $this->processItem($item, $pending, $evaluator);
            }
            $remaining = array_values($pending);
            usort(
                $remaining,
                fn($a, $b) => array_slice($a[0]->position, 1) <=> array_slice($b[0]->position, 1),
            );
            foreach ($remaining as $s)
                $this->unusedSignature($s);
            $this->statistics[$file]['calls'] = $evaluator->calls;
        }
        $this->reports[] = '== summary ==';
        foreach ($this->statistics as $file => $counts) {
            $parts = [];
            foreach ($counts as $name => $count)
                $parts[] = "$name=$count";
            $this->reports[] = $file . ': ' . implode(' ', $parts);
        }
        return [
            'types.txt' => $this->types,
            'values.txt' => $this->values,
            'errors.txt' => $this->reports,
            'formatted.ml' => $this->formatted,
        ];
    }
}

$sources = [];
foreach (['prelude.ml', 'program.ml'] as $file)
    $sources[$file] = file_get_contents('input/' . $file);
if (!is_dir('output'))
    mkdir('output');
foreach (new MiniML($sources)->run() as $name => $lines)
    file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
