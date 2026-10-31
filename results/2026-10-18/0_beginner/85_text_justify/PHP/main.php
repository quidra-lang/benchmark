<?php

$paragraph = 'Good software is written for people first and for machines second. A clear program explains its purpose through careful names, small functions and honest tests. When a team agrees on shared rules for internationalization, documentation and code review, every newcomer can read the code quickly, change it safely and ship new improvements with confidence instead of fear, week after week.';
$lines = [];
$current = [];
$letters = 0;
foreach (explode(' ', $paragraph) as $word) {
    if ($current && $letters + count($current) + strlen($word) > 30) {
        $lines[] = $current;
        $current = [];
        $letters = 0;
    }
    $current[] = $word;
    $letters += strlen($word);
}
$lines[] = $current;
foreach ($lines as $number => $words) {
    if ($number === count($lines) - 1 || count($words) === 1) {
        $line = str_pad(implode(' ', $words), 30, ' ');
    } else {
        $spaces = 30 - array_sum(array_map('strlen', $words));
        $gaps = count($words) - 1;
        $base = intdiv($spaces, $gaps);
        $extra = $spaces % $gaps;
        $line = $words[0];
        for ($i = 0; $i < $gaps; $i++) {
            $line .= str_repeat(' ', $base + ($i < $extra ? 1 : 0)) . $words[$i + 1];
        }
    }
    echo '|', $line, "|\n";
}
