<?php

class Canvas
{
    public $width;
    public $height;
    public $cells;

    public function __construct($width, $height)
    {
        $this->width = $width;
        $this->height = $height;
        $this->cells = array_fill(0, $height, array_fill(0, $width, ' '));
    }

    public function position($point)
    {
        $x = $point['X'] ?? $point['x'];
        $y = $point['Y'] ?? $point['y'];
        $d = $point['D'] ?? 1;
        return [intdiv(2 * $x * ($this->width - 1) + 1000 * $d, 2000 * $d),
            $this->height - 1 - intdiv(2 * $y * ($this->height - 1) + 1000 * $d, 2000 * $d)];
    }

    public function point($point, $character)
    {
        [$column, $row] = $this->position($point);
        $this->cells[$row][$column] = $character;
    }

    public function line($start, $end, $character)
    {
        [$x, $y] = $this->position($start);
        [$x1, $y1] = $this->position($end);
        $dx = abs($x1 - $x);
        $dy = -abs($y1 - $y);
        $sx = $x < $x1 ? 1 : -1;
        $sy = $y < $y1 ? 1 : -1;
        $error = $dx + $dy;
        while (true) {
            $this->cells[$y][$x] = $character;
            if ($x === $x1 && $y === $y1) {
                break;
            }
            $doubled = 2 * $error;
            if ($doubled >= $dy) {
                $error += $dy;
                $x += $sx;
            }
            if ($doubled <= $dx) {
                $error += $dx;
                $y += $sy;
            }
        }
    }

    public function frame()
    {
        $border = '+' . str_repeat('-', $this->width) . '+';
        $lines = [$border];
        foreach ($this->cells as $row) {
            $lines[] = '|' . implode('', $row) . '|';
        }
        $lines[] = $border;
        return $lines;
    }
}

function voronoiPlot($width, $height, $points)
{
    $canvas = new Canvas($width, $height);
    $owners = array_fill(0, $height, array_fill(0, $width, 0));
    for ($row = 0; $row < $height; $row++) {
        for ($column = 0; $column < $width; $column++) {
            $best = PHP_INT_MAX;
            for ($site = 1; $site < count($points); $site++) {
                $x = ($column * 1000 - $points[$site]['x'] * ($width - 1)) * ($height - 1);
                $y = (($height - 1 - $row) * 1000 - $points[$site]['y'] * ($height - 1)) * ($width - 1);
                $distance = $x * $x + $y * $y;
                if ($distance < $best) {
                    $best = $distance;
                    $owners[$row][$column] = $site;
                }
            }
        }
    }
    for ($row = 0; $row < $height; $row++) {
        for ($column = 0; $column < $width; $column++) {
            if (($column < $width - 1 && $owners[$row][$column] !== $owners[$row][$column + 1]) ||
                ($row < $height - 1 && $owners[$row][$column] !== $owners[$row + 1][$column])) {
                $canvas->cells[$row][$column] = '#';
            }
        }
    }
    for ($site = 1; $site < count($points); $site++) {
        $canvas->point($points[$site], 'o');
    }
    return $canvas->frame();
}
