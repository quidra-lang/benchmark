<?php
function zones(array $limits): array {
    [$lcl,$cl,$ucl] = $limits; $a = ($ucl - $cl) / 3; $b = ($cl - $lcl) / 3;
    return [$lcl,$cl,$ucl,$cl + $a,$cl + 2 * $a,$cl - $b,$cl - 2 * $b];
}
function rule_direction(int $rule, array $window, array $zone): ?string {
    [$lcl,$cl,$ucl,$u1,$u2,$l1,$l2] = $zone; $last = $window[count($window) - 1];
    if ($rule === 1) return $last > $ucl || $last < $lcl ? ($last > $cl ? 'UP' : 'DOWN') : null;
    if ($rule === 2 || $rule === 3) {
        $upper = $rule === 2 ? $u2 : $u1; $lower = $rule === 2 ? $l2 : $l1; $needed = $rule === 2 ? 2 : 4;
        if ($last > $upper && count(array_filter($window, fn($v) => $v > $upper)) >= $needed) return 'UP';
        if ($last < $lower && count(array_filter($window, fn($v) => $v < $lower)) >= $needed) return 'DOWN';
    } elseif ($rule === 4) {
        if (count(array_filter($window, fn($v) => $v > $cl)) === count($window)) return 'UP';
        if (count(array_filter($window, fn($v) => $v < $cl)) === count($window)) return 'DOWN';
    } elseif ($rule === 5 || $rule === 6) {
        $differences = []; for ($i = 1; $i < count($window); $i++) $differences[] = $window[$i] - $window[$i - 1];
        if ($rule === 5) { if (min($differences) > 0) return 'UP'; if (max($differences) < 0) return 'DOWN'; }
        else { if (in_array(0, $differences)) return null; for ($i = 1; $i < count($differences); $i++) if (($differences[$i] > 0) === ($differences[$i - 1] > 0)) return null; return 'NONE'; }
    } elseif ($rule === 7) { if (count(array_filter($window, fn($v) => $l1 < $v && $v < $u1)) === count($window)) return 'NONE'; }
    elseif ($rule === 8 && count(array_filter($window, fn($v) => $v > $u1 || $v < $l1)) === count($window) && max($window) > $u1 && min($window) < $l1) return 'NONE';
    return null;
}
function check_rules(string $chart, array $numbers, array $values, array $limits, array $rules): array {
    $lengths = [1 => 1,3,5,8,6,14,15,8]; $zone = zones($limits); $signals = [];
    for ($k = 1; $k <= count($values); $k++) foreach ($rules as $rule) {
        $length = $lengths[$rule]; if ($k < $length) continue; $direction = rule_direction($rule, array_slice($values, $k - $length, $length), $zone);
        if ($direction !== null) $signals[] = ['chart' => $chart,'rule' => (string)$rule,'start' => $numbers[$k - $length],'end' => $numbers[$k - 1],'value' => $values[$k - 1],'direction' => $direction];
    }
    return $signals;
}
