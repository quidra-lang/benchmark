<?php

function costAdd(string $a, string $b): string
{
    $out = '';
    $i = strlen($a) - 1;
    $j = strlen($b) - 1;
    $carry = 0;
    while ($i >= 0 || $j >= 0 || $carry) {
        $v = $carry + ($i >= 0 ? ord($a[$i--]) - 48 : 0) + ($j >= 0 ? ord($b[$j--]) - 48 : 0);
        $out = chr(48 + ($v % 10)) . $out;
        $carry = intdiv($v, 10);
    }
    return $out;
}

function costMultiply(string $a, int $factor): string
{
    if ($factor === 0)
        return '0';
    $out = '';
    $carry = 0;
    for ($i = strlen($a) - 1; $i >= 0; --$i) {
        $v = ((ord($a[$i]) - 48) * $factor) + $carry;
        $out = chr(48 + ($v % 10)) . $out;
        $carry = intdiv($v, 10);
    }
    return ($carry ? (string) $carry : '') . $out;
}

function costCompare(string $a, string $b): int
{
    return strlen($a) <=> strlen($b) ?: strcmp($a, $b);
}

final class Allocation
{
    public array
        $neighbors = [],
        $costs = [],
        $partners = [],
        $order = [],
        $potential = [],
        $colors = [],
        $spills = []
    ;

    public function __construct(TacFunction $f, CFG $g, DataFlow $flow, int $registers)
    {
        $nodes = array_fill_keys($f->parameters, true);
        foreach ($g->instructions as $n => $i)
            if (isset($g->reachable[$g->blockOf[$n]])) {
                foreach ($i->usedVariables() as $v)
                    $nodes[$v] = true;
                if ($i->destination !== null)
                    $nodes[$i->destination] = true;
            }
        $names = array_keys($nodes);
        sort($names, SORT_STRING);
        foreach ($names as $v) {
            $this->neighbors[$v] = $this->partners[$v] = [];
            $this->costs[$v] = '0';
        }
        foreach (numberKeys($g->reachable) as $b) {
            $block = $g->blocks[$b];
            $state = $flow->liveOut[$b];
            foreach (array_reverse($block->instructions) as $n) {
                $i = $g->instructions[$n];
                $dest = $i->destination;
                if ($dest !== null) {
                    $partner = $i->kind === 'copy' ? $i->a : null;
                    foreach ($state as $v => $_)
                        if ($v !== $dest && $v !== $partner)
                            $this->edge($dest, $v);
                }
                $state = liveTransfer($i, $state);
            }
            $weight = '1' . str_repeat('0', $g->depth[$b]);
            foreach ($block->instructions as $n) {
                $i = $g->instructions[$n];
                $occurrences = $i->usedVariables();
                if ($i->destination !== null)
                    $occurrences[] = $i->destination;
                foreach ($occurrences as $v)
                    $this->costs[$v] = costAdd($this->costs[$v], $weight);
            }
        }
        $entry = $flow->liveIn[1] + array_fill_keys($f->parameters, true);
        foreach ($f->parameters as $p) {
            $this->costs[$p] = costAdd($this->costs[$p], '1');
            foreach ($entry as $v => $_)
                if ($v !== $p)
                    $this->edge($p, $v);
        }
        foreach ($f->instructions() as $i)
            if ($i->kind === 'copy' && is_string($i->a) && $i->destination !== $i->a) {
                if (isset($this->partners[$i->destination]))
                    $this->partners[$i->destination][$i->a] = true;
                if (isset($this->partners[$i->a]))
                    $this->partners[$i->a][$i->destination] = true;
            }
        $remaining = $nodes;
        while ($remaining) {
            $degrees = [];
            $simple = [];
            foreach ($remaining as $v => $_) {
                $degrees[$v] = count(array_intersect_key($this->neighbors[$v], $remaining));
                if ($degrees[$v] < $registers)
                    $simple[] = $v;
            }
            if ($simple) {
                usort($simple, fn($a, $b) => $degrees[$a] <=> $degrees[$b] ?: strcmp($a, $b));
                $chosen = $simple[0];
            } else {
                $choices = array_keys($remaining);
                usort(
                    $choices,
                    fn($a, $b) => (
                        costCompare(
                            costMultiply($this->costs[$a], $degrees[$b]),
                            costMultiply($this->costs[$b], $degrees[$a]),
                        ) ?: strcmp($a, $b)
                    ),
                );
                $chosen = $choices[0];
                $this->potential[] = [$chosen, $degrees[$chosen]];
            }
            $this->order[] = $chosen;
            unset($remaining[$chosen]);
        }
        foreach (array_reverse($this->order) as $v) {
            $free = array_fill_keys(range(0, $registers - 1), true);
            foreach ($this->neighbors[$v] as $n => $_)
                if (isset($this->colors[$n]))
                    unset($free[$this->colors[$n]]);
            if (!$free) {
                $this->colors[$v] = null;
                $this->spills[$v] = true;
                continue;
            }
            $preferred = [];
            foreach ($this->partners[$v] as $p => $_)
                if (isset($this->colors[$p]) && isset($free[$this->colors[$p]]))
                    $preferred[$this->colors[$p]] = true;
            $this->colors[$v] = min(array_keys($preferred ?: $free));
        }
    }

    private function edge(string $a, string $b): void
    {
        $this->neighbors[$a][$b] = true;
        $this->neighbors[$b][$a] = true;
    }
}
