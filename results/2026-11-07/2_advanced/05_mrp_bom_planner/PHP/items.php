<?php
function read_rows(string $name): array {
    $lines = explode("\n", file_get_contents("input/$name")); array_pop($lines); $result = [];
    foreach (array_slice($lines, 1) as $index => $line) $result[] = [$index + 2, explode(',', $line)];
    return $result;
}
class Item {
    public string $id, $rule, $description;
    public int $lead, $safety, $onHand, $material, $labor;
    public function __construct(array $fields, public array $lot) {
        $this->id = $fields[0]; $this->lead = (int)$fields[1]; $this->rule = $fields[2]; $this->safety = (int)$fields[4];
        $this->onHand = (int)$fields[5]; $this->material = (int)$fields[6]; $this->labor = (int)$fields[7]; $this->description = $fields[8];
    }
    public function lotLabel(): string { return $this->rule === 'LFL' ? 'LFL' : $this->rule . ' ' . implode($this->rule === 'MIN' ? '/' : '', $this->lot); }
}
function lot_values(string $rule, string $text): ?array {
    $values = array_map('intval', explode('/', $text));
    $valid = $rule === 'MIN' ? count($values) === 2 && min($values) >= 1 : count($values) === 1 && ($rule === 'LFL' ? $values[0] === 0 : $values[0] >= 1);
    return $valid ? $values : null;
}
function read_items(array &$errors): array {
    $items = [];
    foreach (read_rows('items.csv') as [$number, $fields]) {
        [$id, , $rule, $lot] = $fields;
        $reason = isset($items[$id]) ? "duplicate item $id" : (!in_array($rule, ['LFL', 'FOQ', 'POQ', 'MIN'], true) ? "unknown lot rule $rule" : (lot_values($rule, $lot) === null ? "bad lot parameter $lot for $rule" : null));
        if ($reason !== null) $errors[] = "items.csv line $number: $reason";
        else $items[$id] = new Item($fields, lot_values($rule, $lot));
    }
    return $items;
}
