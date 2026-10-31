<?php

foreach (['lexer', 'parser', 'semantic', 'codegen', 'vm'] as $module)
    require_once __DIR__ . "/$module.php";
const RULES = [
    'const-jump',
    'not-compare',
    'not-jump',
    'invert-branch',
    'thread',
    'jump-next',
    'unreachable',
];

const PUSHING = ['PUSH', 'LOADG', 'LOADL', 'READ'];

const POPPING = [
    'POP',
    'STOREG',
    'STOREL',
    'JUMPF',
    'JUMPT',
    'RETV',
    'ADD',
    'SUB',
    'MUL',
    'DIV',
    'MOD',
    'LT',
    'LE',
    'GT',
    'GE',
    'EQ',
    'NE',
];

function collectWarnings(Analyzer $a): array
{
    $warnings = [];
    foreach ($a->variables as $v)
        if ($v->readAccesses === 0)
            $warnings[] = [
                $v->namePosition,
                'unused ' . ($v->kind === 'parameter' ? 'parameter' : 'variable') . " '{$v->name}'",
            ];
    foreach ($a->functions as $function) {
        $pending = [$function->body];
        while ($pending) {
            $s = array_pop($pending);
            if ($s->kind === 'block')
                for ($i = 0; $i < (count($s->statements) - 1); ++$i)
                    if (!canComplete($s->statements[$i])) {
                        $warnings[] = [$s->statements[$i + 1]->position, 'unreachable statement'];
                        break;
                    }
            array_push($pending, ...statementChildren($s));
        }
    }
    $reachable = [];
    $pending = [$a->globals['main']];
    while ($pending) {
        $f = array_pop($pending);
        if (!isset($reachable[$f->name])) {
            $reachable[$f->name] = true;
            array_push($pending, ...array_values($f->calls));
        }
    }
    foreach ($a->functions as $f)
        if (!isset($reachable[$f->name]))
            $warnings[] = [$f->namePosition, "function '{$f->name}' is never called"];
    usort($warnings, fn($x, $y) => $x[0] <=> $y[0]);
    return [$warnings, $reachable];
}

function isRecursive(object $f): bool
{
    $seen = [];
    $pending = array_values($f->calls);
    while ($pending) {
        $x = array_pop($pending);
        if ($x === $f)
            return true;
        if (!isset($seen[$x->name])) {
            $seen[$x->name] = true;
            array_push($pending, ...array_values($x->calls));
        }
    }
    return false;
}

function literalValue(object $n, string $kind, mixed $v): bool
{
    return $n->kind === $kind && $n->value === $v;
}

final class Folder
{
    public int $count = 0;

    private function literal(object $n, mixed $v): object
    {
        ++$this->count;
        return node($n->type === 'bool' ? 'boolean' : 'integer', $n->position, [
            'value' => $n->type === 'bool' ? (bool) $v : $v,
            'type' => $n->type,
        ]);
    }

    private function identity(object $n): object
    {
        ++$this->count;
        return $n;
    }

    public function expression(object $n): object
    {
        if ($n->kind === 'unary') {
            $n->operand = $this->expression($n->operand);
            if (in_array($n->operand->kind, ['integer', 'boolean'], true)) {
                try {
                    $v = calculate($n->operator === '-' ? 'NEG' : 'NOT', (int) $n->operand->value);
                } catch (RuntimeFault) {
                    return $n;
                }
                return $this->literal($n, $v);
            }
        } elseif ($n->kind === 'binary') {
            $n->left = $this->expression($n->left);
            $n->right = $this->expression($n->right);
            $a = $n->left;
            $b = $n->right;
            $op = $n->operator;
            if (
                in_array($a->kind, ['integer', 'boolean'], true)
                && in_array($b->kind, ['integer', 'boolean'], true)
            ) {
                try {
                    $v = match ($op) {
                        '&&' => (bool) $a->value && (bool) $b->value,
                        '||' => (bool) $a->value || (bool) $b->value,
                        default => calculate(BINARY[$op], (int) $a->value, (int) $b->value),
                    };
                    return $this->literal($n, $v);
                } catch (RuntimeFault) {
                }
            }
            if ($op === '&&' && literalValue($a, 'boolean', false))
                return $this->literal($n, false);
            if ($op === '||' && literalValue($a, 'boolean', true))
                return $this->literal($n, true);
            if (
                $op === '&&' && literalValue($a, 'boolean', true)
                || $op === '||' && literalValue($a, 'boolean', false)
                || $op === '+' && literalValue($a, 'integer', 0)
                || $op === '*' && literalValue($a, 'integer', 1)
            )
                return $this->identity($b);
            if (
                in_array($op, ['+', '-'], true) && literalValue($b, 'integer', 0)
                || in_array($op, ['*', '/'], true) && literalValue($b, 'integer', 1)
                || $op === '&&' && literalValue($b, 'boolean', true)
                || $op === '||' && literalValue($b, 'boolean', false)
            )
                return $this->identity($a);
        } elseif ($n->kind === 'array')
            $n->index = $this->expression($n->index);
        elseif ($n->kind === 'call')
            $n->arguments = array_map($this->expression(...), $n->arguments);
        return $n;
    }

    public function statement(object $n): object
    {
        switch ($n->kind) {
            case 'declaration':
                if ($n->initializer !== null)
                    $n->initializer = $this->expression($n->initializer);
                break;
            case 'assignment':
                if ($n->index !== null)
                    $n->index = $this->expression($n->index);
                $n->value = $this->expression($n->value);
                break;
            case 'call_statement':
                $n->expression = $this->expression($n->expression);
                break;
            case 'print':
                $n->arguments = array_map($this->expression(...), $n->arguments);
                break;
            case 'return':
                if ($n->value !== null)
                    $n->value = $this->expression($n->value);
                break;
            case 'block':
                $n->statements = array_map($this->statement(...), $n->statements);
                break;
            case 'if':
                $n->condition = $this->expression($n->condition);
                if ($n->condition->kind === 'boolean') {
                    $selected = $n->condition->value ? $n->then : $n->otherwise;
                    $replacement = $selected === null
                        ? node('empty', $n->position)
                        : $this->statement($selected);
                    ++$this->count;
                    return $replacement;
                }
                $n->then = $this->statement($n->then);
                if ($n->otherwise !== null)
                    $n->otherwise = $this->statement($n->otherwise);
                break;
            case 'while':
                $n->condition = $this->expression($n->condition);
                if (literalValue($n->condition, 'boolean', false)) {
                    ++$this->count;
                    return node('empty', $n->position);
                }
                $n->body = $this->statement($n->body);
                break;
            case 'for':
                if ($n->initial !== null)
                    $n->initial = $this->statement($n->initial);
                if ($n->condition !== null)
                    $n->condition = $this->expression($n->condition);
                if ($n->update !== null)
                    $n->update = $this->statement($n->update);
                $n->body = $this->statement($n->body);
                break;
        }
        return $n;
    }
}

function jumpsOn(string $op, int $value): bool
{
    return ($value === 0) === ($op === 'JUMPF');
}

function deleteInstruction(array &$code, int $p): void
{
    array_splice($code, $p, 1);
    foreach ($code as $i => $v)
        if (in_array($v->op, JUMPS, true) && $v->args[0] > $p)
            $code[$i] = new Instruction($v->op, [$v->args[0] - 1], $v->position);
}

function rewriteAt(array &$code, int $i, array $targets): int
{
    $a = $code[$i];
    $b = $code[$i + 1] ?? null;
    $free = $b !== null && !isset($targets[$i + 1]);
    if ($free && $a->op === 'PUSH' && in_array($b->op, CONDITIONAL, true)) {
        if (jumpsOn($b->op, $a->args[0])) {
            $code[$i] = new Instruction('JUMP', $b->args, $b->position);
            deleteInstruction($code, $i + 1);
        } else {
            deleteInstruction($code, $i + 1);
            deleteInstruction($code, $i);
        }
        return 1;
    }
    if ($free && isset(NEGATED[$a->op]) && $b->op === 'NOT') {
        $code[$i] = new Instruction(NEGATED[$a->op], $a->args, $a->position);
        deleteInstruction($code, $i + 1);
        return 2;
    }
    if ($free && $a->op === 'NOT' && in_array($b->op, CONDITIONAL, true)) {
        $code[$i] = new Instruction(INVERSE[$b->op], $b->args, $b->position);
        deleteInstruction($code, $i + 1);
        return 3;
    }
    if ($free && in_array($a->op, CONDITIONAL, true) && $a->args[0] === ($i + 2) && $b->op === 'JUMP') {
        $code[$i] = new Instruction(INVERSE[$a->op], $b->args, $a->position);
        deleteInstruction($code, $i + 1);
        return 4;
    }
    if (in_array($a->op, JUMPS, true)) {
        $target = $a->args[0];
        $new = null;
        if ($target < count($code)) {
            $dest = $code[$target];
            if ($dest->op === 'JUMP')
                $new = $dest->args[0];
            elseif (
                $dest->op === 'PUSH'
                && isset($code[$target + 1])
                && in_array($code[$target + 1]->op, CONDITIONAL, true)
            )
                $new = jumpsOn($code[$target + 1]->op, $dest->args[0])
                    ? $code[$target + 1]->args[0]
                    : $target + 2;
        }
        if ($new !== null && $new !== $target) {
            $code[$i] = new Instruction($a->op, [$new], $a->position);
            return 5;
        }
        if ($target === ($i + 1)) {
            if ($a->op === 'JUMP')
                deleteInstruction($code, $i);
            else
                $code[$i] = new Instruction('POP', [], $a->position);
            return 6;
        }
    }
    if ($free && in_array($a->op, TRANSFERS, true)) {
        deleteInstruction($code, $i + 1);
        return 7;
    }
    return 0;
}

function optimize(array $code): array
{
    $counts = array_fill(0, count(RULES), 0);
    while (true) {
        $targets = [];
        foreach ($code as $v)
            if (in_array($v->op, JUMPS, true))
                $targets[$v->args[0]] = true;
        $changed = false;
        for ($i = 0; $i < count($code); ++$i) {
            $rule = rewriteAt($code, $i, $targets);
            if ($rule) {
                ++$counts[$rule - 1];
                $changed = true;
                break;
            }
        }
        if (!$changed)
            return [$code, $counts];
    }
}

function successors(array $code, int $i): array
{
    $v = $code[$i];
    $r = [];
    if (!in_array($v->op, TRANSFERS, true) && isset($code[$i + 1]))
        $r[] = $i + 1;
    if (in_array($v->op, JUMPS, true) && $v->args[0] < count($code) && !in_array($v->args[0], $r, true))
        $r[] = $v->args[0];
    return $r;
}

function stackEffect(Instruction $v, array $functions): int
{
    if (in_array($v->op, PUSHING, true))
        return 1;
    if (in_array($v->op, POPPING, true))
        return -1;
    return match ($v->op) {
        'STOREA' => -2,
        'CALL' => -$v->args[1] + (int) ($functions[$v->args[0]]->type !== 'void'),
        'PRINT' => -$v->args[0],
        default => 0,
    };
}

function analyzeFlow(Unit $unit, array $functions): void
{
    $code = $unit->after;
    $leaders = [0 => true];
    foreach ($code as $i => $v) {
        if (in_array($v->op, JUMPS, true) && $v->args[0] < count($code))
            $leaders[$v->args[0]] = true;
        if ((in_array($v->op, JUMPS, true) || in_array($v->op, TRANSFERS, true)) && isset($code[$i + 1]))
            $leaders[$i + 1] = true;
    }
    $starts = array_keys($leaders);
    sort($starts, SORT_NUMERIC);
    $numbers = array_flip($starts);
    foreach ($starts as $i => $start) {
        $end = ($starts[$i + 1] ?? count($code)) - 1;
        $unit->blocks[] = [$start, $end, array_map(fn($t) => $numbers[$t], successors($code, $end))];
    }
    $depths = [0 => 0];
    $pending = [0];
    $maximum = 0;
    while ($pending) {
        $i = array_pop($pending);
        $after = $depths[$i] + stackEffect($code[$i], $functions);
        $maximum = max($maximum, $after);
        foreach (successors($code, $i) as $target)
            if (!isset($depths[$target])) {
                $depths[$target] = $after;
                $pending[] = $target;
            }
    }
    $unit->depth = $maximum;
}

function linkUnits(array $units, string $version): array
{
    $addresses = [];
    $offset = 0;
    $startProperty = $version . 'Start';
    foreach ($units as $u) {
        $addresses[$u->name] = $offset;
        $u->{$startProperty} = $offset;
        $offset += count($u->{$version});
    }
    $code = $owners = $starts = [];
    foreach ($units as $u) {
        $start = $addresses[$u->name];
        $starts[$start] = $u->name;
        foreach ($u->{$version} as $v) {
            $args = $v->args;
            if (in_array($v->op, JUMPS, true))
                $args = [$start + $args[0]];
            elseif ($v->op === 'CALL')
                $args = [$addresses[$args[0]], $args[1]];
            $code[] = new Instruction($v->op, $args, $v->position);
            $owners[] = $u->name;
        }
    }
    return [$code, $owners, $starts];
}

function compileProgram(object $p): void
{
    $p->sourceText = [];
    foreach ($p->lines as [$line, $text])
        $p->sourceText[$line] = $text;
    try {
        $tokens = tokenize($p->lines);
        $declarations = new ToyParser($tokens)->parse();
        $p->analysis = new Analyzer($declarations, $tokens[count($tokens) - 1]->position)->analyze();
    } catch (ToyCompileError $e) {
        $p->error = $e;
        return;
    }
    [$p->warnings, $reachable] = collectWarnings($p->analysis);
    $p->globals = array_values(array_filter($declarations, fn($d) => $d->kind === 'global'));
    $functions = array_values(array_filter($p->analysis->functions, fn($f) => isset($reachable[$f->name])));
    $folder = new Folder();
    foreach ($p->globals as $v)
        if ($v->initializer !== null)
            $v->initializer = $folder->expression($v->initializer);
    foreach ($functions as $f)
        $f->body = $folder->statement($f->body);
    $p->folds = $folder->count;
    [$p->units, $p->globalSize] = generate($p->globals, $functions, $p->analysis->globals['main']);
    $table = [];
    foreach ($functions as $f)
        $table[$f->name] = $f;
    foreach ($p->units as $unit) {
        [$unit->after, $counts] = optimize($unit->before);
        foreach ($counts as $i => $count)
            $p->peephole[$i] += $count;
        analyzeFlow($unit, $table);
        $unit->recursive = $unit->function !== null && isRecursive($unit->function);
    }
    [$p->before, $beforeOwners, $beforeStarts] = linkUnits($p->units, 'before');
    [$p->after, $p->owners, $afterStarts] = linkUnits($p->units, 'after');
    $p->execution = new Execution($p->after, $p->owners, $afterStarts, $p->globalSize, $p->inputs)->run();
    $p->comparison = new Execution(
        $p->before,
        $beforeOwners,
        $beforeStarts,
        $p->globalSize,
        $p->inputs,
    )->run();
}

function spelling(Instruction $v): string
{
    return implode(' ', [$v->op, ...array_map(strval(...), $v->args)]);
}

function formatPosition(array $p): string
{
    return implode(':', $p);
}

function positionDisplay(object $p, array $position): array
{
    return ['  ' . $p->sourceText[$position[0]], str_repeat(' ', $position[1] + 1) . '^'];
}

function listing(object $p): array
{
    $out = [$p->globals ? 'globals:' : 'globals: none'];
    foreach ($p->globals as $v)
        $out[] = "  {$v->address} {$v->name} " . ($v->size === null ? $v->type : 'int[' . $v->size . ']');
    $out[] = 'functions:';
    foreach ($p->units as $u) {
        $signature = '';
        $callees = 'main';
        if ($u->function !== null) {
            $f = $u->function;
            $signature = ' ' . $f->type . '(' . implode(',', array_column($f->parameters, 'type')) . ')';
            $names = array_keys($f->calls);
            sort($names, SORT_STRING);
            $callees = $names ? implode(',', $names) : '-';
        }
        $out[] =
            "  {$u->name}$signature address={$u->beforeStart}->{$u->afterStart} size="
            . count($u->before)
            . '->'
            . count($u->after)
            . ' slots='
            . count($u->slots)
            . " stack={$u->depth} blocks="
            . count($u->blocks)
            . " calls=$callees"
            . ($u->recursive ? ' recursive' : '');
        foreach ($u->slots as $i => $slot)
            $out[] = "    slot $i {$slot->name} {$slot->type}";
    }
    $out[] = 'references:';
    foreach ([...$p->globals, ...$p->analysis->functions] as $d) {
        $used = array_values(array_unique(array_column($d->references, 0)));
        sort($used, SORT_NUMERIC);
        $out[] = "  {$d->name} defined {$d->namePosition[0]} used " . ($used ? implode(' ', $used) : '-');
    }
    foreach (['before', 'after'] as $version) {
        $code = $p->{$version};
        $out[] = "$version peephole: " . count($code) . ' instructions';
        foreach ($p->units as $u) {
            $out[] = $u->name . ':';
            $start = $u->{$version . 'Start'};
            for ($a = $start; $a < ($start + count($u->{$version})); ++$a)
                $out[] = str_pad((string) $a, 5, ' ', STR_PAD_LEFT) . '  ' . spelling($code[$a]);
        }
    }
    $out[] = 'control flow:';
    foreach ($p->units as $u) {
        $out[] = '  ' . $u->name;
        foreach ($u->blocks as $i => [$start, $end, $following])
            $out[] =
                "    B$i "
                . ($u->afterStart + $start)
                . '-'
                . ($u->afterStart + $end)
                . ($following ? ' -> ' . implode(' ', array_map(fn($n) => 'B' . $n, $following)) : '');
    }
    return $out;
}

function diagnostics(object $p): array
{
    if ($p->error !== null) {
        $e = $p->error;
        return [
            $e->kind . ' error ' . formatPosition($e->position) . ': ' . $e->getMessage(),
            ...positionDisplay($p, $e->position),
            'status: compile error',
        ];
    }
    $out = [];
    foreach ($p->warnings as [$position, $message])
        $out[] = 'warning ' . formatPosition($position) . ': ' . $message;
    $e = $p->execution;
    if ($e->error === null) {
        $out[] = 'status: ok';
        return $out;
    }
    $instruction = $p->after[$e->errorPc];
    $out[] =
        'runtime error '
        . formatPosition($instruction->position)
        . ': '
        . $e->error
        . ' in '
        . $p->owners[$e->errorPc];
    array_push($out, ...positionDisplay($p, $instruction->position));
    $callers = array_reverse(array_slice($e->frames, 1));
    foreach (array_slice($callers, 0, 5) as $frame) {
        $address = $frame->returnAddress - 1;
        $out[] =
            '  called from ' . $p->owners[$address] . ' at ' . formatPosition($p->after[$address]->position);
    }
    if (count($callers) > 5)
        $out[] = '  ... ' . (count($callers) - 5) . ' more';
    $out[] = 'status: runtime error';
    return $out;
}

function statistics(object $p): array
{
    $e = $p->execution;
    $c = $p->comparison;
    $same = $e->output === $c->output && $e->error === $c->error;
    $out = [
        'code: ' . count($p->before) . ' -> ' . count($p->after),
        'folds: ' . $p->folds,
        'peephole: ' . array_sum($p->peephole),
    ];
    foreach (RULES as $i => $rule)
        $out[] = "  $rule {$p->peephole[$i]}";
    array_push(
        $out,
        'executed: ' . $e->executed,
        'executed before peephole: ' . $c->executed,
        'behaviour: ' . ($same ? 'same' : 'different'),
        'max call depth: ' . $e->maxDepth,
        'max stack: ' . $e->maxStack,
    );
    $opcodes = $functions = $sourceLines = [];
    foreach ($p->after as $address => $v) {
        $count = $e->counts[$address];
        $opcodes[$v->op] = ($opcodes[$v->op] ?? 0) + $count;
        $owner = $p->owners[$address];
        $functions[$owner] = ($functions[$owner] ?? 0) + $count;
        $line = $v->position[0];
        $sourceLines[$line] = ($sourceLines[$line] ?? 0) + $count;
    }
    $out[] = 'opcodes:';
    $ops = array_keys($opcodes);
    usort($ops, fn($a, $b) => $opcodes[$b] <=> $opcodes[$a] ?: strcmp($a, $b));
    foreach ($ops as $op)
        if ($opcodes[$op])
            $out[] = "  $op {$opcodes[$op]}";
    $out[] = 'functions:';
    $names = [];
    foreach ($p->units as $u)
        if ($u->function !== null)
            $names[] = $u->name;
    usort($names, fn($a, $b) => ($functions[$b] ?? 0) <=> ($functions[$a] ?? 0) ?: strcmp($a, $b));
    foreach ($names as $name)
        $out[] = "  $name calls=" . ($e->calls[$name] ?? 0) . ' executed=' . ($functions[$name] ?? 0);
    $out[] = 'calls:';
    $pairs = [];
    foreach ($e->pairs as $caller => $callees)
        foreach ($callees as $callee => $count)
            $pairs[] = [$caller, $callee, $count];
    usort($pairs, fn($a, $b) => $b[2] <=> $a[2] ?: strcmp($a[0], $b[0]) ?: strcmp($a[1], $b[1]));
    foreach ($pairs as [$caller, $callee, $count])
        $out[] = "  $caller -> $callee $count";
    $out[] = 'hot lines:';
    $executedLines = array_keys(array_filter($sourceLines, fn($v) => $v > 0));
    usort($executedLines, fn($a, $b) => $sourceLines[$b] <=> $sourceLines[$a] ?: $a <=> $b);
    foreach (array_slice($executedLines, 0, 5) as $line)
        $out[] = "  line $line: {$sourceLines[$line]}";
    $out[] = 'coverage: ' . count($executedLines) . ' of ' . count($sourceLines) . ' lines';
    $unexecuted = array_keys(array_filter($sourceLines, fn($v) => $v === 0));
    sort($unexecuted, SORT_NUMERIC);
    $out[] = 'not executed: ' . ($unexecuted ? implode(' ', $unexecuted) : 'none');
    $out[] = 'hot spots:';
    $hot = array_keys(array_filter($e->counts, fn($v) => $v > 0));
    usort($hot, fn($a, $b) => $e->counts[$b] <=> $e->counts[$a] ?: $a <=> $b);
    foreach (array_slice($hot, 0, 5) as $a)
        $out[] = "  pc=$a count={$e->counts[$a]} " . spelling($p->after[$a]);
    return $out;
}

function summary(array $programs): array
{
    $compiled = $runtime = $folds = $executed = 0;
    $errors = array_fill_keys(['lexical', 'syntax', 'semantic'], 0);
    $peephole = array_fill(0, count(RULES), 0);
    $rows = [['program', 'status', 'code', 'executed', 'output']];
    foreach ($programs as $p) {
        if ($p->error !== null) {
            ++$errors[$p->error->kind];
            $rows[] = [$p->name, $p->error->kind . ' error', '-', '-', '-'];
        } else {
            ++$compiled;
            $e = $p->execution;
            if ($e->error !== null)
                ++$runtime;
            $folds += $p->folds;
            $executed += $e->executed;
            foreach ($p->peephole as $i => $count)
                $peephole[$i] += $count;
            $rows[] = [
                $p->name,
                $e->error === null ? 'ok' : 'runtime error',
                (string) count($p->after),
                (string) $e->executed,
                (string) count($e->output),
            ];
        }
    }
    $out = [
        '== summary ==',
        'programs: ' . count($programs),
        "compiled: $compiled",
        "compile errors: lexical {$errors['lexical']} syntax {$errors['syntax']} semantic {$errors['semantic']}",
        "runtime errors: $runtime",
        "folds: $folds",
        'peephole: ' . array_sum($peephole),
    ];
    foreach (RULES as $i => $rule)
        $out[] = "  $rule {$peephole[$i]}";
    $out[] = "executed: $executed";
    $widths = array_fill(0, 5, 0);
    foreach ($rows as $row)
        foreach ($row as $i => $v)
            $widths[$i] = max($widths[$i], strlen($v));
    foreach ($rows as $row) {
        $fields = [];
        foreach ($row as $i => $v)
            $fields[] = str_pad($v, $widths[$i], ' ', $i < 2 ? STR_PAD_RIGHT : STR_PAD_LEFT);
        $out[] = '  ' . implode('  ', $fields);
    }
    return $out;
}

function main(): void
{
    $programs = $byName = [];
    foreach (file('input/program.src', FILE_IGNORE_NEW_LINES) as $i => $line) {
        if (str_starts_with($line, '#program ')) {
            $p = (object) [
                'name' => substr($line, 9),
                'lines' => [],
                'inputs' => [],
                'error' => null,
                'warnings' => [],
                'folds' => 0,
                'peephole' => array_fill(0, count(RULES), 0),
            ];
            $programs[] = $p;
            $byName[$p->name] = $p;
        } else
            $programs[count($programs) - 1]->lines[] = [$i + 1, $line];
    }
    $current = null;
    foreach (file('input/input.txt', FILE_IGNORE_NEW_LINES) as $line) {
        if (str_starts_with($line, '#input '))
            $current = $byName[substr($line, 7)];
        else
            array_push($current->inputs, ...array_map(intval(...), explode(' ', $line)));
    }
    $reports = array_fill_keys(['listing.txt', 'output.txt', 'diagnostics.txt', 'stats.txt'], []);
    foreach ($programs as $p) {
        compileProgram($p);
        foreach (array_keys($reports) as $name)
            $reports[$name][] = '== program ' . $p->name . ' ==';
        array_push($reports['diagnostics.txt'], ...diagnostics($p));
        if ($p->error !== null) {
            $reports['listing.txt'][] = $reports['stats.txt'][] = 'not compiled';
        } else {
            array_push($reports['listing.txt'], ...listing($p));
            array_push($reports['output.txt'], ...$p->execution->output);
            array_push($reports['stats.txt'], ...statistics($p));
        }
    }
    array_push($reports['stats.txt'], ...summary($programs));
    if (!is_dir('output'))
        mkdir('output');
    foreach ($reports as $name => $lines)
        file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
}

main();
