<?php

function readInstance(): object
{
    $lines = file('input/instance.txt', FILE_IGNORE_NEW_LINES);
    [$jobLines, $machineCount] = array_map('intval', explode(' ', $lines[0]));
    $jobs = [];
    $operations = [];
    $errors = [];
    for ($number = 1; $number <= $jobLines; $number++) {
        $tokens = array_map(fn($token) => array_map('intval', explode(':', $token)), explode(' ', $lines[$number]));
        $seen = [];
        $error = null;
        foreach ($tokens as $i => [$machine, $duration]) {
            $reason = null;
            if ($machine < 1 || $machine > $machineCount) {
                $reason = 'unknown machine ' . $machine;
            } elseif ($duration < 1 || $duration > 99) {
                $reason = 'bad duration ' . $duration;
            } elseif (isset($seen[$machine])) {
                $reason = 'repeated machine ' . $machine;
            }
            if ($reason !== null) {
                $error = 'job ' . $number . ' operation ' . ($i + 1) . ': ' . $reason;
                break;
            }
            $seen[$machine] = true;
        }
        if ($error !== null) {
            $errors[] = $error;
            continue;
        }
        $work = array_sum(array_column($tokens, 1));
        $job = (object) ['number' => $number, 'index' => count($jobs), 'letter' => chr(64 + $number), 'work' => $work, 'operations' => []];
        $head = 0;
        foreach ($tokens as $i => [$machine, $duration]) {
            $index = count($operations);
            $operations[] = (object) ['index' => $index, 'job' => $number, 'jobIndex' => $job->index,
                'number' => $i + 1, 'machine' => $machine - 1, 'duration' => $duration, 'head' => $head,
                'tail' => $work - $head - $duration, 'predecessor' => $i === 0 ? -1 : $index - 1,
                'successor' => $i + 1 === count($tokens) ? -1 : $index + 1, 'notation' => 'J' . $number . '-' . ($i + 1)];
            $job->operations[] = $index;
            $head += $duration;
        }
        $jobs[] = $job;
    }
    $machines = [];
    for ($machine = 0; $machine < $machineCount; $machine++) {
        $selected = array_values(array_filter($operations, fn($operation) => $operation->machine === $machine));
        $load = array_sum(array_map(fn($operation) => $operation->duration, $selected));
        $head = min(array_map(fn($operation) => $operation->head, $selected));
        $tail = min(array_map(fn($operation) => $operation->tail, $selected));
        $machines[] = (object) ['number' => $machine + 1, 'operations' => array_map(fn($operation) => $operation->index, $selected),
            'load' => $load, 'head' => $head, 'tail' => $tail, 'bound' => $head + $load + $tail];
    }
    $byNumber = [];
    foreach ($jobs as $job) {
        $byNumber[$job->number] = $job;
    }
    return (object) ['jobs' => $jobs, 'operations' => $operations, 'machines' => $machines, 'errors' => $errors,
        'machineCount' => $machineCount, 'byNumber' => $byNumber, 'work' => array_sum(array_column($jobs, 'work'))];
}
