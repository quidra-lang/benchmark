<?php

function readOrganic(string $text, int $position): ?array
{
    $pair = substr($text, $position, 2);
    if ($pair === 'Cl' || $pair === 'Br')
        return [$pair, false, $position + 2];
    $ch = substr($text, $position, 1);
    if ($ch !== '' && str_contains('BCNOPSFI', $ch))
        return [$ch, false, $position + 1];
    if ($ch !== '' && str_contains('bcnops', $ch))
        return [strtoupper($ch), true, $position + 1];
    return null;
}

function readBracket(string $content, array $elements, int $column): Atom
{
    $i = 0;
    $length = strlen($content);
    while ($i < $length && ctype_digit($content[$i]))
        ++$i;
    if ($i >= 4 || $i > 0 && $content[0] === '0' || $i === $length)
        throw new AnalysisError('bad bracket atom', $column);
    $mass = $i ? (int) substr($content, 0, $i) : 0;
    $ch = $content[$i];
    if (str_contains('bcnops', $ch)) {
        $symbol = strtoupper($ch);
        $aromatic = true;
        ++$i;
    } elseif ($ch >= 'A' && $ch <= 'Z') {
        $pair = substr($content, $i, 2);
        if (strlen($pair) === 2 && $pair[1] >= 'a' && $pair[1] <= 'z' && isset($elements[$pair])) {
            $symbol = $pair;
            $i += 2;
        } elseif (isset($elements[$ch])) {
            $symbol = $ch;
            ++$i;
        } else
            throw new AnalysisError('unknown element', $column);
        $aromatic = false;
    } else
        throw new AnalysisError('bad bracket atom', $column);
    if (substr($content, $i, 2) === '@@')
        $i += 2;
    elseif (substr($content, $i, 1) === '@')
        ++$i;
    $hydrogens = 0;
    if (substr($content, $i, 1) === 'H') {
        $hydrogens = 1;
        ++$i;
        if ($i < $length && ctype_digit($content[$i]))
            $hydrogens = (int) $content[$i++];
    }
    $charge = 0;
    $sign = substr($content, $i, 1);
    if ($sign === '+' || $sign === '-') {
        $charge = $sign === '+' ? 1 : -1;
        ++$i;
        if ($i < $length && $content[$i] >= '1' && $content[$i] <= '9')
            $charge *= (int) $content[$i++];
    }
    if ($i !== $length)
        throw new AnalysisError('bad bracket atom', $column);
    return new Atom($elements[$symbol], $aromatic, $mass, $charge, $hydrogens, true, $column);
}

function readAtom(string $text, int $i, array $elements): array
{
    if ($text[$i] === '[') {
        $end = strpos($text, ']', $i + 1);
        if ($end === false)
            throw new AnalysisError('unclosed bracket', $i + 1);
        return [readBracket(substr($text, $i + 1, $end - $i - 1), $elements, $i + 1), $end + 1];
    }
    $organic = readOrganic($text, $i);
    if ($organic === null)
        throw new AnalysisError('unexpected character', $i + 1);
    [$symbol, $aromatic, $end] = $organic;
    return [new Atom($elements[$symbol], $aromatic, column: $i + 1), $end];
}

function parseSmiles(string $text, array $elements, bool $pattern = false): Molecule
{
    $m = new Molecule($elements);
    $symbols = $pattern ? ['-' => 1, '=' => 2, '#' => 3, ':' => 4, '~' => 5] : BOND_TYPES;
    $current = $pending = null;
    $branches = $open = [];
    $i = 0;
    while ($i < strlen($text)) {
        $ch = $text[$i];
        $column = $i + 1;
        if (isset($symbols[$ch])) {
            if ($current === null || $pending !== null)
                throw new AnalysisError('misplaced bond', $column);
            $pending = [$ch, $column];
            ++$i;
        } elseif ($ch === '(') {
            if ($current === null || $pending !== null || $i > 0 && $text[$i - 1] === '(')
                throw new AnalysisError('misplaced branch', $column);
            $branches[] = [$current, $column];
            ++$i;
        } elseif ($ch === ')') {
            if (!$branches)
                throw new AnalysisError('unmatched parenthesis', $column);
            if ($pending !== null)
                throw new AnalysisError('dangling bond', $pending[1]);
            if ($i > 0 && $text[$i - 1] === '(')
                throw new AnalysisError('empty branch', $column);
            [$current, $opening] = array_pop($branches);
            ++$i;
        } elseif (ctype_digit($ch) || $ch === '%') {
            if ($current === null)
                throw new AnalysisError('misplaced ring closure', $column);
            if ($ch === '%') {
                $digits = substr($text, $i + 1, 2);
                if (strlen($digits) !== 2 || !ctype_digit($digits))
                    throw new AnalysisError('bad ring number', $column);
                $ring = (int) $digits;
                $i += 3;
            } else {
                $ring = (int) $ch;
                ++$i;
            }
            $symbol = $pending[0] ?? null;
            $pending = null;
            if (!isset($open[$ring])) {
                $open[$ring] = [$current, $symbol, $column];
                continue;
            }
            [$first, $initial, $opening] = $open[$ring];
            if ($first === $current)
                throw new AnalysisError('self bond', $column);
            if ($initial !== null && $symbol !== null && $symbols[$initial] !== $symbols[$symbol])
                throw new AnalysisError('ring bond mismatch', $column);
            if (isset($m->neighbors[$first][$current]))
                throw new AnalysisError('duplicate bond', $column);
            $m->addBond($first, $current, $symbol ?? $initial);
            unset($open[$ring]);
        } else {
            [$atom, $next] = $pattern
                ? readPatternAtom($text, $i, $elements)
                : readAtom($text, $i, $elements);
            $new = $m->addAtom($atom);
            if ($current !== null)
                $m->addBond($current, $new, $pending[0] ?? null);
            $current = $new;
            $pending = null;
            $i = $next;
        }
    }
    if ($pending !== null)
        throw new AnalysisError('dangling bond', $pending[1]);
    if ($branches)
        throw new AnalysisError('unmatched parenthesis', $branches[0][1]);
    if ($open)
        throw new AnalysisError('unclosed ring', min(array_column($open, 2)));
    return $m;
}
