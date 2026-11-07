<?php
declare(strict_types=1);

namespace Crossword;

final class Grid
{
    public int $height;
    public int $width;
    public string $cells;

    public function __construct(public array $rows)
    {
        $this->height = count($rows);
        $this->width = strlen($rows[0]);
        $this->cells = implode('', $rows);
    }

    public function size(): int { return $this->height * $this->width; }
    public function cell(int $row, int $column): int { return $row * $this->width + $column; }
    public function location(int $cell): array { return [intdiv($cell, $this->width) + 1, $cell % $this->width + 1]; }

    public function isOpen(int $row, int $column): bool
    {
        return $row >= 0 && $row < $this->height && $column >= 0 && $column < $this->width && $this->rows[$row][$column] !== '#';
    }

    public function isGiven(int $cell): bool
    {
        return $this->cells[$cell] !== '#' && $this->cells[$cell] !== '.';
    }

    public function whiteCells(): array
    {
        $result = [];
        for ($cell = 0; $cell < $this->size(); $cell++) {
            if ($this->cells[$cell] !== '#') {
                $result[] = $cell;
            }
        }
        return $result;
    }

    public function asymmetricCell(string $symmetry): ?int
    {
        for ($row = 0; $row < $this->height; $row++) {
            for ($column = 0; $column < $this->width; $column++) {
                $otherRow = $symmetry === 'rot180' ? $this->height - 1 - $row : $row;
                $otherColumn = $this->width - 1 - $column;
                if ($this->isOpen($row, $column) !== $this->isOpen($otherRow, $otherColumn)) {
                    return $this->cell($row, $column);
                }
            }
        }
        return null;
    }

    public function componentCount(): int
    {
        $seen = [];
        $count = 0;
        foreach ($this->whiteCells() as $start) {
            if (isset($seen[$start])) {
                continue;
            }
            $count++;
            $seen[$start] = true;
            $stack = [$start];
            while ($stack !== []) {
                $cell = array_pop($stack);
                $row = intdiv($cell, $this->width);
                $column = $cell % $this->width;
                foreach ([[-1, 0], [1, 0], [0, -1], [0, 1]] as [$dr, $dc]) {
                    $nr = $row + $dr;
                    $nc = $column + $dc;
                    if ($this->isOpen($nr, $nc)) {
                        $neighbor = $this->cell($nr, $nc);
                        if (!isset($seen[$neighbor])) {
                            $seen[$neighbor] = true;
                            $stack[] = $neighbor;
                        }
                    }
                }
            }
        }
        return $count;
    }
}
