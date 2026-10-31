<?php

final class Doc
{
    public bool $forced = false;
    public ?string $mode = null;

    public function __construct(
        public string $kind,
        public string $value = '',
        public array $items = [],
        public ?Doc $child = null,
        public int $amount = 0,
        public string $flat = '',
    ) {}
}

function mark(string $kind): Doc
{
    return new Doc($kind);
}

function suffix(string $value): Doc
{
    return new Doc('suffix', $value);
}

function ifBreak(string $broken, string $flat): Doc
{
    return new Doc('if_break', $broken, flat: $flat);
}

function concat(mixed ...$parts): Doc
{
    $items = [];
    $add = function (mixed $p) use (&$add, &$items): void {
        if ($p === null)
            return;
        if (is_array($p)) {
            foreach ($p as $x)
                $add($x);
            return;
        }
        if (is_string($p))
            $p = new Doc('text', $p);
        if ($p->kind === 'concat') {
            foreach ($p->items as $x)
                $add($x);
        } elseif ($p->kind === 'text') {
            if ($p->value === '')
                return;
            $last = count($items) - 1;
            if ($last >= 0 && $items[$last]->kind === 'text')
                $items[$last] = new Doc('text', $items[$last]->value . $p->value);
            else
                $items[] = new Doc('text', $p->value);
        } else
            $items[] = $p;
    };
    foreach ($parts as $part)
        $add($part);
    return match (count($items)) {
        0 => new Doc('text'),
        1 => $items[0],
        default => new Doc('concat', items: $items),
    };
}

function forceBroken(Doc $d): bool
{
    if (in_array($d->kind, ['hardline', 'break_parent'], true))
        return true;
    if ($d->kind === 'concat')
        return array_any($d->items, forceBroken(...));
    return $d->child !== null && forceBroken($d->child);
}

function group(mixed $child): Doc
{
    $d = new Doc('group', child: concat($child));
    $d->forced = forceBroken($d->child);
    return $d;
}

function nest(int $amount, mixed $child): Doc
{
    return new Doc('nest', child: concat($child), amount: $amount);
}

function align(mixed $child): Doc
{
    return new Doc('align', child: concat($child));
}

function allGroups(?Doc $d): Generator
{
    if ($d === null)
        return;
    if ($d->kind === 'group')
        yield $d;
    if ($d->child !== null)
        yield from allGroups($d->child);
    foreach ($d->items as $child)
        yield from allGroups($child);
}
