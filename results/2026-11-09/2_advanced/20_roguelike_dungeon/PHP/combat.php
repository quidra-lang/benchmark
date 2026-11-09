<?php
declare(strict_types=1);

namespace Roguelike;

final class Dice
{
    public function __construct(public int $count, public int $sides) {}
    public function roll(Minstd $rng): int { return $rng->roll($this->count, $this->sides); }
}

function parseDice(string $token): Dice
{
    [$count, $sides] = array_map('intval', explode('d', $token));
    return new Dice($count, $sides);
}

function resolveAttack(Minstd $rng, int $toHit, int $defense, Dice $dice, int $bonus): array
{
    $roll = 1 + $rng->rnd(20);
    if ($roll === 1) {
        return ['miss', 0];
    }
    if ($roll === 20) {
        $outcome = 'critical';
        $first = $dice->roll($rng);
        $second = $dice->roll($rng);
        $damage = $first + $second + $bonus;
    } elseif ($roll + $toHit >= $defense) {
        $outcome = 'hit';
        $damage = $dice->roll($rng) + $bonus;
    } else {
        return ['miss', 0];
    }
    return [$outcome, max($damage, 1)];
}
