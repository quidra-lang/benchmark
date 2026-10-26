<?php

require_once __DIR__ . '/instance.php';
require_once __DIR__ . '/minstd.php';
require_once __DIR__ . '/dispatch_rules.php';
require_once __DIR__ . '/genetic.php';
require_once __DIR__ . '/gantt.php';

const RULES = ['SPT', 'LPT', 'MWKR', 'FIFO'];

function readParameters(): object
{
    $rows = [];
    foreach (file('input/ga_params.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $values = explode(' ', $line);
        $name = array_shift($values);
        $rows[$name] = $values;
    }
    return (object) ['seed' => (int) $rows['seed'][0], 'population' => (int) $rows['population'][0],
        'generations' => (int) $rows['generations'][0], 'tournament' => (int) $rows['tournament'][0],
        'crossover' => array_map('intval', explode('/', $rows['crossover'][0])),
        'swap' => array_map('intval', explode('/', $rows['swap_mutation'][0])),
        'insert' => array_map('intval', explode('/', $rows['insert_mutation'][0])),
        'elitism' => (int) $rows['elitism'][0], 'checkpoints' => array_fill_keys(array_map('intval', $rows['checkpoints']), true),
        'tabuIterations' => (int) $rows['tabu_iterations'][0], 'tenure' => (int) $rows['tabu_tenure'][0],
        'width' => (int) $rows['gantt_width'][0]];
}

function percentage(int $numerator, int $denominator): string
{
    $value = intdiv(2000 * $numerator + $denominator, 2 * $denominator);
    return intdiv($value, 10) . '.' . ($value % 10) . '%';
}

function fraction(int $numerator, int $denominator): string
{
    $a = $numerator;
    $b = $denominator;
    while ($b !== 0) {
        [$a, $b] = [$b, $a % $b];
    }
    return intdiv($numerator, $a) . '/' . intdiv($denominator, $a);
}

function jacksonBound(object $instance, object $machine): int
{
    $tasks = [];
    foreach ($machine->operations as $index) {
        $operation = $instance->operations[$index];
        $tasks[] = (object) ['head' => $operation->head, 'tail' => $operation->tail,
            'job' => $operation->job, 'remaining' => $operation->duration];
    }
    $pending = count($tasks);
    $time = $bound = 0;
    while ($pending > 0) {
        $available = array_values(array_filter($tasks, fn($task) => $task->head <= $time && $task->remaining > 0));
        if (!$available) {
            $future = array_values(array_filter($tasks, fn($task) => $task->head > $time));
            $time = min(array_map(fn($task) => $task->head, $future));
            $available = array_values(array_filter($tasks, fn($task) => $task->head <= $time && $task->remaining > 0));
        }
        $chosen = $available[0];
        foreach ($available as $task) {
            if ($task->tail > $chosen->tail || ($task->tail === $chosen->tail && $task->job < $chosen->job)) {
                $chosen = $task;
            }
        }
        $future = array_values(array_filter($tasks, fn($task) => $task->head > $time));
        $elapsed = !$future ? $chosen->remaining : min($chosen->remaining, min(array_map(fn($task) => $task->head, $future)) - $time);
        $time += $elapsed;
        $chosen->remaining -= $elapsed;
        if ($chosen->remaining === 0) {
            $bound = max($bound, $time + $chosen->tail);
            $pending--;
        }
    }
    return $bound;
}

function lowerBounds(object $instance): object
{
    $job = $instance->jobs[0];
    foreach ($instance->jobs as $candidate) {
        if ($candidate->work > $job->work) {
            $job = $candidate;
        }
    }
    $machine = $instance->machines[0];
    $jackson = $machine;
    foreach ($instance->machines as $candidate) {
        $candidate->jackson = jacksonBound($instance, $candidate);
        if ($candidate->bound > $machine->bound) {
            $machine = $candidate;
        }
        if ($candidate->jackson > $jackson->jackson) {
            $jackson = $candidate;
        }
    }
    $lower = max($job->work, $machine->bound, $jackson->jackson);
    return (object) compact('job', 'machine', 'jackson', 'lower');
}

function scheduleOrder(object $instance, array $order, ?array $durations = null): object
{
    $count = count($instance->operations);
    $durations ??= array_map(fn($operation) => $operation->duration, $instance->operations);
    $machinePrevious = $machineNext = array_fill(0, $count, -1);
    foreach ($order as $sequence) {
        for ($i = 1; $i < count($sequence); $i++) {
            $machinePrevious[$sequence[$i]] = $sequence[$i - 1];
            $machineNext[$sequence[$i - 1]] = $sequence[$i];
        }
    }
    $remaining = [];
    $ready = [];
    foreach ($instance->operations as $operation) {
        $remaining[$operation->index] = (int) ($operation->predecessor >= 0) + (int) ($machinePrevious[$operation->index] >= 0);
        if ($remaining[$operation->index] === 0) {
            $ready[] = $operation->index;
        }
    }
    $starts = $ends = array_fill(0, $count, 0);
    $makespan = 0;
    for ($head = 0; $head < count($ready); $head++) {
        $index = $ready[$head];
        $operation = $instance->operations[$index];
        $jobEnd = $operation->predecessor < 0 ? 0 : $ends[$operation->predecessor];
        $machineEnd = $machinePrevious[$index] < 0 ? 0 : $ends[$machinePrevious[$index]];
        $starts[$index] = max($jobEnd, $machineEnd);
        $ends[$index] = $starts[$index] + $durations[$index];
        $makespan = max($makespan, $ends[$index]);
        foreach ([$operation->successor, $machineNext[$index]] as $successor) {
            if ($successor >= 0 && --$remaining[$successor] === 0) {
                $ready[] = $successor;
            }
        }
    }
    return (object) compact('order', 'starts', 'ends', 'makespan', 'machinePrevious', 'machineNext', 'durations');
}

function operationOrder(object $instance, object $schedule): array
{
    $indices = array_map(fn($operation) => $operation->index, $instance->operations);
    usort($indices, fn($a, $b) => ($schedule->starts[$a] <=> $schedule->starts[$b]) ?:
        ($instance->operations[$a]->job <=> $instance->operations[$b]->job));
    return $indices;
}

function chromosomeOf(object $instance, object $schedule): array
{
    return array_map(fn($index) => $instance->operations[$index]->job, operationOrder($instance, $schedule));
}

function criticalAnalysis(object $instance, object $schedule): object
{
    $path = [];
    foreach ($instance->operations as $operation) {
        if ($schedule->ends[$operation->index] === $schedule->makespan) {
            $current = $operation->index;
            break;
        }
    }
    while (true) {
        $path[] = $current;
        if ($schedule->starts[$current] === 0) {
            break;
        }
        $previous = $schedule->machinePrevious[$current];
        $current = $previous >= 0 && $schedule->ends[$previous] === $schedule->starts[$current] ?
            $previous : $instance->operations[$current]->predecessor;
    }
    $path = array_reverse($path);
    $blocks = [];
    $perMachine = array_fill(0, $instance->machineCount, 0);
    foreach ($path as $index) {
        $machine = $instance->operations[$index]->machine;
        if (!$blocks || $blocks[count($blocks) - 1]->machine !== $machine) {
            $blocks[] = (object) ['machine' => $machine, 'operations' => []];
        }
        $blocks[count($blocks) - 1]->operations[] = $index;
        $perMachine[$machine]++;
    }
    $counts = array_fill(0, count($instance->operations), 0);
    $paths = 0;
    foreach (operationOrder($instance, $schedule) as $index) {
        if ($schedule->starts[$index] === 0) {
            $counts[$index] = 1;
        } else {
            foreach ([$instance->operations[$index]->predecessor, $schedule->machinePrevious[$index]] as $previous) {
                if ($previous >= 0 && $schedule->ends[$previous] === $schedule->starts[$index]) {
                    $counts[$index] += $counts[$previous];
                }
            }
        }
        if ($schedule->ends[$index] === $schedule->makespan) {
            $paths += $counts[$index];
        }
    }
    $bottleneck = 0;
    for ($machine = 1; $machine < count($perMachine); $machine++) {
        if ($perMachine[$machine] > $perMachine[$bottleneck]) {
            $bottleneck = $machine;
        }
    }
    return (object) compact('path', 'blocks', 'paths', 'perMachine', 'bottleneck');
}

function neighbours(object $instance, object $schedule, ?object $analysis = null): array
{
    $analysis ??= criticalAnalysis($instance, $schedule);
    $moves = [];
    foreach ($analysis->blocks as $block) {
        for ($i = 1; $i < count($block->operations); $i++) {
            $u = $block->operations[$i - 1];
            $v = $block->operations[$i];
            $order = $schedule->order;
            $position = array_search($u, $order[$block->machine], true);
            [$order[$block->machine][$position], $order[$block->machine][$position + 1]] = [$v, $u];
            $changed = scheduleOrder($instance, $order);
            $moves[] = (object) ['u' => $u, 'v' => $v, 'machine' => $block->machine, 'schedule' => $changed, 'value' => $changed->makespan];
        }
    }
    return $moves;
}

function tabuSearch(object $instance, array $startingOrder, object $parameters): object
{
    $current = scheduleOrder($instance, $startingOrder);
    $best = $current;
    $found = 0;
    $reason = 'limit';
    $expiries = [];
    $records = [];
    for ($iteration = 1; $iteration <= $parameters->tabuIterations; $iteration++) {
        $moves = neighbours($instance, $current);
        if (!$moves) {
            $reason = 'no_moves';
            break;
        }
        $chosen = null;
        $tabu = 0;
        foreach ($moves as $move) {
            $move->tabu = ($expiries[$move->u . ',' . $move->v] ?? 0) >= $iteration;
            if ($move->tabu) {
                $tabu++;
            }
            if ($move->tabu && $move->value >= $best->makespan) {
                continue;
            }
            if ($chosen === null || $move->value < $chosen->value) {
                $chosen = $move;
            }
        }
        if ($chosen === null) {
            $reason = 'all_tabu';
            break;
        }
        $current = $chosen->schedule;
        $expiries[$chosen->v . ',' . $chosen->u] = $iteration + $parameters->tenure;
        if ($chosen->value < $best->makespan) {
            $best = $current;
            $found = $iteration;
        }
        $records[] = (object) ['iteration' => $iteration, 'moves' => count($moves), 'tabu' => $tabu, 'chosen' => $chosen, 'best' => $best->makespan];
    }
    return (object) compact('best', 'found', 'reason', 'records');
}

function leftShifts(object $instance, object $schedule): array
{
    $shifts = [];
    foreach ($schedule->order as $machine => $sequence) {
        for ($i = 1; $i < count($sequence); $i++) {
            $index = $sequence[$i];
            $operation = $instance->operations[$index];
            $ready = $operation->predecessor < 0 ? 0 : $schedule->ends[$operation->predecessor];
            for ($position = 0; $position < $i; $position++) {
                $start = max($position === 0 ? 0 : $schedule->ends[$sequence[$position - 1]], $ready);
                $end = $schedule->starts[$sequence[$position]];
                if ($start + $operation->duration <= $end) {
                    $shifts[] = (object) ['index' => $index, 'machine' => $machine, 'oldPosition' => $i,
                        'position' => $position, 'oldStart' => $schedule->starts[$index], 'newStart' => $start];
                    break;
                }
            }
        }
    }
    return $shifts;
}

function activate(object $instance, array $startingOrder): object
{
    $schedule = scheduleOrder($instance, $startingOrder);
    $records = [];
    while (true) {
        $choices = leftShifts($instance, $schedule);
        if (!$choices) {
            break;
        }
        usort($choices, fn($a, $b) => ($a->oldStart <=> $b->oldStart) ?:
            ($instance->operations[$a->index]->job <=> $instance->operations[$b->index]->job));
        $chosen = $choices[0];
        $order = $schedule->order;
        array_splice($order[$chosen->machine], $chosen->oldPosition, 1);
        array_splice($order[$chosen->machine], $chosen->position, 0, [$chosen->index]);
        $records[] = $chosen;
        $schedule = scheduleOrder($instance, $order);
    }
    return (object) compact('schedule', 'records');
}

function slacks(object $instance, object $schedule): object
{
    $latest = $slack = $free = array_fill(0, count($instance->operations), 0);
    foreach (array_reverse(operationOrder($instance, $schedule)) as $index) {
        $successors = array_values(array_filter([$instance->operations[$index]->successor, $schedule->machineNext[$index]], fn($v) => $v >= 0));
        $limit = $successors ? min(array_map(fn($v) => $latest[$v], $successors)) : $schedule->makespan;
        $nextStart = $successors ? min(array_map(fn($v) => $schedule->starts[$v], $successors)) : $schedule->makespan;
        $latest[$index] = $limit - $instance->operations[$index]->duration;
        $slack[$index] = $latest[$index] - $schedule->starts[$index];
        $free[$index] = $nextStart - $schedule->ends[$index];
    }
    $critical = count(array_filter($slack, fn($value) => $value === 0));
    return (object) compact('slack', 'free', 'critical');
}

function distance(object $first, object $second): array
{
    $distances = [];
    foreach ($first->order as $machine => $sequence) {
        $positions = array_flip($second->order[$machine]);
        $inversions = 0;
        for ($i = 0; $i < count($sequence); $i++) {
            for ($j = $i + 1; $j < count($sequence); $j++) {
                if ($positions[$sequence[$i]] > $positions[$sequence[$j]]) {
                    $inversions++;
                }
            }
        }
        $distances[] = $inversions;
    }
    return $distances;
}

function runGenetic(object $instance, array $baselines, object $parameters): object
{
    $rng = new Minstd($parameters->seed);
    $basic = [];
    foreach ($instance->jobs as $job) {
        foreach ($job->operations as $_) {
            $basic[] = $job->number;
        }
    }
    $population = array_map(fn($baseline) => chromosomeOf($instance, $baseline->schedule), $baselines);
    while (count($population) < $parameters->population) {
        $population[] = $rng->shuffled($basic);
    }
    $counts = (object) ['crossovers' => 0, 'swaps' => 0, 'inserts' => 0];
    $records = [];
    $progress = ['generation,best,mean,worst,distinct'];
    $previousBest = null;
    for ($generation = 0; $generation <= $parameters->generations; $generation++) {
        $decoded = array_map(fn($chromosome) => decode($instance, $chromosome), $population);
        $evaluations = array_map(fn($schedule) => $schedule->makespan, $decoded);
        $ranking = range(0, count($population) - 1);
        usort($ranking, fn($a, $b) => ($evaluations[$a] <=> $evaluations[$b]) ?: ($a <=> $b));
        $bestIndex = $ranking[0];
        if ($generation === 0 || $evaluations[$bestIndex] < $previousBest) {
            $records[] = (object) ['generation' => $generation, 'value' => $evaluations[$bestIndex], 'individual' => $bestIndex + 1];
        }
        $previousBest = $evaluations[$bestIndex];
        if (isset($parameters->checkpoints[$generation])) {
            $distinct = [];
            foreach ($population as $chromosome) {
                $distinct[implode(',', $chromosome)] = true;
            }
            $progress[] = implode(',', [$generation, $evaluations[$bestIndex], fraction(array_sum($evaluations), $parameters->population),
                $evaluations[$ranking[count($ranking) - 1]], count($distinct)]);
        }
        if ($generation === $parameters->generations) {
            break;
        }
        $next = [];
        foreach (array_slice($ranking, 0, $parameters->elitism) as $index) {
            $next[] = $population[$index];
        }
        while (count($next) < $parameters->population) {
            $first = tournament($evaluations, $parameters->tournament, $rng);
            $second = tournament($evaluations, $parameters->tournament, $rng);
            if ($rng->chance($parameters->crossover)) {
                $counts->crossovers++;
                $children = crossover($population[$first], $population[$second], $instance->jobs, $rng);
            } else {
                $children = [$population[$first], $population[$second]];
            }
            foreach ($children as &$child) {
                if ($rng->chance($parameters->swap)) {
                    $counts->swaps++;
                    swapMutation($child, $rng);
                }
                if ($rng->chance($parameters->insert)) {
                    $counts->inserts++;
                    insertionMutation($child, $rng);
                }
            }
            unset($child);
            array_push($next, ...$children);
        }
        $population = $next;
    }
    $best = scheduleOrder($instance, $decoded[$bestIndex]->order);
    $top = [];
    $seen = [];
    foreach ($ranking as $index) {
        $key = implode(',', $population[$index]);
        if (isset($seen[$key])) {
            continue;
        }
        $seen[$key] = true;
        $top[] = (object) ['individual' => $index + 1, 'value' => $evaluations[$index],
            'distance' => array_sum(distance($decoded[$index], $best))];
        if (count($top) === 5) {
            break;
        }
    }
    $chromosome = $population[$bestIndex];
    return (object) compact('best', 'chromosome', 'records', 'progress', 'top', 'counts');
}

function statistics(object $instance, object $schedule): object
{
    $flow = 0;
    foreach ($instance->jobs as $job) {
        $flow += $schedule->ends[$job->operations[count($job->operations) - 1]];
    }
    $machines = [];
    foreach ($instance->machines as $index => $machine) {
        $sequence = $schedule->order[$index];
        $intervals = [];
        $gaps = $longest = 0;
        if ($schedule->starts[$sequence[0]] > 0) {
            $intervals[] = [0, $schedule->starts[$sequence[0]]];
        }
        for ($i = 1; $i < count($sequence); $i++) {
            $start = $schedule->ends[$sequence[$i - 1]];
            $end = $schedule->starts[$sequence[$i]];
            if ($end > $start) {
                $intervals[] = [$start, $end];
                $gaps++;
                $longest = max($longest, $end - $start);
            }
        }
        $finish = $schedule->ends[$sequence[count($sequence) - 1]];
        if ($finish < $schedule->makespan) {
            $intervals[] = [$finish, $schedule->makespan];
        }
        $machines[] = (object) ['idle' => $schedule->makespan - $machine->load,
            'intervals' => $intervals, 'gaps' => $gaps, 'longest' => $longest];
    }
    return (object) ['flow' => $flow, 'waiting' => $flow - $instance->work,
        'idle' => $instance->machineCount * $schedule->makespan - $instance->work, 'machines' => $machines];
}

function baselineLines(object $instance, object $bounds, array $baselines): array
{
    $lines = ['INSTANCE jobs ' . count($instance->jobs) . ' machines ' . $instance->machineCount .
        ' operations ' . count($instance->operations) . ' work ' . $instance->work . ' errors ' . count($instance->errors)];
    foreach ($instance->errors as $error) {
        $lines[] = 'ERROR ' . $error;
    }
    foreach ($instance->jobs as $job) {
        $route = array_map(fn($index) => 'M' . ($instance->operations[$index]->machine + 1), $job->operations);
        $lines[] = 'JOB J' . $job->number . ' operations ' . count($job->operations) . ' work ' . $job->work . ' route ' . implode(' ', $route);
    }
    foreach ($instance->machines as $machine) {
        $lines[] = 'MACHINE M' . $machine->number . ' operations ' . count($machine->operations) . ' load ' . $machine->load .
            ' head ' . $machine->head . ' tail ' . $machine->tail . ' bound ' . $machine->bound . ' jackson ' . $machine->jackson;
    }
    $lines[] = 'BOUND job ' . $bounds->job->work . ' J' . $bounds->job->number;
    $lines[] = 'BOUND machine ' . $bounds->machine->bound . ' M' . $bounds->machine->number;
    $lines[] = 'BOUND jackson ' . $bounds->jackson->jackson . ' M' . $bounds->jackson->number;
    $lines[] = 'BOUND lower ' . $bounds->lower;
    $best = $baselines[0];
    foreach ($baselines as $baseline) {
        $schedule = $baseline->schedule;
        $analysis = $baseline->analysis;
        $search = $baseline->search;
        $stats = statistics($instance, $schedule);
        $lines[] = 'RULE ' . $baseline->rule . ' makespan ' . $schedule->makespan . ' gap ' . percentage($schedule->makespan - $bounds->lower, $bounds->lower) .
            ' flow ' . $stats->flow . ' idle ' . $stats->idle . ' decisions ' . $baseline->dispatched->decisions . ' ties ' . $baseline->dispatched->ties;
        $lines[] = 'PATH ' . $baseline->rule . ' operations ' . count($analysis->path) . ' blocks ' . count($analysis->blocks) .
            ' critical_paths ' . $analysis->paths . ' bottleneck M' . ($analysis->bottleneck + 1);
        $lines[] = 'TABU ' . $baseline->rule . ' makespan ' . $schedule->makespan . ' -> ' . $search->best->makespan . ' found ' . $search->found .
            ' iterations ' . count($search->records) . ' stop ' . $search->reason;
        if ($schedule->makespan < $best->schedule->makespan) {
            $best = $baseline;
        }
    }
    $lines[] = 'BEST ' . $best->rule . ' makespan ' . $best->schedule->makespan;
    foreach ($instance->machines as $machine) {
        $values = [];
        foreach ($baselines as $baseline) {
            $values[] = $baseline->rule . ' ' . percentage($machine->load, $baseline->schedule->makespan);
        }
        $lines[] = 'UTILIZATION M' . $machine->number . ' ' . implode(' ', $values);
    }
    return $lines;
}

function sequenceLetters(object $instance, array $sequence): string
{
    $letters = '';
    foreach ($sequence as $index) {
        $letters .= $instance->byNumber[$instance->operations[$index]->job]->letter;
    }
    return $letters;
}

function bestScheduleLines(object $instance, object $bounds, array $baselines, object $ga, object $activeDecode,
    object $activated, object $final, object $analysis, object $parameters): array
{
    $lastRecord = $ga->records[count($ga->records) - 1];
    $lines = ['GA best ' . $ga->best->makespan . ' generation ' . $lastRecord->generation . ' crossovers ' . $ga->counts->crossovers .
        ' swaps ' . $ga->counts->swaps . ' inserts ' . $ga->counts->inserts];
    foreach ($ga->records as $record) {
        $lines[] = 'RECORD generation ' . $record->generation . ' makespan ' . $record->value . ' individual ' . $record->individual;
    }
    foreach ($ga->top as $i => $individual) {
        $lines[] = 'TOP ' . ($i + 1) . ' individual ' . $individual->individual . ' makespan ' . $individual->value . ' distance ' . $individual->distance;
    }
    $lines[] = 'GA_CHROMOSOME ' . implode(' ', $ga->chromosome);
    $lines[] = 'ACTIVE_DECODE makespan ' . $activeDecode->makespan . ' decisions ' . $activeDecode->decisions;
    foreach ($activated->records as $i => $shift) {
        $lines[] = 'SHIFT ' . ($i + 1) . ' ' . $instance->operations[$shift->index]->notation . ' M' . ($shift->machine + 1) .
            ' start ' . $shift->oldStart . ' -> ' . $shift->newStart;
    }
    $lines[] = 'ACTIVATED makespan ' . $ga->best->makespan . ' -> ' . $activated->schedule->makespan . ' shifts ' . count($activated->records);
    $lines[] = 'SCHEDULE makespan ' . $final->makespan . ' lower_bound ' . $bounds->lower .
        ' gap ' . percentage($final->makespan - $bounds->lower, $bounds->lower) . ' improvement ' . ($ga->best->makespan - $final->makespan) .
        ' shiftable ' . count(leftShifts($instance, $final));
    $lines[] = 'CHROMOSOME ' . implode(' ', chromosomeOf($instance, $final));
    $legend = array_map(fn($job) => $job->letter . '=J' . $job->number, $instance->jobs);
    $lines[] = 'LEGEND ' . implode(' ', $legend);
    $chart = gantt($instance, $final, $analysis->path, $parameters->width);
    $lines[] = 'GANTT scale ' . $chart->scale . ' columns ' . $chart->columns;
    array_push($lines, ...$chart->lines);
    for ($machine = 0; $machine < $instance->machineCount; $machine++) {
        $entries = ['FINAL ' . sequenceLetters($instance, $final->order[$machine])];
        foreach ($baselines as $baseline) {
            $entries[] = $baseline->rule . ' ' . sequenceLetters($instance, $baseline->schedule->order[$machine]);
        }
        $lines[] = 'ORDER M' . ($machine + 1) . ' ' . implode(' ', $entries);
    }
    $stats = statistics($instance, $final);
    for ($machine = 0; $machine < $instance->machineCount; $machine++) {
        $values = $stats->machines[$machine];
        $load = $instance->machines[$machine]->load;
        $sequence = [];
        foreach ($final->order[$machine] as $index) {
            $sequence[] = 'J' . $instance->operations[$index]->job . ':' . $final->starts[$index] . '-' . $final->ends[$index];
        }
        $lines[] = 'MACHINE M' . ($machine + 1) . ' load ' . $load . ' idle ' . $values->idle .
            ' utilization ' . percentage($load, $final->makespan) . ' gaps ' . $values->gaps . ' longest_gap ' . $values->longest .
            ' sequence ' . implode(' ', $sequence);
        $intervals = array_map(fn($interval) => $interval[0] . '-' . $interval[1], $values->intervals);
        $lines[] = 'IDLE M' . ($machine + 1) . ' ' . ($intervals ? implode(' ', $intervals) : 'none');
    }
    foreach ($instance->jobs as $job) {
        $completion = $final->ends[$job->operations[count($job->operations) - 1]];
        $lines[] = 'JOB J' . $job->number . ' operations ' . count($job->operations) . ' work ' . $job->work .
            ' start ' . $final->starts[$job->operations[0]] . ' completion ' . $completion . ' waiting ' . ($completion - $job->work);
    }
    $lines[] = 'TOTAL flow ' . $stats->flow . ' waiting ' . $stats->waiting . ' idle ' . $stats->idle;
    $distances = [];
    foreach ($baselines as $baseline) {
        $distances[] = (object) ['name' => $baseline->rule, 'values' => distance($final, $baseline->schedule)];
    }
    $distances[] = (object) ['name' => 'GA', 'values' => distance($final, $ga->best)];
    $pairs = 0;
    for ($machine = 0; $machine < $instance->machineCount; $machine++) {
        $count = count($final->order[$machine]);
        $machinePairs = intdiv($count * ($count - 1), 2);
        $pairs += $machinePairs;
        $values = array_map(fn($item) => $item->name . ' ' . $item->values[$machine], $distances);
        $lines[] = 'DISTANCE M' . ($machine + 1) . ' pairs ' . $machinePairs . ' ' . implode(' ', $values);
    }
    $values = array_map(fn($item) => $item->name . ' ' . array_sum($item->values), $distances);
    $lines[] = 'DISTANCE total pairs ' . $pairs . ' ' . implode(' ', $values);
    return $lines;
}

function criticalLines(object $instance, object $activated, object $search, object $analysis, object $parameters): array
{
    $final = $search->best;
    $lines = ['SEARCH start ' . $activated->schedule->makespan . ' iterations ' . $parameters->tabuIterations . ' tenure ' . $parameters->tenure];
    foreach ($search->records as $record) {
        $move = $record->chosen;
        $lines[] = 'ITER ' . $record->iteration . ' moves ' . $record->moves . ' tabu ' . $record->tabu . ' swap M' . ($move->machine + 1) .
            ' ' . $instance->operations[$move->u]->notation . ' ' . $instance->operations[$move->v]->notation .
            ' ' . ($move->tabu ? 'aspiration' : 'free') . ' makespan ' . $move->value . ' best ' . $record->best;
    }
    $lines[] = 'STOP iterations ' . count($search->records) . ' reason ' . $search->reason . ' best ' . $final->makespan . ' found ' . $search->found;
    $lines[] = 'PATH operations ' . count($analysis->path) . ' blocks ' . count($analysis->blocks) . ' makespan ' . $final->makespan .
        ' critical_paths ' . $analysis->paths;
    foreach ($analysis->path as $i => $index) {
        $operation = $instance->operations[$index];
        $link = $i === 0 ? 'start' : ($analysis->path[$i - 1] === $final->machinePrevious[$index] ? 'machine' : 'job');
        $lines[] = 'NODE ' . ($i + 1) . ' ' . $operation->notation . ' M' . ($operation->machine + 1) .
            ' ' . $final->starts[$index] . '-' . $final->ends[$index] . ' ' . $link;
    }
    foreach ($analysis->blocks as $i => $block) {
        $operations = array_map(fn($index) => $instance->operations[$index]->notation, $block->operations);
        $first = $block->operations[0];
        $last = $block->operations[count($block->operations) - 1];
        $lines[] = 'BLOCK ' . ($i + 1) . ' M' . ($block->machine + 1) . ' ' . $final->starts[$first] . '-' . $final->ends[$last] .
            ' ' . implode(' ', $operations);
    }
    foreach (neighbours($instance, $final, $analysis) as $i => $move) {
        $lines[] = 'NEIGHBOUR ' . ($i + 1) . ' M' . ($move->machine + 1) . ' ' . $instance->operations[$move->u]->notation .
            ' ' . $instance->operations[$move->v]->notation . ' makespan ' . $move->value;
    }
    $values = slacks($instance, $final);
    $lines[] = 'CRITICAL operations ' . $values->critical . ' total ' . count($instance->operations);
    foreach ($instance->jobs as $job) {
        $lines[] = 'SLACK J' . $job->number . ' ' . implode(' ', array_map(fn($index) => $values->slack[$index], $job->operations));
    }
    foreach ($instance->jobs as $job) {
        $lines[] = 'FREE J' . $job->number . ' ' . implode(' ', array_map(fn($index) => $values->free[$index], $job->operations));
    }
    for ($machine = 0; $machine < $instance->machineCount; $machine++) {
        $critical = 0;
        foreach ($instance->machines[$machine]->operations as $index) {
            if ($values->slack[$index] === 0) {
                $critical++;
            }
        }
        $durations = array_map(fn($operation) => $operation->duration +
            ($operation->machine === $machine ? intdiv($operation->duration + 9, 10) : 0), $instance->operations);
        $sensitivity = scheduleOrder($instance, $final->order, $durations)->makespan;
        $lines[] = 'MACHINE M' . ($machine + 1) . ' critical ' . $critical . ' path ' . $analysis->perMachine[$machine] .
            ' sensitivity ' . $sensitivity . ' delta ' . ($sensitivity - $final->makespan);
    }
    $lines[] = 'BOTTLENECK M' . ($analysis->bottleneck + 1) . ' path ' . $analysis->perMachine[$analysis->bottleneck];
    return $lines;
}

$instance = readInstance();
$parameters = readParameters();
$bounds = lowerBounds($instance);
$baselines = [];
foreach (RULES as $rule) {
    $dispatched = dispatch($instance, $rule);
    $schedule = scheduleOrder($instance, $dispatched->order);
    $baselines[] = (object) ['rule' => $rule, 'dispatched' => $dispatched, 'schedule' => $schedule,
        'analysis' => criticalAnalysis($instance, $schedule), 'search' => tabuSearch($instance, $schedule->order, $parameters)];
}
$ga = runGenetic($instance, $baselines, $parameters);
$genePositions = array_fill(0, count($instance->operations), 0);
$next = array_fill(0, count($instance->jobs), 0);
foreach ($ga->chromosome as $position => $number) {
    $job = $instance->byNumber[$number];
    $genePositions[$job->operations[$next[$job->index]++]] = $position + 1;
}
$activeDecode = dispatch($instance, 'GENES', $genePositions);
$activated = activate($instance, $ga->best->order);
$search = tabuSearch($instance, $activated->schedule->order, $parameters);
$analysis = criticalAnalysis($instance, $search->best);
$outputs = [
    'baselines.txt' => baselineLines($instance, $bounds, $baselines),
    'ga_progress.csv' => $ga->progress,
    'best_schedule.txt' => bestScheduleLines($instance, $bounds, $baselines, $ga, $activeDecode, $activated, $search->best, $analysis, $parameters),
    'critical_path.txt' => criticalLines($instance, $activated, $search, $analysis, $parameters)
];
if (!is_dir('output')) {
    mkdir('output', 0777, true);
}
foreach ($outputs as $name => $lines) {
    file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
}
