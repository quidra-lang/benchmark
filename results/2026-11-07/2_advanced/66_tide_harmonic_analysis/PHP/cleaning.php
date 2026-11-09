<?php

function median($sorted) {
    $middle = intdiv(count($sorted), 2);
    return count($sorted) % 2 === 1 ? $sorted[$middle] : ($sorted[$middle - 1] + $sorted[$middle]) / 2;
}

function flatRuns($numeric, $minimum) {
    $runs = [];
    for ($start = 0; $start < count($numeric);) {
        $end = $start;
        while ($end + 1 < count($numeric) && $numeric[$end + 1]->time === $numeric[$end]->time + 1 && $numeric[$end + 1]->milli === $numeric[$start]->milli) $end++;
        if ($end - $start + 1 >= $minimum) $runs[] = (object)['start' => $numeric[$start]->time, 'end' => $numeric[$end]->time, 'value' => $numeric[$start]->value];
        $start = $end + 1;
    }
    return $runs;
}

function lowerBound($values, $target) {
    $low = 0;
    $high = count($values);
    while ($low < $high) {
        $middle = intdiv($low + $high, 2);
        if ($values[$middle] < $target) $low = $middle + 1;
        else $high = $middle;
    }
    return $low;
}

function mad($sorted, $center) {
    $right = lowerBound($sorted, $center);
    $left = $right - 1;
    $previous = $current = 0.0;
    for ($index = 0; $index <= intdiv(count($sorted), 2); $index++) {
        $previous = $current;
        $before = $left >= 0 ? abs($sorted[$left] - $center) : INF;
        $after = $right < count($sorted) ? abs($sorted[$right] - $center) : INF;
        if ($before <= $after) {
            $current = $before;
            $left--;
        } else {
            $current = $after;
            $right++;
        }
    }
    return count($sorted) % 2 === 1 ? $current : ($previous + $current) / 2;
}

function spikeTests($candidates, $settings) {
    $sorted = $spikes = [];
    $left = $right = $tested = 0;
    foreach ($candidates as $row) {
        while ($right < count($candidates) && $candidates[$right]->time <= $row->time + $settings->window) {
            $value = $candidates[$right++]->preliminary;
            array_splice($sorted, lowerBound($sorted, $value), 0, [$value]);
        }
        while ($left < $right && $candidates[$left]->time < $row->time - $settings->window) {
            $value = $candidates[$left++]->preliminary;
            array_splice($sorted, lowerBound($sorted, $value), 1);
        }
        if (count($sorted) < $settings->count) continue;
        $tested++;
        $center = median($sorted);
        $deviation = mad($sorted, $center);
        $limit = max($settings->factor * 1.4826 * $deviation, $settings->minimum);
        if (abs($row->preliminary - $center) > $limit) $spikes[] = (object)['time' => $row->time, 'value' => $row->value,
            'residual' => $row->preliminary, 'median' => $center, 'mad' => $deviation, 'limit' => $limit];
    }
    return compact('tested', 'spikes');
}

function gaps($first, $last, $reasons) {
    $result = [];
    for ($time = $first; $time <= $last;) {
        if (!isset($reasons[$time])) {
            $time++;
            continue;
        }
        $start = $time;
        $cause = $reasons[$time];
        while ($time <= $last && isset($reasons[$time])) {
            if ($reasons[$time] !== $cause) $cause = 'mixed';
            $time++;
        }
        $result[] = (object)['start' => $start, 'end' => $time - 1, 'cause' => $cause];
    }
    return $result;
}
