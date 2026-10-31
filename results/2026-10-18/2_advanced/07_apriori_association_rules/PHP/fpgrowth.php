<?php
class FPNode {
    public int $count = 0;
    public array $children = [];
    public function __construct(public ?string $item, public ?int $parent) {}
}
class FPTree {
    public array $header, $nodes = [], $links = [];
    public function __construct(array $base, int $minimum) {
        $supports = [];
        foreach ($base as [$items,$weight]) foreach ($items as $item) $supports[$item] = ($supports[$item] ?? 0) + $weight;
        $this->header = array_keys(array_filter($supports,fn($count) => $count >= $minimum)); usort($this->header,fn($a,$b) => ($supports[$b] <=> $supports[$a]) ?: strcmp($a,$b));
        $order = array_flip($this->header); $this->nodes[] = new FPNode(null,null); foreach ($this->header as $item) $this->links[$item] = [];
        foreach ($base as [$items,$weight]) {
            $path = array_values(array_filter($items,fn($item) => isset($order[$item]))); usort($path,fn($a,$b) => $order[$a] <=> $order[$b]); $node = 0;
            foreach ($path as $item) {
                if (!isset($this->nodes[$node]->children[$item])) { $index = count($this->nodes); $this->nodes[] = new FPNode($item,$node); $this->nodes[$node]->children[$item] = $index; $this->links[$item][] = $index; }
                $node = $this->nodes[$node]->children[$item]; $this->nodes[$node]->count += $weight;
            }
        }
    }
    public function support(string $item): int { $total = 0; foreach ($this->links[$item] as $index) $total += $this->nodes[$index]->count; return $total; }
    public function conditionalBase(string $item): array {
        $base = [];
        foreach ($this->links[$item] as $index) { $path = []; $ancestor = $this->nodes[$index]->parent; while ($ancestor !== 0) { $path[] = $this->nodes[$ancestor]->item; $ancestor = $this->nodes[$ancestor]->parent; } $base[] = [array_reverse($path),$this->nodes[$index]->count]; }
        return $base;
    }
}
function fp_growth(array $base, int $minimum, int $maxSize): array {
    $tree = new FPTree($base,$minimum); $result = ['header' => count($tree->header),'nodes' => count($tree->nodes) - 1,'conditionalTrees' => 0,'conditionalNodes' => 0,'itemsets' => []]; $stack = [[$tree,[]]];
    while ($stack) {
        [$current,$suffix] = array_pop($stack);
        foreach (array_reverse($current->header) as $item) {
            $items = [...$suffix,$item]; sort($items,SORT_STRING); $result['itemsets'][set_key($items)] = [$items,$current->support($item)];
            if (count($items) < $maxSize) { $conditional = new FPTree($current->conditionalBase($item),$minimum); if (count($conditional->nodes) > 1) { $stack[] = [$conditional,$items]; $result['conditionalTrees']++; $result['conditionalNodes'] += count($conditional->nodes) - 1; } }
        }
    }
    return $result;
}
