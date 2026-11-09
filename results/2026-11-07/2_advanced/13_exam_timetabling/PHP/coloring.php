<?php

class Attempt
{
    public int $deadEnds = 0;
    public ?string $deadEndCourse = null;
    public bool $aborted = false;
    public array $chosen = [];

    public function __construct(
        public array $courses,
        public ConflictGraph $graph,
        public int $limit,
        public Closure $candidateSlots
    ) {
    }

    public function saturation(string $id, array $assignment): int
    {
        $slots = [];
        foreach ($this->graph->neighbours($id) as $key => $shared) {
            if (isset($assignment[$key])) {
                $slots[$assignment[$key]] = true;
            }
        }
        return count($slots);
    }

    public function search(array &$assignment): bool
    {
        $remaining = array_values(array_filter($this->courses, fn($id) => !isset($assignment[id_key($id)])));
        if (!$remaining) {
            return true;
        }
        usort($remaining, fn($a, $b) =>
            $this->saturation($b, $assignment) <=> $this->saturation($a, $assignment)
            ?: $this->graph->degree($b) <=> $this->graph->degree($a)
            ?: strcmp($a, $b));
        $id = $remaining[0];
        $key = id_key($id);
        $this->chosen[] = [$id, $this->saturation($id, $assignment)];
        foreach (($this->candidateSlots)($id, $assignment) as $slot) {
            $assignment[$key] = $slot;
            if ($this->search($assignment)) {
                return true;
            }
            unset($assignment[$key]);
            if ($this->aborted) {
                return false;
            }
        }
        array_pop($this->chosen);
        $this->deadEnds++;
        $this->deadEndCourse = $id;
        $this->aborted = $this->deadEnds > $this->limit;
        return false;
    }
}

function greedy_numbering(array $order, ConflictGraph $graph): int
{
    $numbers = [];
    $maximum = 0;
    foreach ($order as $id) {
        $taken = [];
        foreach ($graph->neighbours($id) as $key => $shared) {
            if (isset($numbers[$key])) {
                $taken[$numbers[$key]] = true;
            }
        }
        $number = 1;
        while (isset($taken[$number])) {
            $number++;
        }
        $numbers[id_key($id)] = $number;
        $maximum = max($maximum, $number);
    }
    return $maximum;
}
