<?php

$items = [
    ['tent', 10, 120], ['stove', 3, 65], ['lantern', 2, 45], ['rope', 3, 20], ['camera', 5, 90],
    ['blanket', 5, 85], ['water', 6, 100],
];
$capacity = 20;
$table = array_fill(0, count($items) + 1, array_fill(0, $capacity + 1, 0));
foreach ($items as $i => [$name, $weight, $value]) {
    for ($limit = 0; $limit <= $capacity; $limit++) {
        $table[$i + 1][$limit] = $table[$i][$limit];
        if ($weight <= $limit) {
            $table[$i + 1][$limit] = max($table[$i + 1][$limit], $table[$i][$limit - $weight] + $value);
        }
    }
}
$chosen = array_fill(0, count($items), false);
$remaining = $capacity;
for ($i = count($items) - 1; $i >= 0; $i--) {
    if ($table[$i + 1][$remaining] !== $table[$i][$remaining]) {
        $chosen[$i] = true;
        $remaining -= $items[$i][1];
    }
}
$names = [];
foreach ($items as $i => $item) {
    if ($chosen[$i]) {
        $names[] = $item[0];
    }
}
printf(
    "max value: %d\ntotal weight: %d\nitems: %s\n",
    $table[count($items)][$capacity],
    $capacity - $remaining,
    implode(' ', $names),
);
