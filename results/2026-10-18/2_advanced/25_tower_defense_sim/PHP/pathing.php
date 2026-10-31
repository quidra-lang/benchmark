<?php
declare(strict_types=1);

namespace TowerDefense;

const DIRECTIONS = [[0, -1], [1, 0], [0, 1], [-1, 0]];

function neighbor(array $cell, int $direction): array
{
    return [$cell[0] + DIRECTIONS[$direction][0], $cell[1] + DIRECTIONS[$direction][1]];
}

final class DistanceField
{
    public array $exit;
    public array $dist;

    public function __construct(public GridMap $grid, array $towers)
    {
        $this->exit = $grid->exit;
        $this->dist = array_fill(0, $grid->height, array_fill(0, $grid->width, -1));
        $this->dist[$this->exit[1]][$this->exit[0]] = 0;
        $queue = [$this->exit];
        for ($first = 0; $first < count($queue); $first++) {
            $cell = $queue[$first];
            for ($direction = 0; $direction < 4; $direction++) {
                $following = neighbor($cell, $direction);
                if ($grid->inside($following) && !$grid->isRock($following) && !isset($towers[cellKey($following)]) && $this->at($following) === -1) {
                    $this->dist[$following[1]][$following[0]] = $this->at($cell) + 1;
                    $queue[] = $following;
                }
            }
        }
    }

    public function at(array $cell): int { return $this->dist[$cell[1]][$cell[0]]; }

    public function direction(array $cell): ?int
    {
        $best = null;
        $bestDistance = 0;
        for ($direction = 0; $direction < 4; $direction++) {
            $following = neighbor($cell, $direction);
            if (!$this->grid->inside($following)) {
                continue;
            }
            $distance = $this->at($following);
            if ($distance >= 0 && ($best === null || $distance < $bestDistance)) {
                $best = $direction;
                $bestDistance = $distance;
            }
        }
        return $best;
    }

    public function nextCell(array $cell): array { return neighbor($cell, $this->direction($cell)); }

    public function path(array $start): array
    {
        $cells = [$start];
        while ($cells[count($cells) - 1] !== $this->exit) {
            $cells[] = $this->nextCell($cells[count($cells) - 1]);
        }
        return $cells;
    }
}
