<?php
declare(strict_types=1);

namespace Crossword;

function decimal(int $numerator, int $denominator, int $places): string
{
    $scale = 1;
    for ($index = 0; $index < $places; $index++) {
        $scale *= 10;
    }
    $rounded = intdiv(2 * $numerator * $scale + $denominator, 2 * $denominator);
    return intdiv($rounded, $scale) . '.' . str_pad((string)($rounded % $scale), $places, '0', STR_PAD_LEFT);
}

function gridLines(Grid $grid, array $letters): array
{
    $lines = [];
    for ($row = 0; $row < $grid->height; $row++) {
        $lines[] = implode('', array_slice($letters, $row * $grid->width, $grid->width));
    }
    return $lines;
}

function numberLines(Layout $layout): array
{
    $grid = $layout->grid;
    $lines = [];
    for ($row = 0; $row < $grid->height; $row++) {
        $marks = [];
        for ($column = 0; $column < $grid->width; $column++) {
            $cell = $grid->cell($row, $column);
            if (!$grid->isOpen($row, $column)) {
                $marks[] = '##';
            } elseif (isset($layout->numbers[$cell])) {
                $marks[] = str_pad((string)$layout->numbers[$cell], 2, ' ', STR_PAD_LEFT);
            } else {
                $marks[] = ' .';
            }
        }
        $lines[] = implode(' ', $marks);
    }
    return $lines;
}

function listLine(Slot $slot, string $clue, string $entry, int|string $score, bool $theme): string
{
    return "{$slot->number}. {$clue} ({$slot->length}) {$entry} {$score}" . ($theme ? ' theme' : '');
}
