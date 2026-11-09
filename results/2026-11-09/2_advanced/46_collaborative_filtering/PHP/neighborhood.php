<?php

function userSimilarity(object $first, object $second, int $shrinkage): ?object
{
    $common = 0;
    $sx = $sy = $sxx = $syy = $sxy = 0;
    foreach ($first->entries as $row) {
        if (!isset($second->ratings[$row->i])) {
            continue;
        }
        $x = $row->rating;
        $y = $second->ratings[$row->i];
        $common++;
        $sx += $x;
        $sy += $y;
        $sxx += $x * $x;
        $syy += $y * $y;
        $sxy += $x * $y;
    }
    if ($common < 2) {
        return null;
    }
    $numerator = $common * $sxy - $sx * $sy;
    $dx = $common * $sxx - $sx * $sx;
    $dy = $common * $syy - $sy * $sy;
    if ($dx === 0 || $dy === 0) {
        return null;
    }
    $scaled = $numerator * $common;
    $regularized = $common + $shrinkage;
    $a = $scaled * $scaled;
    $b = $dx * $dy * $regularized * $regularized;
    $sign = $numerator <=> 0;
    return (object) ['similarity' => $sign * sqrt($a / $b), 'common' => $common];
}

function buildNeighborhoods(object $data): object
{
    $userCount = count($data->users);
    $itemCount = count($data->items);
    $users = array_fill(0, $userCount, array_fill(0, $userCount, null));
    for ($first = 0; $first < $userCount; $first++) {
        for ($second = $first + 1; $second < $userCount; $second++) {
            $users[$first][$second] = $users[$second][$first] = userSimilarity($data->users[$first], $data->users[$second], $data->settings->shrinkage);
        }
    }
    $items = array_fill(0, $itemCount, array_fill(0, $itemCount, null));
    $common = array_fill(0, $itemCount, array_fill(0, $itemCount, 0));
    $difference = array_fill(0, $itemCount, array_fill(0, $itemCount, 0));
    for ($first = 0; $first < $itemCount; $first++) {
        for ($second = $first + 1; $second < $itemCount; $second++) {
            $count = 0;
            $sum = 0;
            $numerator = $normFirst = $normSecond = 0.0;
            foreach ($data->items[$first]->entries as $row) {
                if (!isset($data->items[$second]->ratings[$row->u])) {
                    continue;
                }
                $other = $data->items[$second]->ratings[$row->u];
                $count++;
                $sum += $row->rating - $other;
                $x = $row->rating - $data->users[$row->u]->mean;
                $y = $other - $data->users[$row->u]->mean;
                $numerator += $x * $y;
                $normFirst += $x * $x;
                $normSecond += $y * $y;
            }
            $common[$first][$second] = $common[$second][$first] = $count;
            $difference[$first][$second] = $sum;
            $difference[$second][$first] = -$sum;
            if ($count >= 2 && $normFirst != 0.0 && $normSecond != 0.0) {
                $similarity = $numerator / sqrt($normFirst * $normSecond) * $count / ($count + $data->settings->shrinkage);
                $items[$first][$second] = $items[$second][$first] = (object) ['similarity' => $similarity, 'common' => $count];
            }
        }
    }
    return (object) compact('users', 'items', 'common', 'difference');
}

function selectNeighbors(array $candidates, int $count): array
{
    usort($candidates, fn($a, $b) => ($b->similarity <=> $a->similarity) ?: ($a->id <=> $b->id));
    return array_slice($candidates, 0, $count);
}
