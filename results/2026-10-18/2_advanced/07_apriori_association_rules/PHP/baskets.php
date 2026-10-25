<?php
class Product {
    public function __construct(public string $name, public string $category, public int $price) {}
}
class Transaction {
    public array $counts = [];
    public function __construct(public string $tid, public string $customer, public int $day) {}
    public function add(string $product): bool { $duplicate = isset($this->counts[$product]); $this->counts[$product] = ($this->counts[$product] ?? 0) + 1; return $duplicate; }
    public function products(): array { $names = array_keys($this->counts); sort($names,SORT_STRING); return $names; }
    public function units(): int { return array_sum($this->counts); }
}
function read_records(string $name): array { return array_map(fn($line) => explode(',',$line),array_slice(file("input/$name",FILE_IGNORE_NEW_LINES),1)); }
function contains(array $basket, array $itemset): bool { foreach ($itemset as $item) if (!isset($basket[$item])) return false; return true; }
function extended_basket(array $products, array $taxonomy): array { $set = array_fill_keys($products,true); foreach ($products as $product) $set[$taxonomy[$product]] = true; return $set; }
function set_key(array $items): string { return implode('+',$items); }
function compare_sets(array $first, array $second): int { foreach ($first as $i => $item) { if (!isset($second[$i])) return 1; $comparison = strcmp($item,$second[$i]); if ($comparison !== 0) return $comparison; } return count($first) <=> count($second); }
function size_order(array $first, array $second): int { return (count($first) <=> count($second)) ?: compare_sets($first,$second); }
