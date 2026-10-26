<?php
declare(strict_types=1);

namespace Roguelike;

final class Room
{
    public function __construct(public int $x, public int $y, public int $width, public int $height) {}
    public function center(): array { return [$this->x + intdiv($this->width, 2), $this->y + intdiv($this->height, 2)]; }
}

final class Region
{
    public ?self $first = null;
    public ?self $second = null;
    public ?int $leaf = null;
    public function __construct(public int $x, public int $y, public int $width, public int $height) {}
}

final class Level
{
    public array $terrain;
    public array $memory;
    public array $rooms = [];
    public array $arrival;
    public int $arrivalRoom;
    public array $target;
    public array $monsters = [];
    public array $items = [];
    public int $monstersCreated = 0;
    public int $itemsPlaced = 0;
    public int $kills = 0;
    public int $picked = 0;

    public function __construct(public int $depth, public int $width, public int $height)
    {
        $this->terrain = $this->memory = array_fill(0, $height, array_fill(0, $width, ' '));
    }

    public function monsterAt(int $x, int $y): ?Monster
    {
        foreach ($this->monsters as $monster) {
            if ($monster->x === $x && $monster->y === $y) {
                return $monster;
            }
        }
        return null;
    }

    public function itemAt(int $x, int $y): ?Item
    {
        foreach ($this->items as $item) {
            if ($item->x === $x && $item->y === $y) {
                return $item;
            }
        }
        return null;
    }

    public function drawInteriorCell(Minstd $rng, int $index): array
    {
        $room = $this->rooms[$index];
        $x = $room->x + 1 + $rng->rnd($room->width - 2);
        $y = $room->y + 1 + $rng->rnd($room->height - 2);
        return [$x, $y];
    }

    public function drawRoomCell(Minstd $rng): array
    {
        $index = $rng->rnd(count($this->rooms));
        [$x, $y] = $this->drawInteriorCell($rng, $index);
        return [$index, $x, $y];
    }
}

final class LevelGenerator
{
    public function __construct(private Minstd $rng, private int $minSize, private int $maxSplit, private int $roomMin, private int $roomMax) {}

    private function split(Region $region, int $depth, array &$leaves): void
    {
        $cv = $region->width >= 2 * $this->minSize;
        $ch = $region->height >= 2 * $this->minSize;
        if ($depth === $this->maxSplit || !($cv || $ch)) {
            $region->leaf = count($leaves);
            $leaves[] = $region;
            return;
        }
        if ($cv && $ch) {
            if (4 * $region->width >= 5 * $region->height) {
                $vertical = true;
            } elseif (4 * $region->height >= 5 * $region->width) {
                $vertical = false;
            } else {
                $vertical = $this->rng->draw() % 2 === 0;
            }
        } else {
            $vertical = $cv;
        }
        if ($vertical) {
            $cut = $this->minSize + $this->rng->rnd($region->width - 2 * $this->minSize + 1);
            $region->first = new Region($region->x, $region->y, $cut, $region->height);
            $region->second = new Region($region->x + $cut, $region->y, $region->width - $cut, $region->height);
        } else {
            $cut = $this->minSize + $this->rng->rnd($region->height - 2 * $this->minSize + 1);
            $region->first = new Region($region->x, $region->y, $region->width, $cut);
            $region->second = new Region($region->x, $region->y + $cut, $region->width, $region->height - $cut);
        }
        $this->split($region->first, $depth + 1, $leaves);
        $this->split($region->second, $depth + 1, $leaves);
    }

    private function makeRoom(Level $level, Region $region): Room
    {
        $width = $this->roomMin + $this->rng->rnd(min($this->roomMax, $region->width - 1) - $this->roomMin + 1);
        $height = $this->roomMin + $this->rng->rnd(min($this->roomMax, $region->height - 1) - $this->roomMin + 1);
        $x = $region->x + $this->rng->rnd($region->width - $width);
        $y = $region->y + $this->rng->rnd($region->height - $height);
        for ($row = $y; $row < $y + $height; $row++) {
            for ($column = $x; $column < $x + $width; $column++) {
                $level->terrain[$row][$column] = $row === $y || $row === $y + $height - 1 ? '-'
                    : ($column === $x || $column === $x + $width - 1 ? '|' : '.');
            }
        }
        return new Room($x, $y, $width, $height);
    }

    private function digCell(Level $level, int $x, int $y): void
    {
        $mark = $level->terrain[$y][$x];
        if ($mark === ' ') {
            $level->terrain[$y][$x] = '#';
        } elseif ($mark === '-' || $mark === '|') {
            $level->terrain[$y][$x] = '+';
        }
    }

    private function dig(Level $level, array $a, array $b, bool $horizontal): void
    {
        [$ax, $ay] = $a;
        [$bx, $by] = $b;
        $sx = $bx >= $ax ? 1 : -1;
        $sy = $by >= $ay ? 1 : -1;
        if ($horizontal) {
            for ($x = $ax; $x !== $bx + $sx; $x += $sx) {
                $this->digCell($level, $x, $ay);
            }
            for ($y = $ay; $y !== $by + $sy; $y += $sy) {
                $this->digCell($level, $bx, $y);
            }
        } else {
            for ($y = $ay; $y !== $by + $sy; $y += $sy) {
                $this->digCell($level, $ax, $y);
            }
            for ($x = $ax; $x !== $bx + $sx; $x += $sx) {
                $this->digCell($level, $x, $by);
            }
        }
    }

    private function connect(Level $level, Region $region): array
    {
        if ($region->leaf !== null) {
            return [$region->leaf];
        }
        $first = $this->connect($level, $region->first);
        $second = $this->connect($level, $region->second);
        $best = null;
        $bestDistance = 0;
        foreach ($first as $a) {
            [$ax, $ay] = $level->rooms[$a]->center();
            foreach ($second as $b) {
                [$bx, $by] = $level->rooms[$b]->center();
                $distance = abs($ax - $bx) + abs($ay - $by);
                if ($best === null || $distance < $bestDistance) {
                    $best = [$a, $b];
                    $bestDistance = $distance;
                }
            }
        }
        $horizontal = $this->rng->draw() % 2 === 0;
        $this->dig($level, $level->rooms[$best[0]]->center(), $level->rooms[$best[1]]->center(), $horizontal);
        return array_merge($first, $second);
    }

    public function generate(int $depth, int $width, int $height): Level
    {
        $level = new Level($depth, $width, $height);
        $root = new Region(0, 0, $width, $height);
        $leaves = [];
        $this->split($root, 0, $leaves);
        foreach ($leaves as $leaf) {
            $level->rooms[] = $this->makeRoom($level, $leaf);
        }
        $this->connect($level, $root);
        [$room, $x, $y] = $level->drawRoomCell($this->rng);
        $level->terrain[$y][$x] = '<';
        $level->arrival = [$x, $y];
        $level->arrivalRoom = $room;
        $other = $this->rng->rnd(count($level->rooms) - 1);
        if ($other >= $room) {
            $other++;
        }
        $level->target = $level->drawInteriorCell($this->rng, $other);
        return $level;
    }
}
