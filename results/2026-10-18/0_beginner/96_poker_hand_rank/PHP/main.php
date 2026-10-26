<?php

function describeHand(string $original): array
{
    $cards = explode(' ', $original);
    $frequencies = array_count_values(array_map(fn($card) => strpos('23456789TJQKA', $card[0]) + 2, $cards));
    $distinct = array_keys($frequencies);
    sort($distinct, SORT_NUMERIC);
    $wheel = $distinct === [2, 3, 4, 5, 14];
    $straight = count($distinct) === 5 && (max($distinct) - min($distinct) === 4 || $wheel);
    $flush = count(array_unique(array_map(fn($card) => $card[1], $cards))) === 1;
    $counts = $frequencies;
    rsort($counts, SORT_NUMERIC);
    $strength = match (true) {
        $straight && $flush => 9,
        $counts[0] === 4 => 8,
        $counts === [3, 2] => 7,
        $flush => 6,
        $straight => 5,
        $counts[0] === 3 => 4,
        $counts === [2, 2, 1] => 3,
        $counts[0] === 2 => 2,
        default => 1,
    };
    usort($distinct, fn($a, $b) => ($frequencies[$b] <=> $frequencies[$a]) ?: ($b <=> $a));
    if ($wheel && $straight) {
        $distinct = [5, 4, 3, 2, 1];
    }
    $categories = [
        'high card', 'one pair', 'two pair', 'three of a kind', 'straight', 'flush', 'full house',
        'four of a kind', 'straight flush',
    ];
    return [
        'original' => $original,
        'strength' => $strength,
        'sequence' => $distinct,
        'category' => $categories[$strength - 1],
    ];
}

$originals = [
    '9C 9D 5H QH 2C', '4D AH 3C 5S 2H', 'KS 8S 2S JS 6S', '7H 7D KC 7S KD',
    '3H 6C 4S 2D 5C', 'JD TC 4H 8C AS', 'QC 6D QS 3S 6H', '9H KH 9S 8H 3D',
];
$hands = array_map('describeHand', $originals);
usort($hands, fn($a, $b) => ($b['strength'] <=> $a['strength']) ?: ($b['sequence'] <=> $a['sequence']));
foreach ($hands as $position => $hand) {
    printf("%d. %s: %s\n", $position + 1, $hand['original'], $hand['category']);
}
