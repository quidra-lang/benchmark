<?php
class Task
{
    public int $day = 0;
    public ?int $crashLimit = null;
    public ?int $cost = null;
    public int $used = 0;
    public ?array $estimate = null;
    public function __construct(public int $base, public string $resource, public int $units) {}
    public function duration(): int
    {
        return $this->base - $this->used;
    }
}

class ScheduleError extends Exception {}

class Scheduler
{
    private array $tasks = [];
    private array $deps = [];
    private array $capacities = [];
    private ?DateTimeImmutable $start = null;
    private ?DateTimeImmutable $deadline = null;
    private array $holidays = [];
    private ?array $baseline = null;
    private const ANALYSIS = ['CPM', 'CRITICAL', 'SLACK', 'DRAG', 'STATS', 'CALENDAR', 'GANTT',
        'LEVEL', 'LOAD', 'PERTSUM', 'CRASH', 'WHATIF', 'BASELINE', 'VARIANCE'];

    private function names(): array
    {
        $names = array_keys($this->tasks);
        sort($names, SORT_STRING);
        return $names;
    }

    private function requireTask(string $name): void
    {
        if (!isset($this->tasks[$name])) {
            throw new ScheduleError("unknown task $name");
        }
    }

    private function predecessors(string $name): array
    {
        $result = [];
        foreach ($this->deps as [$a, $b]) {
            if ($b === $name) {
                $result[] = $a;
            }
        }
        sort($result, SORT_STRING);
        return $result;
    }

    private function successors(string $name): array
    {
        $result = [];
        foreach ($this->deps as [$a, $b]) {
            if ($a === $name) {
                $result[] = $b;
            }
        }
        sort($result, SORT_STRING);
        return $result;
    }

    private function topology(): array
    {
        $remaining = $this->names();
        $order = [];
        while (true) {
            $found = null;
            foreach ($remaining as $name) {
                if (!array_intersect($this->predecessors($name), $remaining)) {
                    $found = $name;
                    break;
                }
            }
            if ($found === null) {
                break;
            }
            $remaining = array_values(array_diff($remaining, [$found]));
            $order[] = $found;
        }
        if (!$remaining) {
            return [$order, null];
        }
        $walk = [$remaining[0]];
        while (true) {
            $preds = array_values(array_intersect($this->predecessors($walk[count($walk) - 1]), $remaining));
            $following = $preds[0];
            $i = array_search($following, $walk, true);
            if ($i !== false) {
                $cycle = [$walk[$i], ...array_reverse(array_slice($walk, $i + 1))];
                $sorted = $cycle;
                sort($sorted, SORT_STRING);
                $first = array_search($sorted[0], $cycle, true);
                $cycle = [...array_slice($cycle, $first), ...array_slice($cycle, 0, $first)];
                return [$order, implode(' -> ', [...$cycle, $cycle[0]])];
            }
            $walk[] = $following;
        }
    }

    private function compute(array $overrides = []): array
    {
        [$order] = $this->topology();
        $result = [];
        foreach ($order as $name) {
            $task = $this->tasks[$name];
            $duration = $overrides[$name] ?? $task->duration();
            $start = $task->day;
            foreach ($this->predecessors($name) as $a) {
                [, , $kind, $lag] = $this->deps["$a:$name"];
                $value = match ($kind) {
                    'FS' => $result[$a]['EF'] + $lag,
                    'SS' => $result[$a]['ES'] + $lag,
                    default => $result[$a]['EF'] + $lag - $duration
                };
                $start = max($start, $value);
            }
            $result[$name] = ['DUR' => $duration, 'ES' => $start, 'EF' => $start + $duration];
        }
        $total = max(array_column($result, 'EF'));
        foreach (array_reverse($order) as $name) {
            $finish = $total;
            foreach ($this->successors($name) as $b) {
                [, , $kind, $lag] = $this->deps["$name:$b"];
                $value = match ($kind) {
                    'FS' => $result[$b]['LS'] - $lag,
                    'SS' => $result[$b]['LS'] - $lag + $result[$name]['DUR'],
                    default => $result[$b]['LF'] - $lag
                };
                $finish = min($finish, $value);
            }
            $result[$name]['LF'] = $finish;
            $result[$name]['LS'] = $finish - $result[$name]['DUR'];
            $result[$name]['TF'] = $result[$name]['LS'] - $result[$name]['ES'];
        }
        foreach ($this->names() as $name) {
            $float = $total - $result[$name]['EF'];
            foreach ($this->successors($name) as $b) {
                $float = min($float, $this->margin($name, $b, $result));
            }
            $result[$name]['FF'] = $float;
        }
        return [$result, $total];
    }

    private function margin(string $a, string $b, array $schedule): int
    {
        [, , $kind, $lag] = $this->deps["$a:$b"];
        return match ($kind) {
            'FS' => $schedule[$b]['ES'] - $schedule[$a]['EF'] - $lag,
            'SS' => $schedule[$b]['ES'] - $schedule[$a]['ES'] - $lag,
            default => $schedule[$b]['EF'] - $schedule[$a]['EF'] - $lag
        };
    }

    private function critical(array $schedule): array
    {
        return array_values(array_filter($this->names(), fn($name) => $schedule[$name]['TF'] === 0));
    }

    private function criticalPaths(array $schedule): array
    {
        $selected = $this->critical($schedule);
        $edges = [];
        $incoming = [];
        foreach ($this->deps as [$a, $b]) {
            if (in_array($a, $selected, true) && in_array($b, $selected, true) && $this->margin($a, $b, $schedule) === 0) {
                $edges[$a][] = $b;
                $incoming[$b] = true;
            }
        }
        foreach ($edges as &$children) {
            sort($children, SORT_STRING);
        }
        unset($children);
        $paths = [];
        $visit = function (array $path) use (&$visit, &$paths, $edges): void {
            $last = $path[count($path) - 1];
            if (!isset($edges[$last])) {
                $paths[] = $path;
            } else {
                foreach ($edges[$last] as $name) {
                    $visit([...$path, $name]);
                }
            }
        };
        foreach ($selected as $name) {
            if (!isset($incoming[$name])) {
                $visit([$name]);
            }
        }
        return $paths;
    }

    private function signed(int $value): string
    {
        return sprintf('%+d', $value);
    }

    private function decimal(int $numerator, int $denominator): string
    {
        $hundredths = intdiv($numerator * 100, $denominator);
        return sprintf('%d.%02d', intdiv($hundredths, 100), $hundredths % 100);
    }

    private function dateValue(string $text): DateTimeImmutable
    {
        [$year, $month, $day] = array_map('intval', explode('-', $text));
        if (!checkdate($month, $day, $year)) {
            throw new ScheduleError("invalid date $text");
        }
        return new DateTimeImmutable($text, new DateTimeZone('UTC'));
    }

    private function dateText(DateTimeImmutable $date): string
    {
        return $date->format('Y-m-d D');
    }

    private function working(DateTimeImmutable $date): bool
    {
        return (int)$date->format('N') <= 5 && !isset($this->holidays[$date->format('Y-m-d')]);
    }

    private function calendar(array $schedule, int $total): void
    {
        $dates = [];
        $current = $this->start;
        while (count($dates) < $total) {
            if ($this->working($current)) {
                $dates[] = $current;
            }
            $current = $current->modify('+1 day');
        }
        $names = $this->names();
        usort($names, fn($a, $b) => ($schedule[$a]['ES'] <=> $schedule[$b]['ES']) ?: strcmp($a, $b));
        foreach ($names as $name) {
            echo "$name ", $this->dateText($dates[$schedule[$name]['ES']]), ' - ',
                $this->dateText($dates[$schedule[$name]['EF'] - 1]), "\n";
        }
        $first = $dates[0];
        $finish = $dates[count($dates) - 1];
        echo 'project ', $this->dateText($first), ' - ', $this->dateText($finish),
            ", $total working days, ", (int)$first->diff($finish)->format('%a') + 1, " calendar days\n";
        if ($this->deadline !== null) {
            $days = 0;
            $lower = min($finish, $this->deadline);
            $upper = max($finish, $this->deadline);
            for ($current = $lower->modify('+1 day'); $current <= $upper; $current = $current->modify('+1 day')) {
                if ($this->working($current)) {
                    $days++;
                }
            }
            echo 'deadline ', $this->dateText($this->deadline), $finish <= $this->deadline ?
                " met, $days working days to spare\n" : " missed by $days working days\n";
        }
        $holidays = $this->holidays;
        ksort($holidays, SORT_STRING);
        $selected = [];
        foreach ($holidays as $date) {
            if ($date >= $first && $date <= $finish && (int)$date->format('N') <= 5) {
                $selected[] = $this->dateText($date);
            }
        }
        echo 'holidays in span: ', $selected ? implode(', ', $selected) : 'none', "\n";
    }

    private function usage(array $schedule, string $resource): array
    {
        $daily = [];
        foreach ($this->tasks as $name => $task) {
            if ($task->resource !== $resource) {
                continue;
            }
            for ($day = $schedule[$name]['ES']; $day < $schedule[$name]['EF']; $day++) {
                $daily[$day] = ($daily[$day] ?? 0) + $task->units;
            }
        }
        return $daily;
    }

    private function level(int $limit, array $schedule, int $total): void
    {
        $capacity = fn($r) => $this->capacities[$r] ?? $limit;
        foreach ($this->names() as $name) {
            $task = $this->tasks[$name];
            if ($task->units > $capacity($task->resource)) {
                throw new ScheduleError('capacity ' . $capacity($task->resource) . " too small for $name");
            }
        }
        $decided = [];
        $order = [];
        $daily = [];
        while (count($decided) < count($this->tasks)) {
            $eligible = [];
            foreach ($this->names() as $name) {
                if (!isset($decided[$name]) && !array_diff($this->predecessors($name), array_keys($decided))) {
                    $eligible[] = $name;
                }
            }
            usort($eligible, fn($a, $b) => ($schedule[$a]['LS'] <=> $schedule[$b]['LS']) ?: strcmp($a, $b));
            $name = $eligible[0];
            $task = $this->tasks[$name];
            $start = $task->day;
            foreach ($this->predecessors($name) as $a) {
                [, , $kind, $lag] = $this->deps["$a:$name"];
                $value = match ($kind) {
                    'FS' => $decided[$a]['F'] + $lag,
                    'SS' => $decided[$a]['S'] + $lag,
                    default => $decided[$a]['F'] + $lag - $task->duration()
                };
                $start = max($start, $value);
            }
            while (true) {
                $valid = true;
                for ($day = $start; $day < $start + $task->duration(); $day++) {
                    if (($daily[$task->resource][$day] ?? 0) + $task->units > $capacity($task->resource)) {
                        $valid = false;
                        break;
                    }
                }
                if ($valid) {
                    break;
                }
                $start++;
            }
            $finish = $start + $task->duration();
            $decided[$name] = ['S' => $start, 'F' => $finish];
            for ($day = $start; $day < $finish; $day++) {
                $daily[$task->resource][$day] = ($daily[$task->resource][$day] ?? 0) + $task->units;
            }
            $order[] = $name;
        }
        echo "level capacity $limit: duration $total -> ", max(array_column($decided, 'F')), "\n";
        foreach ($order as $name) {
            echo "$name start {$decided[$name]['S']} finish {$decided[$name]['F']} shift ",
                $decided[$name]['S'] - $schedule[$name]['ES'], "\n";
        }
        $resources = array_unique(array_map(fn($t) => $t->resource, $this->tasks));
        sort($resources, SORT_STRING);
        foreach ($resources as $r) {
            echo "resource $r capacity ", $capacity($r), ' peak ', max([0, ...$this->usage($schedule, $r)]),
                ' -> ', max([0, ...($daily[$r] ?? [])]), "\n";
        }
    }

    private function crash(int $budget, int $initial): void
    {
        $remaining = $budget;
        $steps = 0;
        $final = $initial;
        while (true) {
            [$schedule, $total] = $this->compute();
            $candidates = [];
            foreach ($this->critical($schedule) as $name) {
                $task = $this->tasks[$name];
                if ($task->crashLimit !== null && $task->used < $task->crashLimit &&
                    $this->compute([$name => $task->duration() - 1])[1] < $total) {
                    $candidates[] = $name;
                }
            }
            if (!$candidates) {
                $reason = 'no candidate';
                break;
            }
            usort($candidates, fn($a, $b) => ($this->tasks[$a]->cost <=> $this->tasks[$b]->cost) ?: strcmp($a, $b));
            $name = $candidates[0];
            $task = $this->tasks[$name];
            if ($task->cost > $remaining) {
                $reason = 'insufficient budget';
                break;
            }
            $before = $task->duration();
            $task->used++;
            $remaining -= $task->cost;
            $steps++;
            $final = $this->compute()[1];
            echo "step $steps: $name $before -> ", $task->duration(), ", cost {$task->cost}, project $final\n";
        }
        echo "crash done: $steps days, cost ", $budget - $remaining,
            ", project $initial -> $final, budget left $remaining, $reason\n";
    }

    private function analyze(string $command, array $args): void
    {
        if (!$this->tasks) {
            throw new ScheduleError('no tasks');
        }
        [, $cycle] = $this->topology();
        if ($cycle !== null) {
            throw new ScheduleError("cycle $cycle");
        }
        if ($command === 'CALENDAR' && $this->start === null) {
            throw new ScheduleError('no start date');
        }
        if ($command === 'LOAD' && !array_filter($this->tasks, fn($t) => $t->resource === $args[0])) {
            throw new ScheduleError("unknown resource {$args[0]}");
        }
        if ($command === 'WHATIF') {
            $this->requireTask($args[0]);
        }
        if ($command === 'VARIANCE' && $this->baseline === null) {
            throw new ScheduleError('no baseline');
        }
        [$schedule, $total] = $this->compute();
        $names = $this->names();
        switch ($command) {
            case 'CPM':
                $width = max(4, max(array_map('strlen', $names)));
                echo str_pad('TASK', $width), implode('', array_map(fn($s) => str_pad($s, 5, ' ', STR_PAD_LEFT), ['DUR', 'ES', 'EF', 'LS', 'LF', 'TF', 'FF'])), "\n";
                foreach ($names as $name) {
                    echo str_pad($name, $width);
                    foreach (['DUR', 'ES', 'EF', 'LS', 'LF', 'TF', 'FF'] as $key) {
                        echo str_pad((string)$schedule[$name][$key], 5, ' ', STR_PAD_LEFT);
                    }
                    echo $schedule[$name]['TF'] === 0 ? " *\n" : "\n";
                }
                echo "project duration $total\n";
                break;
            case 'CRITICAL':
            case 'PERTSUM':
                $paths = $this->criticalPaths($schedule);
                if ($command === 'CRITICAL') {
                    echo 'critical paths: ', count($paths), "\n";
                }
                foreach ($paths as $path) {
                    $notation = implode(' -> ', $path);
                    if ($command === 'CRITICAL') {
                        echo "$notation\n";
                    } else {
                        $expected = 0;
                        $variance = 0;
                        foreach ($path as $name) {
                            $task = $this->tasks[$name];
                            [$o, $m, $p] = $task->estimate ?? array_fill(0, 3, $task->duration());
                            $expected += $o + 4 * $m + $p;
                            $variance += ($p - $o) ** 2;
                        }
                        echo "$notation: expected ", $this->decimal($expected, 6), ' variance ', $this->decimal($variance, 36), "\n";
                    }
                }
                break;
            case 'SLACK':
                $groups = [];
                foreach ($names as $name) {
                    $groups[$schedule[$name]['TF']][] = $name;
                }
                ksort($groups, SORT_NUMERIC);
                foreach ($groups as $float => $tasks) {
                    echo "float $float: ", implode(' ', $tasks), "\n";
                }
                break;
            case 'DRAG':
                foreach ($this->critical($schedule) as $name) {
                    echo "$name drag ", $total - $this->compute([$name => 0])[1], "\n";
                }
                break;
            case 'STATS':
                $count = count($this->critical($schedule));
                $kinds = ['FS' => 0, 'SS' => 0, 'FF' => 0];
                foreach ($this->deps as [, , $kind]) {
                    $kinds[$kind]++;
                }
                echo 'tasks ', count($names), ", critical $count, dependencies ", count($this->deps),
                    " (FS {$kinds['FS']}, SS {$kinds['SS']}, FF {$kinds['FF']})\n";
                $work = [];
                foreach ($this->tasks as $task) {
                    $work[$task->resource] = ($work[$task->resource] ?? 0) + $task->duration() * $task->units;
                }
                ksort($work, SORT_STRING);
                $parts = [];
                foreach ($work as $r => $value) {
                    $parts[] = "$r $value";
                }
                echo 'work ', implode(', ', $parts), "\n";
                $sum = array_sum(array_column($schedule, 'TF'));
                echo "float total $sum, average ", $this->decimal($sum, count($names)), "\n";
                echo "duration $total, critical share ", $this->decimal(100 * $count, count($names)), "%\n";
                break;
            case 'CALENDAR':
                $this->calendar($schedule, $total);
                break;
            case 'GANTT':
                if ($total > 60) {
                    throw new ScheduleError("chart too wide ($total days)");
                }
                $width = max(array_map('strlen', $names));
                echo str_repeat(' ', $width), ' |';
                for ($day = 0; $day < $total; $day++) {
                    echo $day % 10;
                }
                echo "|\n";
                usort($names, fn($a, $b) => ($schedule[$a]['ES'] <=> $schedule[$b]['ES']) ?: strcmp($a, $b));
                foreach ($names as $name) {
                    $value = $schedule[$name];
                    $bar = '';
                    for ($day = 0; $day < $total; $day++) {
                        if ($day >= $value['ES'] && $day < $value['EF']) {
                            $bar .= $value['TF'] === 0 ? '=' : '-';
                        } elseif ($day >= $value['EF'] && $day < $value['LF']) {
                            $bar .= '.';
                        } else {
                            $bar .= ' ';
                        }
                    }
                    echo str_pad($name, $width), " |$bar|\n";
                }
                break;
            case 'LEVEL':
                $this->level((int)$args[0], $schedule, $total);
                break;
            case 'LOAD':
                $resource = $args[0];
                $daily = $this->usage($schedule, $resource);
                $values = [];
                for ($day = 0; $day < $total; $day++) {
                    $values[] = $daily[$day] ?? 0;
                }
                echo "load $resource: ", implode(' ', $values), "\n";
                $peak = max($values);
                echo "peak $peak on day ", array_search($peak, $values, true), "\n";
                if (isset($this->capacities[$resource])) {
                    echo "capacity {$this->capacities[$resource]} exceeded on ",
                        count(array_filter($values, fn($u) => $u > $this->capacities[$resource])), " days\n";
                }
                break;
            case 'CRASH':
                $this->crash((int)$args[0], $total);
                break;
            case 'WHATIF':
                [$name, $duration] = $args;
                [$after, $newTotal] = $this->compute([$name => (int)$duration]);
                echo "whatif $name ", $this->tasks[$name]->duration(), " -> $duration: project $total -> $newTotal\n";
                foreach ($names as $t) {
                    $parts = [];
                    foreach (['ES', 'EF', 'TF'] as $key) {
                        if ($schedule[$t][$key] !== $after[$t][$key]) {
                            $parts[] = "$key {$schedule[$t][$key]}->{$after[$t][$key]}";
                        }
                    }
                    if ($parts) {
                        echo "$t ", implode(' ', $parts), "\n";
                    }
                }
                if ($this->critical($schedule) !== $this->critical($after)) {
                    echo 'critical ', implode(' ', $this->critical($schedule)), ' -> ', implode(' ', $this->critical($after)), "\n";
                }
                break;
            case 'BASELINE':
                $saved = [];
                foreach ($names as $name) {
                    $saved[$name] = [$schedule[$name]['ES'], $schedule[$name]['EF']];
                }
                $this->baseline = [$total, $saved];
                echo 'baseline saved: ', count($names), " tasks, duration $total\n";
                break;
            case 'VARIANCE':
                [$oldTotal, $old] = $this->baseline;
                echo "variance: duration $oldTotal -> $total (", $this->signed($total - $oldTotal), ")\n";
                $all = array_unique(array_merge($names, array_keys($old)));
                sort($all, SORT_STRING);
                $printed = false;
                foreach ($all as $name) {
                    if (!isset($this->tasks[$name])) {
                        echo "$name removed\n";
                    } elseif (!isset($old[$name])) {
                        echo "$name new\n";
                    } elseif ([$schedule[$name]['ES'], $schedule[$name]['EF']] !== $old[$name]) {
                        echo "$name start ", $this->signed($schedule[$name]['ES'] - $old[$name][0]),
                            ' finish ', $this->signed($schedule[$name]['EF'] - $old[$name][1]), "\n";
                    } else {
                        continue;
                    }
                    $printed = true;
                }
                if (!$printed) {
                    echo "no task changes\n";
                }
                break;
        }
    }

    public function execute(string $line): void
    {
        $args = explode(' ', $line);
        $command = array_shift($args);
        try {
            if (in_array($command, self::ANALYSIS, true)) {
                $this->analyze($command, $args);
                return;
            }
            $name = $args[0] ?? null;
            switch ($command) {
                case 'TASK':
                    if (isset($this->tasks[$name])) {
                        throw new ScheduleError("task $name already exists");
                    }
                    $this->tasks[$name] = new Task((int)$args[1], $args[2], (int)$args[3]);
                    echo "task $name added\n";
                    return;
                case 'DEP':
                case 'UNDEP':
                    [$a, $b] = $args;
                    $this->requireTask($a);
                    $this->requireTask($b);
                    $key = "$a:$b";
                    if ($command === 'DEP') {
                        if ($a === $b) {
                            throw new ScheduleError("self dependency $a");
                        }
                        if (isset($this->deps[$key])) {
                            throw new ScheduleError("dependency $a -> $b already exists");
                        }
                        $this->deps[$key] = [$a, $b, $args[2], (int)$args[3]];
                        echo "dependency $a -> $b {$args[2]}", $this->signed((int)$args[3]), " added\n";
                    } else {
                        if (!isset($this->deps[$key])) {
                            throw new ScheduleError("no dependency $a -> $b");
                        }
                        unset($this->deps[$key]);
                        echo "dependency $a -> $b removed\n";
                    }
                    return;
                case 'CAPACITY':
                    $this->capacities[$name] = (int)$args[1];
                    echo "capacity $name {$args[1]}\n";
                    return;
                case 'START':
                case 'HOLIDAY':
                case 'DEADLINE':
                    $date = $this->dateValue($name);
                    if ($command === 'START') {
                        $this->start = $date;
                    } elseif ($command === 'DEADLINE') {
                        $this->deadline = $date;
                    } else {
                        if (isset($this->holidays[$name])) {
                            throw new ScheduleError("duplicate holiday $name");
                        }
                        $this->holidays[$name] = $date;
                    }
                    echo strtolower($command), ' ', $this->dateText($date), "\n";
                    return;
                case 'LIST':
                    echo 'tasks ', count($this->tasks), ', dependencies ', count($this->deps), ', holidays ', count($this->holidays), "\n";
                    foreach ($this->names() as $t) {
                        $task = $this->tasks[$t];
                        $preds = $this->predecessors($t);
                        echo "$t duration ", $task->duration(), " resource {$task->resource} units {$task->units} preds ",
                            $preds ? implode(' ', $preds) : 'none', "\n";
                    }
                    return;
            }
            $this->requireTask($name);
            $task = $this->tasks[$name];
            switch ($command) {
                case 'REMOVE':
                    $removed = 0;
                    foreach ($this->deps as $key => [$a, $b]) {
                        if ($a === $name || $b === $name) {
                            unset($this->deps[$key]);
                            $removed++;
                        }
                    }
                    unset($this->tasks[$name]);
                    echo "task $name removed with $removed dependencies\n";
                    break;
                case 'NOTBEFORE':
                    $task->day = (int)$args[1];
                    echo "notbefore $name {$args[1]}\n";
                    break;
                case 'CRASHCOST':
                    $maximum = (int)$args[1];
                    $cost = (int)$args[2];
                    if ($maximum >= $task->base) {
                        throw new ScheduleError("crash limit too large for $name");
                    }
                    if ($maximum < $task->used) {
                        throw new ScheduleError("crash limit below used days for $name");
                    }
                    $task->crashLimit = $maximum;
                    $task->cost = $cost;
                    echo "crash $name max $maximum cost $cost\n";
                    break;
                case 'UNCRASH':
                    echo "uncrash $name restored {$task->used} days\n";
                    $task->used = 0;
                    break;
                case 'PERT':
                    [$o, $m, $p] = array_map('intval', array_slice($args, 1));
                    if ($o > $m || $m > $p) {
                        throw new ScheduleError('invalid estimate');
                    }
                    $task->estimate = [$o, $m, $p];
                    echo "pert $name expected ", $this->decimal($o + 4 * $m + $p, 6),
                        ' variance ', $this->decimal(($p - $o) ** 2, 36), "\n";
                    break;
                case 'SHOW':
                    echo "task $name duration ", $task->duration(), " resource {$task->resource} units {$task->units}",
                        $task->day === 0 ? '' : " notbefore {$task->day}", "\n";
                    $preds = [];
                    foreach ($this->predecessors($name) as $a) {
                        [, , $kind, $lag] = $this->deps["$a:$name"];
                        $preds[] = "$a $kind" . $this->signed($lag);
                    }
                    $succs = [];
                    foreach ($this->successors($name) as $b) {
                        [, , $kind, $lag] = $this->deps["$name:$b"];
                        $succs[] = "$b $kind" . $this->signed($lag);
                    }
                    echo 'preds: ', $preds ? implode(', ', $preds) : 'none', "\n";
                    echo 'succs: ', $succs ? implode(', ', $succs) : 'none', "\n";
                    echo $task->crashLimit !== null ? "crash: max {$task->crashLimit} used {$task->used} cost {$task->cost}" : 'crash: none', "\n";
                    echo $task->estimate !== null ? 'pert: ' . implode(' ', $task->estimate) : 'pert: none', "\n";
                    [, $cycle] = $this->topology();
                    if ($cycle !== null) {
                        echo "schedule: unavailable\n";
                    } else {
                        [$schedule] = $this->compute();
                        $parts = [];
                        foreach (['ES', 'EF', 'LS', 'LF', 'TF', 'FF'] as $key) {
                            $parts[] = "$key {$schedule[$name][$key]}";
                        }
                        echo 'schedule: ', implode(' ', $parts), $schedule[$name]['TF'] === 0 ? ' critical' : '', "\n";
                    }
                    break;
                case 'IMPACT':
                    $seen = [$name];
                    for ($i = 0; $i < count($seen); $i++) {
                        foreach ($this->successors($seen[$i]) as $b) {
                            if (!in_array($b, $seen, true)) {
                                $seen[] = $b;
                            }
                        }
                    }
                    $affected = array_diff($seen, [$name]);
                    sort($affected, SORT_STRING);
                    echo "impact $name: ", $affected ? implode(' ', $affected) : 'none', "\n";
                    break;
            }
        } catch (ScheduleError $error) {
            echo 'error: ', $error->getMessage(), "\n";
        }
    }
}

$scheduler = new Scheduler();
$count = (int)fgets(STDIN);
for ($i = 0; $i < $count; $i++) {
    $scheduler->execute(rtrim(fgets(STDIN), "\r\n"));
}
