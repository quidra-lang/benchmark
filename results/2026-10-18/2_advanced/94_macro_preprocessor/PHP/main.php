<?php

foreach (['lexer', 'definitions', 'expression', 'expander', 'include_manager'] as $module)
    require_once __DIR__ . "/$module.php";
const CONDITIONALS = ['if', 'ifdef', 'ifndef', 'elif', 'elifdef', 'elifndef', 'else', 'endif'];

final class DirectiveError extends RuntimeException {}

final readonly class Header
{
    public function __construct(
        public string $rendering,
        public string $name,
        public bool $quoted,
    ) {}
}

final class Inclusion
{
    public string $displayFile;
    public int $offset = 0;
    public array $stack = [], $segment = [];

    public function __construct(
        public SourceFile $source,
        public int $depth,
    ) {
        $this->displayFile = $source->path;
    }

    public function position(int $physical): array
    {
        return [$this->displayFile, $physical + $this->offset];
    }

    public function skipping(): bool
    {
        return $this->stack && !$this->stack[count($this->stack) - 1]->active;
    }
}

function separatorNeeded(string $left, string $right): bool
{
    if ($left === '/' && str_contains('/*', $right[0]))
        return true;
    [, , $end] = readToken($left . $right);
    return $end !== strlen($left);
}

function outputRender(array $tokens): string
{
    $out = '';
    $previous = null;
    foreach ($tokens as $t) {
        if ($previous !== null && ($t->space || separatorNeeded($previous, $t->spelling)))
            $out .= ' ';
        $out .= $t->spelling;
        $previous = $t->spelling;
    }
    return $out;
}

function following(string $heading, array $items): string
{
    return $heading . ($items ? ' ' . implode(' ', $items) : '');
}

function headerSpecification(array $tokens, int $i = 0): array
{
    if (!isset($tokens[$i]))
        return [null, $i];
    $t = $tokens[$i];
    if ($t->kind === 'string' || $t->kind === 'header')
        return [new Header($t->spelling, substr($t->spelling, 1, -1), $t->spelling[0] === '"'), $i + 1];
    if ($t->spelling === '<') {
        $close = $i + 1;
        while (isset($tokens[$close]) && $tokens[$close]->spelling !== '>')
            ++$close;
        if (!isset($tokens[$close]))
            throw new DirectiveError('missing terminating > character');
        $text = '<' . render(array_slice($tokens, $i + 1, $close - $i - 1)) . '>';
        return [new Header($text, substr($text, 1, -1), false), $close + 1];
    }
    return [null, $i];
}

function decimalToken(PPToken $t): bool
{
    return $t->kind === 'number' && ctype_digit($t->spelling);
}

final class Preprocessor
{
    private array
        $macros = [],
        $everDefined = [],
        $saved = [],
        $poisoned = [],
        $output = [],
        $history = [],
        $diagnostics = [],
        $tree = ['main.c'],
        $conditionalRecords = [],
        $regions = []
    ;
    private array
        $diagnosticCounts = ['error' => 0, 'warning' => 0],
        $conditionCounts = [
            'taken' => 0,
            'not_taken' => 0,
            'skipped' => 0,
            'not_evaluated' => 0,
            'endif' => 0,
        ]
    ;
    private ?array $previous = null;
    private IncludeManager $manager;
    private Expander $expander;

    public function __construct()
    {
        $this->manager = new IncludeManager();
        $this->expander = new Expander($this->macros, $this->diagnostic(...));
    }

    private function diagnostic(array $p, string $kind, string $message): void
    {
        $this->diagnostics[] = $p[0] . ':' . $p[1] . ": $kind: $message";
        ++$this->diagnosticCounts[$kind];
    }

    private function event(array $p, string $text): void
    {
        $this->history[] = $p[0] . ':' . $p[1] . ': ' . $text;
    }

    private function poisonCheck(Inclusion $c, array $tokens): void
    {
        foreach ($tokens as $t)
            if ($t->kind === 'identifier' && isset($this->poisoned[$t->spelling]))
                $this->diagnostic(
                    $c->position($t->line),
                    'error',
                    'attempt to use poisoned "' . $t->spelling . '"',
                );
    }

    private function unusedCheck(Macro $m): void
    {
        if ($m->mainFile && $m->expanded === 0 && $m->tested === 0)
            $this->diagnostic($m->position, 'warning', 'macro "' . $m->name . '" is not used');
    }

    private function defineMacro(array $tokens, array $p, bool $main): void
    {
        try {
            $m = parseDefinition($tokens, $p, $main);
        } catch (DefinitionError $e) {
            $this->diagnostic($p, 'error', $e->getMessage());
            return;
        }
        $previous = $this->macros[$m->name] ?? null;
        if ($previous === null) {
            $this->macros[$m->name] = $m;
            $this->everDefined[$m->name] = true;
            $op = 'define';
        } elseif ($previous->identical($m))
            $op = 'identical';
        else {
            $this->unusedCheck($previous);
            $this->diagnostic(
                $p,
                'warning',
                '"'
                . $m->name
                . '" redefined (previous definition at '
                . $previous->position[0]
                . ':'
                . $previous->position[1]
                . ')',
            );
            $this->macros[$m->name] = $m;
            $this->everDefined[$m->name] = true;
            $op = 'redefine';
        }
        $this->event($p, $op . ' ' . $m->signature());
    }

    private function undefine(array $tokens, array $p): void
    {
        $error = checkName($tokens, 'undef');
        if ($error !== null) {
            $this->diagnostic($p, 'error', $error);
            return;
        }
        if (count($tokens) >= 2)
            $this->diagnostic($p, 'warning', 'extra tokens at end of #undef directive');
        $name = $tokens[0]->spelling;
        if (isset($this->macros[$name])) {
            $this->unusedCheck($this->macros[$name]);
            unset($this->macros[$name]);
            $this->event($p, 'undef ' . $name);
        } else
            $this->event($p, 'undef ' . $name . ' (not defined)');
    }

    private function processDefines(): void
    {
        foreach (file('input/defines.txt', FILE_IGNORE_NEW_LINES) as $i => $line) {
            if ($line === '')
                continue;
            $equal = strpos($line, '=');
            $text = $equal === false
                ? $line . ' 1'
                : substr($line, 0, $equal) . ' ' . substr($line, $equal + 1);
            $this->defineMacro(lexDefinition($text, $i + 1), ['defines.txt', $i + 1], false);
        }
    }

    private function marker(string $file, int $line, ?int $flag = null): void
    {
        $this->output[] = '# ' . $line . ' "' . $file . '"' . ($flag === null ? '' : ' ' . $flag);
        $this->previous = [$file, $line - 1];
    }

    private function outputLine(Inclusion $c, int $physical, string $text): void
    {
        [$file, $line] = $c->position($physical);
        [$oldFile, $oldLine] = $this->previous;
        if ($file === $oldFile && $oldLine < $line && $line <= ($oldLine + 8))
            array_push($this->output, ...array_fill(0, $line - $oldLine - 1, ''));
        else
            $this->marker($file, $line);
        $this->output[] = $text;
        $this->previous = [$file, $line];
        ++$c->source->outputLines;
    }

    private function flush(Inclusion $c): void
    {
        $segment = $c->segment;
        $c->segment = [];
        if (!$segment)
            return;
        $this->poisonCheck($c, $segment);
        $expanded = $this->expander->expand($segment, $c);
        $group = [];
        $physical = null;
        foreach ($expanded as $t) {
            if ($physical !== null && $physical !== $t->line) {
                $this->outputLine($c, $physical, outputRender($group));
                $group = [];
            }
            $physical = $t->line;
            $group[] = $t;
        }
        if ($group)
            $this->outputLine($c, $physical, outputRender($group));
    }

    private function macroDefined(string $name): bool
    {
        if (isset($this->macros[$name])) {
            ++$this->macros[$name]->tested;
            return true;
        }
        return in_array($name, BUILTINS, true) || $name === '__has_include';
    }

    private function replaceOperators(Inclusion $c, array $operands): array
    {
        $out = [];
        $i = 0;
        while ($i < count($operands)) {
            $t = $operands[$i];
            if ($t->kind === 'identifier' && $t->spelling === 'defined') {
                $index = $i + 1;
                $parenthesized = isset($operands[$index]) && $operands[$index]->spelling === '(';
                if ($parenthesized)
                    ++$index;
                if (!isset($operands[$index]) || $operands[$index]->kind !== 'identifier')
                    throw new DirectiveError('operator "defined" requires an identifier');
                $name = $operands[$index++]->spelling;
                if ($parenthesized) {
                    if (!isset($operands[$index]) || $operands[$index]->spelling !== ')')
                        throw new DirectiveError('missing \')\' after "defined"');
                    ++$index;
                }
                $value = $this->macroDefined($name);
            } elseif ($t->kind === 'identifier' && $t->spelling === '__has_include') {
                $index = $i + 1;
                if (!isset($operands[$index]) || $operands[$index]->spelling !== '(')
                    throw new DirectiveError('missing \'(\' after "__has_include"');
                [$header, $index] = headerSpecification($operands, $index + 1);
                if ($header === null || $header->name === '')
                    throw new DirectiveError('operator "__has_include" requires a header-name');
                if (!isset($operands[$index]) || $operands[$index]->spelling !== ')')
                    throw new DirectiveError('missing \')\' after "__has_include" operand');
                ++$index;
                $value = $this->manager->search($header->name, $header->quoted) !== null;
            } else {
                $out[] = $t;
                ++$i;
                continue;
            }
            $out[] = new PPToken('number', (string) (int) $value, $t->line, $t->space);
            $i = $index;
        }
        return $out;
    }

    private function test(Inclusion $c, LogicalLine $logical, string $name, array $operands): array
    {
        $p = $c->position($logical->tokens[0]->line);
        $this->poisonCheck($c, $operands);
        if ($name !== 'if' && $name !== 'elif') {
            if (!$operands) {
                $this->diagnostic($p, 'error', "no macro name given in #$name directive");
                return [null, null];
            }
            if ($operands[0]->kind !== 'identifier') {
                $this->diagnostic($p, 'error', 'macro names must be identifiers');
                return [null, null];
            }
            if (count($operands) >= 2)
                $this->diagnostic($p, 'warning', "extra tokens at end of #$name directive");
            $value = $this->macroDefined($operands[0]->spelling);
            return [(int) (in_array($name, ['ifndef', 'elifndef'], true) ? !$value : $value), null];
        }
        try {
            $replaced = $this->replaceOperators($c, $operands);
        } catch (DirectiveError $e) {
            $this->diagnostic($p, 'error', $e->getMessage());
            return [null, null];
        }
        $expanded = $this->expander->expand($replaced, $c);
        try {
            $tree = new ExpressionParser($expanded)->parse($name);
            $value = evaluateExpression($tree, fn($message) => $this->diagnostic($p, 'warning', $message));
        } catch (ExpressionError $e) {
            $this->diagnostic($p, 'error', $e->getMessage());
            return [null, $expanded];
        }
        return [$value, $expanded];
    }

    private function testDescription(string $name, ?int $value, ?array $expanded): string
    {
        $s = $value === null ? 'not taken (error)' : ($value !== 0 ? 'taken' : 'not taken');
        if ($value !== null && ($name === 'if' || $name === 'elif'))
            $s .= ' (value ' . $value . ')';
        if ($expanded !== null)
            $s .= ' [' . outputRender($expanded) . ']';
        return $s;
    }

    private function closeRegion(Inclusion $c, object $block, int $end): void
    {
        $start = $block->skipStart;
        if ($start !== null && $end >= $start) {
            [$file, $first] = $c->position($start);
            [, $last] = $c->position($end);
            $count = $end - $start + 1;
            $this->regions[] = "$file:$first-$last lines=$count";
            $c->source->skippedLines += $count;
        }
        $block->skipStart = null;
    }

    private function conditionalRecord(
        array $p,
        int $depth,
        string $name,
        array $operands,
        string $description,
    ): void {
        $directive = '#' . $name . ($operands ? ' ' . render($operands) : '');
        $this->conditionalRecords[] =
            $p[0] . ':' . $p[1] . ': ' . str_repeat('  ', $depth) . $directive . ' => ' . $description;
        foreach ([
            'taken' => 'taken',
            'not taken' => 'not_taken',
            'skipped' => 'skipped',
            'not evaluated' => 'not_evaluated',
            'closes' => 'endif',
        ] as $prefix => $category)
            if (str_starts_with($description, $prefix)) {
                ++$this->conditionCounts[$category];
                break;
            }
    }

    private function conditional(Inclusion $c, LogicalLine $l, string $name, array $operands): void
    {
        $p = $c->position($l->tokens[0]->line);
        if (in_array($name, STARTS, true)) {
            $parent = !$c->stack || $c->stack[count($c->stack) - 1]->active;
            $b = (object) [
                'kind' => $name,
                'position' => $p,
                'parent' => $parent,
                'chosen' => false,
                'active' => false,
                'elseSeen' => false,
                'skipStart' => null,
            ];
            if ($parent) {
                [$value, $expanded] = $this->test($c, $l, $name, $operands);
                if ($value !== null && $value !== 0)
                    $b->chosen = $b->active = true;
                else
                    $b->skipStart = $l->end + 1;
                $description = $this->testDescription($name, $value, $expanded);
            } else
                $description = 'skipped';
            $this->conditionalRecord($p, count($c->stack), $name, $operands, $description);
            $c->stack[] = $b;
            return;
        }
        if (!$c->stack) {
            $this->diagnostic($p, 'error', "#$name without #if");
            return;
        }
        $depth = count($c->stack) - 1;
        $b = $c->stack[$depth];
        $this->closeRegion($c, $b, $l->start - 1);
        if ($name === 'endif') {
            array_pop($c->stack);
            if ($b->parent && $operands)
                $this->diagnostic($p, 'warning', 'extra tokens at end of #endif directive');
            $description = 'closes #' . $b->kind . ' at line ' . $b->position[1];
        } else {
            if ($b->elseSeen)
                $this->diagnostic($p, 'error', "#$name after #else");
            if ($name === 'else') {
                if ($b->parent && $operands)
                    $this->diagnostic($p, 'warning', 'extra tokens at end of #else directive');
                $b->elseSeen = true;
                if ($b->parent) {
                    $b->active = !$b->chosen;
                    $b->chosen = true;
                    $description = $b->active ? 'taken' : 'not taken';
                } else {
                    $b->active = false;
                    $description = 'skipped';
                }
            } elseif (!$b->parent) {
                $b->active = false;
                $description = 'skipped';
            } elseif ($b->chosen) {
                $b->active = false;
                $description = 'not evaluated';
            } else {
                [$value, $expanded] = $this->test($c, $l, $name, $operands);
                $b->active = $value !== null && $value !== 0;
                if ($b->active)
                    $b->chosen = true;
                $description = $this->testDescription($name, $value, $expanded);
            }
            if ($b->parent && !$b->active)
                $b->skipStart = $l->end + 1;
        }
        $this->conditionalRecord($p, $depth, $name, $operands, $description);
    }

    private function includeFile(Inclusion $c, LogicalLine $l, array $operands): void
    {
        $p = $c->position($l->tokens[0]->line);
        try {
            $sequence = $operands;
            [$header, $consumed] = headerSpecification($sequence);
            if ($header === null && $sequence) {
                $sequence = $this->expander->expand($sequence, $c);
                [$header, $consumed] = headerSpecification($sequence);
            }
            if ($header === null)
                throw new DirectiveError('#include expects "FILENAME" or <FILENAME>');
            if ($consumed < count($sequence))
                $this->diagnostic($p, 'warning', 'extra tokens at end of #include directive');
            if ($header->name === '')
                throw new DirectiveError('empty filename in #include');
        } catch (DirectiveError $e) {
            $this->diagnostic($p, 'error', $e->getMessage());
            return;
        }
        $prefix = str_repeat('  ', $c->depth + 1) . $l->tokens[0]->line . ': ';
        $path = $this->manager->search($header->name, $header->quoted);
        if ($path === null) {
            $this->tree[] = $prefix . $header->rendering . ' [not found]';
            $this->diagnostic($p, 'error', 'cannot find include file ' . $header->rendering);
            return;
        }
        $previous = $this->manager->files[$path] ?? null;
        if ($previous !== null && $previous->once) {
            $this->tree[] = $prefix . $path . ' [skipped: pragma once]';
            ++$previous->skipped;
            return;
        }
        if ($previous !== null && $previous->guard !== null && isset($this->macros[$previous->guard])) {
            $this->tree[] = $prefix . $path . ' [skipped: guard ' . $previous->guard . ']';
            ++$previous->skipped;
            return;
        }
        if (($c->depth + 1) > 8) {
            $this->tree[] = $prefix . $path . ' [too deep]';
            $this->diagnostic($p, 'error', '#include nested too deeply');
            return;
        }
        $this->tree[] = $prefix . $path;
        $this->marker($path, 1, 1);
        $this->processFile($path, $c->depth + 1);
        [$file, $line] = $c->position($l->end + 1);
        $this->marker($file, $line, 2);
    }

    private function lineDirective(Inclusion $c, LogicalLine $l, array $operands): void
    {
        $p = $c->position($l->tokens[0]->line);
        if (!$operands || !decimalToken($operands[0]))
            $operands = $this->expander->expand($operands, $c);
        if (
            !in_array(count($operands), [1, 2], true)
            || !decimalToken($operands[0])
            || count($operands) === 2 && $operands[1]->kind !== 'string'
        ) {
            $this->diagnostic($p, 'error', 'invalid #line directive');
            return;
        }
        $line = (int) $operands[0]->spelling;
        if ($line < 1 || $line > 2147483647) {
            $this->diagnostic($p, 'error', 'line number out of range');
            return;
        }
        $c->offset = $line - ($l->end + 1);
        if (count($operands) === 2)
            $c->displayFile = substr($operands[1]->spelling, 1, -1);
    }

    private function macroPragma(array $p, array $operands, string $op): void
    {
        if (
            count($operands) !== 4
            || $operands[1]->spelling !== '('
            || $operands[2]->kind !== 'string'
            || $operands[3]->spelling !== ')'
        ) {
            $this->diagnostic($p, 'error', "invalid #pragma $op directive");
            return;
        }
        $name = substr($operands[2]->spelling, 1, -1);
        if ($op === 'push_macro') {
            $this->saved[$name][] = $this->macros[$name] ?? null;
            $this->event($p, 'push ' . $name);
        } elseif (empty($this->saved[$name]))
            $this->diagnostic($p, 'warning', 'no matching push_macro for "' . $name . '"');
        else {
            $macro = array_pop($this->saved[$name]);
            if ($macro === null) {
                unset($this->macros[$name]);
                $this->event($p, 'pop ' . $name . ' (undefined)');
            } else {
                $this->macros[$name] = $macro;
                $this->event($p, 'pop ' . $name);
            }
        }
    }

    private function pragma(Inclusion $c, LogicalLine $l, array $operands): void
    {
        $p = $c->position($l->tokens[0]->line);
        $name = isset($operands[0]) && $operands[0]->kind === 'identifier' ? $operands[0]->spelling : null;
        if ($name === 'once') {
            if (count($operands) >= 2)
                $this->diagnostic($p, 'warning', 'extra tokens at end of #pragma once directive');
            if ($c->depth === 0)
                $this->diagnostic($p, 'warning', '#pragma once in main file');
            $c->source->once = true;
        } elseif (
            count($operands) >= 2
            && $operands[0]->spelling === 'GCC'
            && $operands[1]->spelling === 'poison'
        ) {
            $names = array_slice($operands, 2);
            if (array_any($names, fn($t) => $t->kind !== 'identifier')) {
                $this->diagnostic($p, 'error', 'invalid #pragma GCC poison directive');
                return;
            }
            foreach ($names as $t) {
                if (isset($this->macros[$t->spelling]))
                    $this->diagnostic($p, 'warning', 'poisoning existing macro "' . $t->spelling . '"');
                $this->poisoned[$t->spelling] = true;
            }
        } elseif ($name === 'push_macro' || $name === 'pop_macro')
            $this->macroPragma($p, $operands, $name);
        else
            $this->outputLine(
                $c,
                $l->tokens[0]->line,
                '#pragma' . ($operands ? ' ' . render($operands) : ''),
            );
    }

    private function directive(Inclusion $c, LogicalLine $l, ?string $name, array $operands): void
    {
        if (count($l->tokens) === 1)
            return;
        $poisoning =
            $name === 'pragma'
            && count($operands) >= 2
            && $operands[0]->spelling === 'GCC'
            && $operands[1]->spelling === 'poison';
        if (!$poisoning)
            $this->poisonCheck($c, $operands);
        $p = $c->position($l->tokens[0]->line);
        switch ($name) {
            case 'define':
                $this->defineMacro($operands, $p, $c->depth === 0);
                break;
            case 'undef':
                $this->undefine($operands, $p);
                break;
            case 'include':
                $this->includeFile($c, $l, $operands);
                break;
            case 'line':
                $this->lineDirective($c, $l, $operands);
                break;
            case 'error':
            case 'warning':
                $this->diagnostic($p, $name, '#' . $name . ($operands ? ' ' . render($operands) : ''));
                break;
            case 'pragma':
                $this->pragma($c, $l, $operands);
                break;
            default:
                $this->diagnostic($p, 'error', 'invalid preprocessing directive #' . $l->tokens[1]->spelling);
        }
    }

    private function processFile(string $path, int $depth): void
    {
        $source = $this->manager->load($path);
        ++$source->entered;
        $c = new Inclusion($source, $depth);
        foreach ($source->lines as $l) {
            $tokens = $l->tokens;
            $isDirective = $tokens && $tokens[0]->spelling === '#';
            $name = directiveName($tokens);
            $operands = array_slice($tokens, 2);
            if ($isDirective && in_array($name, CONDITIONALS, true)) {
                $this->flush($c);
                $this->conditional($c, $l, $name, $operands);
            } elseif ($c->skipping())
                continue;
            elseif ($isDirective) {
                $this->flush($c);
                $this->directive($c, $l, $name, $operands);
            } else
                array_push($c->segment, ...$tokens);
        }
        $this->flush($c);
        foreach ($c->stack as $b)
            $this->closeRegion($c, $b, $source->physicalLines);
        foreach ($c->stack as $b)
            $this->diagnostic($b->position, 'error', 'unterminated #' . $b->kind);
    }

    private function includeReport(): array
    {
        $out = [...$this->tree, '', '== files =='];
        $paths = array_keys($this->manager->files);
        sort($paths, SORT_STRING);
        foreach ($paths as $path) {
            $s = $this->manager->files[$path];
            $out[] =
                "$path entered={$s->entered} skipped={$s->skipped} lines={$s->physicalLines} output_lines={$s->outputLines} skipped_lines={$s->skippedLines} guard="
                . ($s->guard ?? '-')
                . ' once='
                . ($s->once ? 'yes' : 'no');
        }
        $out[] = '';
        $current = 'main.o:';
        $hasPath = false;
        foreach (array_keys($this->manager->files) as $path) {
            if ((strlen($current) + 1 + strlen($path)) > 76 && $hasPath) {
                $out[] = $current . ' \\';
                $current = ' ';
                $hasPath = false;
            }
            $current .= ' ' . $path;
            $hasPath = true;
        }
        $out[] = $current;
        return $out;
    }

    private function references(): array
    {
        $refs = [];
        foreach ($this->macros as $name => $m) {
            $names = [];
            foreach ($m->replacement as $t)
                if (
                    $t->kind === 'identifier'
                    && isset($this->macros[$t->spelling])
                    && !in_array($t->spelling, $m->parameters ?? [], true)
                )
                    $names[$t->spelling] = true;
            $refs[$name] = array_keys($names);
            sort($refs[$name], SORT_STRING);
        }
        return $refs;
    }

    private function recursive(string $name, array $references): bool
    {
        $pending = $references[$name];
        $seen = [];
        while ($pending) {
            $current = array_pop($pending);
            if ($current === $name)
                return true;
            if (!isset($seen[$current])) {
                $seen[$current] = true;
                array_push($pending, ...$references[$current]);
            }
        }
        return false;
    }

    private function macroReport(): array
    {
        $out = ['== history ==', ...$this->history, '', '== table =='];
        $refs = $this->references();
        $names = array_keys($this->macros);
        sort($names, SORT_STRING);
        $objectLike = 0;
        foreach ($names as $name) {
            $m = $this->macros[$name];
            $out[] = '#define ' . $m->signature() . ($m->replacement ? ' ' . render($m->replacement) : '');
            $out[] =
                '  at '
                . $m->position[0]
                . ':'
                . $m->position[1]
                . " expanded={$m->expanded} tested={$m->tested} recursive="
                . ($this->recursive($name, $refs) ? 'yes' : 'no');
            $out[] = following('  refs:', $refs[$name]);
            if ($m->parameters === null)
                ++$objectLike;
        }
        $undefined = array_keys(array_diff_key($this->everDefined, $this->macros));
        sort($undefined, SORT_STRING);
        $count = count($this->macros);
        array_push(
            $out,
            '',
            "macros=$count object_like=$objectLike function_like=" . ($count - $objectLike),
            following('undefined:', $undefined),
        );
        $counts = $this->expander->builtinCounts;
        $out[] = "builtins: __COUNTER__={$counts['__COUNTER__']} __FILE__={$counts['__FILE__']} __LINE__={$counts['__LINE__']}";
        return $out;
    }

    private function conditionalReport(): array
    {
        $c = $this->conditionCounts;
        return [
            ...$this->conditionalRecords,
            '',
            '== skipped regions ==',
            ...$this->regions,
            '',
            'directives='
                . count($this->conditionalRecords)
                . " taken={$c['taken']} not_taken={$c['not_taken']} skipped={$c['skipped']} not_evaluated={$c['not_evaluated']} endif={$c['endif']} regions="
                . count($this->regions),
        ];
    }

    public function run(): void
    {
        $this->processDefines();
        $this->marker('main.c', 1);
        $this->processFile('main.c', 0);
        $names = array_keys($this->macros);
        sort($names, SORT_STRING);
        foreach ($names as $name)
            $this->unusedCheck($this->macros[$name]);
        $diag = [
            ...$this->diagnostics,
            "errors={$this->diagnosticCounts['error']} warnings={$this->diagnosticCounts['warning']}",
        ];
        $reports = [
            'preprocessed.txt' => $this->output,
            'includes.txt' => $this->includeReport(),
            'macros.txt' => $this->macroReport(),
            'conditionals.txt' => $this->conditionalReport(),
            'diagnostics.txt' => $diag,
        ];
        if (!is_dir('output'))
            mkdir('output');
        foreach ($reports as $name => $lines)
            file_put_contents(
                'output/' . $name,
                implode("\n", array_map(fn($s) => rtrim($s, ' '), $lines)) . "\n",
            );
    }
}

new Preprocessor()->run();
