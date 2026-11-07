<?php

function auctionCandidates(array $bids, bool $xor): array
{
    $result = [];
    for ($mask = 1; $mask < (1 << count($bids)); ++$mask) {
        if ($xor && bitCount($mask) !== 1)
            continue;
        $bundle = $value = 0;
        $valid = true;
        foreach ($bids as $i => $b)
            if ($mask & (1 << $i)) {
                if ($bundle & $b->bundle) {
                    $valid = false;
                    break;
                }
                $bundle |= $b->bundle;
                $value += $b->amount;
            }
        if ($valid)
            $result[] = ['number' => $mask, 'bundle' => $bundle, 'value' => $value];
    }
    return $result;
}

function valueOf(array $candidates, int $items): int
{
    $value = 0;
    foreach ($candidates as $c)
        if (($c['bundle'] & $items) === $c['bundle'])
            $value = max($value, $c['value']);
    return $value;
}

function englishAuction(array $participants, int $reserve, int $increment): object
{
    $price = $reserve;
    $steps = 0;
    $remaining = array_keys(array_filter($participants, fn($p) => $p['value'] >= $price));
    $winner = null;
    $paid = 0;
    while (count($remaining) >= 2) {
        $previous = $remaining;
        $price += $increment;
        ++$steps;
        $remaining = [];
        foreach ($previous as $i)
            if ($participants[$i]['value'] >= $price)
                $remaining[] = $i;
        if (!$remaining) {
            $winner = $previous[0];
            $paid = $price - $increment;
            break;
        }
    }
    if ($remaining) {
        $winner = $remaining[0];
        $paid = $price;
    }
    $drops = [];
    foreach ($participants as $p) {
        $drop = $p['value'] < $reserve
            ? $reserve
            : $reserve + ((intdiv($p['value'] - $reserve, $increment) + 1) * $increment);
        $drops[] = $drop <= $price ? $drop : null;
    }
    return (object) ['winner' => $winner, 'price' => $paid, 'steps' => $steps, 'drops' => $drops];
}

function dutchAuction(array $participants, int $reserve, int $start, int $decrement): object
{
    $price = $start;
    $steps = 0;
    while ($price >= $reserve) {
        $winner = null;
        foreach ($participants as $i => $p)
            if ($p['bid'] >= $price && ($winner === null || $p['bid'] > $participants[$winner]['bid']))
                $winner = $i;
        if ($winner !== null)
            return (object) ['winner' => $winner, 'price' => $price, 'steps' => $steps];
        $price -= $decrement;
        ++$steps;
    }
    return (object) ['winner' => null, 'price' => 0, 'steps' => $steps];
}
