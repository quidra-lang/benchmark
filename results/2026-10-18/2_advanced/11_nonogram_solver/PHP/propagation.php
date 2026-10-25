<?php
function lineLabel(bool $isRow, int $index): string { return ($isRow ? 'R' : 'C') . ($index + 1); }
function lineCells(array $grid, bool $isRow, int $index): array { return $isRow ? $grid[$index] : array_column($grid, $index); }
function determinedCount(array $grid): int { $count = 0; foreach ($grid as $row) foreach ($row as $state) if ($state !== CELL_UNKNOWN) $count++; return $count; }
final class PropagationStep {
    public function __construct(public bool $isRow, public int $index, public int $gain, public bool $contradiction) {}
    public function label(): string { return lineLabel($this->isRow, $this->index); }
    public function text(): string { return $this->label() . ($this->contradiction ? '!' : '+' . $this->gain); }
}
final class Propagation {
    public array $steps = [];
    public ?PropagationStep $conflict = null;
    public function lineSolves(): int { return count($this->steps); }
    public function record(): string { return implode(' ', array_map(fn($step) => $step->text(), $this->steps)); }
}
function propagate(array &$grid, array $rows, array $columns, bool $precise, array $rowMarks, array $columnMarks): Propagation {
    $result = new Propagation();
    while (true) {
        $index = array_search(true, $rowMarks, true); $isRow = $index !== false;
        if (!$isRow) { $index = array_search(true, $columnMarks, true); if ($index === false) return $result; }
        if ($isRow) $rowMarks[$index] = false; else $columnMarks[$index] = false;
        $cells = lineCells($grid, $isRow, $index); $solved = solveLine($cells, $isRow ? $rows[$index] : $columns[$index], $precise);
        if ($solved === null) { $step = new PropagationStep($isRow, $index, 0, true); $result->steps[] = $step; $result->conflict = $step; return $result; }
        $gain = 0; foreach ($solved as $position => $state) if ($cells[$position] === CELL_UNKNOWN && $state !== CELL_UNKNOWN) { $gain++; if ($isRow) { $grid[$index][$position] = $state; $columnMarks[$position] = true; } else { $grid[$position][$index] = $state; $rowMarks[$position] = true; } }
        $result->steps[] = new PropagationStep($isRow, $index, $gain, false);
    }
}
