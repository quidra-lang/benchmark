<?php

final class Grid
{
    public int $width, $height;
    public array $rows, $free = [], $adjacent = [];

    public function __construct()
    {
        $lines = file('input/map.txt', FILE_IGNORE_NEW_LINES);
        [$this->width, $this->height] = array_map(intval(...), explode(' ', array_shift($lines)));
        $this->rows = $lines;
        foreach ($lines as $y => $row)
            for ($x = 0; $x < $this->width; ++$x)
                if ($row[$x] === '.')
                    $this->free[($y * $this->width) + $x] = true;
        foreach ($this->free as $c => $unused) {
            $x = $c % $this->width;
            $y = intdiv($c, $this->width);
            $this->adjacent[$c] = [];
            foreach ([[0, 0], [0, -1], [1, 0], [0, 1], [-1, 0]] as [$dx, $dy]) {
                $nx = $x + $dx;
                $ny = $y + $dy;
                $next = ($ny * $this->width) + $nx;
                if (
                    $nx >= 0
                    && $nx < $this->width
                    && $ny >= 0
                    && $ny < $this->height
                    && isset($this->free[$next])
                )
                    $this->adjacent[$c][] = $next;
            }
        }
    }

    public function neighbors(int $cell): array
    {
        return array_slice($this->adjacent[$cell], 1);
    }

    public function distances(int $goal): array
    {
        $distance = [$goal => 0];
        $queue = [$goal];
        for ($i = 0; $i < count($queue); ++$i)
            foreach ($this->neighbors($queue[$i]) as $c)
                if (!isset($distance[$c])) {
                    $distance[$c] = $distance[$queue[$i]] + 1;
                    $queue[] = $c;
                }
        return $distance;
    }

    public function statistics(): array
    {
        $counts = [0, 0, 0, 0];
        foreach ($this->free as $c => $unused)
            ++$counts[min(3, count($this->neighbors($c)))];
        $remaining = $this->free;
        $components = 0;
        while ($remaining) {
            ++$components;
            $seed = array_key_first($remaining);
            unset($remaining[$seed]);
            $queue = [$seed];
            for ($i = 0; $i < count($queue); ++$i)
                foreach ($this->neighbors($queue[$i]) as $c)
                    if (isset($remaining[$c])) {
                        unset($remaining[$c]);
                        $queue[] = $c;
                    }
        }
        return [...$counts, $components];
    }
}

function readAgents(Grid $grid): array
{
    $agents = [];
    foreach (array_slice(file('input/agents.csv', FILE_IGNORE_NEW_LINES), 1) as $line) {
        [$id, $sx, $sy, $gx, $gy] = array_map(intval(...), explode(',', $line));
        $agents[] = [
            'id' => $id,
            'name' => chr(65 + $id),
            'start' => ($sy * $grid->width) + $sx,
            'goal' => ($gy * $grid->width) + $gx,
        ];
    }
    return $agents;
}
