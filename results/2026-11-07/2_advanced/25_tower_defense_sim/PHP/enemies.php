<?php
declare(strict_types=1);

namespace TowerDefense;

final class EnemyType
{
    public int $spawned = 0;
    public int $kills = 0;
    public int $leaks = 0;
    public int $damage = 0;

    public function __construct(public string $name, public string $symbol, public string $movement, public int $hp,
        public int $armor, public int $speed, public int $bounty, public int $lives, public int $regen,
        public ?EnemyType $splitInto, public int $splitCount) {}
}

final class Group
{
    public function __construct(public EnemyType $kind, public int $spawn, public int $count, public int $delay, public int $interval, public int $multiplier) {}
    public function spawnTick(int $start, int $index): int { return $start + $this->delay + $index * $this->interval; }
}

final class Wave
{
    public array $groups = [];
    public function __construct(public int $reward) {}
    public function enemyCount(): int { return array_sum(array_map(static fn(Group $group): int => $group->count, $this->groups)); }
}

function parseWaves(array $lines): array
{
    $types = $known = $waves = [];
    foreach ($lines as $line) {
        $fields = explode(' ', $line);
        if ($fields[0] === 'enemy') {
            $kind = new EnemyType($fields[1], $fields[2], $fields[3], (int)$fields[4], (int)$fields[5], (int)$fields[6],
                (int)$fields[7], (int)$fields[8], (int)$fields[9], $fields[10] === '-' ? null : $known['#' . $fields[10]], (int)$fields[11]);
            $types[] = $kind;
            $known['#' . $kind->name] = $kind;
        } elseif ($fields[0] === 'wave') {
            $waves[] = new Wave((int)$fields[1]);
        } else {
            $waves[count($waves) - 1]->groups[] = new Group($known['#' . $fields[1]], (int)$fields[2], (int)$fields[3], (int)$fields[4], (int)$fields[5], (int)$fields[6]);
        }
    }
    return [$types, $waves];
}

final class Enemy
{
    public int $maxHp;
    public int $hp;
    public Effect $slow;
    public Effect $burn;
    public bool $alive = true;
    public ?array $cell = null;
    public ?array $nextCell = null;
    public int $progress = 0;
    public ?array $point = null;

    public function __construct(public int $number, public EnemyType $kind, public int $multiplier)
    {
        $this->maxHp = $this->hp = intdiv($kind->hp * $multiplier, 100);
        $this->slow = new Effect();
        $this->burn = new Effect();
    }

    public function flying(): bool { return $this->kind->movement === 'air'; }

    public function position(): array
    {
        if ($this->flying()) {
            return $this->point;
        }
        return [100 * $this->cell[0] + ($this->nextCell[0] - $this->cell[0]) * $this->progress,
            100 * $this->cell[1] + ($this->nextCell[1] - $this->cell[1]) * $this->progress];
    }

    public function occupiedCell(): array
    {
        if ($this->flying()) {
            return [intdiv($this->point[0] + 50, 100), intdiv($this->point[1] + 50, 100)];
        }
        return $this->progress < 50 ? $this->cell : $this->nextCell;
    }

    public function remaining(DistanceField $field): int
    {
        return $this->flying() ? integerSqrt(squaredDistance($this->point, cellCenter($field->exit))) : 100 * $field->at($this->nextCell) + 100 - $this->progress;
    }

    public function slowedSpeed(): int
    {
        return $this->slow->active() ? intdiv($this->kind->speed * (100 - $this->slow->strength), 100) : $this->kind->speed;
    }

    public function split(int $number): Enemy
    {
        $child = new self($number, $this->kind->splitInto, $this->multiplier);
        $child->cell = $this->cell;
        $child->nextCell = $this->nextCell;
        $child->progress = $this->progress;
        $child->point = $this->point;
        return $child;
    }
}
