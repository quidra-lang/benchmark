<?php

final class Expander
{
    private array $macros;
    private Closure $diagnostic;
    public int $counter = 0;
    public array $builtinCounts = ['__LINE__' => 0, '__FILE__' => 0, '__COUNTER__' => 0];

    public function __construct(array &$macros, Closure $diagnostic)
    {
        $this->macros = &$macros;
        $this->diagnostic = $diagnostic;
    }

    private function error(Inclusion $context, PPToken $t, string $message): void
    {
        ($this->diagnostic)($context->position($t->line), 'error', $message);
    }

    private function builtin(PPToken $t, Inclusion $context): PPToken
    {
        ++$this->builtinCounts[$t->spelling];
        if ($t->spelling === '__FILE__')
            return new PPToken('string', '"' . $context->displayFile . '"', $t->line, $t->space);
        $spelling = $t->spelling === '__LINE__'
            ? (string) $context->position($t->line)[1]
            : (string) $this->counter++;
        return new PPToken('number', $spelling, $t->line, $t->space);
    }

    private function collect(array $pending, Macro $m, PPToken $t, Inclusion $context): ?array
    {
        $args = [[]];
        $separators = [];
        $depth = 0;
        $closing = null;
        $consumed = 0;
        $n = count($pending);
        for ($i = 1; $i < $n; ++$i) {
            $x = $pending[$n - 1 - $i];
            if ($x->spelling === ')' && $depth === 0) {
                $closing = $x;
                $consumed = $i + 1;
                break;
            }
            if ($x->spelling === ',' && $depth === 0) {
                $separators[] = $x;
                $args[] = [];
            } else {
                if ($x->spelling === '(')
                    ++$depth;
                elseif ($x->spelling === ')')
                    --$depth;
                $args[count($args) - 1][] = $x;
            }
        }
        if ($closing === null) {
            $this->error($context, $t, 'unterminated argument list invoking macro "' . $m->name . '"');
            return null;
        }
        $count = count($args);
        $fixed = count($m->parameters) - (int) $m->variadic;
        $error = null;
        if (!$m->variadic && $fixed === 0 && ($count !== 1 || $args[0]))
            $error = 'macro "' . $m->name . '" passed ' . $count . ' arguments, but takes just 0';
        elseif ($count < $fixed)
            $error =
                'macro "' . $m->name . '" requires ' . $fixed . ' arguments, but only ' . $count . ' given';
        elseif ($count > $fixed && !$m->variadic)
            $error = 'macro "' . $m->name . '" passed ' . $count . ' arguments, but takes just ' . $fixed;
        if ($error !== null) {
            $this->error($context, $t, $error);
            return null;
        }
        $raw = [];
        for ($i = 0; $i < $fixed; ++$i)
            $raw[$m->parameters[$i]] = $args[$i];
        if ($m->variadic) {
            $variable = [];
            for ($i = $fixed; $i < $count; ++$i) {
                if ($i > $fixed)
                    $variable[] = $separators[$i - 1];
                array_push($variable, ...$args[$i]);
            }
            $raw[VARIADIC_NAME] = $variable;
        }
        return [$raw, $consumed, $closing];
    }

    private function stringize(array $tokens, PPToken $sharp): PPToken
    {
        $s = '';
        foreach ($tokens as $i => $t) {
            if ($i && $t->space)
                $s .= ' ';
            $s .= in_array($t->kind, ['string', 'character'], true) ? strtr($t->spelling, [
                    '\\' => '\\\\',
                    '"' => '\\"',
                ]) : $t->spelling;
        }
        return new PPToken('string', '"' . $s . '"', $sharp->line, $sharp->space);
    }

    private function paste(PPToken $left, PPToken $right, PPToken $t, Inclusion $context): array
    {
        if ($left->kind === 'placemarker')
            return [$right->changed(space: $left->space)];
        if ($right->kind === 'placemarker')
            return [$left];
        $s = $left->spelling . $right->spelling;
        $kind = singleToken($s);
        if ($kind !== null)
            return [new PPToken(
                $kind,
                $s,
                $left->line,
                $left->space,
                array_intersect_key($left->hide, $right->hide),
            )];
        $this->error(
            $context,
            $t,
            'pasting "'
            . $left->spelling
            . '" and "'
            . $right->spelling
            . '" does not give a valid preprocessing token',
        );
        return [$left, $right->changed(space: false)];
    }

    private function substitute(Macro $m, array $raw, PPToken $t, array $hide, Inclusion $context): array
    {
        $replacement = $m->replacement;
        $items = $expanded = [];
        $i = 0;
        while ($i < count($replacement)) {
            $x = $replacement[$i];
            if ($x->spelling === '#' && $m->parameters !== null) {
                $items[] = [$this->stringize($raw[$replacement[$i + 1]->spelling], $x)];
                $i += 2;
                continue;
            }
            if ($x->spelling === '##')
                $items[] = $x;
            elseif ($x->kind === 'identifier' && array_key_exists($x->spelling, $raw)) {
                $adjacent =
                    $i > 0 && $replacement[$i - 1]->spelling === '##'
                    || isset($replacement[$i + 1]) && $replacement[$i + 1]->spelling === '##';
                if ($adjacent)
                    $sequence = $raw[$x->spelling];
                else {
                    if (!array_key_exists($x->spelling, $expanded))
                        $expanded[$x->spelling] = $this->expand($raw[$x->spelling], $context);
                    $sequence = $expanded[$x->spelling];
                }
                if ($sequence) {
                    $sequence[0] = $sequence[0]->changed(space: $x->space);
                    $items[] = $sequence;
                } else
                    $items[] = [new PPToken('placemarker', '', $x->line, $x->space)];
            } else
                $items[] = [$x];
            ++$i;
        }
        $pasted = [];
        $i = 0;
        while ($i < count($items)) {
            $item = $items[$i];
            if ($item instanceof PPToken) {
                $left = array_pop($pasted);
                $right = $items[$i + 1];
                if ($right instanceof PPToken)
                    $right = [$right];
                array_push($pasted, ...$this->paste($left, $right[0], $t, $context));
                array_push($pasted, ...array_slice($right, 1));
                $i += 2;
            } else {
                array_push($pasted, ...$item);
                ++$i;
            }
        }
        $result = [];
        $carry = false;
        foreach ($pasted as $x) {
            if ($x->kind === 'placemarker')
                $carry = $carry || $x->space;
            else {
                $result[] = $x->changed(line: $t->line, space: $x->space || $carry, hide: $x->hide + $hide);
                $carry = false;
            }
        }
        if ($result)
            $result[0] = $result[0]->changed(space: $t->space);
        return $result;
    }

    public function expand(array $sequence, Inclusion $context): array
    {
        $pending = array_reverse($sequence);
        $result = [];
        while ($pending) {
            $t = array_pop($pending);
            if ($t->kind !== 'identifier' || isset($t->hide[$t->spelling])) {
                $result[] = $t;
                continue;
            }
            if (in_array($t->spelling, BUILTINS, true)) {
                $result[] = $this->builtin($t, $context);
                continue;
            }
            $m = $this->macros[$t->spelling] ?? null;
            if (
                $m === null
                || $m->parameters !== null && (!$pending || $pending[count($pending) - 1]->spelling !== '(')
            ) {
                $result[] = $t;
                continue;
            }
            $raw = [];
            $hide = $t->hide + [$m->name => true];
            if ($m->parameters !== null) {
                $collected = $this->collect($pending, $m, $t, $context);
                if ($collected === null) {
                    $result[] = $t;
                    continue;
                }
                [$raw, $consumed, $closing] = $collected;
                for ($i = 0; $i < $consumed; ++$i)
                    array_pop($pending);
                $hide = array_intersect_key($t->hide, $closing->hide) + [$m->name => true];
            }
            $r = $this->substitute($m, $raw, $t, $hide, $context);
            ++$m->expanded;
            if (!$r && $t->space && $pending) {
                $i = count($pending) - 1;
                $pending[$i] = $pending[$i]->changed(space: true);
            }
            array_push($pending, ...array_reverse($r));
        }
        return $result;
    }
}
