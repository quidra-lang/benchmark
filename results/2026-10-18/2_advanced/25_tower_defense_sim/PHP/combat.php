<?php
declare(strict_types=1);

namespace TowerDefense;

function integerSqrt(int $value): int
{
    if ($value < 2) {
        return $value;
    }
    $root = $value;
    $following = intdiv($value + 1, 2);
    while ($following < $root) {
        $root = $following;
        $following = intdiv($root + intdiv($value, $root), 2);
    }
    return $root;
}

function squaredDistance(array $first, array $second): int
{
    $dx = $first[0] - $second[0];
    $dy = $first[1] - $second[1];
    return $dx * $dx + $dy * $dy;
}

function scaled(int $delta, int $step, int $length): int
{
    return $delta >= 0 ? intdiv($delta * $step, $length) : -intdiv(-$delta * $step, $length);
}

function advance(array $point, array $goal, int $step): array
{
    $dx = $goal[0] - $point[0];
    $dy = $goal[1] - $point[1];
    $squared = $dx * $dx + $dy * $dy;
    if ($squared <= $step * $step) {
        return [$goal, true];
    }
    $length = integerSqrt($squared);
    return [[$point[0] + scaled($dx, $step, $length), $point[1] + scaled($dy, $step, $length)], false];
}

function damageDealt(int $hp, int $power, int $armor): int { return min($hp, max(1, $power - $armor)); }

final class Effect
{
    public int $strength = 0;
    public int $remaining = 0;
    public ?int $source = null;

    public function active(): bool { return $this->remaining > 0; }

    public function receive(int $strength, int $duration, ?int $source = null): void
    {
        if ($strength > $this->strength) {
            $this->strength = $strength;
            $this->remaining = $duration;
            $this->source = $source;
        } elseif ($strength === $this->strength) {
            $this->remaining = max($this->remaining, $duration);
        }
    }

    public function advanceTime(): void
    {
        $this->remaining--;
        if ($this->remaining === 0) {
            $this->strength = 0;
            $this->source = null;
        }
    }
}

final class Projectile
{
    public int $power;
    public int $speed;
    public int $splash;
    public int $slowRate;
    public int $slowTime;
    public int $burnAmount;
    public int $burnTime;

    public function __construct(public int $number, public int $tower, public int $target, public array $position,
        public array $aim, public string $targets, Level $stats)
    {
        $this->power = $stats->power;
        $this->speed = $stats->shotSpeed;
        $this->splash = $stats->splash;
        $this->slowRate = $stats->slowRate;
        $this->slowTime = $stats->slowTime;
        $this->burnAmount = $stats->burnAmount;
        $this->burnTime = $stats->burnTime;
    }

    public function fly(): bool
    {
        if ($this->speed === 0) {
            return true;
        }
        [$this->position, $arrived] = advance($this->position, $this->aim, $this->speed);
        return $arrived;
    }
}
