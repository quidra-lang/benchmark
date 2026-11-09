<?php
class WorkCenter {
    public string $id, $description;
    public int $minutes, $efficiency, $available;
    public function __construct(array $fields) { $this->id = $fields[0]; $this->minutes = (int)$fields[1]; $this->efficiency = (int)$fields[2]; $this->description = $fields[3]; $this->available = intdiv($this->minutes * $this->efficiency, 100); }
}
class Operation {
    public string $item, $center;
    public int $number, $setup, $run;
    public function __construct(array $fields) { $this->item = $fields[0]; $this->number = (int)$fields[1]; $this->center = $fields[2]; $this->setup = (int)$fields[3]; $this->run = (int)$fields[4]; }
    public function minutes(int $quantity): int { return $this->setup + $quantity * $this->run; }
}
function read_centers(array &$errors): array {
    $centers = [];
    foreach (read_rows('workcenters.csv') as [$number, $fields]) {
        $id = $fields[0]; $efficiency = (int)$fields[2];
        $reason = isset($centers[$id]) ? "duplicate center $id" : ($efficiency < 50 || $efficiency > 150 ? "bad efficiency $efficiency" : null);
        if ($reason !== null) $errors[] = "workcenters.csv line $number: $reason"; else $centers[$id] = new WorkCenter($fields);
    }
    return $centers;
}
function read_routings(array $items, array $centers, Bom $bom, array &$errors): array {
    $routings = [];
    foreach (read_rows('routings.csv') as [$number, $fields]) {
        $operation = new Operation($fields); $id = $operation->item; $center = $operation->center; $reason = null;
        if (!isset($items[$id])) $reason = "unknown item $id";
        elseif (!isset($centers[$center])) $reason = "unknown center $center";
        elseif (!$bom->manufactured($id)) $reason = "purchased item $id";
        elseif ($operation->run < 1) $reason = "bad run time $operation->run";
        elseif (count(array_filter($routings[$id] ?? [], fn($other) => $other->number === $operation->number)) > 0) $reason = "duplicate $id operation $operation->number";
        if ($reason !== null) $errors[] = "routings.csv line $number: $reason"; else $routings[$id][] = $operation;
    }
    foreach ($routings as $id => $operations) { usort($operations, fn($a, $b) => $a->number <=> $b->number); $routings[$id] = $operations; }
    return $routings;
}
function operation_week(int $receipt, int $lead, int $index, int $count): int { return max($receipt - $lead + intdiv($index * $lead, $count), 1); }
function level_loads(array $loads, int $available): array {
    $leveled = array_fill(0, count($loads), 0); $carry = 0;
    for ($week = count($loads) - 1; $week >= 2; $week--) { $total = $loads[$week] + $carry; $leveled[$week] = min($total, $available); $carry = $total - $leveled[$week]; }
    $leveled[1] = $loads[1] + $carry;
    return $leveled;
}
