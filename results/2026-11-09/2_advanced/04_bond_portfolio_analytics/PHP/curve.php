<?php
class ZeroCurve {
    public function __construct(public array $days, public array $rates) {}
    public function zero(int $day): float {
        if ($day <= $this->days[0]) return $this->rates[0];
        $last = count($this->days) - 1;
        if ($day >= $this->days[$last]) return $this->rates[$last];
        $index = 1; while ($this->days[$index] < $day) $index++;
        $low = $this->days[$index - 1];
        return $this->rates[$index - 1] + ($this->rates[$index] - $this->rates[$index - 1]) * (($day - $low) / ($this->days[$index] - $low));
    }
    public function discount(int $day, float $spread = 0.0): float {
        $rate = $this->zero($day) + $spread; $growth = 1.0;
        for ($year = 0; $year < intdiv($day, 365); $year++) $growth *= 1 + $rate;
        return 1 / ($growth * (1 + $rate * ($day % 365) / 365));
    }
    public function forward(int $start, int $end): float { return ($this->discount($start) / $this->discount($end) - 1) * 365 / ($end - $start); }
    public function shifted(array $deltas): self { $rates = []; foreach ($this->rates as $index => $rate) $rates[] = $rate + $deltas[$index]; return new self($this->days, $rates); }
    public function presentValue(array $flows, float $spread = 0.0): float { $sum = 0.0; foreach ($flows as [$day, $flow]) $sum += $flow * $this->discount($day, $spread); return $sum; }
}
function bootstrap(int $settlement, array $pillars): ZeroCurve {
    $days = $rates = [];
    foreach ($pillars as [$maturity, $coupon, $frequency]) {
        $dates = coupon_schedule($settlement, $maturity, $frequency, false, false); $flows = [];
        for ($index = 1; $index < count($dates); $index++) {
            [$n, $m] = year_fraction('30/360', $dates[$index - 1], $dates[$index]);
            $flow = $coupon * $n / (10000 * $m);
            if ($index === count($dates) - 1) $flow += 1;
            $flows[] = [$dates[$index] - $settlement, $flow];
        }
        $days[] = $maturity - $settlement;
        $rates[] = bisection(fn($trial) => (new ZeroCurve($days, [...$rates, $trial]))->presentValue($flows), 0.0, 1.0, 1.0);
    }
    return new ZeroCurve($days, $rates);
}
function z_spread(ZeroCurve $curve, array $flows, int $target): float { return bisection(fn($spread) => $curve->presentValue($flows, $spread), -0.5, 0.5, (float)$target); }
