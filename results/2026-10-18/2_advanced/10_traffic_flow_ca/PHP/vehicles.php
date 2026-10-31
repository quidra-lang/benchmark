<?php
final class VehicleClass {
    public function __construct(public string $name, public int $vmax, public int $weight, public bool $overtakes, public bool $stops) {}
}
final class Vehicle {
    public ?int $inserted = null, $exited = null;
    public ?string $sink = null;
    public ?Segment $segment = null;
    public ?Turn $turn = null;
    public int $lane = 0, $cell = 0, $speed = 0, $steps = 0, $distance = 0, $stoppedSteps = 0, $stopCount = 0, $laneChanges = 0, $dwell = 0;
    public array $route = [], $completedStops = [];
    public function __construct(public int $number, public VehicleClass $kind, public string $source, public int $arrival) {}
    public function maxSpeed(): int { return min($this->kind->vmax, $this->segment->limit); }
    public function place(Segment $segment, int $lane, int $cell): void {
        if ($this->segment !== null) $this->segment->clear($this->lane, $this->cell); $segment->put($lane, $cell, $this->number); $this->segment = $segment; $this->lane = $lane; $this->cell = $cell;
    }
    public function leave(): void { $this->segment->clear($this->lane, $this->cell); $this->segment = null; }
    public function headingForStop(): bool { return $this->segment !== null && $this->kind->stops && $this->segment->stop !== null && !isset($this->completedStops[$this->segment->id]) && $this->cell <= $this->segment->stop->cell; }
    public function travelTime(): int { return $this->exited - $this->inserted + 1; }
}
function randomSlowdown(int $speed, int $previous, int $value, int $dawdle, int $dawdleStopped): int { return $speed > 0 && $value % 1000 < ($previous === 0 ? $dawdleStopped : $dawdle) ? $speed - 1 : $speed; }
