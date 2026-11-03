<?php

final readonly class PatternAtom
{
    public function __construct(
        public ?array $choices = null,
        public ?bool $aromatic = null,
    ) {}

    public function matches(Atom $atom): bool
    {
        return (
            $this->choices !== null
                ? in_array([$atom->element->symbol, $atom->aromatic], $this->choices, true)
                : $this->aromatic === null
                || $this->aromatic === $atom->aromatic
        );
    }
}

function readPatternAtom(string $text, int $i, array $elements): array
{
    $ch = $text[$i];
    if (in_array($ch, ['*', 'A', 'a'], true))
        return [new PatternAtom(aromatic: $ch === '*' ? null : $ch === 'a'), $i + 1];
    if ($ch === '[') {
        $end = strpos($text, ']', $i + 1);
        if ($end === false)
            throw new AnalysisError('unclosed bracket', $i + 1);
        $choices = [];
        foreach (explode(',', substr($text, $i + 1, $end - $i - 1)) as $part) {
            $organic = readOrganic($part, 0);
            if ($organic === null || $organic[2] !== strlen($part))
                throw new AnalysisError('bad bracket atom', $i + 1);
            $choices[] = [$organic[0], $organic[1]];
        }
        return [new PatternAtom($choices), $end + 1];
    }
    $organic = readOrganic($text, $i);
    if ($organic === null)
        throw new AnalysisError('unexpected character', $i + 1);
    return [new PatternAtom([[$organic[0], $organic[1]]]), $organic[2]];
}

function moleculePattern(Molecule $m): Molecule
{
    $p = new Molecule($m->elements);
    foreach ($m->atoms as $a)
        $p->addAtom(new PatternAtom([[$a->element->symbol, $a->aromatic]]));
    foreach ($m->orderedBonds() as $b)
        $p->addBond($b->ends[0], $b->ends[1], $b->kind);
    return $p;
}

function bondMatches(Bond $pattern, Bond $bond): bool
{
    $symbol = $pattern->symbol;
    if ($symbol === null)
        return $bond->kind === 1 || $bond->kind === 4;
    if ($symbol === '~')
        return true;
    return $bond->kind === (is_string($symbol) ? BOND_TYPES[$symbol] : $symbol);
}

function embeddings(Molecule $pattern, Molecule $m): array
{
    if (count($pattern->atoms) > count($m->atoms))
        return [0, 0, null];
    $candidates = $earlier = [];
    foreach ($pattern->atoms as $i => $p) {
        $list = [];
        foreach ($m->atoms as $j => $a)
            if ($p->matches($a) && $m->degree($j) >= $pattern->degree($i))
                $list[] = $j;
        $candidates[] = $list;
        $earlier[$i] = array_filter($pattern->neighbors[$i], fn($bond, $j) => $j < $i, ARRAY_FILTER_USE_BOTH);
    }
    $mapping = $used = $unique = [];
    $count = 0;
    $first = null;
    $assign = function (int $i) use (
        &$assign,
        &$mapping,
        &$used,
        &$unique,
        &$count,
        &$first,
        $candidates,
        $earlier,
        $pattern,
        $m,
    ): void {
        if ($i === count($pattern->atoms)) {
            ++$count;
            $set = array_keys($used);
            sort($set, SORT_NUMERIC);
            $unique[implode(',', $set)] = true;
            $first ??= $mapping;
            return;
        }
        foreach ($candidates[$i] as $a) {
            if (isset($used[$a]))
                continue;
            $valid = true;
            foreach ($earlier[$i] as $j => $bond) {
                $target = $m->neighbors[$a][$mapping[$j]] ?? null;
                if ($target === null || !bondMatches($bond, $target)) {
                    $valid = false;
                    break;
                }
            }
            if ($valid) {
                $mapping[] = $a;
                $used[$a] = true;
                $assign($i + 1);
                unset($used[$a]);
                array_pop($mapping);
            }
        }
    };
    $assign(0);
    return [$count, count($unique), $first];
}

function fingerprint(Molecule $m): array
{
    $codes = [];
    foreach ($m->atoms as $i => $a)
        $codes[] = (16 * $a->element->number) + (8 * (int) $a->aromatic) + $m->degree($i);
    $bits = $used = [];
    $count = 0;
    $extend = function (int $a, int $depth, int $value) use (
        &$extend,
        &$bits,
        &$used,
        &$count,
        $codes,
        $m,
    ): void {
        ++$count;
        $bits[$value % 1024] = true;
        if ($depth === 5)
            return;
        $neighbors = $m->neighbors[$a];
        ksort($neighbors, SORT_NUMERIC);
        foreach ($neighbors as $b => $bond)
            if (!isset($used[$b])) {
                $next = (($value * 31) + $bond->kind) % 1000003;
                $next = (($next * 31) + $codes[$b]) % 1000003;
                $used[$b] = true;
                $extend($b, $depth + 1, $next);
                unset($used[$b]);
            }
    };
    foreach ($codes as $a => $code) {
        $used[$a] = true;
        $extend($a, 0, $code);
        unset($used[$a]);
    }
    return [$bits, $count];
}

function tanimoto(array $a, array $b): array
{
    $common = count(array_intersect_key($a, $b));
    return [$common, count($a) + count($b) - $common];
}
