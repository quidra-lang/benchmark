<?php
function guessCell(array $grid): ?array {
    $rowCounts = []; foreach ($grid as $row) $rowCounts[] = count(array_filter($row, fn($state) => $state === CELL_UNKNOWN)); $columnCounts = array_fill(0, count($grid[0]), 0);
    foreach ($grid as $row) foreach ($row as $c => $state) if ($state === CELL_UNKNOWN) $columnCounts[$c]++; $best = null; $bestScore = 0;
    foreach ($grid as $r => $row) foreach ($row as $c => $state) if ($state === CELL_UNKNOWN) { $score = $rowCounts[$r] + $columnCounts[$c]; if ($best === null || $score < $bestScore) { $best = [$r, $c]; $bestScore = $score; } } return $best;
}
final class Guess {
    public function __construct(public int $number, public int $depth, public int $row, public int $column, public int $value, public int $solves, public int $known, public string $result) {}
}
final class Search {
    public array $guesses = [], $solutions = [];
    public int $backtracks = 0;
    public function __construct(private array $rows, private array $columns) {}
    public function guessCount(): int { return count($this->guesses); }
    public function maxDepth(): int { $depth = 0; foreach ($this->guesses as $guess) $depth = max($depth, $guess->depth); return $depth; }
    public function lineSolves(): int { $sum = 0; foreach ($this->guesses as $guess) $sum += $guess->solves; return $sum; }
    public function run(array $grid, int $depth = 1): bool {
        [$row, $column] = guessCell($grid); $height = count($this->rows); $width = count($this->columns);
        foreach ([CELL_FILLED, CELL_EMPTY] as $value) {
            $number = count($this->guesses) + 1; $child = $grid; $child[$row][$column] = $value; $rowMarks = array_fill(0, $height, false); $columnMarks = array_fill(0, $width, false); $rowMarks[$row] = $columnMarks[$column] = true;
            $propagation = propagate($child, $this->rows, $this->columns, true, $rowMarks, $columnMarks); $known = determinedCount($child);
            if ($propagation->conflict !== null) { $result = 'contradiction at=' . $propagation->conflict->label(); $this->backtracks++; }
            elseif ($known === $height * $width) { $this->solutions[] = $child; $result = 'solution' . count($this->solutions); }
            else $result = 'open';
            $this->guesses[] = new Guess($number, $depth, $row, $column, $value, $propagation->lineSolves(), $known, $result);
            if ($result === 'open') { if ($this->run($child, $depth + 1)) return true; } elseif (count($this->solutions) === 2) return true;
        } return false;
    }
}
