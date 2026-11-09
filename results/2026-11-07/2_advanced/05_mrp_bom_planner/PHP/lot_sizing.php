<?php
function smallest_multiple(int $quantity, int $factor): int { return intdiv($quantity + $factor - 1, $factor) * $factor; }
function lot_size(Item $item, int $week, int $projected, array $receipts, array $gross, int $horizon): int {
    $net = $item->safety - $projected;
    if ($item->rule === 'LFL') return $net;
    if ($item->rule === 'FOQ') return smallest_multiple($net, $item->lot[0]);
    if ($item->rule === 'MIN') return smallest_multiple(max($net, $item->lot[0]), $item->lot[1]);
    $quantity = $net;
    for ($later = $week + 1; $later <= min($week + $item->lot[0] - 1, $horizon); $later++) { $projected += $receipts[$later] - $gross[$later]; $quantity = max($quantity, $item->safety - $projected); }
    return $quantity;
}
