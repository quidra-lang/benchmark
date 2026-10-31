<?php

$monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
    'October', 'November', 'December',
];
foreach ([[2024, 2], [2026, 8], [2026, 11]] as $index => [$year, $month]) {
    if ($index > 0) {
        echo "\n";
    }
    printf("%s %d\nSu Mo Tu We Th Fr Sa\n", $monthNames[$month - 1], $year);
    $adjustedYear = $month < 3 ? $year - 1 : $year;
    $adjustedMonth = $month < 3 ? $month + 12 : $month;
    $century = intdiv($adjustedYear, 100);
    $within = $adjustedYear % 100;
    $weekday = (1 + intdiv(13 * ($adjustedMonth + 1), 5) + $within + intdiv($within, 4)
        + intdiv($century, 4) + 5 * $century + 6) % 7;
    $leap = $year % 4 === 0 && ($year % 100 !== 0 || $year % 400 === 0);
    $days = $month === 2 && $leap ? 29 : [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][$month - 1];
    $fields = array_fill(0, $weekday, '  ');
    for ($day = 1; $day <= $days; $day++) {
        $fields[] = sprintf('%2d', $day);
        if (count($fields) === 7 || $day === $days) {
            echo implode(' ', $fields), "\n";
            $fields = [];
        }
    }
}
