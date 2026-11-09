<?php
function standard_costs(array $items, Bom $bom, array $order): array {
    $costs = [];
    foreach (array_reverse($order) as $id) {
        $material = $items[$id]->material; $labor = $items[$id]->labor;
        foreach ($bom->children[$id] as $row) { $factor = $row->quantity * (100 + $row->scrap); $material += intdiv($factor * $costs[$row->child][0] + 50, 100); $labor += intdiv($factor * $costs[$row->child][1] + 50, 100); }
        $costs[$id] = [$material, $labor, $material + $labor];
    }
    return $costs;
}
function abc_classes(array $values): array {
    $ids = array_keys($values); usort($ids, fn($a, $b) => ($values[$b] <=> $values[$a]) ?: strcmp((string)$a, (string)$b));
    $total = array_sum($values); $before = 0; $classes = [];
    foreach ($ids as $id) { $value = $values[$id]; $classes[$id] = $value === 0 ? 'C' : (100 * $before < 80 * $total ? 'A' : (100 * $before < 95 * $total ? 'B' : 'C')); $before += $value; }
    return $classes;
}
