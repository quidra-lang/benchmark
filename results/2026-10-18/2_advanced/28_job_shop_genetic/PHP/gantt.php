<?php

function scaleFor(int $makespan, int $width): array
{
    for ($power = 1; ; $power *= 10) {
        foreach ([1, 2, 5] as $multiplier) {
            $scale = $power * $multiplier;
            $columns = intdiv($makespan + $scale - 1, $scale);
            if ($columns <= $width) {
                return [$scale, $columns];
            }
        }
    }
}

function ganttRow(string $label, array $intervals, int $scale, int $columns): string
{
    $cells = '';
    for ($column = 0; $column < $columns; $column++) {
        $chosen = null;
        $greatest = 0;
        foreach ($intervals as $interval) {
            $overlap = min($interval->end, ($column + 1) * $scale) - max($interval->start, $column * $scale);
            if ($overlap > $greatest || ($overlap > 0 && $overlap === $greatest && $interval->start < $chosen->start)) {
                $greatest = $overlap;
                $chosen = $interval;
            }
        }
        $cells .= $chosen === null ? '.' : $chosen->mark;
    }
    return str_pad($label, 4) . ' |' . $cells . '|';
}

function gantt(object $instance, object $schedule, array $path, int $width): object
{
    [$scale, $columns] = scaleFor($schedule->makespan, $width);
    $time = 'time';
    for ($column = 0; $column < $columns; $column += 10) {
        $time .= str_repeat(' ', 6 + $column - strlen($time)) . ($column * $scale);
    }
    $rule = '      ';
    for ($column = 0; $column < $columns; $column++) {
        $rule .= $column % 10 === 0 ? '+' : '-';
    }
    $lines = [$time, $rule];
    $critical = array_fill_keys($path, true);
    for ($machine = 0; $machine < $instance->machineCount; $machine++) {
        $intervals = [];
        foreach ($schedule->order[$machine] as $index) {
            $letter = $instance->byNumber[$instance->operations[$index]->job]->letter;
            $intervals[] = (object) ['start' => $schedule->starts[$index], 'end' => $schedule->ends[$index],
                'mark' => isset($critical[$index]) ? strtolower($letter) : $letter];
        }
        $lines[] = ganttRow('M' . ($machine + 1), $intervals, $scale, $columns);
    }
    $busy = '';
    for ($column = 0; $column < $columns; $column++) {
        $instant = $column * $scale;
        $count = 0;
        foreach ($schedule->order as $sequence) {
            foreach ($sequence as $index) {
                if ($schedule->starts[$index] <= $instant && $instant < $schedule->ends[$index]) {
                    $count++;
                    break;
                }
            }
        }
        $busy .= $count === 10 ? 'X' : (string) $count;
    }
    $lines[] = 'busy |' . $busy . '|';
    foreach ($instance->jobs as $job) {
        $intervals = [];
        foreach ($job->operations as $index) {
            $intervals[] = (object) ['start' => $schedule->starts[$index], 'end' => $schedule->ends[$index],
                'mark' => (string) (($instance->operations[$index]->machine + 1) % 10)];
        }
        $lines[] = ganttRow('J' . $job->number, $intervals, $scale, $columns);
    }
    return (object) compact('scale', 'columns', 'lines');
}
