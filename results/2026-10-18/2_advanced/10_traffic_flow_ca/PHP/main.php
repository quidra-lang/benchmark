<?php
require_once __DIR__ . '/minstd.php';
require_once __DIR__ . '/road.php';
require_once __DIR__ . '/vehicles.php';
require_once __DIR__ . '/signals.php';
require_once __DIR__ . '/stats.php';

function timeText(int $step): string { return str_pad((string)$step, 4, '0', STR_PAD_LEFT); }
function flagText(bool $value): string { return $value ? 'Y' : 'N'; }
final class Rational {
    public int $numerator, $denominator;
    public function __construct(int $numerator = 0, int $denominator = 1) { $divisor = gcd($numerator, $denominator); $this->numerator = intdiv($numerator, $divisor); $this->denominator = intdiv($denominator, $divisor); }
    public function multiply(int $numerator, int $denominator): self { return new self($this->numerator * $numerator, $this->denominator * $denominator); }
    public function add(self $other): self { return new self($this->numerator * $other->denominator + $other->numerator * $this->denominator, $this->denominator * $other->denominator); }
    public function text(): string { return "$this->numerator/$this->denominator"; }
}
final class Source {
    public SplQueue $queue;
    public int $queueStart = 0, $queueMax = 0;
    public function __construct(public string $node, public array $rates, public Segment $segment) { $this->queue = new SplQueue(); }
    public function rate(int $step): int { foreach ($this->rates as [$rate, $end]) if ($step <= $end) return $rate; return 0; }
}
final class Detector {
    public function __construct(public string $name, public Segment $segment, public int $cell, public int $width) {}
    public function covers(int $cell): bool { return $this->cell <= $cell && $cell < $this->cell + $this->width; }
}
final class Diagram {
    public array $lines = [];
    public function __construct(public Segment $segment, public int $lane, public int $start, public int $end) {}
}
final class Ring {
    public int $length, $vmax, $warmup, $measure, $seed;
    public array $counts;
    public function __construct(public int $number, array $values) { [$this->length, $this->vmax, $this->warmup, $this->measure, $this->seed] = array_slice($values, 0, 5); $this->counts = array_slice($values, 5); }
}
final class Interval {
    public int $arrivals = 0, $insertions = 0, $exits = 0, $vehicleSteps = 0, $speedSum = 0;
    public array $passing, $occupancy, $occupancySpeed;
    public function __construct(int $count) { $this->passing = $this->occupancy = $this->occupancySpeed = array_fill(0, $count, 0); }
}
final class Move {
    public Segment $segment;
    public int $cell, $speed = 0;
    public function __construct(public Vehicle $vehicle) { $this->segment = $vehicle->segment; $this->cell = $vehicle->cell; }
}
function runRing(Ring $ring, int $count, int $dawdle, int $dawdleStopped): int {
    $rng = new Minstd($ring->seed); $positions = []; for ($j = 0; $j < $count; $j++) $positions[] = intdiv($j * $ring->length, $count); $speeds = array_fill(0, $count, 0); $total = 0;
    for ($step = 1; $step <= $ring->warmup + $ring->measure; $step++) {
        $order = array_keys($positions); usort($order, fn($a, $b) => $positions[$b] <=> $positions[$a]); $next = array_fill(0, $count, 0);
        foreach ($order as $rank => $j) { $ahead = $order[$rank === 0 ? $count - 1 : $rank - 1]; $gap = ($positions[$ahead] - $positions[$j] - 1 + $ring->length) % $ring->length; $speed = min($speeds[$j] + 1, $ring->vmax, $gap); $next[$j] = randomSlowdown($speed, $speeds[$j], $rng->draw(), $dawdle, $dawdleStopped); }
        foreach ($positions as $j => $position) $positions[$j] = ($position + $next[$j]) % $ring->length; $speeds = $next; if ($step > $ring->warmup) $total += array_sum($next);
    }
    return $total;
}
final class Simulation {
    private array $segments = [], $byId = [], $junctions = [], $incidents = [], $stops = [], $classes = [], $sources = [], $sinks = [], $detectors = [], $diagrams = [], $trackNumbers = [], $rings = [], $vehicles = [], $intervals = [], $events = [], $tracks = [];
    private int $seed = 1, $steps = 0, $dawdle = 0, $dawdleStopped = 0, $intervalLength = 1, $binWidth = 1;
    private Minstd $rng;
    public function __construct() {
        foreach (['network.txt', 'demand.txt', 'params.txt'] as $file) foreach (file('input/' . $file, FILE_IGNORE_NEW_LINES) as $line) {
            $p = explode(' ', $line); $kind = array_shift($p);
            switch ($kind) {
                case 'SEGMENT': $segment = new Segment($p[0], $p[1], $p[2], (int)$p[3], (int)$p[4], (int)$p[5]); $this->segments[] = $segment; $this->byId[$p[0]] = $segment; break;
                case 'JUNCTION': $junction = new Junction($p[0], (int)$p[1], array_slice($p, 2)); foreach ($this->segments as $segment) if ($segment->end === $p[0]) { $segment->junction = $junction; $junction->incoming[] = $segment; } $this->junctions[] = $junction; break;
                case 'INCIDENT': $this->incidents[] = new Incident($this->byId[$p[0]], (int)$p[1], (int)$p[2], (int)$p[3], (int)$p[4]); break;
                case 'STOP': $segment = $this->byId[$p[0]]; $stop = new BusStop($segment, (int)$p[1], (int)$p[2]); $segment->stop = $stop; $this->stops[] = $stop; break;
                case 'CLASS': $this->classes[] = new VehicleClass($p[0], (int)$p[1], (int)$p[2], $p[3] === 'Y', $p[4] === 'Y'); break;
                case 'SOURCE': $rates = []; foreach (array_slice($p, 1) as $period) $rates[] = array_map('intval', explode(':', $period)); foreach ($this->segments as $segment) if ($segment->start === $p[0]) { $this->sources[] = new Source($p[0], $rates, $segment); break; } break;
                case 'SINK': $this->sinks[] = $p[0]; break;
                case 'TURN': $this->byId[$p[0]]->turns[] = new Turn($this->byId[$p[1]], (int)$p[2]); break;
                case 'seed': $this->seed = (int)$p[0]; break;
                case 'steps': $this->steps = (int)$p[0]; break;
                case 'dawdle': $this->dawdle = (int)$p[0]; $this->dawdleStopped = (int)$p[1]; break;
                case 'interval': $this->intervalLength = (int)$p[0]; break;
                case 'bin': $this->binWidth = (int)$p[0]; break;
                case 'detector': $this->detectors[] = new Detector($p[0], $this->byId[$p[1]], (int)$p[2], (int)$p[3]); break;
                case 'diagram': $this->diagrams[] = new Diagram($this->byId[$p[0]], (int)$p[1], (int)$p[2], (int)$p[3]); break;
                case 'track': $this->trackNumbers = array_map('intval', $p); foreach ($this->trackNumbers as $number) $this->tracks[$number] = []; break;
                case 'ring': $this->rings[] = new Ring(count($this->rings) + 1, array_map('intval', $p)); break;
            }
        }
        $this->rng = new Minstd($this->seed);
    }
    private function record(int $step, string $event): void { $this->events[] = timeText($step) . ' ' . $event; }
    private function interval(): Interval { return $this->intervals[count($this->intervals) - 1]; }
    private function green(Segment $segment, int $step): bool { return $segment->junction->green($segment->id, $step); }
    private function vehiclesOn(Segment $segment): array {
        $found = []; for ($lane = 1; $lane <= $segment->lanes; $lane++) foreach ($segment->vehicleNumbers($lane) as $number) $found[] = $this->vehicles[$number - 1]; return $found;
    }
    private function enter(Vehicle $vehicle, Segment $segment): void {
        $vehicle->route[] = $segment->id; $segment->entered++; $vehicle->turn = $segment->junction === null ? null : $segment->turns[selectWeighted(array_map(fn($turn) => $turn->weight, $segment->turns), $this->rng->draw())];
    }
    private function updateIncidents(int $step): void { foreach ($this->incidents as $incident) { $event = $incident->update($step); if ($event !== null) $this->record($step, "$event {$incident->segment->id} lane $incident->lane cell $incident->cell"); } }
    private function arrive(int $step): void {
        $weights = array_map(fn($kind) => $kind->weight, $this->classes); $interval = $this->interval();
        foreach ($this->sources as $source) if ($this->rng->draw() % 1000 < $source->rate($step)) { $kind = $this->classes[selectWeighted($weights, $this->rng->draw())]; $vehicle = new Vehicle(count($this->vehicles) + 1, $kind, $source->node, $step); $this->vehicles[] = $vehicle; $source->queue->enqueue($vehicle); $interval->arrivals++; }
    }
    private function entryLane(Segment $segment): ?int {
        $best = null; $first = -1; for ($lane = 1; $lane <= $segment->lanes; $lane++) if ($segment->empty($lane, 0) && $segment->first($lane) > $first) { $best = $lane; $first = $segment->first($lane); } return $best;
    }
    private function insert(int $step): void {
        $interval = $this->interval(); foreach ($this->sources as $source) {
            while (!$source->queue->isEmpty()) { $lane = $this->entryLane($source->segment); if ($lane === null) break; $vehicle = $source->queue->dequeue(); $vehicle->place($source->segment, $lane, 0); $vehicle->inserted = $step; $this->enter($vehicle, $source->segment); $interval->insertions++; }
            if (!$source->queue->isEmpty() && $source->queueStart === 0) { $source->queueStart = $step; $source->queueMax = 0; }
            if ($source->queueStart !== 0) { $source->queueMax = max($source->queueMax, $source->queue->count()); if ($source->queue->isEmpty()) { $this->record($step, "QUEUE $source->node from $source->queueStart max $source->queueMax"); $source->queueStart = 0; } }
        }
    }
    private function desiredLane(Vehicle $vehicle): array {
        $s = $vehicle->segment; $lane = $vehicle->lane; $cell = $vehicle->cell; $top = $vehicle->maxSpeed(); $here = $s->free($lane, $cell, $top + 1); $want = min($vehicle->speed + 1, $top); $ahead = $cell + $here + 1;
        if ($here < $top + 1 && $ahead < $s->length && $s->obstacle($lane, $ahead)) foreach ([$lane + 1, $lane - 1] as $target) if (1 <= $target && $target <= $s->lanes && $s->free($target, $cell, $top + 1) > $here && $s->safe($target, $cell)) return [$target, 'avoidance'];
        if ($vehicle->headingForStop()) return $lane >= 2 && $s->safe($lane - 1, $cell) ? [$lane - 1, 'return'] : [$lane, null];
        if ($vehicle->kind->overtakes && $lane + 1 <= $s->lanes && $here < $want && $s->free($lane + 1, $cell, $top + 1) > $here && $s->safe($lane + 1, $cell)) return [$lane + 1, 'overtaking'];
        if ($lane >= 2 && $s->free($lane - 1, $cell, $top + 1) > $want && $s->safe($lane - 1, $cell)) return [$lane - 1, 'return']; return [$lane, null];
    }
    private function changeLanes(): void {
        $changes = []; foreach ($this->segments as $segment) if ($segment->lanes >= 2) {
            $reserved = []; for ($lane = 1; $lane <= $segment->lanes; $lane++) foreach ($segment->vehicleNumbers($lane) as $number) {
                $vehicle = $this->vehicles[$number - 1]; if ($vehicle->dwell > 0) continue; [$target, $kind] = $this->desiredLane($vehicle); $key = "$target,$vehicle->cell";
                if ($target !== $lane && !isset($reserved[$key])) { $reserved[$key] = true; $changes[] = [$vehicle, $target, $kind]; }
            }
        }
        foreach ($changes as [$vehicle, $target, $kind]) { $segment = $vehicle->segment; $vehicle->place($segment, $target, $vehicle->cell); $vehicle->laneChanges++; $segment->changes[$kind]++; }
    }
    private function processingOrder(): array {
        $moves = []; foreach ($this->segments as $segment) for ($lane = 1; $lane <= $segment->lanes; $lane++) foreach (array_reverse($segment->vehicleNumbers($lane)) as $number) $moves[] = new Move($this->vehicles[$number - 1]); return $moves;
    }
    private function determineSpeed(Vehicle $vehicle, int $step): int {
        $s = $vehicle->segment; $lane = $vehicle->lane; $cell = $vehicle->cell; $accelerated = min($vehicle->speed + 1, $vehicle->maxSpeed()); $gap = $s->free($lane, $cell, $accelerated);
        if ($gap < $accelerated && $cell + $gap === $s->length - 1) {
            if ($s->junction === null) $gap = $accelerated;
            elseif ($this->green($s, $step)) { $target = $vehicle->turn->target; $gap += $target->free(min($lane, $target->lanes), -1, $accelerated - $gap); }
        }
        if ($vehicle->headingForStop()) $gap = min($gap, $s->stop->cell - $cell); $speed = randomSlowdown(min($accelerated, $gap), $vehicle->speed, $this->rng->draw(), $this->dawdle, $this->dawdleStopped);
        if ($vehicle->dwell > 0) { $speed = 0; $vehicle->dwell--; } return $speed;
    }
    private function moveVehicles(array $moves, int $step): array {
        $passing = []; $interval = $this->interval(); foreach ($moves as $move) {
            $vehicle = $move->vehicle; $segment = $move->segment;
            if ($move->cell + $move->speed < $segment->length) $vehicle->place($segment, $vehicle->lane, $move->cell + $move->speed);
            elseif ($segment->junction === null) { $vehicle->leave(); $vehicle->exited = $step; $vehicle->sink = $segment->end; $interval->exits++; }
            else $passing[] = $move;
        } return $passing;
    }
    private function passJunctions(array $passing): void {
        foreach ($passing as $move) {
            $vehicle = $move->vehicle; $segment = $move->segment; $turn = $vehicle->turn; $target = $turn->target; $lane = min($vehicle->lane, $target->lanes); $overshoot = $move->cell + $move->speed - $segment->length; $cell = min($overshoot, $target->first($lane) - 1);
            if ($cell < $overshoot) $segment->blocked++;
            if ($cell >= 0) { $vehicle->place($target, $lane, $cell); $move->speed = $segment->length - $move->cell + $cell; $segment->passed++; $turn->vehicles++; $this->enter($vehicle, $target); }
            else { $vehicle->place($segment, $vehicle->lane, $segment->length - 1); $move->speed = $segment->length - 1 - $move->cell; }
        }
    }
    private function trackLine(Vehicle $vehicle, int $step): string {
        return timeText($step) . ($vehicle->segment === null ? " EXIT $vehicle->speed" : " {$vehicle->segment->id} $vehicle->lane $vehicle->cell $vehicle->speed");
    }
    private function aggregateVehicle(Move $move, int $step): void {
        $v = $move->vehicle; $interval = $this->interval(); $speed = $move->speed; $v->steps++; $v->distance += $speed;
        if ($speed === 0) { $v->stoppedSteps++; if ($v->speed > 0) $v->stopCount++; } $v->speed = $speed; $interval->vehicleSteps++; $interval->speedSum += $speed;
        if ($v->headingForStop() && $v->lane === 1 && $v->cell === $v->segment->stop->cell) { $stop = $v->segment->stop; $v->completedStops[$v->segment->id] = true; $v->dwell = $stop->dwell; $stop->buses++; $this->record($step, "BUS_STOP $v->number {$v->segment->id} cell $stop->cell"); }
        if (array_key_exists($v->number, $this->tracks)) $this->tracks[$v->number][] = $this->trackLine($v, $step);
        foreach ($this->detectors as $j => $detector) if ($move->segment === $detector->segment && $move->cell < $detector->cell && ($v->segment !== $detector->segment || $v->cell >= $detector->cell)) $interval->passing[$j]++;
    }
    private function signalText(Segment $segment, int $step): string { return $segment->junction === null ? 'E' : ($this->green($segment, $step) ? 'G' : 'R'); }
    private function aggregateState(int $step): void {
        $interval = $this->interval(); foreach ($this->detectors as $j => $detector) foreach ($this->vehiclesOn($detector->segment) as $vehicle) if ($detector->covers($vehicle->cell)) { $interval->occupancy[$j]++; $interval->occupancySpeed[$j] += $vehicle->speed; }
        foreach ($this->segments as $segment) {
            $present = $this->vehiclesOn($segment); $count = count($present); $segment->vehicleSum += $count; foreach ($present as $v) $segment->speedSum += $v->speed; $segment->maxVehicles = max($segment->maxVehicles, $count);
            if ($segment->junction === null) continue; $green = $this->green($segment, $step); if ($green) $segment->greenSteps++; $queued = count(array_filter($present, fn($v) => $v->speed === 0)); $segment->queueSum += $queued; $segment->maxQueue = max($segment->maxQueue, $queued);
            if ($step < $this->steps && $queued > 0 && $green && !$this->green($segment, $step + 1)) $segment->failures++;
        }
        foreach ($this->diagrams as $diagram) if ($diagram->start <= $step && $step <= $diagram->end) $diagram->lines[] = timeText($step) . ' ' . $diagram->segment->cellsText($diagram->lane, $this->vehicles) . ' ' . $this->signalText($diagram->segment, $step);
    }
    public function run(): void {
        for ($step = 1; $step <= $this->steps; $step++) {
            $this->updateIncidents($step); if (($step - 1) % $this->intervalLength === 0) $this->intervals[] = new Interval(count($this->detectors));
            $this->arrive($step); $this->insert($step); $this->changeLanes(); $moves = $this->processingOrder(); foreach ($moves as $move) $move->speed = $this->determineSpeed($move->vehicle, $step);
            $this->passJunctions($this->moveVehicles($moves, $step)); foreach ($moves as $move) $this->aggregateVehicle($move, $step); $this->aggregateState($step);
        }
        foreach ($this->sources as $source) if ($source->queueStart !== 0) $this->record($this->steps, "QUEUE $source->node from $source->queueStart max $source->queueMax open");
    }
    private function enumerateRoutes(Segment $segment): array {
        if ($segment->junction === null) return [[[$segment->id], new Rational(1)]]; $total = 0; foreach ($segment->turns as $turn) $total += $turn->weight; $routes = [];
        foreach ($segment->turns as $turn) foreach ($this->enumerateRoutes($turn->target) as [$route, $share]) $routes[] = [array_merge([$segment->id], $route), $share->multiply($turn->weight, $total)]; return $routes;
    }
    private function spacetimeLines(): array {
        $lines = []; foreach ($this->diagrams as $diagram) { $lines[] = "DIAGRAM {$diagram->segment->id} lane $diagram->lane steps $diagram->start-$diagram->end"; array_push($lines, ...$diagram->lines); } return $lines;
    }
    private function detectorLines(): array {
        $lines = ['detector,interval,flow,density,speed']; foreach ($this->detectors as $j => $detector) {
            $capacity = $this->intervalLength * $detector->width * $detector->segment->lanes; foreach ($this->intervals as $k => $interval) $lines[] = implode(',', [$detector->name, $k + 1, $interval->passing[$j], dec($interval->occupancy[$j], $capacity, 4), dec($interval->occupancySpeed[$j], $interval->occupancy[$j], 2)]);
        } return $lines;
    }
    private function travelBlock(string $heading, array $vehicles): array {
        $times = array_map(fn($v) => $v->travelTime(), $vehicles); sort($times, SORT_NUMERIC); $count = count($times); if ($count === 0) return ["$heading exited 0"];
        return array_merge(["$heading exited $count min {$times[0]} p50 " . percentile($times, 50) . ' p90 ' . percentile($times, 90) . ' max ' . $times[$count - 1] . ' mean ' . dec(array_sum($times), $count, 2)], histogramLines($times, $this->binWidth));
    }
    private function outcomeText(array $vehicles, int $exited): string {
        $count = count($vehicles); $total = 0; foreach ($vehicles as $v) $total += $v->travelTime(); return "vehicles $count share " . frac($count, $exited) . ' mean ' . dec($total, $count, 2);
    }
    private function sourceLines(Source $source, array $exited): array {
        $group = array_values(array_filter($exited, fn($v) => $v->source === $source->node)); $lines = ["SOURCE $source->node exited " . count($group)]; $routes = $this->enumerateRoutes($source->segment);
        foreach ($routes as [$route, $share]) { $matched = array_values(array_filter($group, fn($v) => $v->route === $route)); $lines[] = '  ROUTE ' . implode(',', $route) . ' expected ' . $share->text() . ' ' . $this->outcomeText($matched, count($group)); }
        foreach ($this->sinks as $sink) {
            $share = new Rational(); $found = false; foreach ($routes as [$route, $expected]) if ($this->byId[$route[count($route) - 1]]->end === $sink) { $share = $share->add($expected); $found = true; }
            if (!$found) continue; $matched = array_values(array_filter($group, fn($v) => $v->sink === $sink)); $lines[] = "  SINK $sink expected " . $share->text() . ' ' . $this->outcomeText($matched, count($group));
        } return $lines;
    }
    private function travelTimeLines(): array {
        $exited = array_values(array_filter($this->vehicles, fn($v) => $v->exited !== null)); $lines = [];
        foreach ($this->classes as $kind) array_push($lines, ...$this->travelBlock('CLASS ' . $kind->name, array_values(array_filter($exited, fn($v) => $v->kind === $kind))));
        array_push($lines, ...$this->travelBlock('ALL', $exited)); foreach ($this->sources as $source) array_push($lines, ...$this->sourceLines($source, $exited)); return $lines;
    }
    private function classBlock(string $heading, array $vehicles): array {
        $inserted = 0; $exited = []; $steps = 0; $distance = 0;
        foreach ($vehicles as $v) { if ($v->inserted !== null) $inserted++; if ($v->exited !== null) $exited[] = $v; $steps += $v->steps; $distance += $v->distance; }
        $travel = $delay = $stopped = $stops = $changes = 0; foreach ($exited as $v) { $travel += $v->travelTime(); $delay += $v->inserted - $v->arrival; $stopped += $v->stoppedSteps; $stops += $v->stopCount; $changes += $v->laneChanges; }
        $count = count($exited); return [$heading, '  generated ' . count($vehicles) . " inserted $inserted exited $count in_network " . ($inserted - $count) . ' queued ' . (count($vehicles) - $inserted), "  vehicle_steps $steps distance $distance mean_speed " . frac($distance, $steps) . ' = ' . dec($distance, $steps, 3), '  travel ' . dec($travel, $count, 2) . ' entry_delay ' . dec($delay, $count, 2) . ' stopped ' . dec($stopped, $count, 2) . ' stops ' . dec($stops, $count, 2) . ' lane_changes ' . dec($changes, $count, 2)];
    }
    private function classStatsLines(): array {
        $lines = []; foreach ($this->classes as $kind) {
            $heading = "CLASS $kind->name vmax $kind->vmax weight $kind->weight overtake " . flagText($kind->overtakes) . ' stops ' . flagText($kind->stops);
            array_push($lines, ...$this->classBlock($heading, array_values(array_filter($this->vehicles, fn($v) => $v->kind === $kind))));
        } array_push($lines, ...$this->classBlock('ALL', $this->vehicles)); return $lines;
    }
    private function networkStatsLines(): array {
        $lines = []; foreach ($this->segments as $s) $lines[] = "SEGMENT $s->id $s->start $s->end length $s->length lanes $s->lanes limit $s->limit entered $s->entered mean_vehicles " . dec($s->vehicleSum, $this->steps, 3) . ' density ' . dec($s->vehicleSum, $this->steps * $s->length * $s->lanes, 4) . ' mean_speed ' . dec($s->speedSum, $s->vehicleSum, 2) . " max_vehicles $s->maxVehicles changes " . implode('/', $s->changes);
        foreach ($this->junctions as $junction) {
            array_push($lines, ...$junction->planLines()); foreach ($junction->incoming as $s) { $lines[] = "  IN $s->id green $s->greenSteps passed $s->passed blocked $s->blocked max_queue $s->maxQueue mean_queue " . dec($s->queueSum, $this->steps, 3) . " failures $s->failures"; foreach ($s->turns as $turn) $lines[] = "    TURN {$turn->target->id} weight $turn->weight vehicles $turn->vehicles"; }
        }
        foreach ($this->stops as $stop) $lines[] = "STOP {$stop->segment->id} cell $stop->cell dwell $stop->dwell buses $stop->buses";
        foreach ($this->incidents as $incident) $lines[] = "INCIDENT {$incident->segment->id} lane $incident->lane cell $incident->cell planned $incident->start-$incident->end active " . ($incident->activeStart === null ? 'none' : "$incident->activeStart-$incident->activeEnd"); return $lines;
    }
    private function timelineLines(): array {
        $lines = ['interval,arrived,inserted,exited,in_network,queued,mean_speed']; $arrived = $inserted = $exited = 0;
        foreach ($this->intervals as $j => $interval) { $arrived += $interval->arrivals; $inserted += $interval->insertions; $exited += $interval->exits; $lines[] = implode(',', [$j + 1, $interval->arrivals, $interval->insertions, $interval->exits, $inserted - $exited, $arrived - $inserted, dec($interval->speedSum, $interval->vehicleSteps, 2)]); } return $lines;
    }
    private function trackLines(): array {
        $lines = []; foreach ($this->trackNumbers as $number) {
            if ($number > count($this->vehicles)) { $lines[] = "VEHICLE $number none"; continue; } $v = $this->vehicles[$number - 1];
            $lines[] = "VEHICLE $number class {$v->kind->name} source $v->source arrival $v->arrival inserted " . ($v->inserted ?? '-') . ' exited ' . ($v->exited ?? '-') . ' sink ' . ($v->sink ?? '-');
            $lines[] = 'ROUTE ' . ($v->route ? implode(' ', $v->route) : '-'); array_push($lines, ...$this->tracks[$number]);
        } return $lines;
    }
    private function fundamentalLines(): array {
        $lines = ['ring,vehicles,density,flow,speed']; foreach ($this->rings as $ring) foreach ($ring->counts as $count) { $total = runRing($ring, $count, $this->dawdle, $this->dawdleStopped); $lines[] = implode(',', [$ring->number, $count, dec($count, $ring->length, 4), dec($total, $ring->length * $ring->measure, 4), dec($total, $count * $ring->measure, 3)]); } return $lines;
    }
    public function write(): void {
        if (!is_dir('output')) mkdir('output'); $outputs = ['spacetime.txt' => $this->spacetimeLines(), 'detectors.csv' => $this->detectorLines(), 'travel_times.txt' => $this->travelTimeLines(), 'class_stats.txt' => $this->classStatsLines(), 'network_stats.txt' => $this->networkStatsLines(), 'timeline.csv' => $this->timelineLines(), 'tracks.txt' => $this->trackLines(), 'fundamental.csv' => $this->fundamentalLines(), 'events.txt' => $this->events];
        foreach ($outputs as $name => $lines) file_put_contents('output/' . $name, $lines ? implode("\n", $lines) . "\n" : '');
    }
}
$simulation = new Simulation(); $simulation->run(); $simulation->write();
