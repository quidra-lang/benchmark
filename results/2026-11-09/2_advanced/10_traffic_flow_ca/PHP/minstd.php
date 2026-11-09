<?php
final class Minstd {
    public function __construct(private int $state) {}
    public function draw(): int { return $this->state = 48271 * $this->state % 2147483647; }
}
function selectWeighted(array $weights, int $value): int {
    $remainder = $value % array_sum($weights); $total = 0; foreach ($weights as $index => $weight) { $total += $weight; if ($remainder < $total) return $index; }
}
