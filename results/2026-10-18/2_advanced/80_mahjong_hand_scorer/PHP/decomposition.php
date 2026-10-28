<?php

namespace Decomposition;

function standard(array $counts, int $melds = 0): array
{
    static $cache = [];
    $key = implode(',', $counts) . ':' . $melds;
    if (isset($cache[$key]))
        return $cache[$key];
    $needed = 4 - $melds;
    if (array_sum($counts) !== (($needed * 3) + 2))
        return [];
    $found = [];
    $visit = function (int $pair, array $sets) use (&$visit, &$counts, &$found, $needed): void {
        if (count($sets) === $needed) {
            if (!array_sum($counts)) {
                usort($sets, fn($a, $b) => $a[0] <=> $b[0] ?: ($a[0] !== $a[2]) <=> ($b[0] !== $b[2]));
                $found[json_encode([$pair, $sets])] = [$pair, $sets];
            }
            return;
        }
        $first = null;
        foreach ($counts as $k => $n)
            if ($n) {
                $first = $k;
                break;
            }
        if ($first === null)
            return;
        if ($counts[$first] >= 3) {
            $counts[$first] -= 3;
            $visit($pair, [...$sets, [$first, $first, $first]]);
            $counts[$first] += 3;
        }
        if ($first < 27 && ($first % 9) <= 6 && $counts[$first + 1] && $counts[$first + 2]) {
            --$counts[$first];
            --$counts[$first + 1];
            --$counts[$first + 2];
            $visit($pair, [...$sets, [$first, $first + 1, $first + 2]]);
            ++$counts[$first];
            ++$counts[$first + 1];
            ++$counts[$first + 2];
        }
    };
    for ($pair = 0; $pair < 34; ++$pair)
        if ($counts[$pair] >= 2) {
            $counts[$pair] -= 2;
            $visit($pair, []);
            $counts[$pair] += 2;
        }
    return $cache[$key] = array_values($found);
}

function sevenPairs(array $counts): bool
{
    return (
        count(array_filter($counts, fn($n) => $n === 2)) === 7
        && !array_filter($counts, fn($n) => $n !== 0 && $n !== 2)
    );
}

function thirteenOrphans(array $counts): bool
{
    if (array_sum($counts) !== 14)
        return false;
    foreach ($counts as $k => $n)
        if (in_array($k, \Tiles\YAOCHUU, true) ? !$n : $n)
            return false;
    return true;
}

function winning(array $counts, int $melds = 0): bool
{
    return (bool) standard($counts, $melds) || !$melds && (sevenPairs($counts) || thirteenOrphans($counts));
}

function waitingTiles(array $hand, array $meldCounts, int $melds): array
{
    $result = [];
    for ($k = 0; $k < 34; ++$k)
        if (($hand[$k] + $meldCounts[$k]) < 4) {
            ++$hand[$k];
            if (winning($hand, $melds))
                $result[] = $k;
            --$hand[$k];
        }
    return $result;
}

function waitShape(string $form, ?array $block, int $winning, array $hand): string
{
    if ($form === 'chiitoitsu')
        return 'tanki';
    if ($form === 'kokushi') {
        foreach (\Tiles\YAOCHUU as $k)
            if ($hand[$k] !== 1)
                return 'single';
        return 'thirteen';
    }
    if (count($block) === 2)
        return 'tanki';
    if ($block[0] === $block[2])
        return 'shanpon';
    if ($winning === ($block[0] + 1))
        return 'kanchan';
    if (
        ($block[0] % 9) === 0 && $winning === ($block[0] + 2)
        || ($block[0] % 9) === 6 && $winning === $block[0]
    )
        return 'penchan';
    return 'ryanmen';
}
