<?php
class BomRow {
    public string $parent, $child;
    public int $quantity, $scrap;
    public function __construct(array $fields) { [$this->parent, $this->child] = $fields; $this->quantity = (int)$fields[2]; $this->scrap = (int)$fields[3]; }
}
function need(BomRow $row, int $quantity): int { return intdiv($quantity * $row->quantity * (100 + $row->scrap) + 99, 100); }
class Bom {
    public array $children, $parents;
    public function __construct(array $items) { $this->children = $this->parents = array_fill_keys(array_keys($items), []); }
    public function manufactured(string $id): bool { return count($this->children[$id]) > 0; }
    public function path(string $id, string $target, array &$visited): ?array {
        if ($id === $target) return [$id];
        $visited[$id] = true;
        foreach ($this->children[$id] as $row) if (!isset($visited[$row->child])) { $rest = $this->path($row->child, $target, $visited); if ($rest !== null) return [$id, ...$rest]; }
        return null;
    }
    public function code(string $id, array &$codes): int {
        if (isset($codes[$id])) return $codes[$id];
        $value = 0; foreach ($this->parents[$id] as $row) $value = max($value, $this->code($row->parent, $codes) + 1);
        return $codes[$id] = $value;
    }
    public function cumulative(string $id, array $items, array &$times): int {
        if (isset($times[$id])) return $times[$id];
        $longest = 0; foreach ($this->children[$id] as $row) $longest = max($longest, $this->cumulative($row->child, $items, $times));
        return $times[$id] = $items[$id]->lead + $longest;
    }
}
function read_bom(array $items, array &$errors): Bom {
    $bom = new Bom($items);
    foreach (read_rows('bom.csv') as [$number, $fields]) {
        $row = new BomRow($fields); $parent = $row->parent; $child = $row->child; $reason = null;
        if (!isset($items[$parent])) $reason = "unknown item $parent";
        elseif (!isset($items[$child])) $reason = "unknown item $child";
        elseif ($row->quantity < 1) $reason = "bad quantity $row->quantity";
        elseif ($row->scrap > 50) $reason = "bad scrap $row->scrap";
        elseif ($parent === $child) $reason = "cycle $parent -> $parent";
        elseif (count(array_filter($bom->children[$parent], fn($other) => $other->child === $child)) > 0) $reason = "duplicate $parent -> $child";
        else { $visited = []; $path = $bom->path($child, $parent, $visited); if ($path !== null) $reason = "cycle $parent -> " . implode(' -> ', $path); }
        if ($reason !== null) { $errors[] = "bom.csv line $number: $reason"; continue; }
        $bom->children[$parent][] = $row; $bom->parents[$child][] = $row;
        usort($bom->children[$parent], fn($a, $b) => strcmp($a->child, $b->child));
        usort($bom->parents[$child], fn($a, $b) => strcmp($a->parent, $b->parent));
    }
    return $bom;
}
