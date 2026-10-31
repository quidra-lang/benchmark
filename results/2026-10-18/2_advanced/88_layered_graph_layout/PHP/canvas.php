<?php

final class Canvas
{
    public bool $vertical;
    public int $rows, $columns;
    private array $lineBits = [], $arrows = [], $boxes = [], $highlighted = [];
    private string $mainCharacter, $secondaryCharacter;

    public function __construct(
        private string $direction,
        public int $mainLength,
        int $secondaryLength,
    ) {
        $this->vertical = in_array($direction, ['TB', 'BT'], true);
        $this->rows = $this->vertical ? $mainLength : $secondaryLength;
        $this->columns = $this->vertical ? $secondaryLength : $mainLength;
        $this->mainCharacter = $this->vertical ? '|' : '-';
        $this->secondaryCharacter = $this->vertical ? '-' : '|';
    }

    public function cell(int $main, int $secondary): array
    {
        if ($this->direction === 'BT' || $this->direction === 'RL')
            $main = $this->mainLength - 1 - $main;
        return $this->vertical ? [$main, $secondary] : [$secondary, $main];
    }

    private function addLine(int $main, int $secondary, string $character): void
    {
        [$r, $c] = $this->cell($main, $secondary);
        $key = $r . ':' . $c;
        $this->lineBits[$key] = ($this->lineBits[$key] ?? 0) | ['|' => 1, '-' => 2, '+' => 4][$character];
    }

    public function mainLine(int $start, int $end, int $secondary): void
    {
        for ($m = $start; $m <= $end; ++$m)
            $this->addLine($m, $secondary, $this->mainCharacter);
    }

    public function segment(int $start, int $gap, int $first, int $second, ?int $offset): void
    {
        if ($first === $second) {
            $this->mainLine($start, $start + $gap - 1, $first);
            return;
        }
        $this->mainLine($start, $start + $offset - 1, $first);
        $this->addLine($start + $offset, $first, '+');
        $this->addLine($start + $offset, $second, '+');
        for ($c = min($first, $second) + 1; $c < max($first, $second); ++$c)
            $this->addLine($start + $offset, $c, $this->secondaryCharacter);
        $this->mainLine($start + $offset + 1, $start + $gap - 1, $second);
    }

    public function arrow(array $point, bool $reverse): void
    {
        [$r, $c] = $this->cell(...$point);
        $this->arrows[$r . ':' . $c] = ($reverse
            ? ['TB' => '^', 'BT' => 'v', 'LR' => '<', 'RL' => '>']
            : ['TB' => 'v', 'BT' => '^', 'LR' => '>', 'RL' => '<'])[$this->direction];
    }

    public function highlightRoute(array $points): void
    {
        for ($i = 1; $i < count($points); ++$i) {
            [$r1, $c1] = $points[$i - 1];
            [$r2, $c2] = $points[$i];
            $dr = $r2 <=> $r1;
            $dc = $c2 <=> $c1;
            $length = abs($r2 - $r1) + abs($c2 - $c1);
            for ($j = 0; $j <= $length; ++$j)
                $this->highlighted[($r1 + ($j * $dr)) . ':' . ($c1 + ($j * $dc))] = true;
        }
    }

    public function box(string $label, int $band, int $coordinate, int $left, bool $onPath): void
    {
        $text = ($onPath ? '{' : '[') . $label . ($onPath ? '}' : ']');
        if ($this->vertical)
            [$r, $c] = $this->cell($band, $coordinate - $left);
        else {
            $r = $coordinate;
            $c = $this->direction === 'LR' ? $band : $this->mainLength - $band - strlen($text);
        }
        for ($i = 0; $i < strlen($text); ++$i)
            $this->boxes[$r . ':' . ($c + $i)] = $text[$i];
    }

    private function character(int $r, int $c): string
    {
        $key = $r . ':' . $c;
        return (
            $this->boxes[$key] ?? $this->arrows[$key]
            ?? (
                isset($this->highlighted[$key])
                    ? '#'
                    : [0 => ' ', 1 => '|', 2 => '-', 4 => '+'][$this->lineBits[$key] ?? 0] ?? '+'
            )
        );
    }

    public function crossingCells(): int
    {
        return count(array_filter($this->lineBits, fn($bits) => ($bits & 3) === 3));
    }

    public function drawingLines(): array
    {
        $ruler = '    ';
        for ($c = 0; $c < $this->columns; ++$c)
            $ruler .= $c % 10;
        $lines = [$ruler];
        for ($r = 0; $r < $this->rows; ++$r) {
            $text = sprintf('%3d ', $r);
            for ($c = 0; $c < $this->columns; ++$c)
                $text .= $this->character($r, $c);
            $lines[] = rtrim($text, ' ');
        }
        return $lines;
    }
}
