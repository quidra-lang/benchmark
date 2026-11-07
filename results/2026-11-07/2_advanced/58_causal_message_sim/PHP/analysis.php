<?php

function eventGraph($processes, $events, $copies) {
    $graph = array_fill(0, count($events), []);
    foreach ($processes as $process) for ($i = 1; $i < count($process->events); $i++) {
        $graph[$process->events[$i - 1]->number - 1][] = $process->events[$i]->number - 1;
    }
    foreach ($copies as $copy) if ($copy->received !== null) $graph[$copy->message->event->number - 1][] = $copy->received->number - 1;
    return $graph;
}

function breadthFirst($graph, $start, $end) {
    $parents = array_fill(0, count($graph), -1);
    $parents[$start] = $start;
    $queue = [$start];
    for ($head = 0; $head < count($queue); $head++) {
        foreach ($graph[$queue[$head]] as $destination) {
            if ($parents[$destination] !== -1) continue;
            $parents[$destination] = $queue[$head];
            if ($destination === $end) {
                $path = [$end];
                while ($path[count($path) - 1] !== $start) $path[] = $parents[$path[count($path) - 1]];
                return array_reverse($path);
            }
            $queue[] = $destination;
        }
    }
    return null;
}

function concurrentPairs($events, $size) {
    $ordered = $concurrent = $sameLamport = $inversions = 0;
    $pairs = array_fill(0, $size, array_fill(0, $size, 0));
    for ($i = 0; $i < count($events); $i++) for ($j = $i + 1; $j < count($events); $j++) {
        $left = $events[$i];
        $right = $events[$j];
        if (relation($left->V, $right->V) === '||') {
            $concurrent++;
            if ($left->L === $right->L) $sameLamport++;
            $pairs[min($left->process, $right->process)][max($left->process, $right->process)]++;
        } else $ordered++;
        if (($left->time < $right->time && $left->L > $right->L) || ($left->time > $right->time && $left->L < $right->L)) $inversions++;
    }
    return compact('ordered', 'concurrent', 'sameLamport', 'inversions', 'pairs');
}

function deliveryRelations($processes) {
    $races = $violations = [];
    $fifo = 0;
    foreach ($processes as $process) {
        $deliveries = $process->deliveries;
        for ($i = 0; $i < count($deliveries); $i++) {
            $first = $deliveries[$i];
            if ($i + 1 < count($deliveries) && relation($first->message->event->V, $deliveries[$i + 1]->message->event->V) === '||') {
                $races[] = ['process' => $process->index, 'first' => $first, 'second' => $deliveries[$i + 1]];
            }
            for ($j = $i + 1; $j < count($deliveries); $j++) {
                $second = $deliveries[$j];
                if (relation($second->message->event->V, $first->message->event->V) !== '->') continue;
                $violations[] = ['process' => $process->index, 'first' => $first, 'second' => $second];
                if ($first->source === $second->source) $fifo++;
            }
        }
    }
    return compact('races', 'violations', 'fifo');
}

function nextCut(&$cut, $bounds) {
    foreach ($cut as $i => $value) {
        if ($value < $bounds[$i]) {
            $cut[$i]++;
            return;
        }
        $cut[$i] = 0;
    }
}

function countCuts($processes, $time, $initialTotal) {
    $bounds = [];
    foreach ($processes as $process) {
        $count = 0;
        foreach ($process->events as $event) if ($event->time <= $time) $count++;
        $bounds[] = $count;
    }
    $strides = [];
    $product = 1;
    $maximumLevel = 0;
    foreach ($bounds as $bound) {
        $strides[] = $product;
        $product *= $bound + 1;
        $maximumLevel += $bound;
    }
    $valid = array_fill(0, $product, false);
    $amount = array_fill(0, $product, 0);
    $levels = array_fill(0, $maximumLevel + 1, 0);
    $cut = array_fill(0, count($bounds), 0);
    $consistent = 0;
    for ($index = 0; $index < $product; $index++) {
        $accepted = true;
        foreach ($cut as $i => $count) if ($count > 0 && !lessEqual($processes[$i]->events[$count - 1]->V, $cut)) {
            $accepted = false;
            break;
        }
        if ($accepted) {
            $valid[$index] = true;
            $consistent++;
            $level = $balances = 0;
            foreach ($cut as $i => $count) {
                $level += $count;
                $balances += balanceAt($processes[$i], $count);
            }
            $levels[$level]++;
            $amount[$index] = $initialTotal - $balances;
        }
        nextCut($cut, $bounds);
    }
    return compact('bounds', 'strides', 'product', 'valid', 'amount', 'levels', 'consistent');
}

function predicate($cuts, $threshold) {
    $reachable = array_fill(0, $cuts['product'], false);
    $cut = array_fill(0, count($cuts['bounds']), 0);
    $count = 0;
    for ($index = 0; $index < $cuts['product']; $index++) {
        if ($cuts['valid'][$index]) {
            if ($cuts['amount'][$index] >= $threshold) $count++;
            else {
                $found = $index === 0;
                foreach ($cut as $i => $value) if ($value > 0 && $reachable[$index - $cuts['strides'][$i]]) $found = true;
                if ($found) $reachable[$index] = true;
            }
        }
        nextCut($cut, $cuts['bounds']);
    }
    return ['count' => $count, 'possibly' => $count > 0, 'definitely' => !$reachable[$cuts['product'] - 1]];
}
