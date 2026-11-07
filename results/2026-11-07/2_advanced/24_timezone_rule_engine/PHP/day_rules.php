<?php
declare(strict_types=1);

namespace TimezoneRules;

const MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const WEEKDAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const COMMON_MONTH_DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
const NEG_INFINITY = -4611686018427387904;
const POS_INFINITY = 4611686018427387904;
const SECONDS_PER_DAY = 86400;

function floorDiv(int $value, int $divisor): int { return intdiv($value, $divisor) - (int)($value < 0 && $value % $divisor !== 0); }
function floorMod(int $value, int $divisor): int { return $value - $divisor * floorDiv($value, $divisor); }
function isLeapYear(int $year): bool { return $year % 4 === 0 && $year % 100 !== 0 || $year % 400 === 0; }
function daysInMonth(int $year, int $month): int { return $month === 2 && isLeapYear($year) ? 29 : COMMON_MONTH_DAYS[$month - 1]; }

function daysBeforeYear(int $year): int
{
    $previous = $year - 1;
    return $previous * 365 + floorDiv($previous, 4) - floorDiv($previous, 100) + floorDiv($previous, 400);
}

function dayNumber(int $year, int $month, int $day): int
{
    $days = daysBeforeYear($year) - daysBeforeYear(1970) + $day - 1;
    for ($earlier = 1; $earlier < $month; $earlier++) {
        $days += daysInMonth($year, $earlier);
    }
    return $days;
}

function weekdayOf(int $number): int { return floorMod($number + 4, 7); }

function dateOfDay(int $number): array
{
    $year = 1970 + floorDiv($number, 366);
    while (dayNumber($year, 1, 1) > $number) {
        $year--;
    }
    while (dayNumber($year + 1, 1, 1) <= $number) {
        $year++;
    }
    $month = 1;
    $day = $number - dayNumber($year, 1, 1) + 1;
    while ($day > daysInMonth($year, $month)) {
        $day -= daysInMonth($year, $month);
        $month++;
    }
    return [$year, $month, $day];
}

function timeValue(int $year, int $month, int $day, int $hour, int $minute, int $second): int
{
    return dayNumber($year, $month, $day) * 86400 + $hour * 3600 + $minute * 60 + $second;
}

function splitTime(int $time): array
{
    [$year, $month, $day] = dateOfDay(floorDiv($time, 86400));
    $seconds = floorMod($time, 86400);
    return [$year, $month, $day, intdiv($seconds, 3600), intdiv($seconds, 60) % 60, $seconds % 60];
}

final class DaySpec
{
    public function __construct(public string $kind, public int $weekday, public int $day) {}

    public function value(int $year, int $month): int
    {
        if ($this->kind === 'last') {
            $last = dayNumber($year, $month, daysInMonth($year, $month));
            return $last - floorMod(weekdayOf($last) - $this->weekday, 7);
        }
        $base = dayNumber($year, $month, $this->day);
        return match ($this->kind) {
            'after' => $base + floorMod($this->weekday - weekdayOf($base), 7),
            'before' => $base - floorMod(weekdayOf($base) - $this->weekday, 7),
            default => $base,
        };
    }
}
