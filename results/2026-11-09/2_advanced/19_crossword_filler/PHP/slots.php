<?php
declare(strict_types=1);

namespace Crossword;

const RUN_STEPS = [[0, 1], [1, 0]];

function startsRun(Grid $grid, int $row, int $column, array $step): bool
{
    return $grid->isOpen($row, $column) && !$grid->isOpen($row - $step[0], $column - $step[1]);
}

function runLength(Grid $grid, int $row, int $column, array $step): int
{
    $length = 0;
    while ($grid->isOpen($row + $length * $step[0], $column + $length * $step[1])) {
        $length++;
    }
    return $length;
}

function findShortRun(Grid $grid): ?array
{
    for ($row = 0; $row < $grid->height; $row++) {
        for ($column = 0; $column < $grid->width; $column++) {
            foreach (RUN_STEPS as $direction => $step) {
                if (startsRun($grid, $row, $column, $step) && runLength($grid, $row, $column, $step) === 2) {
                    return [$grid->cell($row, $column), $direction === 0 ? 'across' : 'down'];
                }
            }
        }
    }
    return null;
}

final class Slot
{
    public int $length;
    public string $label;
    public array $crossings = [];

    public function __construct(public int $index, public int $number, public bool $across, public array $cells)
    {
        $this->length = count($cells);
        $this->label = $number . ($across ? 'A' : 'D');
    }
}

final class Layout
{
    public array $numbers = [];
    public array $slots = [];
    public array $acrossSlot;
    public array $downSlot;

    public function __construct(public Grid $grid)
    {
        $this->acrossSlot = $this->downSlot = array_fill(0, $grid->size(), null);
        for ($row = 0; $row < $grid->height; $row++) {
            for ($column = 0; $column < $grid->width; $column++) {
                foreach (RUN_STEPS as $direction => $step) {
                    if (!startsRun($grid, $row, $column, $step)) {
                        continue;
                    }
                    $length = runLength($grid, $row, $column, $step);
                    if ($length < 3) {
                        continue;
                    }
                    $start = $grid->cell($row, $column);
                    if (!isset($this->numbers[$start])) {
                        $this->numbers[$start] = count($this->numbers) + 1;
                    }
                    $cells = [];
                    for ($offset = 0; $offset < $length; $offset++) {
                        $cells[] = $grid->cell($row + $offset * $step[0], $column + $offset * $step[1]);
                    }
                    $slot = new Slot(count($this->slots), $this->numbers[$start], $direction === 0, $cells);
                    $this->slots[] = $slot;
                    foreach ($cells as $cell) {
                        if ($slot->across) {
                            $this->acrossSlot[$cell] = $slot->index;
                        } else {
                            $this->downSlot[$cell] = $slot->index;
                        }
                    }
                }
            }
        }
        foreach ($this->slots as $slot) {
            $owners = $slot->across ? $this->downSlot : $this->acrossSlot;
            foreach ($slot->cells as $cell) {
                if ($owners[$cell] !== null) {
                    $slot->crossings[] = $owners[$cell];
                }
            }
            sort($slot->crossings, SORT_NUMERIC);
        }
    }

    public function ownerCount(int $cell): int
    {
        return (int)($this->acrossSlot[$cell] !== null) + (int)($this->downSlot[$cell] !== null);
    }

    public function orphanCell(): ?int
    {
        foreach ($this->grid->whiteCells() as $cell) {
            if ($this->ownerCount($cell) === 0) {
                return $cell;
            }
        }
        return null;
    }
}
