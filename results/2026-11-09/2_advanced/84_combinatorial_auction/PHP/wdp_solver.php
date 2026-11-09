<?php

function bundleReserve(int $mask, array $reserves): int
{
    $sum = 0;
    foreach ($reserves as $i => $v)
        if ($mask & (1 << $i))
            $sum += $v;
    return $sum;
}

function shares(array $items, array $reserves, array $bids): array
{
    $result = [];
    foreach ($items as $i) {
        $share = new Rational($reserves[$i]);
        $source = null;
        foreach ($bids as $b)
            if ($b->bundle & (1 << $i)) {
                $candidate = new Rational($b->amount, $b->size);
                if ($candidate->cmp($share) > 0) {
                    $share = $candidate;
                    $source = $b->number;
                }
            }
        $result[] = [$i, $share, $source];
    }
    return $result;
}

function solveWDP(array $items, array $reserves, array $bids): object
{
    usort($bids, fn($a, $b) => $a->number <=> $b->number);
    $rootShares = shares($items, $reserves, $bids);
    $bound = new Rational();
    foreach ($rootShares as [$i, $s, $source])
        $bound = $bound->add($s);
    $result = (object) [
        'welfare' => null,
        'numbers' => [],
        'nodes' => 0,
        'pruned' => 0,
        'leaves' => 0,
        'improvements' => [],
        'shares' => $rootShares,
        'bound' => $bound,
        'winning' => [],
    ];
    $all = 0;
    foreach ($items as $i)
        $all |= 1 << $i;
    $visit = function (int $decided, array $used, int $welfare, array $chosen) use (
        &$visit,
        $items,
        $reserves,
        $bids,
        $result,
        $all,
    ): void {
        ++$result->nodes;
        if ($decided === $all) {
            ++$result->leaves;
            sort($chosen, SORT_NUMERIC);
            if (
                $result->welfare === null
                || $welfare > $result->welfare
                || $welfare === $result->welfare && lexCompare($chosen, $result->numbers) < 0
            ) {
                $result->welfare = $welfare;
                $result->numbers = $chosen;
                $result->improvements[] = [$result->nodes, $welfare, $chosen];
            }
            return;
        }
        $available = array_values(array_filter(
            $bids,
            fn($b) => !($b->bundle & $decided) && !($b->xor && isset($used[$b->bidder])),
        ));
        $remaining = array_values(array_filter($items, fn($i) => !($decided & (1 << $i))));
        $upper = new Rational($welfare);
        foreach (shares($remaining, $reserves, $available) as [$i, $share, $source])
            $upper = $upper->add($share);
        if ($result->welfare !== null && $upper->cmp($result->welfare) < 0) {
            ++$result->pruned;
            return;
        }
        $first = $remaining[0];
        foreach ($available as $b)
            if ($b->bundle & (1 << $first)) {
                $nextUsed = $used;
                if ($b->xor)
                    $nextUsed[$b->bidder] = true;
                $visit($decided | $b->bundle, $nextUsed, $welfare + $b->amount, [...$chosen, $b->number]);
            }
        $visit($decided | (1 << $first), $used, $welfare + $reserves[$first], $chosen);
    };
    $visit(0, [], 0, []);
    $byNumber = [];
    foreach ($bids as $b)
        $byNumber[$b->number] = $b;
    foreach ($result->numbers as $n)
        $result->winning[] = $byNumber[$n];
    return $result;
}

function greedyOrder(array $bids): array
{
    usort(
        $bids,
        fn($a, $b) => (
            ($b->amount * $b->amount * $a->size) <=> ($a->amount * $a->amount * $b->size)
            ?: $a->number <=> $b->number
        ),
    );
    return $bids;
}

function greedySelect(array $bids): array
{
    $occupied = 0;
    $used = $chosen = [];
    foreach ($bids as $b)
        if (!($b->bundle & $occupied) && !($b->xor && isset($used[$b->bidder]))) {
            $chosen[] = $b;
            $occupied |= $b->bundle;
            if ($b->xor)
                $used[$b->bidder] = true;
        }
    return $chosen;
}
