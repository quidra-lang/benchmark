<?php

final class Safety
{
    public const PROPERTIES = ['OCCUPANCY', 'POINT_MOTION', 'CONFLICT', 'SIGNAL_PASSING'];

    public array $checks, $violations, $records = [];

    public function __construct()
    {
        $this->checks = $this->violations = array_fill_keys(self::PROPERTIES, 0);
    }

    public function check(int $time, string $kind, ?string $details = null): void
    {
        ++$this->checks[$kind];
        if ($details !== null) {
            ++$this->violations[$kind];
            $this->records[] = "VIOLATION $time $kind $details";
        }
    }

    public function inspect(int $time, Layout $layout, array $routes): void
    {
        foreach ($layout->sections as $s)
            $this->check(
                $time,
                'OCCUPANCY',
                count($s->occupants) >= 2 ? $s->name . ' ' . implode(',', $s->occupants) : null,
            );
        foreach ($layout->points as $p)
            if ($p->moving) {
                $details = null;
                if ($layout->sections[$p->common]->occupants)
                    $details = $p->name . ' occupied';
                elseif (array_any($p->locks, fn($lock) => in_array(
                    $routes[$lock[0]]->state,
                    ['USED', 'APPROACH'],
                    true,
                )))
                    $details = $p->name . ' locked';
                $this->check($time, 'POINT_MOTION', $details);
            }
        $locked = array_values(array_filter($routes, fn($r) => in_array(
            $r->state,
            ['LOCKED', 'APPROACH'],
            true,
        )));
        foreach ($locked as $i => $a)
            for ($j = $i + 1; $j < count($locked); ++$j) {
                $b = $locked[$j];
                $conflict =
                    in_array($b->name, $a->conflicts, true) || in_array($a->name, $b->conflicts, true);
                $this->check($time, 'CONFLICT', $conflict ? $a->name . ' ' . $b->name : null);
            }
    }

    public function report(): array
    {
        $lines = [];
        foreach (self::PROPERTIES as $kind)
            $lines[] =
                $kind
                . ' '
                . ($this->violations[$kind] ? 'FAIL' : 'OK')
                . " checks {$this->checks[$kind]} violations {$this->violations[$kind]}";
        return [...$lines, ...$this->records, 'RESULT ' . ($this->records ? 'UNSAFE' : 'SAFE')];
    }
}
