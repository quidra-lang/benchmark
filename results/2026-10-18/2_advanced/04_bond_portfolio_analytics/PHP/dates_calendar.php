<?php
const BUSINESS_DAY_RULES = ['FOLLOWING', 'MODIFIED_FOLLOWING', 'PRECEDING', 'UNADJUSTED'];
function is_leap(int $year): bool { return $year % 4 === 0 && ($year % 100 !== 0 || $year % 400 === 0); }
function month_length(int $year, int $month): int { return $month === 2 && is_leap($year) ? 29 : [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][$month - 1]; }
function split_date(string $text): array { return [(int)substr($text, 0, 4), (int)substr($text, 5, 2), (int)substr($text, 8, 2)]; }
function valid_date(string $text): bool {
    [$year, $month, $day] = split_date($text);
    return $year >= 2001 && $year <= 2099 && $month >= 1 && $month <= 12 && $day >= 1 && $day <= month_length($year, $month);
}
function day_number(int $year, int $month, int $day): int {
    $number = $day - 1;
    for ($earlier = 2000; $earlier < $year; $earlier++) $number += is_leap($earlier) ? 366 : 365;
    for ($earlier = 1; $earlier < $month; $earlier++) $number += month_length($year, $earlier);
    return $number;
}
function parse_date(string $text): int { return day_number(...split_date($text)); }
function civil_date(int $number): array {
    $year = 2000;
    while ($number >= ($days = is_leap($year) ? 366 : 365)) { $number -= $days; $year++; }
    $month = 1;
    while ($number >= month_length($year, $month)) $number -= month_length($year, $month++);
    return [$year, $month, $number + 1];
}
function format_date(int $number): string { return sprintf('%04d-%02d-%02d', ...civil_date($number)); }
class Calendar {
    private array $holidays;
    public function __construct(array $holidays) { $this->holidays = array_fill_keys($holidays, true); }
    public function business(int $day): bool { return ($day + 5) % 7 < 5 && !isset($this->holidays[$day]); }
    public function following(int $day): int { while (!$this->business($day)) $day++; return $day; }
    public function preceding(int $day): int { while (!$this->business($day)) $day--; return $day; }
    public function adjust(int $day, string $rule): int {
        if ($rule === 'FOLLOWING') return $this->following($day);
        if ($rule === 'PRECEDING') return $this->preceding($day);
        if ($rule === 'MODIFIED_FOLLOWING') { $next = $this->following($day); return civil_date($next)[1] === civil_date($day)[1] ? $next : $this->preceding($day); }
        return $day;
    }
    public function move(int $day, int $count): int {
        $direction = $count < 0 ? -1 : 1;
        if ($count < 0) $count = -$count;
        while ($count > 0) { $day += $direction; if ($this->business($day)) $count--; }
        return $day;
    }
}
