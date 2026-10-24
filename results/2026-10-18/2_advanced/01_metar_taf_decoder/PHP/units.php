<?php
function divfloor(int $a, int $b): int {
    $q = intdiv($a, $b);
    return $q - ($a < 0 && $a % $b !== 0 ? 1 : 0);
}

function sine(int $x): int {
    $s = [0, 174, 342, 500, 643, 766, 866, 940, 985, 1000];
    $y = ($x % 360 + 360) % 360;
    if ($y <= 90) return $s[intdiv($y, 10)];
    if ($y <= 180) return $s[intdiv(180 - $y, 10)];
    if ($y <= 270) return - $s[intdiv($y - 180, 10)];
    return - $s[intdiv(360 - $y, 10)];
}

function cosine(int $x): int {
    return sine($x + 90);
}

function knots(int $v): int {
    return intdiv($v * 1944 + 500, 1000);
}

function inhg(int $v): int {
    return intdiv($v * 2953 + 500, 1000);
}

function hpa(int $v): int {
    return intdiv($v * 33864 + 50000, 100000);
}

function miles(array $v): array {
    return $v['kind'] === 'miles' ? [$v['whole'] * $v['den'] + $v['num'], $v['den']] : [1000 * $v['value'], 1609344];
}

function meters(array $v): int {
    [$n, $d] = miles($v);
    return $v['kind'] === 'miles' ? intdiv(1609344 * $n, 1000 * $d) : $v['value'];
}

function fraction(int $n, int $d): string {
    if (!$d) return 'undefined';
    $a = abs($n);
    $b = $d;
    while ($b) {
        $r = $a % $b;
        $a = $b;
        $b = $r;
    }
    return intdiv($n, $a) . '/' . intdiv($d, $a);
}

function monthdays(int $y, int $m): int {
    if ($m === 2) return $y % 400 === 0 || ($y % 4 === 0 && $y % 100 !== 0) ? 29 : 28;
    return in_array($m, [4, 6, 9, 11], true) ? 30 : 31;
}

class Calendar {
    public int $days;
    private int $nextYear;
    private int $nextMonth;
    public function __construct(private int $year, private int $month) {
        $this->days = monthdays($year, $month);
        $this->nextYear = $year + ($month === 12 ? 1 : 0);
        $this->nextMonth = $month === 12 ? 1 : $month + 1;
    }
    public function reportTime(string $s): ?int {
        if (!preg_match('/\A(\d{2})(\d{2})(\d{2})Z\z/', $s, $m)) return null;
        [$d, $h, $n] = array_map('intval', array_slice($m, 1));
        return $d >= 1 && $d <= $this->days && $h <= 23 && $n <= 59 ? (($d - 1) * 24 + $h) * 60 + $n : null;
    }
    public function dayTime(int $d, int $h, int $n, int $issue): ?int {
        $next = $d < $issue;
        if ($d < 1 || $d > ($next ? monthdays($this->nextYear, $this->nextMonth) : $this->days)) return null;
        return ($next ? $this->days * 1440 : 0) + (($d - 1) * 24 + $h) * 60 + $n;
    }
    public function period(string $s, int $issue, ?int $limit = null): ?array {
        if (!preg_match('/\A(\d{2})(\d{2})\/(\d{2})(\d{2})\z/', $s, $m)) return null;
        [$d, $h, $e, $j] = array_map('intval', array_slice($m, 1));
        if ($h > 23 || $j < 1 || $j > 24) return null;
        $a = $this->dayTime($d, $h, 0, $issue);
        $b = $this->dayTime($e, $j, 0, $issue);
        return $a !== null && $b !== null && $a < $b && ($limit === null || $b <= $a + $limit) ? [$a, $b] : null;
    }
    public function stamp(int $t): string {
        $y = $this->year;
        $m = $this->month;
        if ($t >= $this->days * 1440) {
            $t -= $this->days * 1440;
            $y = $this->nextYear;
            $m = $this->nextMonth;
        }
        return sprintf('%04d-%02d-%02dT%02d:%02dZ', $y, $m, intdiv($t, 1440) + 1, intdiv($t % 1440, 60), $t % 60);
    }
}
