<?php
declare(strict_types=1);

namespace TowerDefense;

const TARGET_MODES = ['FIRST', 'LAST', 'STRONGEST', 'WEAKEST', 'CLOSEST'];

final class Level
{
    public function __construct(public int $cost, public int $range, public int $power, public int $interval,
        public int $shotSpeed, public int $splash, public int $slowRate, public int $slowTime, public int $burnAmount, public int $burnTime) {}
}

final class TowerType
{
    public function __construct(public string $name, public string $symbol, public string $targets, public array $levels) {}
}

function parseTowerTypes(array $lines): array
{
    $types = [];
    for ($index = 0; $index < count($lines);) {
        [$keyword, $name, $symbol, $targets, $count] = explode(' ', $lines[$index]);
        $levels = [];
        for ($offset = 1; $offset <= (int)$count; $offset++) {
            $levels[] = new Level(...array_map('intval', array_slice(explode(' ', $lines[$index + $offset]), 1)));
        }
        $types[] = new TowerType($name, $symbol, $targets, $levels);
        $index += (int)$count + 1;
    }
    return $types;
}

function canAim(string $targets, Enemy $enemy): bool { return $targets === 'both' || $targets === $enemy->kind->movement; }

final class Tower
{
    public int $level = 1;
    public string $mode = 'FIRST';
    public int $ready;
    public int $investment;
    public int $built;
    public ?int $sold = null;
    public int $shots = 0;
    public int $hits = 0;
    public int $fizzles = 0;
    public int $kills = 0;
    public int $damage = 0;

    public function __construct(public int $number, public TowerType $kind, public array $cell, int $tick)
    {
        $this->ready = $this->built = $tick;
        $this->investment = $kind->levels[0]->cost;
    }

    public function stats(): Level { return $this->kind->levels[$this->level - 1]; }
    public function center(): array { return cellCenter($this->cell); }
    public function standing(): bool { return $this->sold === null; }

    public function inRange(array $point): bool
    {
        $reach = $this->stats()->range;
        return squaredDistance($this->center(), $point) <= $reach * $reach;
    }

    public function targetKey(Enemy $enemy, DistanceField $field): int
    {
        return match ($this->mode) {
            'FIRST' => $enemy->remaining($field), 'LAST' => -$enemy->remaining($field),
            'STRONGEST' => -$enemy->hp, 'WEAKEST' => $enemy->hp,
            default => squaredDistance($this->center(), $enemy->position()),
        };
    }

    public function selectTarget(array $enemies, DistanceField $field): ?Enemy
    {
        $best = null;
        $bestKey = 0;
        foreach ($enemies as $enemy) {
            if (!canAim($this->kind->targets, $enemy) || !$this->inRange($enemy->position())) {
                continue;
            }
            $key = $this->targetKey($enemy, $field);
            if ($best === null || $key < $bestKey) {
                $best = $enemy;
                $bestKey = $key;
            }
        }
        return $best;
    }
}
