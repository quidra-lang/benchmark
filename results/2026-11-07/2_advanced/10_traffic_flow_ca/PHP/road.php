<?php
final class Turn {
    public int $vehicles = 0;
    public function __construct(public Segment $target, public int $weight) {}
}
final class BusStop {
    public int $buses = 0;
    public function __construct(public Segment $segment, public int $cell, public int $dwell) {}
}
final class Segment {
    public array $cells, $turns = [], $changes = ['overtaking' => 0, 'return' => 0, 'avoidance' => 0];
    public ?Junction $junction = null;
    public ?BusStop $stop = null;
    public int $entered = 0, $vehicleSum = 0, $speedSum = 0, $maxVehicles = 0, $greenSteps = 0, $queueSum = 0, $maxQueue = 0, $failures = 0, $passed = 0, $blocked = 0;
    public function __construct(public string $id, public string $start, public string $end, public int $length, public int $lanes, public int $limit) { $this->cells = array_fill(0, $lanes, array_fill(0, $length, 0)); }
    public function empty(int $lane, int $cell): bool { return $this->cells[$lane - 1][$cell] === 0; }
    public function obstacle(int $lane, int $cell): bool { return $this->cells[$lane - 1][$cell] === -1; }
    public function put(int $lane, int $cell, int $value): void { $this->cells[$lane - 1][$cell] = $value; }
    public function clear(int $lane, int $cell): void { $this->put($lane, $cell, 0); }
    public function free(int $lane, int $cell, int $limit): int {
        $count = 0; while ($count < $limit && $cell + $count + 1 < $this->length && $this->empty($lane, $cell + $count + 1)) $count++; return $count;
    }
    public function first(int $lane): int { foreach ($this->cells[$lane - 1] as $cell => $value) if ($value !== 0) return $cell; return $this->length; }
    public function safe(int $lane, int $cell): bool { for ($x = max(0, $cell - $this->limit); $x <= $cell; $x++) if (!$this->empty($lane, $x)) return false; return true; }
    public function vehicleNumbers(int $lane): array { return array_values(array_filter($this->cells[$lane - 1], fn($value) => $value > 0)); }
    public function cellsText(int $lane, array $vehicles): string {
        $text = ''; foreach ($this->cells[$lane - 1] as $value) $text .= $value === 0 ? '.' : ($value === -1 ? '#' : (string)$vehicles[$value - 1]->speed); return $text;
    }
}
final class Incident {
    public string $state = 'planned';
    public ?int $activeStart = null, $activeEnd = null;
    public function __construct(public Segment $segment, public int $lane, public int $cell, public int $start, public int $end) {}
    public function update(int $step): ?string {
        $event = null;
        if ($this->state === 'active' && $step > $this->end) { $this->state = 'cleared'; $this->segment->clear($this->lane, $this->cell); $event = 'INCIDENT_END'; }
        elseif ($this->state === 'planned' && $step > $this->end) $this->state = 'cancelled';
        elseif ($this->state === 'planned' && $step >= $this->start && $this->segment->empty($this->lane, $this->cell)) { $this->state = 'active'; $this->segment->put($this->lane, $this->cell, -1); $this->activeStart = $step; $event = 'INCIDENT_START'; }
        if ($this->state === 'active') $this->activeEnd = $step; return $event;
    }
}
