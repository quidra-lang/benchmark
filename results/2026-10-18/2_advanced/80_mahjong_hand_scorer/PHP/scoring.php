<?php

namespace Scoring;

function tripletFu(array $block, bool $concealed, bool $kan): array
{
    [$type, $value] = $kan
        ? ($concealed ? ['closed_kan', 16] : ['open_kan', 8])
        : ($concealed ? ['closed_triplet', 4] : ['open_triplet', 2]);
    return [$type . ' ' . \Tiles\block($block), $value * (\Tiles\yaochuu($block[0]) ? 2 : 1)];
}

function fuBreakdown(
    string $form,
    ?int $pair,
    array $triplets,
    string $wait,
    bool $closed,
    string $method,
    int $seat,
    int $round,
    bool $pinfu,
): array {
    if ($form === 'chiitoitsu')
        return [[['chiitoitsu', 25]], 25, 25];
    $items = [['base', 20]];
    if ($closed && $method === 'ron')
        $items[] = ['closed_ron', 10];
    if ($method === 'tsumo' && !$pinfu)
        $items[] = ['tsumo', 2];
    $value = 2 * ((int) ($pair >= 31) + (int) ($pair === $seat) + (int) ($pair === $round));
    if ($value)
        $items[] = ['pair ' . \Tiles\block([$pair, $pair]), $value];
    foreach ($triplets as [$block, $hidden, $kan])
        $items[] = tripletFu($block, $hidden, $kan);
    if (in_array($wait, ['kanchan', 'penchan', 'tanki'], true))
        $items[] = ['wait ' . $wait, 2];
    $total = array_sum(array_column($items, 1));
    if (!$closed && $total === 20) {
        $items[] = ['open_pinfu', 10];
        $total += 10;
    }
    return [$items, $total, intdiv($total + 9, 10) * 10];
}

function limit(int $han, int $fu, array $rules): array
{
    if ($han >= 13 && $rules['kazoe_yakuman'])
        return ['kazoe_yakuman', 8000];
    if ($han >= 11)
        return ['sanbaiman', 6000];
    if ($han >= 8)
        return ['baiman', 4000];
    if ($han >= 6)
        return ['haneman', 3000];
    $base = $fu * (1 << ($han + 2));
    return (
        $han === 5 || $base >= 2000 || $rules['kiriage'] && $base === 1920
            ? ['mangan', 2000]
            : ['none', $base]
    );
}

function roundHundred(int $value): int
{
    return intdiv($value + 99, 100) * 100;
}

function payments(int $base, bool $dealer, string $method): array
{
    if ($method === 'ron') {
        $ron = roundHundred($base * ($dealer ? 6 : 4));
        return [$ron, 0, 0, $ron];
    }
    if ($dealer) {
        $payment = roundHundred($base * 2);
        return [0, 0, $payment, $payment * 3];
    }
    $east = roundHundred($base * 2);
    $other = roundHundred($base);
    return [0, $east, $other, $east + (2 * $other)];
}
