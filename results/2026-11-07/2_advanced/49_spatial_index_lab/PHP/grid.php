<?php

class GridCell {
    public $column;
    public $row;
    public $points = [];

    public function __construct($column, $row) {
        $this->column = $column;
        $this->row = $row;
    }
}

class Grid {
    public $size;
    public $side;
    public $cells = [];

    public function __construct($points, $world, $size) {
        $this->size = $size;
        $this->side = intdiv($world, $size);
        for ($row = 0; $row < $this->side; $row++) {
            for ($column = 0; $column < $this->side; $column++) $this->cells[] = new GridCell($column, $row);
        }
        foreach ($points as $point) $this->insert($point);
    }

    public function cell($point) {
        return $this->cells[intdiv($point['y'], $this->size) * $this->side + intdiv($point['x'], $this->size)];
    }

    public function insert($point) {
        $cell = $this->cell($point);
        $cell->points[] = $point;
        usort($cell->points, fn($a, $b) => $a['id'] <=> $b['id']);
    }

    public function remove($point) {
        $cell = $this->cell($point);
        foreach ($cell->points as $i => $held) if ($held['id'] === $point['id']) {
            array_splice($cell->points, $i, 1);
            break;
        }
    }
}
