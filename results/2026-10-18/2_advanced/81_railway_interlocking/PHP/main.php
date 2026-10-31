<?php

foreach (['layout', 'interlocking', 'signals', 'trains', 'safety'] as $module)
    require_once __DIR__ . "/$module.php";
final class Simulation
{
    private Layout $layout;
    private Interlocking $interlocking;
    private Safety $safety;
    private array
        $routes,
        $trains,
        $planned = [],
        $events = [],
        $snapshotTimes = [],
        $queue = [],
        $logLines = [],
        $snapshots = []
    ;
    private int $end, $throwTime, $overlapTime, $time = 0, $requestCount = 0, $dropped = 0;

    public function __construct()
    {
        $this->layout = new Layout();
        $this->interlocking = new Interlocking($this->layout);
        $this->routes = $this->interlocking->routes;
        $this->safety = new Safety();
        [$this->trains, $requests] = readTrains();
        foreach ($requests as [$t, $train, $route])
            $this->planned[$t][] = [$train, $route];
        foreach (file('input/events.txt', FILE_IGNORE_NEW_LINES) as $line) {
            $f = explode(' ', $line);
            $t = (int) array_shift($f);
            $command = array_shift($f);
            $this->events[$t][] = [$command, $f];
        }
        $settings = [];
        foreach (file('input/params.txt', FILE_IGNORE_NEW_LINES) as $line) {
            $f = explode(' ', $line);
            $key = array_shift($f);
            $settings[$key] = array_map(intval(...), $f);
        }
        $this->end = $settings['END'][0];
        $this->throwTime = $settings['THROW'][0];
        $this->overlapTime = $settings['OVERLAP'][0];
        $this->snapshotTimes = $settings['SNAPSHOTS'];
    }

    private function log(string $text): void
    {
        $this->logLines[] = $this->time . ' ' . $text;
    }

    private function occupied(string $name): bool
    {
        $s = $this->layout->sections[$name];
        return (bool) $s->occupants || $s->failed;
    }

    private function startThrow(object $p, string $target): void
    {
        $p->moving = true;
        $p->target = $target;
        $p->completion = $this->time + $this->throwTime;
        $this->log("MOVE {$p->name} $target until {$p->completion}");
    }

    private function addRequest(string $name, string $requester): void
    {
        $q = (object) [
            'number' => ++$this->requestCount,
            'route' => $name,
            'time' => $this->time,
            'reason' => null,
        ];
        $this->log("REQUEST q{$q->number} $name $requester");
        ++$this->routes[$name]->requests;
        $this->queue[] = $q;
    }

    private function cancel(string $name): void
    {
        $removed = array_filter($this->queue, fn($q) => $q->route === $name);
        if ($removed) {
            foreach ($removed as $q) {
                $this->log("DROP q{$q->number} $name");
                ++$this->dropped;
            }
            $this->queue = array_values(array_filter($this->queue, fn($q) => $q->route !== $name));
            return;
        }
        $r = $this->routes[$name];
        if ($r->state === 'LOCKED') {
            ++$r->cancels;
            $g = $this->layout->signals[$r->start];
            if ($g->aspect !== 'RED' && $this->occupied($g->section)) {
                $r->state = 'APPROACH';
                $r->releaseTime = $this->time + $r->approachTime;
                $this->log("CANCEL $name approach until {$r->releaseTime}");
            } else {
                $this->interlocking->release($r);
                $this->log("CANCEL $name released");
            }
        } else
            $this->log("CANCEL $name " . ($r->state === null ? 'none' : 'refused'));
    }

    private function executeEvents(): void
    {
        foreach ($this->events[$this->time] ?? [] as [$command, $arguments]) {
            $name = $arguments[0];
            if ($command === 'REQUEST')
                $this->addRequest($name, 'OPERATOR');
            elseif ($command === 'CANCEL')
                $this->cancel($name);
            elseif ($command === 'THROW') {
                $p = $this->layout->points[$name];
                $target = $arguments[1];
                $result = $p->locks
                    ? 'locked'
                    : (
                        $p->failed
                            ? 'failed'
                            : (
                                $p->moving
                                    ? 'moving'
                                    : (
                                        $this->occupied($p->common)
                                            ? 'occupied'
                                            : ($p->position === $target ? 'none' : 'start')
                                    )
                            )
                    );
                $this->log("THROW $name $target $result");
                if ($result === 'start')
                    $this->startThrow($p, $target);
            } elseif ($command === 'TCFAIL' || $command === 'TCFIX') {
                $this->layout->sections[$name]->failed = $command === 'TCFAIL';
                $this->log("$command $name");
            } else {
                $p = $this->layout->points[$name];
                $p->failed = $command === 'POINTFAIL';
                if ($p->failed && $p->moving)
                    $p->completion = null;
                $this->log("$command $name");
                if (!$p->failed && $p->moving)
                    $this->startThrow($p, $p->target);
            }
        }
    }

    private function oppositeLock(array $names, object $r): bool
    {
        return array_any($names, fn($name) => $this->routes[$name]->direction !== $r->direction);
    }

    private function requestReason(object $r): ?string
    {
        if ($r->state !== null)
            return 'busy';
        foreach ($r->conflicts as $name)
            if (in_array($this->routes[$name]->state, ['LOCKED', 'APPROACH'], true))
                return 'conflict ' . $name;
        foreach ($r->sections as $name) {
            $s = $this->layout->sections[$name];
            if ($this->occupied($name))
                return 'occupied ' . $name;
            if ($s->routeLock !== null || $this->oppositeLock(array_keys($s->overlapLocks), $r))
                return 'locked ' . $name;
        }
        foreach ($r->overlap as $name) {
            $s = $this->layout->sections[$name];
            if ($this->occupied($name))
                return 'occupied ' . $name;
            $locks = array_keys($s->overlapLocks);
            if ($s->routeLock !== null)
                $locks[] = $s->routeLock;
            if ($this->oppositeLock($locks, $r))
                return 'locked ' . $name;
        }
        foreach ($r->requirements as [$name, $target]) {
            $p = $this->layout->points[$name];
            if (array_any($p->locks, fn($lock) => $lock[1] !== $target))
                return "point $name locked";
            if (!$p->moving && $p->position === $target || $p->moving && $p->target === $target)
                continue;
            if ($p->failed)
                return "point $name failed";
            if ($p->moving)
                return "point $name moving";
            if ($this->occupied($p->common))
                return "point $name occupied";
        }
        return null;
    }

    private function judgeRequests(): void
    {
        $waiting = [];
        foreach ($this->queue as $q) {
            $r = $this->routes[$q->route];
            $reason = $this->requestReason($r);
            if ($reason !== null) {
                if ($reason !== $q->reason) {
                    $this->log("WAIT q{$q->number} {$r->name} $reason");
                    $q->reason = $reason;
                }
                $waiting[] = $q;
                continue;
            }
            $this->interlocking->lock($r);
            $wait = $this->time - $q->time;
            $this->log("GRANT q{$q->number} {$r->name} wait $wait");
            ++$r->grants;
            $r->wait += $wait;
            $r->maxwait = max($r->maxwait, $wait);
            foreach ($r->requirements as [$name, $target]) {
                $p = $this->layout->points[$name];
                if (!$p->moving && $p->position !== $target)
                    $this->startThrow($p, $target);
            }
        }
        $this->queue = $waiting;
    }

    private function occupiedParts(object $train): array
    {
        $parts = [];
        if ($train->state === 'RUNNING') {
            $tail = $train->head - $train->length;
            foreach ($train->path as [$name, $start]) {
                $end = $start + $this->layout->sections[$name]->length;
                if ($start < $train->head && $end > $tail)
                    $parts[] = [$name, $start, max($tail, $start), min($train->head, $end)];
            }
        }
        return $parts;
    }

    private function headSection(object $train): array
    {
        for ($i = count($train->path) - 1; $i >= 0; --$i)
            if ($train->path[$i][1] < $train->head)
                return $train->path[$i];
        return $train->path[0];
    }

    private function nextStop(object $train): ?object
    {
        return $train->stops[$train->stopIndex] ?? null;
    }

    private function enter(object $train, array &$entered): bool
    {
        if ($train->state === 'EXITED')
            return false;
        if ($train->state === 'RUNNING')
            return true;
        $b = $this->layout->boundaries[$train->entry];
        if ($this->time < $train->entryTime || $this->occupied($b->section) || isset($entered[$train->entry]))
            return false;
        $train->state = 'RUNNING';
        $train->direction = $b->end === 'L' ? 'UP' : 'DOWN';
        $train->path = [[$b->section, 0]];
        $train->head = 0;
        $train->speed = $train->entrySpeed;
        $train->entered = $this->time;
        $entered[$train->entry] = true;
        $this->log("ENTER {$train->name} {$train->entry}");
        return true;
    }

    private function finishDwell(object $train): bool
    {
        if (!$train->dwelling)
            return true;
        $stop = $this->nextStop($train);
        if ($this->time < ($stop->arrival + $stop->dwell) || $this->time < $stop->scheduledDeparture)
            return false;
        $train->dwelling = false;
        $train->awaitingDeparture = $stop;
        ++$train->stopIndex;
        if ($stop->kind === 'TURN') {
            [$name, $start] = $this->headSection($train);
            $end = $start + $this->layout->sections[$name]->length;
            $path = [];
            foreach (array_reverse($this->occupiedParts($train)) as [$section, $origin, $lo, $hi])
                $path[] = [$section, $end - ($origin + $this->layout->sections[$section]->length)];
            $train->path = $path;
            $train->head = $end - ($train->head - $train->length);
            $train->direction = $train->direction === 'UP' ? 'DOWN' : 'UP';
            $this->log("REVERSE {$train->name} {$stop->section}");
        }
        return true;
    }

    private function limitDistance(object $train): ?int
    {
        if ($train->boundary !== null)
            return null;
        [$name, $start] = $this->headSection($train);
        $distance = $start + $this->layout->sections[$name]->length - $train->head;
        while (true) {
            $g = $this->layout->signalsAt[$name . ':' . $train->direction] ?? null;
            if ($g !== null && $g->aspect === 'RED')
                return $distance;
            $stop = $this->nextStop($train);
            if ($stop !== null && $stop->section === $name)
                return $distance;
            [$kind, $following] = $this->layout->beyond($name, $train->direction);
            if ($kind === 'boundary')
                return null;
            if ($kind === 'buffer' || $kind === 'impassable')
                return $distance;
            $distance += $this->layout->sections[$following]->length;
            $name = $following;
        }
    }

    private function passSignal(object $train, object $signal): void
    {
        $route = null;
        foreach ($this->routes as $r)
            if ($r->start === $signal->name && in_array($r->state, ['LOCKED', 'APPROACH'], true)) {
                $route = $r;
                break;
            }
        $name = $route?->name ?? '-';
        $this->log("PASS {$train->name} {$signal->name} {$signal->aspect} $name");
        ++$signal->passes;
        ++$train->passes;
        if ($route !== null) {
            $route->state = 'USED';
            ++$route->uses;
        }
        $details = null;
        if ($signal->aspect === 'RED') {
            $this->log("SPAD {$train->name} {$signal->name}");
            $details = $train->name . ' ' . $signal->name;
            $train->emergency = true;
        }
        $this->safety->check($this->time, 'SIGNAL_PASSING', $details);
    }

    private function move(object $train, int $distance): void
    {
        [$name, $start] = $this->headSection($train);
        $remaining = $distance;
        while ($remaining > 0) {
            if ($train->boundary !== null) {
                $train->head += $remaining;
                break;
            }
            $end = $start + $this->layout->sections[$name]->length;
            if (($train->head + $remaining) <= $end) {
                $train->head += $remaining;
                break;
            }
            $remaining -= $end - $train->head;
            $train->head = $end;
            $g = $this->layout->signalsAt[$name . ':' . $train->direction] ?? null;
            if ($g !== null)
                $this->passSignal($train, $g);
            $stop = $train->awaitingDeparture;
            if ($stop !== null && $stop->section === $name) {
                $this->log("DEPART {$train->name} $name");
                $stop->departure = $this->time;
                $train->awaitingDeparture = null;
            }
            [$kind, $following] = $this->layout->beyond($name, $train->direction);
            if ($kind === 'boundary') {
                $train->boundary = $following;
                $train->boundaryCoordinate = $end;
            } else {
                $name = $following;
                $start = $end;
                $train->path[] = [$name, $start];
            }
        }
    }

    private function runTrains(): void
    {
        $entered = [];
        foreach ($this->trains as $train) {
            if (!$this->enter($train, $entered) || !$this->finishDwell($train))
                continue;
            $oldSpeed = $train->speed;
            $speed = selectSpeed($train, $this->limitDistance($train));
            $this->move($train, $speed);
            $train->speed = $speed;
            $train->distance += $speed;
            $train->maximumSpeed = max($train->maximumSpeed, $speed);
            if (!$speed)
                $train->emergency = false;
            [$name, $start] = $this->headSection($train);
            $stop = $this->nextStop($train);
            $arrived =
                $stop !== null
                && $speed === 0
                && $name === $stop->section
                && $train->head === ($start + $this->layout->sections[$name]->length);
            if ($arrived) {
                $train->dwelling = true;
                $stop->arrival = $this->time;
                $this->log("ARRIVE {$train->name} $name");
            }
            if (!$speed && !$arrived) {
                ++$train->standing;
                if ($oldSpeed > 0)
                    $this->log("HOLD {$train->name} $name");
            }
            if ($train->boundary !== null && ($train->head - $train->length) >= $train->boundaryCoordinate) {
                $train->state = 'EXITED';
                $train->exited = $this->time;
                $this->log("EXIT {$train->name} {$train->boundary}");
            }
        }
    }

    private function recomputeOccupancy(): void
    {
        foreach ($this->layout->sections as $s)
            $s->occupants = [];
        foreach ($this->trains as $train)
            foreach ($this->occupiedParts($train) as [$name, $start, $lo, $hi]) {
                $s = $this->layout->sections[$name];
                if (!in_array($train->name, $s->occupants, true))
                    $s->occupants[] = $train->name;
            }
    }

    private function sectionalRelease(): void
    {
        foreach ($this->routes as $r) {
            if ($r->state !== 'USED')
                continue;
            $remaining = array_values(array_filter(
                $r->sections,
                fn($name) => $this->layout->sections[$name]->routeLock === $r->name,
            ));
            foreach ($remaining as $name)
                if ($this->occupied($name))
                    $r->passed[$name] = true;
            foreach ($remaining as $name) {
                if (!isset($r->passed[$name]) || $this->occupied($name))
                    break;
                $this->interlocking->unlockSection($r, $name);
                $this->log("RELEASE {$r->name} $name");
            }
            if (!array_any(
                $r->sections,
                fn($name) => $this->layout->sections[$name]->routeLock === $r->name,
            )) {
                $this->interlocking->release($r);
                $this->log('DONE ' . $r->name);
            } elseif ($r->overlap && $r->overlapLocked) {
                $r->overlapCounter = $this->occupied($r->sections[count($r->sections) - 1])
                    ? $r->overlapCounter + 1
                    : 0;
                if ($r->overlapCounter >= $this->overlapTime) {
                    $this->interlocking->unlockOverlap($r);
                    $this->log('OVERLAP ' . $r->name);
                }
            }
        }
    }

    private function statistics(): void
    {
        foreach ($this->routes as $r)
            $r->lockedSeconds += (int) ($r->state !== null);
        foreach ($this->layout->points as $p) {
            $p->lockedSeconds += (int) (bool) $p->locks;
            $p->movingSeconds += (int) $p->moving;
        }
        foreach ($this->layout->sections as $s) {
            $s->occupiedSeconds += (int) $this->occupied($s->name);
            $s->lockedSeconds += (int) ($s->routeLock !== null || (bool) $s->overlapLocks);
            foreach ($s->occupants as $name)
                $s->trains[$name] = true;
        }
        foreach ($this->layout->signals as $g)
            ++$g->seconds[$g->aspect];
    }

    private function diagram(): array
    {
        $rowMax = $columnMax = 0;
        foreach ($this->layout->sections as $s) {
            $rowMax = max($rowMax, $s->row);
            $columnMax = max($columnMax, $s->last);
        }
        foreach ([
            ...array_values($this->layout->points),
            ...array_values($this->layout->signals),
            ...array_values($this->layout->buffers),
        ] as $item) {
            $rowMax = max($rowMax, $item->row);
            $columnMax = max($columnMax, $item->column);
        }
        foreach ($this->layout->labels as [$row, $column, $text]) {
            $rowMax = max($rowMax, $row);
            $columnMax = max($columnMax, $column + strlen($text) - 1);
        }
        $grid = array_fill(0, $rowMax + 1, str_repeat(' ', $columnMax + 1));
        foreach ($this->layout->labels as [$row, $column, $text])
            for ($i = 0; $i < strlen($text); ++$i)
                $grid[$row][$column + $i] = $text[$i];
        foreach ($this->layout->sections as $s) {
            $ch = $s->failed ? '#' : ($s->routeLock !== null ? '=' : ($s->overlapLocks ? '~' : '-'));
            for ($col = $s->first; $col <= $s->last; ++$col)
                $grid[$s->row][$col] = $ch;
        }
        foreach ($this->trains as $train)
            foreach ($this->occupiedParts($train) as [$name, $start, $lo, $hi]) {
                $s = $this->layout->sections[$name];
                $length = $s->length;
                $cells = $s->last - $s->first + 1;
                [$left, $right] = $train->direction === 'UP'
                    ? [$lo - $start, $hi - $start]
                    : [$length - ($hi - $start), $length - ($lo - $start)];
                for ($j = 0; $j < $cells; ++$j)
                    if (($left * $cells) < (($j + 1) * $length) && ($right * $cells) > ($j * $length)) {
                        $col = $s->first + $j;
                        $previous = $grid[$s->row][$col];
                        $grid[$s->row][$col] =
                            $previous >= 'a' && $previous <= 'z' || $previous === '*' ? '*' : $train->symbol;
                    }
            }
        foreach ($this->layout->buffers as $b)
            $grid[$b->row][$b->column] = '|';
        foreach ($this->layout->points as $p)
            $grid[$p->row][$p->column] = !$p->moving && !$p->failed ? $p->position : '?';
        foreach ($this->layout->signals as $g)
            $grid[$g->row][$g->column] = ['RED' => 'X', 'YELLOW' => 'Y', 'GREEN' => 'G'][$g->aspect];
        return array_map(fn($row) => rtrim($row, ' '), $grid);
    }

    private function snapshot(): void
    {
        $lines = ['SNAPSHOT ' . $this->time, ...$this->diagram()];
        foreach ($this->trains as $train)
            if ($train->state === 'RUNNING')
                $lines[] =
                    "TRAIN {$train->symbol} {$train->name} {$train->direction} {$train->speed} "
                    . implode(',', array_column($this->occupiedParts($train), 0));
        $routes = [];
        foreach ($this->routes as $r)
            if ($r->state !== null)
                $routes[] = $r->name . '/' . $r->state;
        $lines[] = 'ROUTES ' . ($routes ? implode(' ', $routes) : '-');
        array_push($this->snapshots, ...$lines);
    }

    private function writeReports(): void
    {
        $rows = [];
        $trainLines = ['train,location,scheduled,actual,delay'];
        $summary = [];
        $onTime = $late = $missing = $delaySum = $maxDelay = 0;
        foreach ($this->trains as $train) {
            $rows[] = [$train->name, 'enter:' . $train->entry, $train->entryTime, $train->entered];
            foreach ($train->stops as $stop) {
                $rows[] = [$train->name, 'arr:' . $stop->section, $stop->scheduledArrival, $stop->arrival];
                $rows[] = [
                    $train->name,
                    'dep:' . $stop->section,
                    $stop->scheduledDeparture,
                    $stop->departure,
                ];
            }
            $rows[] = [$train->name, 'exit:' . $train->exit, $train->scheduledExit, $train->exited];
        }
        foreach ($rows as [$name, $location, $scheduled, $actual]) {
            $timing = $actual === null ? '-,-' : $actual . ',' . ($actual - $scheduled);
            $trainLines[] = "$name,$location,$scheduled,$timing";
            if ($actual === null)
                ++$missing;
            elseif ($actual <= $scheduled)
                ++$onTime;
            else {
                ++$late;
                $delaySum += $actual - $scheduled;
                $maxDelay = max($maxDelay, $actual - $scheduled);
            }
        }
        $grants = 0;
        foreach ($this->routes as $r) {
            $summary[] = "ROUTE {$r->name} {$r->start}-{$r->finish} requests {$r->requests} grants {$r->grants} uses {$r->uses} cancels {$r->cancels} wait {$r->wait} maxwait {$r->maxwait} locked {$r->lockedSeconds}";
            $grants += $r->grants;
        }
        foreach ($this->layout->points as $p)
            $summary[] =
                "POINT {$p->name} throws {$p->throws} locked {$p->lockedSeconds} moving {$p->movingSeconds} final "
                . (!$p->moving && !$p->failed ? $p->position : '?');
        foreach ($this->layout->sections as $s)
            $summary[] =
                "SECTION {$s->name} occupied {$s->occupiedSeconds} locked {$s->lockedSeconds} trains "
                . count($s->trains);
        foreach ($this->layout->signals as $g)
            $summary[] = "SIGNAL {$g->name} red {$g->seconds['RED']} yellow {$g->seconds['YELLOW']} green {$g->seconds['GREEN']} passes {$g->passes}";
        $states = ['EXITED' => 0, 'RUNNING' => 0, 'WAITING' => 0];
        foreach ($this->trains as $train) {
            $summary[] = "TRAIN {$train->name} {$train->symbol} {$train->state} distance {$train->distance} maxspeed {$train->maximumSpeed} standing {$train->standing} passes {$train->passes}";
            ++$states[$train->state];
        }
        $summary[] =
            'TRAINS total '
            . count($this->trains)
            . " exited {$states['EXITED']} running {$states['RUNNING']} waiting {$states['WAITING']}";
        $summary[] = "PUNCTUALITY on_time $onTime late $late missing $missing total_delay $delaySum max_delay $maxDelay";
        $summary[] =
            "REQUESTS total {$this->requestCount} granted $grants dropped {$this->dropped} pending "
            . count($this->queue);
        if (!is_dir('output'))
            mkdir('output');
        foreach ([
            'events.txt' => $this->logLines,
            'snapshots.txt' => $this->snapshots,
            'train_log.csv' => $trainLines,
            'safety.txt' => $this->safety->report(),
            'summary.txt' => $summary,
        ] as $name => $lines)
            file_put_contents('output/' . $name, $lines ? implode("\n", $lines) . "\n" : '');
    }

    public function run(): void
    {
        for ($this->time = 0; $this->time <= $this->end; ++$this->time) {
            foreach ($this->layout->points as $p)
                if ($p->moving && $p->completion === $this->time) {
                    $p->position = $p->target;
                    $p->moving = false;
                    $p->completion = null;
                    $this->log("POINT {$p->name} {$p->position}");
                    ++$p->throws;
                }
            foreach ($this->routes as $r)
                if ($r->state === 'APPROACH' && $r->releaseTime === $this->time) {
                    $this->interlocking->release($r);
                    $this->log('TIMEOUT ' . $r->name);
                }
            foreach ($this->planned[$this->time] ?? [] as [$train, $route])
                $this->addRequest($route, $train);
            $this->executeEvents();
            $this->judgeRequests();
            foreach (signalAspects($this->interlocking, $this->occupied(...)) as [$g, $aspect])
                if ($g->aspect !== $aspect) {
                    $g->aspect = $aspect;
                    $this->log("SIGNAL {$g->name} $aspect");
                }
            $this->runTrains();
            $this->recomputeOccupancy();
            $this->sectionalRelease();
            $this->safety->inspect($this->time, $this->layout, $this->routes);
            $this->statistics();
            if (in_array($this->time, $this->snapshotTimes, true))
                $this->snapshot();
        }
        $this->writeReports();
    }
}

new Simulation()->run();
