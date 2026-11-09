<?php
function coupon_schedule(int $issue, int $maturity, int $frequency, bool $eom, bool $long): array {
    [$year, $month, $day] = civil_date($maturity);
    $eom = $eom && $day === month_length($year, $month);
    $dates = []; $boundary = $maturity;
    while ($boundary > $issue) {
        $dates[] = $boundary;
        $index = $year * 12 + $month - 1 - intdiv(12, $frequency) * count($dates);
        $y = intdiv($index, 12); $m = $index % 12 + 1;
        $boundary = day_number($y, $m, $eom ? month_length($y, $m) : min($day, month_length($y, $m)));
    }
    if ($long && $boundary !== $issue && count($dates) >= 2) array_pop($dates);
    $dates[] = $issue;
    return array_reverse($dates);
}
