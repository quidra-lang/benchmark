<?php
declare(strict_types=1);

namespace TowerDefense;

function cellCenter(array $cell): array { return [100 * $cell[0], 100 * $cell[1]]; }
function cellKey(array $cell): string { return $cell[0] . ',' . $cell[1]; }

final class GridMap
{
    public array $exit;
    public array $spawns = [];

    public function __construct(public int $width, public int $height, public array $rows)
    {
        $found = [];
        foreach ($rows as $y => $row) {
            for ($x = 0; $x < $width; $x++) {
                $terrain = $row[$x];
                if ($terrain >= '1' && $terrain <= '9') {
                    $found[(int)$terrain] = [$x, $y];
                } elseif ($terrain === 'E') {
                    $this->exit = [$x, $y];
                }
            }
        }
        for ($number = 1; $number <= count($found); $number++) {
            $this->spawns[] = $found[$number];
        }
    }

    public function inside(array $cell): bool { return 0 <= $cell[0] && $cell[0] < $this->width && 0 <= $cell[1] && $cell[1] < $this->height; }
    public function terrain(array $cell): string { return $this->rows[$cell[1]][$cell[0]]; }
    public function isRock(array $cell): bool { return $this->terrain($cell) === '#'; }
    public function isWater(array $cell): bool { return $this->terrain($cell) === '~'; }
    public function buildable(array $cell): bool { return $this->terrain($cell) === '.'; }
}

function readMap(string $path): GridMap
{
    $lines = file($path, FILE_IGNORE_NEW_LINES);
    [$width, $height] = array_map('intval', explode(' ', $lines[0]));
    return new GridMap($width, $height, array_slice($lines, 1, $height));
}
