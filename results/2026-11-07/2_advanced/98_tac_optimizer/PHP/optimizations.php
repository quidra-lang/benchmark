<?php

function rewrite(TacFunction $f, array $replacements, array $insertions = []): void
{
    $out = [];
    $number = 0;
    foreach ($f->code as $index => $line) {
        array_push($out, ...$insertions[$index] ?? []);
        if (is_string($line))
            $out[] = $line;
        else {
            ++$number;
            array_push($out, ...$replacements[$number] ?? [$line]);
        }
    }
    array_push($out, ...$insertions[count($f->code)] ?? []);
    $f->code = $out;
}

function fold(TacInstruction $i): ?TacInstruction
{
    if (!in_array($i->kind, ['bin', 'if'], true))
        return $i;
    $a = $i->a;
    $b = $i->b;
    $ac = is_int($a);
    $bc = is_int($b);
    if ($ac && $bc) {
        if (in_array($i->operation, ['/', '%'], true) && $b === 0)
            return $i;
        $v = calculate($i->operation, $a, $b);
        if ($i->kind === 'if')
            return $v !== 0 ? new TacInstruction('goto', name: $i->name) : null;
        return $v >= -2147483648 && $v <= 2147483647 ? new TacInstruction('copy', $i->destination, $v) : $i;
    }
    if ($i->kind !== 'bin' || $ac === $bc)
        return $i;
    $op = $i->operation;
    $replacement = null;
    if ($op === '+' && ($a === 0 || $b === 0))
        $replacement = $ac ? $b : $a;
    elseif ($op === '-' && $b === 0)
        $replacement = $a;
    elseif ($op === '*' && ($a === 1 || $b === 1))
        $replacement = $ac ? $b : $a;
    elseif ($op === '/' && $b === 1)
        $replacement = $a;
    elseif ($op === '*' && ($a === 0 || $b === 0))
        $replacement = 0;
    return $replacement === null ? $i : new TacInstruction('copy', $i->destination, $replacement);
}

function cseReplacements(TacFunction $f, CFG $g, array $sources, array $candidates): array
{
    $temporary = '_t' . ++$f->temporarySerial;
    $edits = [];
    foreach ($sources as $n) {
        $i = $g->instructions[$n];
        $edits[$n] = [
            $i->changed(['destination' => $temporary]),
            new TacInstruction('copy', $i->destination, $temporary),
        ];
    }
    foreach ($candidates as $n)
        $edits[$n] = [new TacInstruction('copy', $g->instructions[$n]->destination, $temporary)];
    return [$temporary, $edits];
}

function hoist(TacFunction $f, CFG $g, NaturalLoop $loop, array $moves): string
{
    $header = $g->blocks[$loop->header];
    $outside = array_values(array_filter($header->predecessors, fn($n) => !isset($loop->blocks[$n])));
    $edits = [];
    $instructions = [];
    foreach ($moves as $n) {
        $edits[$n] = [];
        $instructions[] = $g->instructions[$n];
    }
    if (
        $loop->header !== 1
        && count($outside) === 1
        && $g->blocks[$outside[0]]->successors === [$loop->header]
    ) {
        $preheader = $g->blocks[$outside[0]];
        $last = $preheader->instructions[count($preheader->instructions) - 1];
        $position = $g->positions[$last];
        if (!in_array($g->instructions[$last]->kind, ['goto', 'if'], true))
            ++$position;
        $insertion = $instructions;
        $destination = 'B' . $preheader->number;
    } else {
        $label = '_p' . ++$f->preheaderSerial;
        $position = $header->start;
        $insertion = [$label, ...$instructions];
        $destination = 'new ' . $label;
        foreach ($outside as $n) {
            $b = $g->blocks[$n];
            $last = $b->instructions[count($b->instructions) - 1];
            $i = $g->instructions[$last];
            if (in_array($i->kind, ['goto', 'if'], true) && in_array($i->name, $header->labels, true))
                $edits[$last] = [$i->changed(['name' => $label])];
        }
    }
    rewrite($f, $edits, [$position => $insertion]);
    return $destination;
}

function removeUnreachable(TacFunction $f, CFG $g): array
{
    $blocks = [];
    $deleted = [];
    foreach ($g->blocks as $n => $b)
        if (!isset($g->reachable[$n])) {
            $blocks[] = $n;
            for ($i = $b->start; $i < $b->end; ++$i)
                $deleted[$i] = true;
        }
    $numbers = array_flip($g->positions);
    $remaining = [];
    foreach ($f->code as $i => $line)
        if (!isset($deleted[$i]))
            $remaining[] = [$line, $numbers[$i] ?? null];
    $jumps = [];
    foreach ($remaining as $index => [$line, $number]) {
        if (is_string($line) || !in_array($line->kind, ['goto', 'if'], true))
            continue;
        $labels = [];
        $next = $index + 1;
        while (isset($remaining[$next]) && is_string($remaining[$next][0]))
            $labels[] = $remaining[$next++][0];
        if (in_array($line->name, $labels, true))
            $jumps[] = $number;
    }
    $jumpSet = array_fill_keys($jumps, true);
    $remaining = array_values(array_filter($remaining, fn($x) => $x[1] === null || !isset($jumpSet[$x[1]])));
    $targets = [];
    foreach ($remaining as [$line, $number])
        if (!is_string($line) && in_array($line->kind, ['goto', 'if'], true))
            $targets[$line->name] = true;
    $labels = $code = [];
    foreach ($remaining as [$line, $number]) {
        if (is_string($line) && !isset($targets[$line]))
            $labels[] = $line;
        else
            $code[] = $line;
    }
    $f->code = $code;
    return [$blocks, $jumps, $labels];
}
