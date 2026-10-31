<?php

function vcgPayments(array $items, array $reserves, array $bids, object $optimal, array $names): array
{
    $result = [];
    foreach ($names as $name) {
        $winning = array_filter($optimal->winning, fn($b) => $b->bidder === $name);
        if (!$winning)
            continue;
        $alternative = solveWDP(
            $items,
            $reserves,
            array_values(array_filter($bids, fn($b) => $b->bidder !== $name)),
        );
        $value = array_sum(array_map(fn($b) => $b->amount, $winning));
        $result[$name] = [$alternative->welfare - ($optimal->welfare - $value), $alternative];
    }
    return $result;
}

function criticalPayments(array $order, array $winning, array $reserves): array
{
    $results = [];
    foreach ($winning as $b) {
        $rival = null;
        foreach (greedySelect(array_values(array_filter($order, fn($c) => $c->number !== $b->number))) as $c)
            if ($b->bundle & $c->bundle || $b->xor && $b->bidder === $c->bidder) {
                $rival = $c;
                break;
            }
        $payment = bundleReserve($b->bundle, $reserves);
        if ($rival !== null) {
            $threshold = $rival->amount * $rival->amount * $b->size;
            $earlier = fn($n) => (
                ($n * $n * $rival->size) > $threshold
                || ($n * $n * $rival->size) === $threshold
                && $b->number < $rival->number
            );
            $lo = $hi = 1;
            while (!$earlier($hi))
                $hi *= 2;
            while ($lo < $hi) {
                $middle = intdiv($lo + $hi, 2);
                if ($earlier($middle))
                    $hi = $middle;
                else
                    $lo = $middle + 1;
            }
            $payment = max($payment, $lo);
        }
        $results[$b->number] = [$payment, $rival];
    }
    return $results;
}

function coalitionWelfares(array $items, array $reserves, array $bids, array $names): array
{
    $subsets = [];
    for ($mask = 0; $mask < (1 << count($names)); ++$mask) {
        $positions = [];
        foreach ($names as $i => $name)
            if ($mask & (1 << $i))
                $positions[] = $i;
        $subsets[] = [$mask, $positions];
    }
    usort($subsets, fn($a, $b) => count($a[1]) <=> count($b[1]) ?: lexCompare($a[1], $b[1]));
    $result = [];
    foreach ($subsets as [$mask, $positions]) {
        $members = array_map(fn($i) => $names[$i], $positions);
        $allocation = solveWDP(
            $items,
            $reserves,
            array_values(array_filter($bids, fn($b) => in_array($b->bidder, $members, true))),
        );
        $result[] = (object) [
            'members' => $members,
            'mask' => $mask,
            'welfare' => $allocation->welfare,
            'numbers' => $allocation->numbers,
        ];
    }
    return $result;
}

function blockingCoalitions(array $coalitions, int $seller, array $utilities): array
{
    $blocking = $minimal = [];
    foreach ($coalitions as $c) {
        $payoff = $seller + array_sum(array_map(fn($name) => $utilities[$name], $c->members));
        if ($c->welfare > $payoff) {
            $record = (object) ['coalition' => $c, 'payoff' => $payoff, 'deficit' => $c->welfare - $payoff];
            if (!array_any($blocking, fn($r) => ($r->coalition->mask & $c->mask) === $r->coalition->mask))
                $minimal[] = $record;
            $blocking[] = $record;
        }
    }
    return [$blocking, $minimal];
}

function gspPrice(array $ranking, int $rank): int
{
    return $ranking[$rank + 1]['bid'] ?? 0;
}

function slotVCGPayment(array $ranking, array $rates, int $rank): Rational
{
    $payment = new Rational();
    for ($t = $rank + 1; $t < min(count($ranking), count($rates) + 1); ++$t)
        $payment = $payment->add($rates[$t - 1]->sub($rates[$t] ?? 0)->mul($ranking[$t]['value']));
    return $payment;
}
