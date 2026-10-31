<?php
const BP = 0.0001;
function bisection(callable $function, float $low, float $high, float $target): float {
    for ($step = 0; $step < 80; $step++) { $middle = ($low + $high) / 2; if ($function($middle) > $target) $low = $middle; else $high = $middle; }
    return ($low + $high) / 2;
}
class YieldPricer {
    public function __construct(public array $flows, public float $fraction, public int $frequency, public int $outstanding) {}
    public function values(float $rate): array {
        $first = 1 + $this->fraction * $rate / $this->frequency; $growth = 1 + $rate / $this->frequency; $factor = 1.0; $values = [];
        foreach ($this->flows as $flow) { $values[] = $flow / ($first * $factor); $factor *= $growth; }
        return $values;
    }
    public function dirty(float $rate): float { $sum = 0.0; foreach ($this->values($rate) as $value) $sum += $value; return $sum * 100 / $this->outstanding; }
    public function solve(float $target): float { return bisection(fn($rate) => $this->dirty($rate), 0.0, 1.0, $target); }
    public function inRange(float $target): bool { return $this->dirty(0.0) > $target && $target > $this->dirty(1.0); }
    public function risk(float $rate): array {
        $growth = 1 + $rate / $this->frequency; $total = $weighted = $curvature = 0.0;
        foreach ($this->values($rate) as $index => $value) { $years = ($index + $this->fraction) / $this->frequency; $total += $value; $weighted += $years * $value; $curvature += $years * ($years + 1 / $this->frequency) * $value; }
        $macaulay = $weighted / $total;
        return ['macaulay' => $macaulay, 'modified' => $macaulay / $growth, 'convexity' => $curvature / ($total * $growth * $growth), 'dv01' => ($this->dirty($rate - BP) - $this->dirty($rate + BP)) / 2];
    }
}
