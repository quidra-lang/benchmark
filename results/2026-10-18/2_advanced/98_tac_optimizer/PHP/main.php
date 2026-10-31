<?php

foreach (['tac_parser', 'cfg', 'dataflow', 'optimizations', 'regalloc'] as $module)
    require_once __DIR__ . "/$module.php";
const PASS_ORDER = ['constprop', 'copyprop', 'cse', 'dce', 'licm', 'unreachable'];

const VERSIONS = ['original', 'optimized', 'allocated'];

function commaList(array $values): string
{
    return $values ? implode(',', $values) : '-';
}

function blockList(array $numbers): string
{
    return commaList(array_map(fn($n) => 'B' . $n, $numbers));
}

function instructionList(array $numbers): string
{
    return commaList(array_map(fn($n) => '#' . $n, $numbers));
}

function reachableInstructions(CFG $g): Generator
{
    foreach ($g->instructions as $n => $i)
        if (isset($g->reachable[$g->blockOf[$n]]))
            yield $n => $i;
}

function reachingNumbers(DataFlow $flow, int $number, string $variable): array
{
    $r = [];
    foreach ($flow->reachingBefore[$number] as [$v, $n])
        if ($v === $variable)
            $r[$n] = true;
    return $r;
}

function constantValue(CFG $g, array $definitions): ?int
{
    if (!$definitions || isset($definitions[0]))
        return null;
    $value = null;
    foreach ($definitions as $n => $_) {
        $i = $g->instructions[$n];
        if ($i->kind !== 'copy' || !is_int($i->a) || $value !== null && $value !== $i->a)
            return null;
        $value = $i->a;
    }
    return $value;
}

function constantPropagation(TacFunction $f, CFG $g, DataFlow $flow): array
{
    $edits = $records = [];
    foreach (reachableInstructions($g) as $n => $original) {
        $i = $original;
        foreach ($original->operandFields() as $field) {
            $v = $original->{$field};
            if (!is_string($v))
                continue;
            $value = constantValue($g, reachingNumbers($flow, $n, $v));
            if ($value !== null) {
                $i = $i->changed([$field => $value]);
                $records[] = "#$n: $v -> $value";
            }
        }
        $result = fold($i);
        if ($result === null) {
            $records[] = "#$n: delete " . instructionString($i);
            $edits[$n] = [];
        } else {
            if ($result !== $i)
                $records[] = "#$n: fold " . instructionString($result);
            $edits[$n] = [$result];
        }
    }
    rewrite($f, $edits);
    return [count($records), $records];
}

function copyPropagation(TacFunction $f, CFG $g, DataFlow $flow): array
{
    $edits = $records = [];
    foreach (reachableInstructions($g) as $n => $original) {
        $i = $original;
        $available = [];
        foreach ($flow->copyBefore[$n] as [$a, $b])
            $available[$a] = $b;
        foreach ($original->operandFields() as $field) {
            $v = $original->{$field};
            if (is_string($v) && isset($available[$v])) {
                $w = $available[$v];
                $i = $i->changed([$field => $w]);
                $records[] = "#$n: $v -> $w";
            }
        }
        $edits[$n] = [$i];
    }
    rewrite($f, $edits);
    return [count($records), $records];
}

function expressionSources(CFG $g, array $expression, int $candidate): array
{
    $b = $g->blockOf[$candidate];
    foreach (array_reverse($g->blocks[$b]->instructions) as $n)
        if ($n < $candidate && $g->instructions[$n]->expression() === $expression)
            return [$n => true];
    $sources = $examined = [];
    $pending = $g->reachablePredecessors[$b];
    while ($pending) {
        $block = array_pop($pending);
        if (isset($examined[$block]))
            continue;
        $examined[$block] = true;
        $found = false;
        foreach (array_reverse($g->blocks[$block]->instructions) as $n)
            if ($g->instructions[$n]->expression() === $expression) {
                $sources[$n] = true;
                $found = true;
                break;
            }
        if (!$found)
            array_push($pending, ...$g->reachablePredecessors[$block]);
    }
    return $sources;
}

function commonSubexpressions(TacFunction $f, CFG $g, DataFlow $flow): array
{
    $candidates = [];
    foreach (reachableInstructions($g) as $n => $i) {
        $e = $i->expression();
        if ($e !== null && isset($flow->expressionBefore[$n][tupleKey($e)])) {
            $key = tupleKey($e);
            if (!isset($candidates[$key]))
                $candidates[$key] = ['expression' => $e, 'numbers' => []];
            $candidates[$key]['numbers'][] = $n;
        }
    }
    $groups = array_values($candidates);
    usort($groups, fn($a, $b) => $a['numbers'][0] <=> $b['numbers'][0]);
    $edits = $records = [];
    $changes = 0;
    foreach ($groups as $group) {
        $e = $group['expression'];
        $numbers = $group['numbers'];
        $sources = [];
        foreach ($numbers as $n)
            $sources += expressionSources($g, $e, $n);
        $sources = array_diff_key($sources, array_fill_keys($numbers, true));
        $sourceNumbers = numberKeys($sources);
        [$temporary, $replacements] = cseReplacements($f, $g, $sourceNumbers, $numbers);
        $edits = array_replace($edits, $replacements);
        $records[] =
            expressionString($e)
            . ": $temporary sources="
            . instructionList($sourceNumbers)
            . ' replaced='
            . instructionList($numbers);
        $changes += count($numbers);
    }
    rewrite($f, $edits);
    return [$changes, $records];
}

function deadCode(TacFunction $f, CFG $g, DataFlow $flow): array
{
    $edits = $records = [];
    foreach (numberKeys($g->reachable) as $b) {
        $state = $flow->liveOut[$b];
        foreach (array_reverse($g->blocks[$b]->instructions) as $n) {
            $i = $g->instructions[$n];
            $dest = $i->destination;
            if (
                $i->kind === 'copy' && $dest === $i->a
                || in_array($i->kind, ['copy', 'bin', 'load'], true) && !isset($state[$dest])
            ) {
                $edits[$n] = [];
                $records[$n] = "#$n: delete " . instructionString($i);
                continue;
            }
            if ($i->kind === 'call' && $dest !== null && !isset($state[$dest])) {
                $records[$n] = "#$n: unused result " . instructionString($i);
                $i = $i->changed(['destination' => null]);
                $edits[$n] = [$i];
            }
            $state = liveTransfer($i, $state);
        }
    }
    rewrite($f, $edits);
    ksort($records, SORT_NUMERIC);
    return [count($records), array_values($records)];
}

function insideDefinitions(CFG $g, NaturalLoop $loop, array $definitions): array
{
    $r = [];
    foreach ($definitions as $n => $_)
        if ($n !== 0 && isset($loop->blocks[$g->blockOf[$n]]))
            $r[$n] = true;
    return $r;
}

function markedInvariants(CFG $g, DataFlow $flow, NaturalLoop $loop, array $numbers): array
{
    $stores = [];
    $calls = false;
    foreach ($numbers as $n) {
        $i = $g->instructions[$n];
        if ($i->kind === 'store')
            $stores[$i->name] = true;
        if ($i->kind === 'call')
            $calls = true;
    }
    $marked = $order = [];
    do {
        $changed = false;
        foreach ($numbers as $n) {
            $i = $g->instructions[$n];
            if (
                isset($marked[$n])
                || !in_array($i->kind, ['copy', 'bin', 'load'], true)
                || $i->kind === 'load' && ($calls || isset($stores[$i->name]))
            )
                continue;
            $invariant = true;
            foreach ($i->usedVariables() as $v) {
                $definitions = reachingNumbers($flow, $n, $v);
                $inside = insideDefinitions($g, $loop, $definitions);
                if ($inside && !(count($definitions) === 1 && !array_diff_key($inside, $marked))) {
                    $invariant = false;
                    break;
                }
            }
            if ($invariant) {
                $marked[$n] = true;
                $order[] = $n;
                $changed = true;
            }
        }
    } while ($changed);
    return $order;
}

function movableInvariants(
    CFG $g,
    DataFlow $flow,
    NaturalLoop $loop,
    array $numbers,
    array $markedOrder,
): array {
    $definitions = [];
    foreach ($numbers as $n)
        if (($v = $g->instructions[$n]->destination) !== null)
            $definitions[$v] = ($definitions[$v] ?? 0) + 1;
    $moved = $order = [];
    foreach ($markedOrder as $n) {
        $i = $g->instructions[$n];
        $dest = $i->destination;
        if ($definitions[$dest] !== 1 || isset($flow->liveIn[$loop->header][$dest]))
            continue;
        $block = $g->blockOf[$n];
        $dominates = true;
        foreach ($loop->exits as $exit => $_)
            if (!isset($g->dominators[$exit][$block]))
                $dominates = false;
        $dangerous =
            $i->kind === 'load'
            || $i->kind === 'bin'
            && in_array($i->operation, ['/', '%'], true)
            && (is_string($i->b) || $i->b === 0);
        $dead = true;
        foreach ($loop->outside as $s => $_)
            if (isset($flow->liveIn[$s][$dest]))
                $dead = false;
        if (!$dominates && ($dangerous || !$dead))
            continue;
        $ready = true;
        foreach ($i->usedVariables() as $v)
            if (array_diff_key(insideDefinitions($g, $loop, reachingNumbers($flow, $n, $v)), $moved))
                $ready = false;
        if ($ready) {
            $moved[$n] = true;
            $order[] = $n;
        }
    }
    return $order;
}

function loopInvariantMotion(TacFunction $f, CFG $g, DataFlow $flow): array
{
    $loops = $g->loops;
    usort($loops, fn($a, $b) => count($a->blocks) <=> count($b->blocks) ?: $a->header <=> $b->header);
    foreach ($loops as $loop) {
        $numbers = [];
        foreach ($loop->blocks as $b => $_)
            array_push($numbers, ...$g->blocks[$b]->instructions);
        sort($numbers, SORT_NUMERIC);
        $moves = movableInvariants($g, $flow, $loop, $numbers, markedInvariants($g, $flow, $loop, $numbers));
        if ($moves) {
            $destination = hoist($f, $g, $loop, $moves);
            return [
                count($moves),
                ['B' . $loop->header . ': hoist ' . instructionList($moves) . ' to ' . $destination],
            ];
        }
    }
    return [0, []];
}

function unreachableCode(TacFunction $f, CFG $g, DataFlow $flow): array
{
    [$blocks, $jumps, $labels] = removeUnreachable($f, $g);
    $records = [
        ...array_map(fn($n) => 'remove block B' . $n, $blocks),
        ...array_map(fn($n) => 'remove jump #' . $n, $jumps),
        ...array_map(fn($l) => 'remove label ' . $l, $labels),
    ];
    return [count($records), $records];
}

function optimizeFunction(TacFunction $f, array $enabled, int $maximum, array &$totals): array
{
    $before = count($f->instructions());
    $out = ['== ' . $f->name . ' =='];
    $passes = [
        'constprop' => constantPropagation(...),
        'copyprop' => copyPropagation(...),
        'cse' => commonSubexpressions(...),
        'dce' => deadCode(...),
        'licm' => loopInvariantMotion(...),
        'unreachable' => unreachableCode(...),
    ];
    for ($round = 1; $round <= $maximum; ++$round) {
        $counts = $records = [];
        $changed = false;
        foreach ($enabled as $name) {
            $g = new CFG($f);
            $flow = new DataFlow($g);
            [$count, $lines] = $passes[$name]($f, $g, $flow);
            $totals[$name] += $count;
            $counts[] = "$name=$count";
            if ($count)
                $changed = true;
            foreach ($lines as $line)
                $records[] = "  $name $line";
        }
        $out[] = "round $round: " . implode(' ', $counts);
        array_push($out, ...$records);
        if (!$changed)
            break;
    }
    $out[] = "result: rounds=$round instructions=$before->" . count($f->instructions());
    return $out;
}

function callGraph(TacProgram $program): array
{
    $names = array_column($program->functions, 'name');
    $callees = [];
    foreach ($program->functions as $f) {
        $called = [];
        foreach ($f->instructions() as $i)
            if ($i->kind === 'call')
                $called[$i->name] = true;
        $callees[$f->name] = array_values(array_filter($names, fn($n) => isset($called[$n])));
    }
    $reachable = function (array $starts) use ($callees): array {
        $seen = [];
        $pending = $starts;
        while ($pending) {
            $name = array_pop($pending);
            if (!isset($seen[$name])) {
                $seen[$name] = true;
                array_push($pending, ...$callees[$name]);
            }
        }
        return $seen;
    };
    $recursive = [];
    foreach ($names as $name)
        if (isset($reachable($callees[$name])[$name]))
            $recursive[$name] = true;
    return [$callees, $reachable(['main']), $recursive];
}

function callGraphLines(TacProgram $p, string $heading): array
{
    [$callees, $reachable, $recursive] = callGraph($p);
    $out = ["== call graph ($heading) =="];
    $unreachable = [];
    foreach ($p->functions as $f) {
        $out[] =
            $f->name
            . ' -> '
            . commaList($callees[$f->name])
            . (isset($recursive[$f->name]) ? ' (recursive)' : '');
        if (!isset($reachable[$f->name]))
            $unreachable[] = $f->name;
    }
    $out[] = 'unreachable functions: ' . commaList($unreachable);
    return [$out, $reachable];
}

function definitionList(array $definitions): string
{
    $values = array_values($definitions);
    usort($values, fn($a, $b) => $a[1] <=> $b[1] ?: strcmp($a[0], $b[0]));
    return commaList(array_map(fn($v) => $v[0] . ':' . $v[1], $values));
}

function functionAnalysis(TacFunction $f, string $heading): array
{
    $g = new CFG($f);
    $flow = new DataFlow($g);
    $out = ["== {$f->name} ($heading) ==", 'code:'];
    $number = 0;
    foreach ($f->code as $line) {
        if (is_string($line)) {
            $out[] = $line . ':';
            continue;
        }
        ++$number;
        $text = "  #$number " . instructionString($line);
        if (isset($g->reachable[$g->blockOf[$number]])) {
            $variables = array_values(array_unique($line->usedVariables()));
            if ($variables) {
                $chains = [];
                foreach ($variables as $v)
                    $chains[] = $v . ':' . commaList(numberKeys(reachingNumbers($flow, $number, $v)));
                $text .= ' | ' . implode(' ', $chains);
            }
        }
        $out[] = $text;
    }
    $out[] = 'blocks: ' . count($g->blocks);
    foreach ($g->blocks as $n => $b)
        $out[] =
            "B$n "
            . $b->instructions[0]
            . '-'
            . $b->instructions[count($b->instructions) - 1]
            . ' labels='
            . commaList($b->labels)
            . ' preds='
            . blockList($b->predecessors)
            . ' succs='
            . blockList($b->successors);
    $out[] = 'unreachable: ' . blockList(numberKeys(array_diff_key($g->blocks, $g->reachable)));
    $out[] = 'order: ' . blockList($g->reversePostorder);
    $out[] = 'dominators:';
    foreach (numberKeys($g->reachable) as $n)
        $out[] =
            "B$n idom="
            . ($g->immediate[$n] === null ? '-' : 'B' . $g->immediate[$n])
            . ' dom='
            . blockList(numberKeys($g->dominators[$n]));
    $out[] = 'dominator tree:';
    $pending = [[1, 0]];
    while ($pending) {
        [$n, $depth] = array_pop($pending);
        $out[] = str_repeat('  ', $depth) . 'B' . $n;
        $children = [];
        foreach ($g->immediate as $child => $parent)
            if ($parent === $n)
                $children[] = $child;
        sort($children, SORT_NUMERIC);
        foreach (array_reverse($children) as $child)
            $pending[] = [$child, $depth + 1];
    }
    $out[] = 'loops: ' . count($g->loops);
    foreach ($g->loops as $loop)
        $out[] =
            'header=B'
            . $loop->header
            . ' latches='
            . blockList($loop->latches)
            . ' depth='
            . $loop->depth
            . ' blocks='
            . blockList(numberKeys($loop->blocks))
            . ' exits='
            . blockList(numberKeys($loop->exits));
    $analyses = [
        ['reaching definitions', 'reaching', $flow->reachingIn, $flow->reachingOut, definitionList(...)],
        [
            'liveness',
            'liveness',
            $flow->liveIn,
            $flow->liveOut,
            static function ($set) {
                $v = array_keys($set);
                sort($v, SORT_STRING);
                return commaList($v);
            },
        ],
        [
            'available expressions',
            'expressions',
            $flow->expressionIn,
            $flow->expressionOut,
            static function ($set) {
                $v = array_map(expressionString(...), array_values($set));
                sort($v, SORT_STRING);
                return commaList($v);
            },
        ],
    ];
    foreach ($analyses as [$title, $key, $incoming, $outgoing, $render]) {
        $out[] = "$title: iterations={$flow->iterations[$key]}";
        foreach (numberKeys($g->reachable) as $n)
            $out[] = "B$n in=" . $render($incoming[$n]) . ' out=' . $render($outgoing[$n]);
    }
    return $out;
}

function rewriteRegisters(TacFunction $f, array $colors): array
{
    $names = [];
    foreach ($colors as $v => $color)
        if ($color !== null)
            $names[$v] = 'R' . $color;
    $code = [];
    $moves = 0;
    foreach ($f->code as $line) {
        if (is_string($line)) {
            $code[] = $line;
            continue;
        }
        $fields = [];
        if ($line->destination !== null)
            $fields['destination'] = $names[$line->destination] ?? $line->destination;
        foreach ($line->operandFields() as $field) {
            $value = $line->{$field};
            $fields[$field] = is_string($value) ? $names[$value] ?? $value : $value;
        }
        $i = $line->changed($fields);
        if ($i->kind === 'copy' && $i->destination === $i->a)
            ++$moves;
        else
            $code[] = $i;
    }
    return [new TacFunction($f->name, array_map(fn($p) => $names[$p] ?? $p, $f->parameters), $code), $moves];
}

function allocationReport(TacFunction $f, int $registers): array
{
    $g = new CFG($f);
    $flow = new DataFlow($g);
    $a = new Allocation($f, $g, $flow, $registers);
    [$allocated, $moves] = rewriteRegisters($f, $a->colors);
    $nodes = array_keys($a->neighbors);
    $edges = intdiv(array_sum(array_map(count(...), $a->neighbors)), 2);
    $out = ['== ' . $f->name . ' ==', 'nodes=' . count($nodes) . " edges=$edges registers=$registers"];
    foreach ($nodes as $v) {
        $neighbors = array_keys($a->neighbors[$v]);
        sort($neighbors, SORT_STRING);
        $out[] =
            "$v degree="
            . count($neighbors)
            . ' cost='
            . $a->costs[$v]
            . ' neighbors='
            . commaList($neighbors);
    }
    $out[] = 'simplify: ' . commaList($a->order);
    $out[] =
        'potential spills: '
        . commaList(array_map(fn($x) => $x[0] . '(' . $a->costs[$x[0]] . '/' . $x[1] . ')', $a->potential));
    foreach ($nodes as $v)
        $out[] = $v . ' -> ' . ($a->colors[$v] === null ? 'spill' : 'R' . $a->colors[$v]);
    $pressure = 0;
    foreach ([$flow->liveBefore, $flow->liveAfter] as $states)
        foreach ($states as $s)
            $pressure = max($pressure, count($s));
    $used = [];
    foreach ($a->colors as $color)
        if ($color !== null)
            $used[$color] = true;
    $spillUses = $spillDefs = 0;
    foreach ($f->instructions() as $i) {
        foreach ($i->usedVariables() as $v)
            if (isset($a->spills[$v]))
                ++$spillUses;
        if ($i->destination !== null && isset($a->spills[$i->destination]))
            ++$spillDefs;
    }
    foreach ($f->parameters as $p)
        if (isset($a->spills[$p]))
            ++$spillDefs;
    $out[] =
        "summary: pressure=$pressure used="
        . count($used)
        . ' spilled='
        . count($a->spills)
        . " moves=$moves spill_uses=$spillUses spill_defs=$spillDefs";
    array_push($out, ...functionLines($allocated));
    return [$allocated, $out];
}

final class Interpreter
{
    private array $functions = [], $arrays = [];
    private int $inputPosition = 0;
    public array $output = [], $steps = [], $calls = [], $kinds = [];

    public function __construct(
        TacProgram $program,
        private array $inputs,
    ) {
        foreach ($program->functions as $f) {
            $labels = $instructions = [];
            foreach ($f->code as $line) {
                if (is_string($line))
                    $labels[$line] = count($instructions);
                else
                    $instructions[] = $line;
            }
            $this->functions[$f->name] = [$f->parameters, $instructions, $labels];
        }
        foreach ($program->arrays as [$name, $size])
            $this->arrays[$name] = array_fill(0, $size, 0);
    }

    private function value(int|string|null $operand, array $variables): ?int
    {
        return is_string($operand) ? $variables[$operand] : $operand;
    }

    private function call(string $name, array $arguments): ?int
    {
        [$parameters, $instructions, $labels] = $this->functions[$name];
        $variables = [];
        foreach ($parameters as $i => $p)
            $variables[$p] = $arguments[$i];
        $pushed = [];
        $position = 0;
        $this->calls[$name] = ($this->calls[$name] ?? 0) + 1;
        while (true) {
            $i = $instructions[$position++];
            $this->steps[$name] = ($this->steps[$name] ?? 0) + 1;
            $this->kinds[$i->kind] = ($this->kinds[$i->kind] ?? 0) + 1;
            switch ($i->kind) {
                case 'copy':
                    $variables[$i->destination] = $this->value($i->a, $variables);
                    break;
                case 'bin':
                    $a = $this->value($i->a, $variables);
                    $b = $this->value($i->b, $variables);
                    $variables[$i->destination] = calculate($i->operation, $a, $b);
                    break;
                case 'load':
                    $index = $this->value($i->a, $variables);
                    $variables[$i->destination] = $this->arrays[$i->name][$index];
                    break;
                case 'store':
                    $index = $this->value($i->a, $variables);
                    $value = $this->value($i->b, $variables);
                    $this->arrays[$i->name][$index] = $value;
                    break;
                case 'goto':
                    $position = $labels[$i->name];
                    break;
                case 'if':
                    $a = $this->value($i->a, $variables);
                    $b = $this->value($i->b, $variables);
                    if (calculate($i->operation, $a, $b) !== 0)
                        $position = $labels[$i->name];
                    break;
                case 'param':
                    $pushed[] = $this->value($i->a, $variables);
                    break;
                case 'call':
                    $args = $i->count ? array_splice($pushed, -$i->count) : [];
                    $result = $this->call($i->name, $args);
                    if ($i->destination !== null)
                        $variables[$i->destination] = $result;
                    break;
                case 'return':
                    return $this->value($i->a, $variables);
                case 'read':
                    $variables[$i->destination] = $this->inputs[$this->inputPosition++];
                    break;
                case 'print':
                    $this->output[] = $this->value($i->a, $variables);
                    break;
            }
        }
    }

    public function run(): void
    {
        $this->call('main', []);
    }
}

function staticKinds(TacProgram $p): array
{
    $counts = array_fill_keys(KINDS, 0);
    foreach ($p->functions as $f)
        foreach ($f->instructions() as $i)
            ++$counts[$i->kind];
    return $counts;
}

function addCounts(array &$total, array $counts): void
{
    foreach ($counts as $key => $value)
        $total[$key] = ($total[$key] ?? 0) + $value;
}

function comparisonReport(
    TacProgram $original,
    TacProgram $optimized,
    TacProgram $allocated,
    array $runs,
): array {
    $programs = ['original' => $original, 'optimized' => $optimized, 'allocated' => $allocated];
    $profiles = $dynamic = [];
    $totalSteps = array_fill_keys(VERSIONS, 0);
    foreach (VERSIONS as $v)
        $profiles[$v] = $dynamic[$v] = [];
    $originalCalls = [];
    $out = [];
    $same = 0;
    foreach ($runs as $run => $inputs) {
        $out[] = 'run ' . ($run + 1) . ': inputs=' . count($inputs);
        $outputs = [];
        foreach ($programs as $version => $program) {
            $interpreter = new Interpreter($program, $inputs);
            $interpreter->run();
            $steps = array_sum($interpreter->steps);
            $calls = array_sum($interpreter->calls);
            $out[] = "  $version: steps=$steps calls=$calls output=" . commaList($interpreter->output);
            addCounts($profiles[$version], $interpreter->steps);
            addCounts($dynamic[$version], $interpreter->kinds);
            $totalSteps[$version] += $steps;
            if ($version === 'original')
                addCounts($originalCalls, $interpreter->calls);
            $outputs[] = $interpreter->output;
        }
        $equal = $outputs[0] === $outputs[1] && $outputs[1] === $outputs[2];
        if ($equal)
            ++$same;
        $out[] = '  result: ' . ($equal ? 'same' : 'different');
    }
    $out[] = '== profile ==';
    foreach ($original->functions as $f) {
        $name = $f->name;
        $out[] =
            "$name: calls="
            . ($originalCalls[$name] ?? 0)
            . ' original='
            . ($profiles['original'][$name] ?? 0)
            . ' optimized='
            . ($profiles['optimized'][$name] ?? 0)
            . ' allocated='
            . ($profiles['allocated'][$name] ?? 0);
    }
    $before = staticKinds($original);
    $after = staticKinds($optimized);
    array_push(
        $out,
        '== summary ==',
        'runs=' . count($runs) . " same=$same different=" . (count($runs) - $same),
        'instructions: original=' . array_sum($before) . ' optimized=' . array_sum($after),
    );
    $parts = [];
    foreach (KINDS as $kind)
        $parts[] = "$kind={$before[$kind]}->{$after[$kind]}";
    $out[] = 'kinds: ' . implode(' ', $parts);
    $parts = [];
    foreach (VERSIONS as $v)
        $parts[] = "$v={$totalSteps[$v]}";
    $out[] = 'steps: ' . implode(' ', $parts);
    foreach (VERSIONS as $v) {
        $parts = [];
        foreach (KINDS as $kind)
            $parts[] = "$kind=" . ($dynamic[$v][$kind] ?? 0);
        $out[] = "dynamic $v: " . implode(' ', $parts);
    }
    return $out;
}

function main(): void
{
    $settings = file('input/params.txt', FILE_IGNORE_NEW_LINES);
    $registers = (int) explode(' ', $settings[0])[1];
    $requested = array_fill_keys(array_slice(explode(' ', $settings[1]), 1), true);
    $enabled = array_values(array_filter(PASS_ORDER, fn($p) => isset($requested[$p])));
    $maximum = (int) explode(' ', $settings[2])[1];
    $input = file('input/input.txt', FILE_IGNORE_NEW_LINES);
    $runs = [];
    foreach (array_slice($input, 1, (int) $input[0]) as $line) {
        $v = array_map(intval(...), explode(' ', $line));
        $runs[] = array_slice($v, 1, $v[0]);
    }
    $original = readProgram();
    [$analysis] = callGraphLines($original, 'original');
    foreach ($original->functions as $f)
        array_push($analysis, ...functionAnalysis($f, 'original'));
    $working = new TacProgram($original->arrays, array_map(fn($f) => $f->copy(), $original->functions));
    $passLines = [];
    $totals = array_fill_keys($enabled, 0);
    foreach ($working->functions as $f)
        array_push($passLines, ...optimizeFunction($f, $enabled, $maximum, $totals));
    [$graphLines, $reachable] = callGraphLines($working, 'optimized');
    array_push($analysis, ...$graphLines);
    $removed = [];
    foreach ($working->functions as $f)
        if (isset($requested['unreachable']) && !isset($reachable[$f->name]))
            $removed[] = $f->name;
    $optimized = new TacProgram(
        $working->arrays,
        array_values(array_filter($working->functions, fn($f) => !in_array($f->name, $removed, true))),
    );
    array_push($passLines, '== program ==', 'removed functions: ' . commaList($removed), '== total ==');
    $parts = [];
    foreach ($enabled as $p)
        $parts[] = "$p={$totals[$p]}";
    $passLines[] = implode(' ', $parts);
    $allocatedFunctions = $allocationLines = [];
    foreach ($optimized->functions as $f) {
        array_push($analysis, ...functionAnalysis($f, 'optimized'));
        [$allocated, $lines] = allocationReport($f, $registers);
        $allocatedFunctions[] = $allocated;
        array_push($allocationLines, ...$lines);
    }
    $allocated = new TacProgram($optimized->arrays, $allocatedFunctions);
    $reports = [
        'optimized.tac' => programLines($optimized),
        'analysis.txt' => $analysis,
        'passes.txt' => $passLines,
        'regalloc.txt' => $allocationLines,
        'comparison.txt' => comparisonReport($original, $optimized, $allocated, $runs),
    ];
    if (!is_dir('output'))
        mkdir('output');
    foreach ($reports as $name => $lines)
        file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
}

main();
