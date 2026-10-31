<?php
const CELL_UNKNOWN = 0;
const CELL_FILLED = 1;
const CELL_EMPTY = 2;
function fitTable(array $cells, array $clue): array {
    $empties = [0]; foreach ($cells as $state) $empties[] = $empties[count($empties) - 1] + (int)($state === CELL_EMPTY);
    $table = array_fill(0, count($cells) + 1, array_fill(0, count($clue) + 1, false)); $table[0][0] = true;
    for ($end = 1; $end <= count($cells); $end++) for ($count = 0; $count <= count($clue); $count++) {
        $fits = $cells[$end - 1] !== CELL_FILLED && $table[$end - 1][$count];
        if (!$fits && $count > 0) { $start = $end - $clue[$count - 1]; if ($start >= 0 && $empties[$end] === $empties[$start]) $fits = $start === 0 ? $count === 1 : $cells[$start - 1] !== CELL_FILLED && $table[$start - 1][$count - 1]; }
        $table[$end][$count] = $fits;
    }
    return $table;
}
final class LinePlacements {
    private array $before, $after;
    private int $length;
    public function __construct(private array $cells, private array $clue) { $this->length = count($cells); $this->before = fitTable($cells, $clue); $this->after = fitTable(array_reverse($cells), array_reverse($clue)); }
    public function consistent(): bool { return $this->before[$this->length][count($this->clue)]; }
    private function canStart(int $block, int $start): bool {
        $end = $start + $this->clue[$block]; for ($j = $start; $j < $end; $j++) if ($this->cells[$j] === CELL_EMPTY) return false;
        $left = $start === 0 ? $block === 0 : $this->cells[$start - 1] !== CELL_FILLED && $this->before[$start - 1][$block]; $rest = count($this->clue) - $block - 1;
        $right = $end === $this->length ? $rest === 0 : $this->cells[$end] !== CELL_FILLED && $this->after[$this->length - $end - 1][$rest]; return $left && $right;
    }
    public function starts(int $block): array { $starts = []; for ($start = 0; $start <= $this->length - $this->clue[$block]; $start++) if ($this->canStart($block, $start)) $starts[] = $start; return $starts; }
    public function canBeEmpty(int $index): bool {
        if ($this->cells[$index] === CELL_FILLED) return false; $count = count($this->clue);
        for ($blocks = 0; $blocks <= $count; $blocks++) if ($this->before[$index][$blocks] && $this->after[$this->length - $index - 1][$count - $blocks]) return true; return false;
    }
}
function hasPlacement(array $cells, array $clue): bool { return (new LinePlacements($cells, $clue))->consistent(); }
function solveLine(array $cells, array $clue, bool $precise): ?array {
    $placements = new LinePlacements($cells, $clue); if (!$placements->consistent()) return null; $solved = $cells; $possible = array_fill(0, count($cells), false);
    foreach ($clue as $block => $length) {
        $starts = $placements->starts($block);
        if ($precise) { foreach ($starts as $start) for ($j = $start; $j < $start + $length; $j++) $possible[$j] = true; }
        else { $low = $starts[0]; $high = $starts[count($starts) - 1]; for ($j = $high; $j < $low + $length; $j++) if ($solved[$j] === CELL_UNKNOWN) $solved[$j] = CELL_FILLED; for ($j = $low; $j < $high + $length; $j++) $possible[$j] = true; }
    }
    foreach ($cells as $j => $state) if ($state === CELL_UNKNOWN) {
        if ($precise) { $empty = $placements->canBeEmpty($j); if ($possible[$j] && !$empty) $solved[$j] = CELL_FILLED; elseif ($empty && !$possible[$j]) $solved[$j] = CELL_EMPTY; }
        elseif (!$possible[$j]) $solved[$j] = CELL_EMPTY;
    }
    return $solved;
}
